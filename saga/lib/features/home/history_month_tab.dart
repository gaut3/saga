import 'dart:math' show max;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/plex/models/plex_book.dart';
import '../../core/providers.dart';
import '../../core/storage/bookmark_store.dart';
import '../../core/storage/completed_books_store.dart';
import '../../core/storage/listening_history_store.dart';
import '../../core/storage/named_bookmark_store.dart';
import '../../shared/widgets/saga_sheet.dart';
import '../../core/theme/saga_theme.dart';
import '../../shared/widgets/book_cover_image.dart';
import '../../core/book_progress.dart';
import 'history_data.dart';
import 'history_shared.dart';
import '../../core/utils/date_math.dart';
import '../../core/utils/format.dart';

/// Readable day-number colour for a heat cell. The cell colour already encodes
/// the theme (terra's ramp runs to cream, ink/cream's max cells get bright), so
/// we contrast against the cell itself — muted ink on light cells, muted cream
/// on dark ones — rather than a single fixed tone that vanishes at one end.
Color _heatTextColor(int ms) =>
    historyHeatColor(ms).computeLuminance() > 0.42
        ? const Color(0xCC1E1410) // muted ink
        : const Color(0xCCF4EAD8); // muted cream

// ── MONTH TAB ─────────────────────────────────────────────────────────────────

class HistoryMonthTab extends ConsumerStatefulWidget {
  final String? libraryKey;
  const HistoryMonthTab({super.key, this.libraryKey});

  @override
  ConsumerState<HistoryMonthTab> createState() => _MonthTabState();
}

class _MonthTabState extends ConsumerState<HistoryMonthTab> {
  late DateTime _month;

