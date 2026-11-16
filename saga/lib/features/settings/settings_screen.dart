import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:package_info_plus/package_info_plus.dart';
import '../../core/theme/saga_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:url_launcher/url_launcher.dart';
import '../../core/audio/audio_level.dart';
import '../../core/build_channel.dart';
import '../../core/diagnostics/app_log.dart';
import '../../core/mark_motion.dart';
import '../../core/plex/plex_client.dart';
import '../../core/utils/format.dart';
import '../../core/plex/models/plex_library.dart';
import '../../core/plex/models/plex_track.dart';
import '../../core/providers.dart';
import '../../core/storage/book_download_store.dart';
import '../../core/storage/bookmark_store.dart';
import '../../core/storage/completed_books_store.dart';
import '../../core/storage/download_store.dart';
import '../../core/storage/listen_days_store.dart';
import '../../core/storage/listening_history_store.dart';
import '../../core/storage/named_bookmark_store.dart';
import '../../core/storage/playback_log_store.dart';
import '../../core/storage/progress_backup.dart';
import '../../core/storage/save_audit_store.dart';
import '../../core/storage/settings_store.dart';
import '../../core/storage/timeline_queue_store.dart';
import '../../core/storage/track_cache_store.dart';
import '../../core/update/update_checker.dart';
import '../auth/server_selection_screen.dart';
import '../home/history_shared.dart' show historyMonthAbbr;
import '../player/player_provider.dart';
import '../player/server_position.dart';
import '../player/sync_decision.dart';
import '../player/session_restore.dart' show mostRecentBookRatingKey;
import '../../core/book_status.dart' show finishedBookKeys;
import '../../core/audio/canned_audio_level.dart';
import '../../shared/widgets/confirm_dialog.dart';
import '../../shared/widgets/saga_mark.dart'
    show SagaWordmark, SagaMark, AnimatedSagaMark, SagaMarkState;
import '../../shared/widgets/saga_sheet.dart';
import '../../shared/widgets/saga_toast.dart';
import '../widget/home_widget_sync.dart';

part 'settings_widgets.dart';
part 'settings_playback.dart';
part 'settings_server.dart';
part 'settings_downloads.dart';
part 'settings_data.dart';
part 'settings_about.dart';
part 'settings_developer.dart';

