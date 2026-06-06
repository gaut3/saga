import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../../core/theme/saga_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/mark_motion.dart';
import '../../core/plex/plex_client.dart';
import '../../core/utils/format.dart';
import '../../core/plex/models/plex_library.dart';
import '../../core/providers.dart';
import '../../core/storage/bookmark_store.dart';
import '../../core/storage/completed_books_store.dart';
import '../../core/storage/listen_days_store.dart';
import '../../core/storage/listening_history_store.dart';
import '../../core/storage/named_bookmark_store.dart';
import '../../core/storage/playback_log_store.dart';
import '../../core/storage/progress_backup.dart';
import '../../core/storage/settings_store.dart';
import '../auth/server_selection_screen.dart';
import '../player/player_provider.dart';
import '../../shared/widgets/saga_mark.dart' show SagaWordmark, SagaMark;
import '../../shared/widgets/saga_sheet.dart';
import '../../shared/widgets/saga_toast.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  static const _skipOptions = [15, 30, 45, 60];
  static const _speedOptions = [0.75, 1.0, 1.25, 1.5, 2.0];

  late int _skipForward;
  late int _skipBackward;
  late double _defaultSpeed;
  late bool _autoRewind;
  late bool _wifiOnly;
  late int _markMotion;
  String _version = '';

  @override
  void initState() {
    super.initState();
    _skipForward = SettingsStore.skipForwardSeconds;
    _skipBackward = SettingsStore.skipBackwardSeconds;
    _defaultSpeed = SettingsStore.defaultSpeed;
    _autoRewind = SettingsStore.autoRewindEnabled;
    _wifiOnly = SettingsStore.downloadWifiOnly;
    _markMotion = SettingsStore.markMotionIndex;
    PackageInfo.fromPlatform().then((info) {
      if (mounted) setState(() => _version = 'v${info.version}');
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(sagaThemeVariantProvider);
    final client = ref.watch(plexClientProvider);

    return Scaffold(
      backgroundColor: SagaColors.bg,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            backgroundColor: Colors.transparent,
            foregroundColor: SagaColors.fg,
            elevation: 0,
            surfaceTintColor: Colors.transparent,
            shadowColor: Colors.transparent,
            flexibleSpace: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [SagaColors.bg, SagaColors.bg.withValues(alpha: 0.0)],
                  stops: const [0.6, 1.0],
                ),
              ),
            ),
            title: Text('Settings',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 22)),
          ),
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8),

                // ── Appearance ────────────────────────────────────────────────
                _SectionHeader('Appearance'),
                _ThemePicker(),
                const SizedBox(height: 16),

                // ── Playback ──────────────────────────────────────────────────
                _SectionHeader('Playback'),
                _SegmentedTile(
                  icon: Icons.replay_rounded,
                  title: 'Skip back',
                  options: _skipOptions.map((s) => '${s}s').toList(),
                  selectedIndex:
                      _skipOptions.indexOf(_skipBackward).clamp(0, 3),
                  onChanged: (i) async {
                    final v = _skipOptions[i];
                    await SettingsStore.setSkipBackward(v);
                    setState(() => _skipBackward = v);
                  },
                ),
                _SegmentedTile(
                  icon: Icons.fast_forward_rounded,
                  title: 'Skip forward',
                  options: _skipOptions.map((s) => '${s}s').toList(),
                  selectedIndex:
                      _skipOptions.indexOf(_skipForward).clamp(0, 3),
                  onChanged: (i) async {
                    final v = _skipOptions[i];
                    await SettingsStore.setSkipForward(v);
                    setState(() => _skipForward = v);
                  },
                ),
                _SegmentedTile(
                  icon: Icons.speed,
                  title: 'Default speed',
                  options: _speedOptions.map((s) => '${s}x').toList(),
                  selectedIndex:
                      _speedOptions.indexOf(_defaultSpeed).clamp(0, 4),
                  onChanged: (i) async {
                    final v = _speedOptions[i];
                    await SettingsStore.setDefaultSpeed(v);
                    setState(() => _defaultSpeed = v);
                    // Apply immediately if player is active
                    final service = ref.read(playerServiceProvider);
                    service.setSpeed(v);
                    ref.read(playbackSpeedProvider.notifier).state = v;
                  },
                ),
                _SegmentedTile(
                  icon: Icons.graphic_eq_rounded,
                  title: 'Player animation',
                  options: const ['Reactive', 'Gentle', 'Pause'],
                  selectedIndex: _markMotion.clamp(0, 2),
                  onChanged: (i) async {
                    await setMarkMotion(MarkMotion.values[i]);
                    setState(() => _markMotion = i);
                  },
                ),
                _SwitchTile(
                  icon: Icons.history_rounded,
                  title: 'Auto-rewind on resume',
                  subtitle: 'Rewind slightly when resuming playback',
                  value: _autoRewind,
                  onChanged: (v) async {
                    await SettingsStore.setAutoRewindEnabled(v);
                    setState(() => _autoRewind = v);
                  },
                ),
                const SizedBox(height: 16),

                // ── Downloads ─────────────────────────────────────────────────
                _SectionHeader('Downloads'),
                _SwitchTile(
                  icon: Icons.wifi_rounded,
                  title: 'Download on Wi-Fi only',
                  subtitle: 'Don\'t use mobile data for downloads',
                  value: _wifiOnly,
                  onChanged: (v) async {
                    await SettingsStore.setDownloadWifiOnly(v);
                    setState(() => _wifiOnly = v);
                  },
                ),
                const SizedBox(height: 16),

                // ── Server ─────────────────────────────────────────────────────
                _SectionHeader('Server'),
                _SettingsTile(
                  icon: Icons.dns_outlined,
                  title: 'Plex Server',
                  subtitle: client.serverUri ?? 'Not connected',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const ServerSelectionScreen()),
                  ).then((_) => ref.invalidate(activeLibraryKeyProvider)),
                ),
                _LibraryPickerTile(),
                const SizedBox(height: 16),

                // ── Data ───────────────────────────────────────────────────────
                _SectionHeader('Data & Backup'),
                _SettingsTile(
                  icon: Icons.upload_outlined,
                  title: 'Export progress',
                  subtitle: 'Share a backup of your listening positions and bookmarks',
                  onTap: _exportProgress,
                ),
                _SettingsTile(
                  icon: Icons.download_outlined,
                  title: 'Import progress',
                  subtitle: 'Restore from an exported backup file',
                  onTap: _importProgress,
                ),
                _SettingsTile(
                  icon: Icons.delete_sweep_outlined,
                  title: 'Clear listening progress',
                  subtitle: 'Remove all bookmarks and resume positions',
                  iconColor: Colors.orangeAccent,
                  onTap: _confirmClearProgress,
                ),
                const SizedBox(height: 16),

                // ── Account ────────────────────────────────────────────────────
                _SectionHeader('Account'),
                _SettingsTile(
                  icon: Icons.logout,
                  title: 'Sign Out',
                  subtitle: 'Sign out of your Plex account',
                  iconColor: Colors.redAccent,
                  onTap: () => _confirmSignOut(ref),
                ),
                const SizedBox(height: 16),

                // ── About ──────────────────────────────────────────────────────
                _SectionHeader('About'),
                _SettingsTile(
                  icon: Icons.lock_outline,
                  title: 'Privacy',
                  subtitle: 'Local-first · nothing leaves your devices',
                  onTap: () =>
                      _showInfoSheet(context, 'Privacy', _privacyText),
                ),
                _SettingsTile(
                  icon: Icons.description_outlined,
                  title: 'Terms',
                  subtitle: 'Unofficial Plex client · provided as-is',
                  onTap: () => _showInfoSheet(context, 'Terms', _termsText),
                ),
                _SettingsTile(
                  icon: Icons.favorite_outline,
                  title: 'Acknowledgements',
                  subtitle: 'Open-source licenses & thanks',
                  onTap: () => _showAcknowledgements(context),
                ),
                const SizedBox(height: 36),

                // Brand footer — the actual app/launcher icon + wordmark.
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(15),
                        child: Image.asset(
                          'assets/icons/ic_launcher.png',
                          width: 62,
                          height: 62,
                          cacheWidth: 124,
                        ),
                      ),
                      const SizedBox(height: 12),
                      const SagaWordmark(fontSize: 22),
                      const SizedBox(height: 6),
                      Text(_version,
                          style: TextStyle(
                              color: SagaColors.fgSubtle, fontSize: 12)),
                    ],
                  ),
                ),
                SizedBox(height: MediaQuery.of(context).padding.bottom + 160),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _exportProgress() async {
    try {
      await ProgressBackup.export();
    } catch (e) {
      if (mounted) showSagaToast(context, 'Export failed: $e', isError: true);
    }
  }

  Future<void> _importProgress() async {
    try {
      final data = await ProgressBackup.pickAndParse();
      if (data == null || !mounted) return;

      // Warn if the backup came from a different Plex server. Plex ratingKeys
      // are per-server integers — restoring across servers can silently overwrite
      // positions for unrelated books that happen to share the same integer key.
      final backupId = data.serverMachineIdentifier;
      final localId = PlexClient.instance.machineIdentifier;
      if (backupId != null && localId != null && backupId != localId) {
        final proceed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            backgroundColor: SagaColors.surface,
            title: Text('Different server',
                style: TextStyle(color: SagaColors.fg)),
            content: Text(
              'This backup is from a different Plex server. '
              'Book IDs may overlap, so restoring could overwrite positions '
              'for unrelated books. Continue anyway?',
              style: TextStyle(color: SagaColors.fgMuted),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text('Continue',
                    style: TextStyle(color: SagaColors.accent)),
              ),
            ],
          ),
        );
        if (proceed != true || !mounted) return;
      }

      final conflicts = ProgressBackup.detectConflicts(data);
      Set<String>? skipKeys;

      if (conflicts.isEmpty) {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            backgroundColor: SagaColors.surface,
            title: Text('Restore progress',
                style: TextStyle(color: SagaColors.fg)),
            content: Text(
              'Restore ${data.positions.length} listening position${data.positions.length == 1 ? '' : 's'}, '
              '${data.completed.length} completed, '
              '${data.namedBookmarks.length} bookmark${data.namedBookmarks.length == 1 ? '' : 's'}?',
              style: TextStyle(color: SagaColors.fgMuted),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text('Restore',
                    style: TextStyle(color: SagaColors.accent)),
              ),
            ],
          ),
        );
        if (confirmed != true) return;
        skipKeys = const {};
      } else {
        skipKeys = await showDialog<Set<String>>(
          context: context,
          builder: (_) => _ConflictResolutionDialog(
            conflicts: conflicts,
            nonConflictCount: data.positions.length - conflicts.length,
          ),
        );
      }

      if (skipKeys == null || !mounted) return;

      await ProgressBackup.restore(data, skipPositionKeys: skipKeys);
      ref.read(completionRevisionProvider.notifier).state++;
      ref.read(bookmarkRevisionProvider.notifier).state++;

      if (mounted) showSagaToast(context, 'Progress restored');
    } catch (e) {
      if (mounted) showSagaToast(context, 'Import failed: $e', isError: true);
    }
  }

  Future<void> _confirmClearProgress() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: SagaColors.surface,
        title: Text('Clear progress', style: TextStyle(color: SagaColors.fg)),
        content: Text(
          'This will permanently erase:\n'
          '• All listening positions\n'
          '• Listening history, streaks and heatmap\n'
          '• Completed-book records\n'
          '• Named bookmarks\n'
          '• Session logs\n\n'
          'This cannot be undone.',
          style: TextStyle(color: SagaColors.fgMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Clear all',
                style: TextStyle(color: Colors.orangeAccent)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await BookmarkStore.clearAll();
      await CompletedBooksStore.clearAll();
      await ListeningHistoryStore.clearAll();
      await NamedBookmarkStore.clearAll();
      await PlaybackLogStore.clearAll();
      await ListenDaysStore.clearAll();
      if (!mounted) return;
      ref.read(bookmarkRevisionProvider.notifier).state++;
      ref.read(completionRevisionProvider.notifier).state++;
      ref.read(historyRevisionProvider.notifier).state++;
      showSagaToast(context, 'Listening progress cleared');
    }
  }

  Future<void> _confirmSignOut(WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: SagaColors.surface,
        title: Text('Sign out', style: TextStyle(color: SagaColors.fg)),
        content: Text('Sign out of your Plex account?',
            style: TextStyle(color: SagaColors.fgMuted)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sign out',
                style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(plexClientProvider).clearAuth();
      ref.read(isAuthenticatedProvider.notifier).state = false;
    }
  }

  void _showInfoSheet(BuildContext context, String title, String body) {
    final bottomPad = MediaQuery.of(context).padding.bottom;
    showSagaSheet(context, (ctx) => Padding(
        padding: EdgeInsets.only(bottom: bottomPad),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
              child: Text(title,
                  style: TextStyle(
                      color: SagaColors.fg,
                      fontWeight: FontWeight.bold,
                      fontSize: 18)),
            ),
            ConstrainedBox(
              constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(ctx).size.height * 0.7),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: Text(body,
                    style: TextStyle(
                        color: SagaColors.fgMuted, fontSize: 14, height: 1.55)),
              ),
            ),
          ],
        ),
      ));
  }

  void _showAcknowledgements(BuildContext context) {
    const credits = <(String, String)>[
      ('just_audio', 'audio playback engine'),
      ('audio_service', 'background playback & media notification'),
      ('audio_session', 'audio focus & interruptions'),
      ('flutter_riverpod', 'state management'),
      ('hive', 'encrypted on-device storage'),
      ('dio', 'networking'),
      ('cached_network_image', 'cover-art caching'),
      ('connectivity_plus', 'network status'),
      ('flutter_secure_storage', 'key storage'),
    ];
    final bottomPad = MediaQuery.of(context).padding.bottom;
    showSagaSheet(context, (ctx) => Padding(
        padding: EdgeInsets.only(bottom: bottomPad),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
              child: Text('Acknowledgements',
                  style: TextStyle(
                      color: SagaColors.fg,
                      fontWeight: FontWeight.bold,
                      fontSize: 18)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text(
                  'Saga stands on a lot of open-source work — thank you to the '
                  'maintainers of, among others:',
                  style: TextStyle(
                      color: SagaColors.fgMuted, fontSize: 13.5, height: 1.5)),
            ),
            ...credits.map((c) => Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(c.$1,
                          style: TextStyle(
                              color: SagaColors.fg,
                              fontSize: 14,
                              fontWeight: FontWeight.w600)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(c.$2,
                            style: TextStyle(
                                color: SagaColors.fgSubtle, fontSize: 12)),
                      ),
                    ],
                  ),
                )),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  showLicensePage(
                    context: context,
                    applicationName: 'Saga',
                    applicationVersion: _version,
                    applicationIcon: const Padding(
                      padding: EdgeInsets.all(12),
                      child: SagaMark(size: 56),
                    ),
                  );
                },
                child: Text('View all licenses',
                    style: TextStyle(color: SagaColors.accent)),
              ),
            ),
          ],
        ),
      ));
  }

  static const _privacyText =
      'Saga is local-first and built to keep your data yours.\n\n'
      '• Your positions, bookmarks, listening history, downloads and settings live '
      'only on this device, encrypted at rest.\n\n'
      '• The only servers Saga talks to are your own Plex server (to browse and '
      'stream your library) and plex.tv (to sign in).\n\n'
      '• No analytics, no tracking, no advertising, no telemetry — nothing is sent '
      'to us or any third party.\n\n'
      '• Saga requests no microphone, camera, contacts, or location access. Even the '
      'now-playing visualizer reads the audio in-process — never the microphone.';

  static const _termsText =
      'Saga is an independent, unofficial client for Plex Media Server. It is not '
      'affiliated with, endorsed by, or sponsored by Plex, Inc.\n\n'
      'Saga is provided as-is, without warranty of any kind. You are responsible for '
      'your own Plex server, account, and content, and for complying with the terms '
      'of any service you connect to.\n\n'
      '“Plex” is a trademark of Plex, Inc., used here only to describe compatibility.';
}