  static const _monthNames = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month);
  }

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final todayClean = dayOnly(today);

    // Mon-first calendar: leadingBlanks gives Mon=0, Tue=1, … Sun=6
    final grid = monthGridMetrics(_month.year, _month.month);
    final daysInMonth = grid.daysInMonth;
    final calOffset = grid.leadingBlanks;

    final monthStart = DateTime(_month.year, _month.month, 1);
    final monthEnd = DateTime(_month.year, _month.month, daysInMonth);
    final dayData = ListeningHistoryStore.getRange(monthStart, monthEnd);

    // Book map for lookup
    final booksAsync = widget.libraryKey != null
        ? ref.watch(booksProvider(widget.libraryKey!))
        : const AsyncValue<List<PlexBook>>.data([]);
    final bookMap = <String, PlexBook>{
      for (final b in (booksAsync.valueOrNull ?? [])) b.ratingKey: b,
    };

    // Books listened this month, keyed by day for calendar indicators +
    // sheet — from the shared memoized log index rather than a scan of every
    // book's log inside build.
    final logIndex = ref.watch(playbackLogIndexProvider);
    final booksPlayedByDay = <DateTime, Set<String>>{
      for (final e in logIndex.eventsByDay.entries)
        if (e.key.year == _month.year && e.key.month == _month.month)
          e.key: e.value.keys.toSet(),
    };
    final allCompleted = CompletedBooksStore.allCompleted();
    final booksThisMonth = booksPlayedByDay.values
        .expand((s) => s)
        .toSet()
        .map((k) => bookMap[k])
        .whereType<PlexBook>()
        .toList();

    // Named bookmarks created this month, keyed by day.
    final bookmarksByDay = <DateTime, List<NamedBookmark>>{};
    for (final bm in NamedBookmarkStore.getAll()) {
      final d = DateTime(
          bm.createdAt.year, bm.createdAt.month, bm.createdAt.day);
      if (d.year == _month.year && d.month == _month.month) {
        bookmarksByDay.putIfAbsent(d, () => []).add(bm);
      }
    }

    // Book completions this month, keyed by day.
    final completedByDay = <DateTime, List<String>>{};
    for (final key in allCompleted) {
      for (final dt in CompletedBooksStore.completionDates(key)) {
        if (dt.millisecondsSinceEpoch == 0) continue;
        final d = dayOnly(dt);
        if (d.year == _month.year && d.month == _month.month) {
          completedByDay.putIfAbsent(d, () => []).add(key);
        }
      }
    }

    int monthMs = 0;
    int listenedDays = 0;
    int bestDayMs = 0;
    for (final ms in dayData.values) {
      if (ms > 0) {
        monthMs += ms;
        listenedDays++;
        if (ms > bestDayMs) bestDayMs = ms;
      }
    }
    // Per *active* day — the same denominator the Total tab uses. Dividing by
    // every calendar day (including ones that hadn't happened yet) meant the
    // 3rd of a 31-day month with 3h listened read "6m Avg / day" here and
    // "1h" on the Total tab.
    final avgDayMs = listenedDays > 0 ? monthMs ~/ listenedDays : 0;

    // By-week: group days by ISO week (Mon–Sun)
    final weekTotals = <int>[];
    var runMs = 0;
    for (int d = 1; d <= daysInMonth; d++) {
      final date = DateTime(_month.year, _month.month, d);
      runMs += dayData[date] ?? 0;
      if (date.weekday == 7 || d == daysInMonth) {
        weekTotals.add(runMs);
        runMs = 0;
      }
    }
    final maxWeekMs = weekTotals.fold(0, max);

    final monthName = '${_monthNames[_month.month - 1]} ${_month.year}';
    // Back stops at the earliest month with any recorded activity (the old
    // bound compared the shown month against a year before *itself* — always
    // true, so the chevron paged into empty months forever). Forward stops at
    // the current month, computed per build so it rolls over at midnight on
    // the 1st instead of freezing at whatever month the screen opened in.
    final earliest = ListeningHistoryStore.earliestDay();
    final maxMonth = DateTime(today.year, today.month);
    final minMonth = earliest == null
        ? maxMonth
        : DateTime(earliest.year, earliest.month);
    final canGoBack = _month.isAfter(minMonth);
    final canGoForward = _month.isBefore(maxMonth);

    // Grid cell count (padded to a multiple of 7)
    final gridCount = grid.gridCount;

    final bottomPad = MediaQuery.of(context).padding.bottom;
    return ListView(
      padding: EdgeInsets.fromLTRB(20, 0, 20, bottomPad + 16),
      children: [
        // Month stepper
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            IconButton(
              icon: Icon(Icons.chevron_left,
                  color: canGoBack
                      ? SagaColors.fg
                      : SagaColors.fgSubtle.withValues(alpha: 0.3)),
              tooltip: 'Previous month',
              onPressed: canGoBack
                  ? () => setState(() =>
                      _month = DateTime(_month.year, _month.month - 1))
                  : null,
            ),
            Column(
              children: [
                Text(
                  monthName,
                  style: TextStyle(
                    color: SagaColors.fg,
                    fontSize: 21,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                  ),
                ),
                if (monthMs > 0)
                  Text(
                    '${fmtListenedMs(monthMs)} · $listenedDays day${listenedDays == 1 ? '' : 's'}',
                    style: TextStyle(color: SagaColors.fgMuted, fontSize: 12),
                  ),
              ],
            ),
            IconButton(
              icon: Icon(Icons.chevron_right,
                  color: canGoForward
                      ? SagaColors.fg
                      : SagaColors.fgSubtle.withValues(alpha: 0.3)),
              tooltip: 'Next month',
              onPressed: canGoForward
                  ? () => setState(() =>
                      _month = DateTime(_month.year, _month.month + 1))
                  : null,
            ),
          ],
        ),
        const SizedBox(height: 8),

        // Calendar card
        Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          decoration: BoxDecoration(
            color: SagaColors.surface,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Weekday header M T W T F S S
              Row(
                children: ['M', 'T', 'W', 'T', 'F', 'S', 'S']
                    .map((d) => Expanded(
                          child: Text(d,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: SagaColors.fgSubtle,
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                              )),
                        ))
                    .toList(),
              ),
              const SizedBox(height: 8),
              LayoutBuilder(builder: (_, constraints) {
                const spacing = 4.0;
                final cellW =
                    (constraints.maxWidth - 6 * spacing) / 7;
                final rows = (gridCount / 7).ceil();
                final gridH =
                    rows * cellW + (rows - 1) * spacing;
                return SizedBox(
                  height: gridH,
                  child: GridView.builder(
                physics: const NeverScrollableScrollPhysics(),
                padding: EdgeInsets.zero,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 7,
                  mainAxisSpacing: spacing,
                  crossAxisSpacing: spacing,
                  mainAxisExtent: cellW,
                ),
                itemCount: gridCount,
                itemBuilder: (context, i) {
                  if (i < calOffset || i >= calOffset + daysInMonth) {
                    return const SizedBox.shrink();
                  }
                  final day = i - calOffset + 1;
                  final date = DateTime(_month.year, _month.month, day);
                  final ms = dayData[date] ?? 0;
                  final isToday = date == todayClean;
                  final isFuture = date.isAfter(todayClean);
                  final dayBookmarks = bookmarksByDay[date] ?? [];
                  final dayCompleted = completedByDay[date] ?? [];
                  final dayPlayed = booksPlayedByDay[date] ?? {};
                  final hasDots = !isFuture &&
                      (dayBookmarks.isNotEmpty || dayCompleted.isNotEmpty);
                  final tappable = !isFuture &&
                      (ms > 0 ||
                          dayBookmarks.isNotEmpty ||
                          dayCompleted.isNotEmpty);

                  Widget cell = Container(
                    decoration: BoxDecoration(
                      color: isFuture ? Colors.transparent : historyHeatColor(ms),
                      borderRadius: BorderRadius.circular(9),
                      border: isToday
                          ? Border.all(color: SagaColors.accent, width: 2)
                          : isFuture
                              ? Border.all(
                                  color: SagaColors.border, width: 1)
                              : null,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '$day',
                          style: TextStyle(
                            color: isFuture
                                ? SagaColors.fgSubtle
                                : _heatTextColor(ms),
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (hasDots) ...[
                          const SizedBox(height: 2),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (dayBookmarks.isNotEmpty)
                                _CalDot(color: SagaColors.accent),
                              if (dayBookmarks.isNotEmpty &&
                                  dayCompleted.isNotEmpty)
                                const SizedBox(width: 2),
                              if (dayCompleted.isNotEmpty)
                                _CalDot(color: SagaColors.fg),
                            ],
                          ),
                        ],
                      ],
                    ),
                  );

                  if (!isFuture) {
                    cell = Semantics(
                      label: ms > 0
                          ? '${historyMonthAbbr(date.month)} $day: ${ms ~/ 60000} min'
                          : '${historyMonthAbbr(date.month)} $day',
                      excludeSemantics: true,
                      child: cell,
                    );
                  }
                  if (!tappable) return cell;
                  return GestureDetector(
                    onTap: () => _showDaySheet(
                      context, date, ms,
                      dayBookmarks, dayCompleted, dayPlayed.toList(),
                      bookMap,
                    ),
                    child: cell,
                  );
                },
                  ),
                );
              }),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Stat cards
        Row(
          children: [
            Expanded(
                child: HistoryStatCard(
                    label: 'Days listened', value: '$listenedDays')),
            const SizedBox(width: 10),
            Expanded(
                child: HistoryStatCard(
                    label: 'Best day',
                    value: bestDayMs > 0 ? fmtListenedMs(bestDayMs) : '–')),
            const SizedBox(width: 10),
            Expanded(
                child: HistoryStatCard(
                    label: 'Avg / active day',
                    value: avgDayMs > 0 ? fmtListenedMs(avgDayMs) : '–')),
          ],
        ),

        // By week
        if (weekTotals.any((w) => w > 0)) ...[
          const SizedBox(height: 20),
          Text('BY WEEK',
              style: historyMonoLabel.copyWith(color: SagaColors.fgSubtle)),
          const SizedBox(height: 10),
          ...weekTotals.asMap().entries.map((e) {
            final fraction =
                maxWeekMs > 0 ? e.value / maxWeekMs : 0.0;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  SizedBox(
                    width: 36,
                    child: Text('Wk ${e.key + 1}',
                        style: TextStyle(
                            color: SagaColors.fgSubtle, fontSize: 12)),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: fraction,
                        backgroundColor: SagaColors.heatEmpty,
                        valueColor: AlwaysStoppedAnimation(
                            SagaColors.accent.withValues(alpha: 0.6)),
                        minHeight: 12,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 52,
                    child: Text(
                      e.value > 0 ? fmtListenedMs(e.value) : '–',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        color: SagaColors.fgMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],

        // Books listened this month
        if (booksThisMonth.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text('BOOKS THIS MONTH',
              style: historyMonoLabel.copyWith(color: SagaColors.fgSubtle)),
          const SizedBox(height: 10),
          ...booksThisMonth.map((b) {
            final pct =
                bookProgressFraction(b, BookmarkStore.load(b.ratingKey)) ?? 0.0;
            final isFinished = allCompleted.contains(b.ratingKey);
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Container(
                padding: const EdgeInsets.all(13),
                decoration: BoxDecoration(
                  color: SagaColors.surface,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(9),
                      child: SizedBox(
                        width: 48,
                        height: 48,
                        child: BookCoverImage(
                            thumbPath: b.thumbPath,
                            cacheWidth: kCoverCacheWidthThumb),
                      ),
                    ),
                    const SizedBox(width: 13),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            b.title,
                            style: TextStyle(
                              color: SagaColors.fg,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 8),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(3),
                            child: LinearProgressIndicator(
                              value: pct,
                              backgroundColor: SagaColors.heatEmpty,
                              valueColor:
                                  AlwaysStoppedAnimation(SagaColors.accent),
                              minHeight: 5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      isFinished ? 'Finished' : 'In progress',
                      style: TextStyle(
                        color: isFinished
                            ? SagaColors.accentText
                            : SagaColors.fgMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ],
    );
  }

  static const _weekDayNames = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday',
    'Friday', 'Saturday', 'Sunday',
  ];

  void _showDaySheet(
    BuildContext context,
    DateTime date,
    int ms,
    List<NamedBookmark> bookmarks,
    List<String> completedKeys,
    List<String> playedKeys,
    Map<String, PlexBook> bookMap,
  ) {
    final dayLabel =
        '${_weekDayNames[date.weekday - 1]}, ${_monthNames[date.month - 1]} ${date.day}';
    final playedBooks = playedKeys
        .map((k) => bookMap[k])
        .whereType<PlexBook>()
        .toSet()
        .toList();

    final bottom = MediaQuery.of(context).padding.bottom;
    showSagaSheet(context, (ctx) {
      return Padding(
        padding: EdgeInsets.fromLTRB(20, 4, 20, bottom + 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    dayLabel,
                    style: TextStyle(
                      color: SagaColors.fg,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (ms > 0)
                  Text(fmtListenedMs(ms),
                      style:
                          TextStyle(color: SagaColors.fgMuted, fontSize: 13)),
              ],
            ),
            if (completedKeys.isEmpty && bookmarks.isEmpty && playedBooks.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text('No recorded activity',
                    style: TextStyle(
                        color: SagaColors.fgSubtle, fontSize: 14)),
              ),
            if (completedKeys.isNotEmpty) ...[
              const SizedBox(height: 16),
              _sheetSectionHeader(Icons.check_circle_outline, 'Completed'),
              const SizedBox(height: 6),
              for (final key in completedKeys)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(bookMap[key]?.title ?? 'Unknown book',
                      style: TextStyle(color: SagaColors.fg, fontSize: 14)),
                ),
            ],
            if (bookmarks.isNotEmpty) ...[
              const SizedBox(height: 16),
              _sheetSectionHeader(Icons.bookmark_outline, 'Bookmarks'),
              const SizedBox(height: 6),
              for (final bm in bookmarks)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(bm.label,
                          style:
                              TextStyle(color: SagaColors.fg, fontSize: 14)),
                      if (bookMap[bm.bookRatingKey] != null)
                        Text(bookMap[bm.bookRatingKey]!.title,
                            style: TextStyle(
                                color: SagaColors.fgMuted, fontSize: 12)),
                    ],
                  ),
                ),
            ],
            if (playedBooks.isNotEmpty) ...[
              const SizedBox(height: 16),
              _sheetSectionHeader(Icons.headphones_outlined, 'Listened'),
              const SizedBox(height: 6),
              for (final book in playedBooks)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(book.title,
                      style: TextStyle(color: SagaColors.fg, fontSize: 14)),
                ),
            ],
          ],
        ),
      );
    });
  }

  Widget _sheetSectionHeader(IconData icon, String label) => Row(
        children: [
          Icon(icon, color: SagaColors.accent, size: 16),
          const SizedBox(width: 6),
          Text(label,
              style: TextStyle(
                color: SagaColors.accentText,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
              )),
        ],
      );
}

// ── Calendar dot indicator ────────────────────────────────────────────────────

class _CalDot extends StatelessWidget {
  final Color color;
  const _CalDot({required this.color});

  @override
  Widget build(BuildContext context) => Container(
        width: 4,
        height: 4,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );
}