/// Settings (handoff frame 13): an index that fits one screen — the theme
/// inline, one row per page with a line saying what's set, and Sign out set
/// apart. Each page is a part of this library, so the tiles stay private to
/// Settings and are shared without being renamed.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  String _version = '';

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((info) {
      if (mounted) setState(() => _version = info.version);
    }).catchError((_) {});
  }

  /// Pushes [page] on the Settings tab, and redraws the summaries when it's
  /// closed: the pages write settings this screen only reads at build.
  Future<void> _open(Widget page) async {
    await Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => page));
    if (mounted) setState(() {});
  }

  /// "30s skips · 1.0x · end of chapter", from what Playback has set.
  static String _playbackSummary() {
    final back = SettingsStore.skipBackwardSeconds;
    final forward = SettingsStore.skipForwardSeconds;
    final sleep = SettingsStore.defaultSleepTimerMinutes;
    return [
      back == forward ? '${back}s skips' : '${back}s back · ${forward}s forward',
      '${SettingsStore.defaultSpeed}x',
      if (sleep == -1) 'end of chapter' else if (sleep > 0) '$sleep min timer',
    ].join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(sagaThemeVariantProvider);
    final client = ref.watch(plexClientProvider);

    // The update banner's tap lands here, with the tab already popped to
    // this screen (main_shell). Check for updates lives on About now. After a
    // frame, so the tab switch that came with it has laid this screen out.
    ref.listen(revealUpdateRowProvider, (_, _) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _open(const _AboutPage(revealUpdate: true));
      });
    });

    final library = ref.watch(librariesProvider).valueOrNull;
    final selectedKey = ref.watch(selectedLibraryKeyProvider);
    final libraryTitle = library == null || library.isEmpty
        ? null
        : library
            .firstWhere((l) => l.key == selectedKey, orElse: () => library.first)
            .title;
    final update = ref.watch(updateCheckProvider).valueOrNull;

    return Scaffold(
      backgroundColor: SagaColors.bg,
      body: CustomScrollView(
        slivers: [
          _settingsAppBar(Text('Settings',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 22))),
          // The page is one Column, which — unlike a ListView's items — gets
          // no repaint boundary of its own: every scroll frame re-recorded
          // every tile, 5–15 ms on the UI thread, and Settings stuttered.
          // Behind a boundary it's painted once and scrolling only moves the
          // layer. The pages do the same ([_SettingsPage]).
          SliverToBoxAdapter(
            child: RepaintBoundary(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 8),
                  _SectionHeader('Appearance'),
                  _ThemePicker(),
                  const SizedBox(height: 16),
                  _SettingsTile(
                    icon: Icons.play_circle_outline,
                    title: 'Playback',
                    subtitle: _playbackSummary(),
                    onTap: () => _open(const _PlaybackPage()),
                  ),
                  _SettingsTile(
                    icon: Icons.dns_outlined,
                    title: 'Server',
                    subtitle: client.serverUri == null
                        ? 'Not connected'
                        : libraryTitle == null
                            ? 'Plex'
                            : 'Plex · $libraryTitle',
                    onTap: () => _open(const _ServerPage()),
                  ),
                  _SettingsTile(
                    icon: Icons.download_for_offline_outlined,
                    title: 'Downloads',
                    subtitle: SettingsStore.downloadWifiOnly
                        ? 'Wi-Fi only'
                        : 'Over Wi-Fi or mobile data',
                    onTap: () => _open(const _DownloadsPage()),
                  ),
                  _SettingsTile(
                    icon: Icons.settings_backup_restore_rounded,
                    title: 'Data and backup',
                    subtitle: 'Export, import or clear progress',
                    onTap: () => _open(const _DataPage()),
                  ),
                  _SettingsTile(
                    icon: update?.isNewer == true
                        ? Icons.new_releases_outlined
                        : Icons.info_outline,
                    title: 'About',
                    subtitle: [
                      if (_version.isNotEmpty) 'Saga $_version',
                      if (update?.isNewer == true) 'update available',
                    ].join(' · '),
                    onTap: () => _open(const _AboutPage()),
                  ),
                  if (BuildChannel.developerOptions)
                    _SettingsTile(
                      icon: Icons.developer_mode_outlined,
                      title: 'Developer options',
                      subtitle: 'Position saves · beta and dev builds',
                      onTap: () => _open(const _DeveloperPage()),
                    ),
                  const SizedBox(height: 24),
                  _SettingsTile(
                    icon: Icons.logout,
                    title: 'Sign out',
                    subtitle: 'Sign out of your Plex account',
                    iconColor: Colors.redAccent,
                    onTap: () => _confirmSignOut(ref),
                  ),
                  SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmSignOut(WidgetRef ref) async {
    final confirmed = await confirmDialog(
      context,
      title: 'Sign out',
      message: 'Sign out of your Plex account?',
      confirmLabel: 'Sign out',
      confirmColor: Colors.redAccent,
    );
    if (confirmed) {
      // Stop cleanly first: position saves file under the *current* server's
      // storage scope, and clearAuth re-points the scope at the primary
      // server's keys — a book left playing across sign-out would file the
      // rest of its session under the wrong server's book.
      await ref.read(playerServiceProvider).stopAndClear();
      try {
        await ref.read(plexClientProvider).clearAuth();
      } catch (e) {
        // clearAuth throws only while the token is still stored. Showing the
        // sign-in screen now would claim a sign-out that didn't happen.
        AppLog.log('auth', 'sign-out failed, still signed in: $e');
        if (mounted) showSagaToast(context, "Couldn't sign out. Try again.");
        return;
      }
      // clearAuth emptied the client, not this provider, which only reads
      // it at start: the next sign-in routed straight to the shell with no
      // server, instead of to server selection.
      ref.read(activeServerUriProvider.notifier).state = null;
      ref.read(isAuthenticatedProvider.notifier).state = false;
      // The shell (and its lifecycle hook) is gone from here on: take the
      // book off the home-screen widget now.
      HomeWidgetSync.refresh();
    }
  }
}

class _ThemePicker extends ConsumerWidget {
  const _ThemePicker();

  static const _themes = [
    (variant: SagaThemeVariant.ink,   label: 'Ink',   bg: Color(0xFF1E1410), accent: Color(0xFFE0A050)),
    (variant: SagaThemeVariant.cream, label: 'Cream', bg: Color(0xFFF4EAD8), accent: Color(0xFFC25A3A)),
    (variant: SagaThemeVariant.terra, label: 'Ember', bg: Color(0xFF8E3A22), accent: Color(0xFFE0A050)),
    (variant: SagaThemeVariant.onyx,  label: 'Onyx',  bg: Color(0xFF000000), accent: Color(0xFFE0A050)),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(sagaThemeVariantProvider);
    return Container(
      color: SagaColors.surface,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: _themes.map((t) {
          final selected = t.variant == current;
          return Expanded(
            child: GestureDetector(
              onTap: () async {
                ref.read(sagaThemeVariantProvider.notifier).state = t.variant;
                await SettingsStore.setThemeIndex(t.variant.index);
                HomeWidgetSync.refresh();
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Column(
                  children: [
                    Container(
                      height: 52,
                      decoration: BoxDecoration(
                        color: t.bg,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: selected
                              ? SagaColors.accent
                              : Colors.transparent,
                          width: 2.5,
                        ),
                        boxShadow: selected
                            ? [BoxShadow(color: SagaColors.accent.withValues(alpha: 0.4), blurRadius: 6)]
                            : null,
                      ),
                      child: Center(
                        child: Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            color: t.accent,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      t.label,
                      style: TextStyle(
                        color: selected ? SagaColors.fg : SagaColors.fgMuted,
                        fontSize: 12,
                        fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
