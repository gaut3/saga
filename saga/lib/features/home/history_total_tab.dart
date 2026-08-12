import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/plex/models/plex_book.dart';
import '../../core/providers.dart';
import '../../core/storage/listening_history_store.dart';
import '../../core/theme/saga_theme.dart';
import '../../shared/widgets/book_cover_image.dart';
import '../library/book_detail_screen.dart';
import 'history_shared.dart';
import '../../core/utils/date_math.dart';
import '../../core/utils/format.dart';

// ── TOTAL TAB ─────────────────────────────────────────────────────────────────

class HistoryTotalTab extends ConsumerWidget {
  final String? libraryKey;
  const HistoryTotalTab({super.key, this.libraryKey});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = DateTime.now();
    final todayClean = dayOnly(today);

    // Listening-history aggregates (local, always available)
    final allData = ListeningHistoryStore.exportAll();
    int totalMs = 0;
    int activeDays = 0;
    int bestMs = 0;
    for (final entry in allData.entries) {
      if (entry.key.startsWith('t_')) {
        final ms = (entry.value as num).toInt();
        if (ms > 0) {
          totalMs += ms;
          activeDays++;
          if (ms > bestMs) bestMs = ms;
        }
      }
    }
    final avgDayMs = activeDays > 0 ? totalMs ~/ activeDays : 0;
    final totalHours = totalMs ~/ 3600000;

    // Streak
    final longestStreak = computeHistoryStreak().longest;

    // 13-week heatmap
    final heatStart = heatmapStart(todayClean);
    final heatData = ListeningHistoryStore.getRange(heatStart, todayClean);

    // Riverpod data (requires libraryKey)
    final completedAsync = libraryKey != null
        ? ref.watch(completedBooksListProvider(libraryKey!))
        : const AsyncValue<List<PlexBook>>.data([]);

    final completedBooks = completedAsync.valueOrNull ?? [];