// ── Shared widgets ─────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          color: SagaColors.fgSubtle,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color? iconColor;
  final VoidCallback onTap;

  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: SagaColors.surface,
      child: ListTile(
        leading: Icon(icon, color: iconColor ?? SagaColors.accent),
        title: Text(title, style: TextStyle(color: SagaColors.fg)),
        subtitle: Text(
          subtitle,
          style: TextStyle(color: SagaColors.fgSubtle, fontSize: 12),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Icon(Icons.chevron_right, color: SagaColors.fgSubtle),
        onTap: onTap,
      ),
    );
  }
}

class _ThemePicker extends ConsumerWidget {
  const _ThemePicker();

  static const _themes = [
    (variant: SagaThemeVariant.ink,   label: 'Ink',   bg: Color(0xFF1E1410), accent: Color(0xFFE0A050)),
    (variant: SagaThemeVariant.cream, label: 'Cream', bg: Color(0xFFF4EAD8), accent: Color(0xFFC25A3A)),
    (variant: SagaThemeVariant.terra, label: 'Terra', bg: Color(0xFFC25A3A), accent: Color(0xFF1E1410)),
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

class _SegmentedTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final List<String> options;
  final int selectedIndex;
  final ValueChanged<int> onChanged;

  const _SegmentedTile({
    required this.icon,
    required this.title,
    required this.options,
    required this.selectedIndex,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: SagaColors.surface,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(icon, color: SagaColors.accent, size: 22),
          const SizedBox(width: 16),
          Expanded(
            child: Text(title,
                style: TextStyle(color: SagaColors.fg, fontSize: 16)),
          ),
          ToggleButtons(
            isSelected: List.generate(
                options.length, (i) => i == selectedIndex),
            onPressed: onChanged,
            borderColor: SagaColors.border,
            selectedBorderColor: SagaColors.accent,
            selectedColor: SagaColors.accentFg,
            fillColor: SagaColors.accent,
            color: SagaColors.fgMuted,
            borderRadius: BorderRadius.circular(8),
            constraints:
                const BoxConstraints(minWidth: 44, minHeight: 32),
            children: options
                .map((o) => Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Text(o, style: const TextStyle(fontSize: 12)),
                    ))
                .toList(),
          ),
        ],
      ),
    );
  }
}

