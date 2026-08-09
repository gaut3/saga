import 'package:flutter/material.dart';
import '../../core/stats/streak.dart';
import '../../core/storage/listening_history_store.dart';
import '../../core/theme/saga_theme.dart';

// ── Shared helpers ────────────────────────────────────────────────────────────

String historyWeekdayShort(DateTime d) =>
    const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][d.weekday - 1];

String historyMonthAbbr(int month) =>
    const ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
           'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][month - 1];

Color historyHeatColor(int ms) {
  if (ms == 0) return SagaColors.heatEmpty;
  final m = ms ~/ 60000;
  if (m < 15) return SagaColors.heat1;
  if (m < 30) return SagaColors.heat2;
  if (m < 60) return SagaColors.heat3;
  if (m < 120) return SagaColors.heat4;
  return SagaColors.heatMax;
}

({int current, int longest}) computeHistoryStreak() =>
    computeStreak(msForDay: ListeningHistoryStore.getMs);

const TextStyle historyMonoLabel = TextStyle(
  fontSize: 11,
  letterSpacing: 2.0,
  fontWeight: FontWeight.w500,
);

// ── Stat card ─────────────────────────────────────────────────────────────────

class HistoryStatCard extends StatelessWidget {
  final String label;
  final String value;
  const HistoryStatCard({super.key, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: SagaColors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: TextStyle(
              color: SagaColors.fg,
              fontSize: 20,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 2),
          Text(label,
              style: TextStyle(color: SagaColors.fgSubtle, fontSize: 11)),
        ],
      ),
    );
  }
}
