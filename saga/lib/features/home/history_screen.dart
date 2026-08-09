import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers.dart';
import '../../core/theme/saga_theme.dart';
import 'history_day_tab.dart';
import 'history_month_tab.dart';
import 'history_total_tab.dart';

// ── Enum ──────────────────────────────────────────────────────────────────────

enum _Tab { day, month, total }

// ── Root ──────────────────────────────────────────────────────────────────────

class HistoryScreen extends ConsumerStatefulWidget {
  final String? libraryKey;
  const HistoryScreen({super.key, this.libraryKey});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  _Tab _tab = _Tab.day;
  late final PageController _pageController;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _goTo(_Tab t) {
    setState(() => _tab = t);
    _pageController.animateToPage(
      t.index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(sagaThemeVariantProvider);
    return Scaffold(
      backgroundColor: SagaColors.bg,
      body: CustomScrollView(
        physics: const NeverScrollableScrollPhysics(),
        slivers: [
          SliverAppBar(
            pinned: true,
            backgroundColor: Colors.transparent,
            foregroundColor: SagaColors.fg,
            elevation: 0,
            surfaceTintColor: Colors.transparent,
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
            title: const Text('History'),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: _SegControl(tab: _tab, onChanged: _goTo),
              ),
            ],
          ),
          SliverFillRemaining(
            hasScrollBody: true,
            child: PageView(
              controller: _pageController,
              onPageChanged: (i) => setState(() => _tab = _Tab.values[i]),
              children: [
                HistoryDayTab(libraryKey: widget.libraryKey),
                HistoryMonthTab(
                    key: const PageStorageKey('month'),
                    libraryKey: widget.libraryKey),
                HistoryTotalTab(libraryKey: widget.libraryKey),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Segmented control ─────────────────────────────────────────────────────────

class _SegControl extends StatelessWidget {
  final _Tab tab;
  final ValueChanged<_Tab> onChanged;
  const _SegControl({required this.tab, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: SagaColors.surface,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: _Tab.values.map((t) {
          final selected = tab == t;
          final label = switch (t) {
            _Tab.day => 'Day',
            _Tab.month => 'Month',
            _Tab.total => 'Total',
          };
          final animDuration = MediaQuery.of(context).disableAnimations
              ? Duration.zero
              : const Duration(milliseconds: 200);
          return GestureDetector(
            onTap: () => onChanged(t),
            child: AnimatedContainer(
              duration: animDuration,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: selected ? SagaColors.accent : Colors.transparent,
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text(
                label,
                style: TextStyle(
                  color: selected ? SagaColors.accentFg : SagaColors.fgMuted,
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