class _SwitchTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SwitchTile({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: SagaColors.surface,
      child: SwitchListTile(
        secondary: Icon(icon, color: SagaColors.accent),
        title: Text(title, style: TextStyle(color: SagaColors.fg)),
        subtitle: subtitle != null
            ? Text(subtitle!,
                style: TextStyle(color: SagaColors.fgSubtle, fontSize: 12))
            : null,
        value: value,
        onChanged: onChanged,
        // On: amber. Off: Saga-themed instead of Material's white/grey default.
        activeThumbColor: SagaColors.accent,
        inactiveThumbColor: SagaColors.fgMuted,
        inactiveTrackColor: SagaColors.surfaceAlt,
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? Colors.transparent
              : SagaColors.border,
        ),
      ),
    );
  }
}

// ── Library picker ────────────────────────────────────────────────────────────

class _LibraryPickerTile extends ConsumerWidget {
  const _LibraryPickerTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final librariesAsync = ref.watch(librariesProvider);
    final selectedKey = ref.watch(selectedLibraryKeyProvider);

    final subtitle = librariesAsync.when(
      loading: () => 'Loading…',
      error: (_, _) => 'Could not load libraries',
      data: (libs) {
        if (libs.isEmpty) return 'No libraries found';
        if (selectedKey == null) return libs.first.title;
        return libs
                .firstWhere((l) => l.key == selectedKey,
                    orElse: () => libs.first)
                .title;
      },
    );

