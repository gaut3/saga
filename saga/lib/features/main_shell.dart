import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import '../core/theme/saga_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/widgets/mini_player_pill.dart';
import 'authors/authors_screen.dart';
import 'browse/browse_screen.dart';
import 'collections/collections_screen.dart';
import 'home/home_screen.dart';
import '../core/providers.dart' show sagaThemeVariantProvider, tabIndexProvider;
import 'player/player_provider.dart';
import 'settings/settings_screen.dart';

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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      ref.read(playerServiceProvider).savePositionForLifecycle();
    } else if (state == AppLifecycleState.resumed) {
      // Back in the foreground — push any positions queued while offline.
      ref.read(playerServiceProvider).flushTimelineQueue();
    }
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
        // Download progress strip — visible only while downloads are active
        if (activeProgress.isNotEmpty)
          LinearProgressIndicator(
            value: dlValue,
            backgroundColor: SagaColors.surfaceAlt,
            valueColor: AlwaysStoppedAnimation<Color>(SagaColors.accent),
            minHeight: 3,
          ),
        // Mini player pill — only when something is loaded
        StreamBuilder<MediaItem?>(
          stream: service.mediaItem,
          builder: (context, snap) {
            if (snap.data == null) return const SizedBox.shrink();
            return MiniPlayerPill(service: service, mediaItem: snap.data!);
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
          ),
        ),
      ],
    );
  }
}

class _NavPill extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onTap;
  final List<({IconData icon, IconData activeIcon, String label})> navItems;

  const _NavPill({
    required this.selectedIndex,
    required this.onTap,
    required this.navItems,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
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
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    selected ? item.activeIcon : item.icon,
                    color: selected ? SagaColors.accent : SagaColors.fgSubtle,
                    size: 22,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.label,
                    style: TextStyle(
                      fontSize: 10,
                      color: selected ? SagaColors.accent : SagaColors.fgSubtle,
                      fontWeight:
                          selected ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }
}
