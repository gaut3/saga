import 'package:flutter/material.dart';

import '../../core/theme/saga_theme.dart';
import '../../core/utils/format.dart';

const _weekdayNames = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

/// The Mon-first week bar chart — Home's listening-strip sparkline and
/// History's week card are the same chart at two sizes, and their two
/// hand-rolled copies had already drifted apart in bar colour.
///
/// What is shared here is the *rule set*: a future day and a silent day draw
/// the empty track colour, today draws [todayColor], a listened day draws
/// [activeColor], and bar height scales against the loudest day with a floor
/// so a day with any listening never vanishes. The two call sites keep their
/// deliberate differences as parameters — the week card uses `accentDim`
/// because a 74-px column of full amber is a large fill, which is a size
/// concern, not a rule difference.
///
/// With a [labelBuilder] the bars each carry a caption below and the widget
/// must be given a bounded height; without one it renders bars alone at
/// [maxBarHeight] and needs none.
class WeekBars extends StatelessWidget {
  final List<int> weekMs;
  final List<DateTime> weekDays;
  final DateTime todayClean;
  final double maxBarHeight;
  final double minBarHeight;
  final double barPadding;
  final double cornerRadius;
  final Color todayColor;
  final Color activeColor;

  /// Entrance progress, 0..1, staggered per bar. 1.0 renders settled.
  final double animationValue;

  final Widget Function(int index, bool isToday)? labelBuilder;

  const WeekBars({
    super.key,
    required this.weekMs,
    required this.weekDays,
    required this.todayClean,
    required this.maxBarHeight,
    required this.minBarHeight,
    required this.barPadding,
    required this.cornerRadius,
    required this.todayColor,
    required this.activeColor,
    this.animationValue = 1.0,
    this.labelBuilder,
  });

  @override
  Widget build(BuildContext context) {
    final maxMs = weekMs.fold(0, (a, b) => b > a ? b : a);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: List.generate(7, (i) {
        final ms = weekMs[i];
        final day = weekDays[i];
        final isToday = day == todayClean;
        final isFuture = day.isAfter(todayClean);
        final fraction = maxMs > 0 ? ms / maxMs : 0.0;
        final stagger = ((animationValue - i * 0.04) / (1.0 - i * 0.04))
            .clamp(0.0, 1.0);
        final h = ms > 0
            ? (maxBarHeight * fraction * stagger)
                .clamp(minBarHeight, maxBarHeight)
            : minBarHeight;

        final bar = Container(
          width: double.infinity,
          height: h,
          decoration: BoxDecoration(
            color: isFuture
                ? SagaColors.heatEmpty
                : isToday
                    ? todayColor
                    : ms > 0
                        ? activeColor
                        : SagaColors.heatEmpty,
            borderRadius: BorderRadius.circular(cornerRadius),
          ),
        );

        final label = labelBuilder?.call(i, isToday);
        // The bars are plain Containers — silent under TalkBack without this.
        // Month/year heatmaps already label per cell; the same data shouldn't
        // be readable in one view and invisible in the next. Future days are
        // skipped rather than read as seven "no listening"s.
        final semanticLabel = isFuture
            ? null
            : '${_weekdayNames[day.weekday - 1]}: '
                '${ms > 0 ? fmtListenedMs(ms) : 'no listening'}';
        return Expanded(
          child: Semantics(
            label: semanticLabel,
            excludeSemantics: true,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: barPadding),
              child: label == null
                  ? Align(alignment: Alignment.bottomCenter, child: bar)
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Align(
                              alignment: Alignment.bottomCenter, child: bar),
                        ),
                        const SizedBox(height: 6),
                        label,
                      ],
                    ),
            ),
          ),
        );
      }),
    );
  }
}
