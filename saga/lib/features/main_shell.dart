import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import '../core/theme/saga_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/diagnostics/app_log.dart';
import '../core/storage/settings_store.dart';
import '../core/update/update_checker.dart';
import '../shared/widgets/mini_player_pill.dart';
import '../shared/widgets/saga_sheet.dart';
import '../shared/widgets/saga_toast.dart';
import '../shared/widgets/swipe_away_pill.dart';
import 'authors/authors_screen.dart';
import 'browse/browse_screen.dart';
import 'collections/collections_screen.dart';
import 'home/home_screen.dart';
import '../core/providers.dart'
    show
        connectivityProvider,
        recheckServerProvider,
        sagaThemeVariantProvider,
        tabIndexProvider;
import 'player/player_provider.dart';
import 'player/player_service.dart';
import 'settings/settings_screen.dart';
import 'widget/home_widget_sync.dart';

class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key});

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell>
    with WidgetsBindingObserver {
  static const _tabCount = 5;

  // One stable navigator key per tab — survives rebuilds.
  final _navKeys = List<GlobalKey<NavigatorState>>.generate(
    _tabCount,
    (_) => GlobalKey<NavigatorState>(),
  );

  /// The release the update toast has already announced this session.
  /// Settings re-runs the check when its toggle flips, and the listener below
  /// can't tell a re-run from a first run — without this, every off/on showed
  /// the same toast again.
  String? _announcedUpdate;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _checkForUpdate();
    });
  }

  /// When the update check last ran this session; null before the first.
  DateTime? _lastUpdateCheck;

  /// Opt-in, default off: one anonymous GET to GitHub when Saga starts, and
  /// again on returning to it once a day has passed. Starts alone weren't
  /// enough: an audiobook player can stay running for days, so a release
  /// went unseen until the next fresh start (GitHub #22). Never blocks; the
  /// result is cached in the provider for Settings and the banner.
  void _checkForUpdate() {
    if (!SettingsStore.updateCheckEnabled) return;
    final last = _lastUpdateCheck;
    if (last != null) {
      if (DateTime.now().difference(last) < const Duration(hours: 24)) return;
      ref.invalidate(updateCheckProvider);
    }
    _lastUpdateCheck = DateTime.now();
    ref.read(updateCheckProvider);
  }

  Timer? _networkRecheck;

  /// The network changed: the saved server address may no longer be the best
  /// one, or reachable at all. One chosen away from home is often unreachable
  /// from inside it, and with a downloaded book playing nothing else would
  /// ask again until the next launch (#24). Waits a moment for the new
  /// network to settle; the re-check is shared with every other caller.
  void _onNetworkChanged() {
    _networkRecheck?.cancel();
    _networkRecheck = Timer(const Duration(seconds: 3), () {
      if (mounted) ref.read(recheckServerProvider)('network changed');
    });
  }

  @override
  void dispose() {
    _networkRecheck?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      // Not awaited (the OS doesn't wait for us), but not unwatched either: this
      // is the save most likely to come just before a kill, and a throw here
      // used to vanish into the zone handler as one anonymous line.
      ref.read(playerServiceProvider).savePositionForLifecycle().catchError(
          (Object e) => AppLog.log('playback', 'lifecycle save failed: $e'));
      // Leaving the app is when the home-screen widget becomes visible, and
      // anything changed in here (a finish marked by hand, cleared progress)
      // reached no player event.
      HomeWidgetSync.refresh();
    } else if (state == AppLifecycleState.resumed) {
      // Back in the foreground — push any positions queued while offline.
      ref.read(playerServiceProvider).flushTimelineQueue();
      // The media session may have been rebuilt while we were away, which
      // leaves it with no title or artwork. Reopening the app is a free moment
      // to heal it, so the lock screen is right without waiting for a play.
      ref.read(playerServiceProvider).republishNowPlaying();
      _checkForUpdate();
    }
  }

  static const _settingsTab = 4;

  /// Settings, scrolled to "Check for updates", whose tap opens the release
  /// on GitHub. Closes the player or a sheet first: the banner shows over
  /// everything, so it can be tapped from anywhere.
  void _openUpdateInSettings() {
    rootNavigatorKey.currentState?.popUntil((r) => r.isFirst);
    _navKeys[_settingsTab].currentState?.popUntil((r) => r.isFirst);
    ref.read(tabIndexProvider.notifier).state = _settingsTab;
    ref.read(revealUpdateRowProvider.notifier).state++;
  }

  static const _navItems = [
    (icon: Icons.home_outlined,    activeIcon: Icons.home,         label: 'Home'),
    (icon: Icons.grid_view_outlined, activeIcon: Icons.grid_view,  label: 'Browse'),
    (icon: Icons.person_outline,   activeIcon: Icons.person,       label: 'Authors'),
    (icon: Icons.folder_outlined,  activeIcon: Icons.folder,       label: 'Collections'),
    (icon: Icons.settings_outlined, activeIcon: Icons.settings,    label: 'Settings'),
  ];

  // Root screens are const — one instance per tab, never rebuilt.
  static const _rootScreens = <Widget>[
    HomeScreen(),
    BrowseScreen(),
    AuthorsScreen(),
    CollectionsScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final selectedIndex = ref.watch(tabIndexProvider);
    ref.watch(sagaThemeVariantProvider);

    // Surface the launch update check — the result was only ever visible in
    // Settings › About, so an enabled check could find an update nobody saw.
    // A banner, not a toast: a 2.5 s toast fired while the app was still
    // opening, and people missed it (GitHub #22). It comes back each launch
    // until it's closed or tapped for that release; once per session at most
    // (see [_announcedUpdate]).
    ref.listen(connectivityProvider, (prev, next) {
      final was = prev?.valueOrNull;
      final now = next.valueOrNull;
      if (was == null || now == null || listEquals(was, now)) return;
      if (now.every((r) => r == ConnectivityResult.none)) return;
      _onNetworkChanged();
    });

    ref.listen(updateCheckProvider, (_, next) {
      final result = next.valueOrNull;
      final tag = result?.latestTag;
      if (result?.isNewer != true || tag == null) return;
      if (tag == _announcedUpdate || tag == SettingsStore.dismissedUpdateTag) {
        return;
      }
      _announcedUpdate = tag;
      showSagaBanner(
        context,
        'Update available: $tag',
        onTap: () {
          SettingsStore.setDismissedUpdateTag(tag);
          _openUpdateInSettings();
        },
        onClose: () => SettingsStore.setDismissedUpdateTag(tag),
      );
    });

    return PopScope(
      // Let the tab's nested navigator consume back-presses first.
      canPop: false,
      onPopInvokedWithResult: (_, _) {
        final nav = _navKeys[selectedIndex].currentState;
        if (nav != null && nav.canPop()) nav.pop();
      },
      child: Scaffold(
        backgroundColor: SagaColors.bg,
        extendBody: true,
        body: IndexedStack(
          index: selectedIndex,
          children: List.generate(
            _tabCount,
            (i) => _TabNavigator(
              key: ValueKey(i),
              navigatorKey: _navKeys[i],
              child: _rootScreens[i],
            ),
          ),
        ),
        bottomNavigationBar: _BottomArea(
          selectedIndex: selectedIndex,
          onTap: (i) {
            if (i == selectedIndex) {
              _navKeys[i].currentState?.popUntil((r) => r.isFirst);
            } else {
              ref.read(tabIndexProvider.notifier).state = i;
            }
          },
          navItems: _navItems,
        ),
      ),
    );
  }
}