    return _SettingsTile(
      icon: Icons.library_books_outlined,
      title: 'Active Library',
      subtitle: subtitle,
      onTap: () => _showPicker(context, ref,
          librariesAsync.valueOrNull ?? [], selectedKey),
    );
  }

  void _showPicker(BuildContext context, WidgetRef ref,
      List<PlexLibrary> libraries, String? selectedKey) {
    if (libraries.isEmpty) return;
    final bottomPad = MediaQuery.of(context).padding.bottom;
    showSagaSheet<void>(context, (_) => Padding(
        padding: EdgeInsets.fromLTRB(0, 24, 0, 24 + bottomPad),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text('Select Library',
                  style: TextStyle(
                      color: SagaColors.fg,
                      fontSize: 18,
                      fontWeight: FontWeight.bold)),
            ),
            ...libraries.map((lib) {
              final isSelected = selectedKey == lib.key ||
                  (selectedKey == null && lib == libraries.first);
              return ListTile(
                leading: Icon(
                  Icons.library_music_outlined,
                  color: isSelected ? SagaColors.accent : SagaColors.fgMuted,
                ),
                title: Text(lib.title,
                    style: TextStyle(
                        color: isSelected ? SagaColors.accent : SagaColors.fg,
                        fontWeight: isSelected
                            ? FontWeight.bold
                            : FontWeight.normal)),
                trailing: isSelected
                    ? Icon(Icons.check, color: SagaColors.accent)
                    : null,
                onTap: () async {
                  await SettingsStore.setSelectedLibraryKey(lib.key);
                  ref.read(selectedLibraryKeyProvider.notifier).state =
                      lib.key;
                  ref.invalidate(activeLibraryKeyProvider);
                  if (context.mounted) Navigator.pop(context);
                },
              );
            }),
          ],
        ),
      ), scrollable: false);
  }
}