    final bottomPad = MediaQuery.of(context).padding.bottom;
    return ListView(
      padding: EdgeInsets.fromLTRB(20, 12, 20, bottomPad + 16),
      children: [
        // Lifetime stats
        Text('LIFETIME',
            style: historyMonoLabel.copyWith(color: SagaColors.fgSubtle)),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
                child: HistoryStatCard(
                    label: 'Books finished',
                    value: '${completedBooks.length}')),
            const SizedBox(width: 10),
            Expanded(
                child:
                    HistoryStatCard(label: 'Total hours', value: '$totalHours')),
            const SizedBox(width: 10),
            Expanded(
                child: HistoryStatCard(
                    label: 'Avg / active day',
                    value: avgDayMs > 0 ? fmtListenedMs(avgDayMs) : '–')),
          ],
        ),

        // Finished books horizontal shelf
        if (completedBooks.isNotEmpty) ...[
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('FINISHED BOOKS',
                  style: historyMonoLabel.copyWith(color: SagaColors.fgSubtle)),
              Text('${completedBooks.length}',
                  style:
                      TextStyle(color: SagaColors.fgSubtle, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 112,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: completedBooks.length,
              separatorBuilder: (context2, i2) =>
                  const SizedBox(width: 10),
              itemBuilder: (ctx, i) {
                final book = completedBooks[i];
                return GestureDetector(
                  onTap: () => Navigator.push(
                    ctx,
                    MaterialPageRoute(
                        builder: (c) => BookDetailScreen(book: book)),
                  ),
                  child: SizedBox(
                    width: 82,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: SizedBox(
                            width: 82,
                            height: 82,
                            child: BookCoverImage(
                                thumbPath: book.thumbPath,
                                cacheWidth: kCoverCacheWidthThumb),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Expanded(
                          child: Text(
                            book.title,
                            style: TextStyle(
                                color: SagaColors.fgMuted, fontSize: 10),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],

        // 13-week heatmap
        const SizedBox(height: 24),
        _HeatmapCard(
            data: heatData, todayClean: todayClean, heatStart: heatStart),

        // Records
        const SizedBox(height: 16),
        Text('RECORDS',
            style: historyMonoLabel.copyWith(color: SagaColors.fgSubtle)),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _RecordCard(
                icon: Icons.local_fire_department,
                label: 'Longest streak',
                value: '$longestStreak day${longestStreak == 1 ? '' : 's'}',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _RecordCard(
                icon: Icons.bolt,
                label: 'Best day',
                value: bestMs > 0 ? fmtListenedMs(bestMs) : '–',
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ── 13-week heatmap ───────────────────────────────────────────────────────────

class _HeatmapCard extends StatelessWidget {
  final Map<DateTime, int> data;
  final DateTime todayClean;
  final DateTime heatStart;

  static const _cols = 13;
  static const _rows = 7;
  static const _gap = 4.0;

  const _HeatmapCard({
    required this.data,
    required this.todayClean,
    required this.heatStart,
  });

  @override
  Widget build(BuildContext context) {
    final totalMs = data.values.fold(0, (a, b) => a + b);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: SagaColors.surface,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('LAST 13 WEEKS',
              style: historyMonoLabel.copyWith(color: SagaColors.fgSubtle)),
          const SizedBox(height: 4),
          Text(
            totalMs > 0 ? '${totalMs ~/ 3600000}h total' : 'No activity',
            style: TextStyle(
                color: SagaColors.fg,
                fontSize: 14,
                fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 14),
          LayoutBuilder(builder: (context, constraints) {
            final w = constraints.maxWidth;
            final cellW = (w - (_cols - 1) * _gap) / _cols;
            final cellH = (cellW * _rows + (_rows - 1) * _gap) / _rows;

            return Row(
              children: List.generate(_cols, (col) {
                return Padding(
                  padding:
                      EdgeInsets.only(right: col < _cols - 1 ? _gap : 0),
                  child: Column(
                    children: List.generate(_rows, (row) {
                      final date = addDays(heatStart, col * 7 + row);
                      final isFuture = date.isAfter(todayClean);
                      final isToday = date == todayClean;
                      final ms =
                          isFuture ? 0 : (data[date] ?? 0);
                      return Padding(
                        padding: EdgeInsets.only(
                            bottom: row < _rows - 1 ? _gap : 0),
                        child: Semantics(
                          label: isFuture
                              ? null
                              : ms > 0
                                  ? '${historyMonthAbbr(date.month)} ${date.day}: ${ms ~/ 60000} min'
                                  : '${historyMonthAbbr(date.month)} ${date.day}: no activity',
                          child: Container(
                            width: cellW,
                            height: cellH,
                            decoration: BoxDecoration(
                              color: isFuture
                                  ? Colors.transparent
                                  : historyHeatColor(ms),
                              borderRadius: BorderRadius.circular(3),
                              border: isToday
                                  ? Border.all(
                                      color: SagaColors.accent, width: 1.5)
                                  : null,
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                );
              }),
            );
          }),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text('0 ',
                  style: TextStyle(
                      color: SagaColors.fgSubtle, fontSize: 10)),
              ...[
                (SagaColors.heatEmpty, 'No activity'),
                (SagaColors.heat1, '1–14 min'),
                (SagaColors.heat2, '15–29 min'),
                (SagaColors.heat3, '30–59 min'),
                (SagaColors.heat4, '1–2 hours'),
                (SagaColors.heatMax, 'Over 2 hours'),
              ].map((e) => Semantics(
                    label: e.$2,
                    child: Container(
                      width: 11,
                      height: 11,
                      margin: const EdgeInsets.only(left: 3),
                      decoration: BoxDecoration(
                          color: e.$1,
                          borderRadius: BorderRadius.circular(2)),
                    ),
                  )),
              Text(' 2h+',
                  style: TextStyle(
                      color: SagaColors.fgSubtle, fontSize: 10)),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Record card ───────────────────────────────────────────────────────────────

class _RecordCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _RecordCard(
      {required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: SagaColors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(icon, color: SagaColors.accent, size: 18),
          const SizedBox(width: 11),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: TextStyle(
                  color: SagaColors.fg,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 2),
              Text(label,
                  style: TextStyle(
                    color: SagaColors.fgSubtle,
                    fontSize: 10,
                    letterSpacing: 1.5,
                    fontWeight: FontWeight.w500,
                  )),
            ],
          ),
        ],
      ),
    );
  }
}