// ── Per-tab navigator ─────────────────────────────────────────────────────────
//
// Wrapping each tab in its own Navigator means any Navigator.push() from within
// the tab pushes onto the tab stack, not the root. The shell (nav bar + mini
// player) stays visible. The PlayerScreen is the exception — it is pushed with
// rootNavigator: true so it takes over the full screen as an immersive view.

class _TabNavigator extends StatefulWidget {
  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;

  const _TabNavigator({
    super.key,
    required this.navigatorKey,
    required this.child,
  });

  @override
  State<_TabNavigator> createState() => _TabNavigatorState();
}

class _TabNavigatorState extends State<_TabNavigator> {
  late final HeroController _heroController =
      MaterialApp.createMaterialHeroController();

  @override
  Widget build(BuildContext context) {
    return HeroControllerScope(
      controller: _heroController,
      child: Navigator(
        key: widget.navigatorKey,
        onGenerateInitialRoutes: (_, _) => [
          MaterialPageRoute(builder: (_) => widget.child),
        ],
      ),
    );
  }
}

// ── Bottom area: mini player + nav pill ───────────────────────────────────────

class _BottomArea extends ConsumerWidget {
  final int selectedIndex;
  final ValueChanged<int> onTap;
  final List<({IconData icon, IconData activeIcon, String label})> navItems;