// ── Backup conflict resolution ─────────────────────────────────────────────────

class _ConflictResolutionDialog extends StatefulWidget {
  final List<PositionConflict> conflicts;
  final int nonConflictCount;

  const _ConflictResolutionDialog({
    required this.conflicts,
    required this.nonConflictCount,
  });

  @override
  State<_ConflictResolutionDialog> createState() =>
      _ConflictResolutionDialogState();
}

class _ConflictResolutionDialogState
    extends State<_ConflictResolutionDialog> {
  // Keys whose local position the user wants to keep (not overwritten).
  // Defaults to all conflict keys — "keep current" is the safe default.
  late final Set<String> _keepLocal;

  @override
  void initState() {
    super.initState();
    _keepLocal = widget.conflicts.map((c) => c.bookKey).toSet();
  }

  bool get _allKeep => _keepLocal.length == widget.conflicts.length;
  bool get _allRestore => _keepLocal.isEmpty;

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  String _fmtDate(DateTime dt) => '${_months[dt.month - 1]} ${dt.day}';

  @override
  Widget build(BuildContext context) {
    final n = widget.conflicts.length;
    final showBulk = n > 3;
    return AlertDialog(
      backgroundColor: SagaColors.surface,
      title: Text('Restore progress', style: TextStyle(color: SagaColors.fg)),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$n book${n == 1 ? '' : 's'} '
              'ha${n == 1 ? 's' : 've'} a newer local position than this backup.',
              style: TextStyle(color: SagaColors.fgMuted, fontSize: 13),
            ),
            if (widget.nonConflictCount > 0) ...[
              const SizedBox(height: 4),
              Text(
                '${widget.nonConflictCount} other position'
                '${widget.nonConflictCount == 1 ? '' : 's'} '
                'will be restored automatically.',
                style: TextStyle(color: SagaColors.fgSubtle, fontSize: 12),
              ),
            ],
            if (showBulk) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  _bulkChip('Keep all current', _allKeep,
                      () => setState(() => _keepLocal.addAll(
                          widget.conflicts.map((c) => c.bookKey)))),
                  const SizedBox(width: 8),
                  _bulkChip('Restore all', _allRestore,
                      () => setState(() => _keepLocal.clear())),
                ],
              ),
            ],
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 280),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: widget.conflicts.length,
                separatorBuilder: (_, _) => Divider(
                  color: SagaColors.border,
                  height: 1,
                  thickness: 0.5,
                ),
                itemBuilder: (_, i) => _conflictTile(widget.conflicts[i]),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () =>
              Navigator.pop(context, Set<String>.from(_keepLocal)),
          child: Text('Restore', style: TextStyle(color: SagaColors.accent)),
        ),
      ],
    );
  }

  Widget _bulkChip(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected
              ? SagaColors.accent.withValues(alpha: 0.15)
              : SagaColors.surfaceAlt,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected
                ? SagaColors.accent
                : SagaColors.fgSubtle.withValues(alpha: 0.3),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? SagaColors.accent : SagaColors.fgMuted,
            fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _conflictTile(PositionConflict c) {
    final keepLocal = _keepLocal.contains(c.bookKey);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Book #${c.bookKey}',
            style: TextStyle(
                color: SagaColors.fg,
                fontSize: 13,
                fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: _positionChip(
                  label: 'Keep current',
                  pos: c.local,
                  selected: keepLocal,
                  onTap: () => setState(() => _keepLocal.add(c.bookKey)),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _positionChip(
                  label: 'Restore',
                  pos: c.backup,
                  selected: !keepLocal,
                  onTap: () => setState(() => _keepLocal.remove(c.bookKey)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _positionChip({
    required String label,
    required BookPosition pos,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? SagaColors.accent.withValues(alpha: 0.12)
              : SagaColors.surfaceAlt,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected
                ? SagaColors.accent
                : SagaColors.fgSubtle.withValues(alpha: 0.25),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (selected) ...[
                  Icon(Icons.check_circle, color: SagaColors.accent, size: 11),
                  const SizedBox(width: 3),
                ],
                Text(
                  label,
                  style: TextStyle(
                    color: selected ? SagaColors.accent : SagaColors.fgSubtle,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              fmtDurationMs(pos.absolutePositionMs),
              style: TextStyle(color: SagaColors.fg, fontSize: 12),
            ),
            Text(
              _fmtDate(pos.savedAt),
              style: TextStyle(color: SagaColors.fgSubtle, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}