  const _BottomArea({
    required this.selectedIndex,
    required this.onTap,
    required this.navItems,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final service = ref.watch(playerServiceProvider);
    final downloadState = ref.watch(downloadNotifierProvider);
    final bottom = MediaQuery.of(context).padding.bottom;

    final activeProgress = downloadState.progress;
    final dlValue = activeProgress.isEmpty
        ? null
        : activeProgress.values.fold(0.0, (a, b) => a + b) /
            activeProgress.length;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Mini player pill — only when something is loaded. stopAndClear()
        // nulls mediaItem, which is what makes the pill (and the notification)
        // actually go away after a swipe.
        StreamBuilder<MediaItem?>(
          stream: service.mediaItem,
          builder: (context, snap) {
            final item = snap.data;
            if (item == null) return const SizedBox.shrink();
            return SwipeAwayPill(
              // Keyed on the book so dismiss state resets for the next one.
              key: ValueKey(item.id),
              onDismissed: service.stopAndClear,
              onLongPress: () => _showPillOptions(context, service),
              child: MiniPlayerPill(service: service, mediaItem: item),
            );
          },
        ),
        // Nav pill — gradient so content fades behind it
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                SagaColors.bg.withValues(alpha: 0.0),
                SagaColors.bg.withValues(alpha: 0.92),
              ],
              stops: const [0.0, 0.45],
            ),
          ),
          padding: EdgeInsets.fromLTRB(16, 0, 16, bottom + 8),
          child: _NavPill(
            selectedIndex: selectedIndex,
            onTap: onTap,
            navItems: navItems,
            downloadProgress: dlValue,
          ),
        ),
      ],
    );
  }
}

/// Long-press menu for the mini player.
///
/// The swipe is unlabeled by design — the motion carries the meaning — so this
/// is the discoverable, screen-reader-reachable way to stop playback. Long-press
/// on a mini player conventionally means "give me options", which leaves room
/// for queue/speed here later.
void _showPillOptions(BuildContext context, AudioPlayerService service) {
  final bottomPad = MediaQuery.of(context).padding.bottom;
  showSagaSheet(
    context,
    (ctx) => Padding(
      padding: EdgeInsets.only(bottom: bottomPad),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SagaSheetTitle('Now playing',
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8)),
          ListTile(
            leading: Icon(Icons.stop_rounded, color: SagaColors.fgMuted),
            title: Text('Stop playback', style: TextStyle(color: SagaColors.fg)),
            subtitle: Text('Keeps your place — resume from Continue Listening',
                style: TextStyle(color: SagaColors.fgSubtle, fontSize: 12)),
            onTap: () {
              Navigator.pop(ctx);
              service.stopAndClear();
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
    scrollable: false,
  );
}

class _NavPill extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onTap;
  final List<({IconData icon, IconData activeIcon, String label})> navItems;
  final double? downloadProgress;

  const _NavPill({
    required this.selectedIndex,
    required this.onTap,
    required this.navItems,
    this.downloadProgress,
  });

  @override
  Widget build(BuildContext context) {
    final pill = Container(
      height: 60,
      decoration: BoxDecoration(
        color: SagaColors.surface,
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: SagaColors.accentFg.withValues(alpha: 0.4),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: List.generate(navItems.length, (i) {
          final item = navItems[i];
          final selected = i == selectedIndex;
          return Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onTap(i),
              // The active tab is signalled by colour alone on screen;
              // `selected` is that signal for TalkBack.
              child: MergeSemantics(
                child: Semantics(
                  button: true,
                  selected: selected,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        selected ? item.activeIcon : item.icon,
                        // accentText so the icon matches the 12px label
                        // below, which needs the AA text tier.
                        color: selected
                            ? SagaColors.accentText
                            : SagaColors.fgSubtle,
                        size: 22,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        item.label,
                        style: TextStyle(
                          fontSize: 12,
                          color: selected
                              ? SagaColors.accentText
                              : SagaColors.fgSubtle,
                          fontWeight:
                              selected ? FontWeight.w600 : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );

    if (downloadProgress == null) return pill;

    return CustomPaint(
      foregroundPainter: _NavProgressPainter(
        progress: downloadProgress!,
        color: SagaColors.accent,
      ),
      child: pill,
    );
  }
}

class _NavProgressPainter extends CustomPainter {
  final double progress;
  final Color color;

  const _NavProgressPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    const strokeWidth = 2.5;
    const inset = strokeWidth / 2;
    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(inset, inset, size.width - strokeWidth, size.height - strokeWidth),
      const Radius.circular(30 - inset),
    );
    final path = Path()..addRRect(rrect);
    // A degenerate rect (pill smaller than the stroke) yields no contour, and
    // `.first` on empty metrics would throw on every frame of a download.
    final it = path.computeMetrics().iterator;
    if (!it.moveNext()) return;
    final metric = it.current;
    final drawn = metric.extractPath(
        0, metric.length * progress.clamp(0.0, 1.0));
    canvas.drawPath(
      drawn,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..isAntiAlias = true,
    );
  }

  @override
  bool shouldRepaint(_NavProgressPainter old) => old.progress != progress;
}
