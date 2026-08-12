import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/plex/models/plex_book.dart';
import '../../core/providers.dart';
import '../../core/stats/listening_sessions.dart';
import '../../core/storage/bookmark_store.dart';
import '../../core/storage/listening_history_store.dart';
import '../../core/storage/playback_log_store.dart';
import '../../core/storage/track_cache_store.dart';
import '../player/track_position_math.dart';
import '../../shared/widgets/week_bars.dart';
import '../../core/theme/saga_theme.dart';
import '../../shared/widgets/book_cover_image.dart';
import '../../core/book_progress.dart';
import '../../core/diagnostics/app_log.dart';
import '../../shared/widgets/saga_toast.dart';
import '../player/book_launch.dart';
import '../player/open_player.dart';
import 'history_data.dart';
import 'history_shared.dart';
import '../player/player_provider.dart';
import '../../core/utils/date_math.dart';
import '../../core/utils/format.dart';

// ── DAY TAB ───────────────────────────────────────────────────────────────────

class HistoryDayTab extends ConsumerWidget {
  final String? libraryKey;
  const HistoryDayTab({super.key, this.libraryKey});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Rebuild when history ticks or a new book starts playing.
    ref.watch(historyRevisionProvider);
    ref.watch(nowPlayingKeyProvider);

    final todayClean = dayOnly(DateTime.now());

    // Book map for cover/title lookup
    final booksAsync = libraryKey != null
        ? ref.watch(booksProvider(libraryKey!))
        : const AsyncValue<List<PlexBook>>.data([]);
    final bookMap = <String, PlexBook>{
      for (final b in (booksAsync.valueOrNull ?? [])) b.ratingKey: b,
    };

    // One shared scan of the playback log, memoized per history revision —
    // see [playbackLogIndexProvider] for the bucketing and the midnight-split
    // credit rules.
    final logIndex = ref.watch(playbackLogIndexProvider);
    final allDayLogs = logIndex.eventsByDay;
    final creditedMs = logIndex.creditedMsByDay;

    // Calendar days via [mondayWeek]/[addDays], the same helpers Home's
    // listening strip uses. Built with `Duration(days:)` these landed at 23:00
    // of the day before across a DST change, and the history box is keyed by
    // y-m-d — so the two screens disagreed about which seven days "this week"
    // meant, twice a year.
    final weekDays = mondayWeek(todayClean);
    final weekMs = weekDays.map(ListeningHistoryStore.getMs).toList();
    final weekTotalMs = weekMs.fold(0, (a, b) => a + b);
    final weekListenedDays = weekMs.where((m) => m > 0).length;

    // 90 days matches the take(90) display cap — no need to scan a full year.
    final start = addDays(todayClean, -90);
    final activeDaysSet = ListeningHistoryStore.activeDays(start, todayClean).toSet();

    // Always include today if PlaybackLogStore already has events for it,
    // even before the history timer has recorded any accumulated time.
    if (allDayLogs[todayClean]?.isNotEmpty == true) {
      activeDaysSet.add(todayClean);
    }

    final activeDays = activeDaysSet.toList()
      ..sort((a, b) => b.compareTo(a)); // most recent first

    final bestDayMs = activeDays.fold(0, (best, d) {
      final ms = ListeningHistoryStore.getMs(d);
      return ms > best ? ms : best;
    });

    final streak = computeHistoryStreak();
    final last7 = List.generate(7, (i) => addDays(todayClean, i - 6));
    final last7Ms = last7.map(ListeningHistoryStore.getMs).toList();

    final bottomPad = MediaQuery.of(context).padding.bottom;
    return ListView(
      padding: EdgeInsets.fromLTRB(20, 0, 20, bottomPad + 16),
      children: [
        _StreakBanner(
          current: streak.current,
          longest: streak.longest,
          last7Ms: last7Ms,
        ),
        const SizedBox(height: 16),
        _WeekCard(
          weekMs: weekMs,
          weekDays: weekDays,
          totalMs: weekTotalMs,
          listenedDays: weekListenedDays,
        ),
        const SizedBox(height: 24),
        Text('RECENT DAYS', style: historyMonoLabel.copyWith(color: SagaColors.fgSubtle)),
        const SizedBox(height: 12),
        if (activeDays.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 24),
            child: Center(
              child: Text('No listening history yet',
                  style: TextStyle(color: SagaColors.fgSubtle)),
            ),
          )
        else
          ...activeDays.take(90).map((d) {
            final ms = ListeningHistoryStore.getMs(d);
            final dayBooks = allDayLogs[d] ?? {};
            final isToday = d == todayClean;
            return _DayRow(
              // Keyed by date: rows are stateful (expansion), and midnight
              // inserts a new row at index 0 — keyless, yesterday's expanded
              // panel re-attached itself under today's date.
              key: ValueKey(d),
              date: d,
              ms: ms,
              bestDayMs: bestDayMs,
              dayBooks: dayBooks,
              creditedMs: creditedMs[d] ?? const {},
              bookMap: bookMap,
              isToday: isToday,
              initialExpanded: isToday && dayBooks.isNotEmpty,
            );
          }),
      ],
    );
  }
}

// ── Streak banner ─────────────────────────────────────────────────────────────

class _StreakBanner extends StatelessWidget {
  final int current;
  final int longest;
  final List<int> last7Ms;
  const _StreakBanner(
      {required this.current, required this.longest, required this.last7Ms});

  @override
  Widget build(BuildContext context) {
    final hasStreak = current > 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: SagaColors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(
            Icons.local_fire_department,
            color: hasStreak ? SagaColors.accent : SagaColors.fgSubtle,
            size: 22,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hasStreak ? '$current-day streak' : 'No active streak',
                  style: TextStyle(
                    color: hasStreak ? SagaColors.fg : SagaColors.fgMuted,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  hasStreak
                      ? 'Longest run · $longest day${longest == 1 ? '' : 's'}'
                      : longest > 0
                          ? 'Best: $longest day${longest == 1 ? '' : 's'} — listen today!'
                          : 'Listen today to start one',
                  style: TextStyle(color: SagaColors.fgMuted, fontSize: 12),
                ),
              ],
            ),
          ),
          Row(
            children: last7Ms.map((ms) {
              return Container(
                width: 9,
                height: 9,
                margin: const EdgeInsets.only(left: 4),
                decoration: BoxDecoration(
                  color: ms > 0 ? SagaColors.accent : SagaColors.heatEmpty,
                  borderRadius: BorderRadius.circular(3),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

// ── This-week card ────────────────────────────────────────────────────────────

class _WeekCard extends StatefulWidget {
  final List<int> weekMs;
  final List<DateTime> weekDays;
  final int totalMs;
  final int listenedDays;

  const _WeekCard({
    required this.weekMs,
    required this.weekDays,
    required this.totalMs,
    required this.listenedDays,
  });

  @override
  State<_WeekCard> createState() => _WeekCardState();
}

class _WeekCardState extends State<_WeekCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700));
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (MediaQuery.of(context).disableAnimations) {
        _ctrl.value = 1.0;
      } else {
        _ctrl.forward();
      }
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final todayClean = dayOnly(today);
    final avgMs = widget.listenedDays > 0
        ? widget.totalMs ~/ widget.listenedDays
        : 0;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: SagaColors.surface,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('THIS WEEK', style: historyMonoLabel.copyWith(color: SagaColors.fgSubtle)),
          const SizedBox(height: 4),
          Text(
            widget.totalMs == 0 ? '0m' : fmtListenedMs(widget.totalMs),
            style: TextStyle(
              color: SagaColors.fg,
              fontSize: 30,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.8,
            ),
          ),
          if (widget.listenedDays > 0)
            Text(
              '${widget.listenedDays} day${widget.listenedDays == 1 ? '' : 's'} · ${fmtListenedMs(avgMs)} / day',
              style: TextStyle(color: SagaColors.fgMuted, fontSize: 12),
            ),
          const SizedBox(height: 26),
          AnimatedBuilder(
            animation: _anim,
            builder: (context2, child2) {
              // Shared chart, large palette: accentDim, because a 74-px
              // column of full amber is a large fill (see
              // SagaColors.accentDim).
              return SizedBox(
                height: 90,
                child: WeekBars(
                  weekMs: widget.weekMs,
                  weekDays: widget.weekDays,
                  todayClean: todayClean,
                  maxBarHeight: 74,
                  minBarHeight: 4,
                  barPadding: 3,
                  cornerRadius: 7,
                  todayColor: SagaColors.accentDim,
                  activeColor: SagaColors.accentDim.withValues(alpha: 0.42),
                  animationValue: _anim.value,
                  labelBuilder: (i, isToday) => Text(
                    ['M', 'T', 'W', 'T', 'F', 'S', 'S'][i],
                    style: TextStyle(
                      color: isToday
                          ? SagaColors.accentText
                          : SagaColors.fgSubtle,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

// ── Day row ───────────────────────────────────────────────────────────────────

class _DayRow extends StatelessWidget {
  final DateTime date;
  final int ms;
  final int bestDayMs;
  final Map<String, List<AudioLogEvent>> dayBooks;

  /// Wall-clock ms each book earned *on this day*, from midnight-split
  /// sessions — see the credit pass in [HistoryDayTab.build].
  final Map<String, int> creditedMs;
  final Map<String, PlexBook> bookMap;
  final bool isToday;
  final bool initialExpanded;

  const _DayRow({
    super.key,
    required this.date,
    required this.ms,
    required this.bestDayMs,
    required this.dayBooks,
    required this.creditedMs,
    required this.bookMap,
    required this.isToday,
    this.initialExpanded = false,
  });

  static int _firstEventMs(List<AudioLogEvent> events) {
    var min = 1 << 62;
    for (final e in events) {
      if (e.type == 'play' || e.type == 'pause') {
        final t = e.timestamp.millisecondsSinceEpoch;
        if (t < min) min = t;
      }
    }
    return min;
  }

  @override
  Widget build(BuildContext context) {
    final empty = ms == 0;

    final sortedEntries = dayBooks.entries
        .where((e) => e.value.any((ev) => ev.type == 'play' || ev.type == 'pause'))
        .toList()
      ..sort((a, b) => _firstEventMs(a.value).compareTo(_firstEventMs(b.value)));

    return Opacity(
      opacity: empty ? 0.5 : 1.0,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: 42,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${date.day}',
                        style: TextStyle(
                          color: isToday ? SagaColors.accent : SagaColors.fg,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          height: 1,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        historyWeekdayShort(date).toUpperCase(),
                        style: TextStyle(
                          color: SagaColors.fgSubtle,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 13),
                if (empty)
                  Expanded(
                    child: Container(
                      height: 8,
                      decoration: BoxDecoration(
                        color: SagaColors.heatEmpty,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  )
                else ...[
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: bestDayMs > 0 ? (ms / bestDayMs).clamp(0.0, 1.0) : 0,
                        backgroundColor: SagaColors.heatEmpty,
                        valueColor: AlwaysStoppedAnimation(
                            SagaColors.accent.withValues(alpha: 0.35)),
                        minHeight: 4,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    fmtListenedMs(ms),
                    style: TextStyle(
                      color: SagaColors.fg,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (!empty && sortedEntries.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 55),
              child: Column(
                children: [
                  for (var i = 0; i < sortedEntries.length; i++) ...[
                    if (i > 0) const SizedBox(height: 6),
                    _DayBookEntry(
                      // Keyed: entries hold expansion state, and the day's
                      // book set grows while listening.
                      key: ValueKey(sortedEntries[i].key),
                      bookKey: sortedEntries[i].key,
                      events: sortedEntries[i].value,
                      listenedMs: creditedMs[sortedEntries[i].key] ?? 0,
                      book: bookMap[sortedEntries[i].key],
                      initialExpanded: initialExpanded,
                    ),
                  ],
                ],
              ),
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

// ── Day book entry ────────────────────────────────────────────────────────────

class _DayBookEntry extends ConsumerStatefulWidget {
  final String bookKey;
  final List<AudioLogEvent> events;

  /// Midnight-split wall-clock credit for this book on this day, computed by
  /// [HistoryDayTab.build] — not derivable from [events] alone, whose pause may sit
  /// in the next day's bucket.
  final int listenedMs;
  final PlexBook? book;
  final bool initialExpanded;

  const _DayBookEntry({
    super.key,
    required this.bookKey,
    required this.events,
    required this.listenedMs,
    required this.book,
    this.initialExpanded = false,
  });

  @override
  ConsumerState<_DayBookEntry> createState() => _DayBookEntryState();
}

class _DayBookEntryState extends ConsumerState<_DayBookEntry> {
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = widget.initialExpanded;
  }

  @override
  Widget build(BuildContext context) {
    final book = widget.book;
    final listenedMs = widget.listenedMs;

    // Per-day progress: how far into the book the day's last event sits. The
    // event's positionMs is an offset inside ONE file, so it has to be
    // resolved to a book-absolute offset before dividing by the book length —
    // dividing it directly made a twenty-file book on file twelve read a few
    // percent (the exact bug book_progress.dart exists to prevent). When it
    // can't be resolved, the bar hides rather than draw a wrong one.
    double? pct;
    final total = pickTotalDurationMs(book?.totalDurationMs,
        BookmarkStore.load(widget.bookKey)?.totalDurationMs);
    final chrono = [
      for (final e in widget.events)
        if (e.type == 'play' || e.type == 'pause') e
    ]..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    if (chrono.isNotEmpty && total != null) {
      final absMs = _absoluteEventPositionMs(widget.bookKey, chrono.last);
      if (absMs != null) pct = (absMs / total).clamp(0.0, 1.0);
    }
    final bookPct = pct;

    return Material(
      color: SagaColors.surface,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
        child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(7),
                  child: SizedBox(
                    width: 38,
                    height: 38,
                    child: book != null
                        ? BookCoverImage(
                            thumbPath: book.thumbPath,
                            cacheWidth: kCoverCacheWidthThumb)
                        : Container(color: SagaColors.heatEmpty),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        book?.title ?? 'Unknown',
                        style: TextStyle(
                          color: SagaColors.fg,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (bookPct != null) ...[
                        const SizedBox(height: 5),
                        Row(
                          children: [
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(3),
                                child: LinearProgressIndicator(
                                  value: bookPct,
                                  backgroundColor: SagaColors.heatEmpty,
                                  valueColor:
                                      AlwaysStoppedAnimation(SagaColors.accent),
                                  minHeight: 4,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '${(bookPct * 100).round()}%',
                              style: TextStyle(
                                  color: SagaColors.fgSubtle, fontSize: 10),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (listenedMs > 0)
                  Text(
                    fmtListenedMs(listenedMs),
                    style: TextStyle(
                      color: SagaColors.fgMuted,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                const SizedBox(width: 6),
                AnimatedRotation(
                  turns: _expanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(Icons.expand_more,
                      color: SagaColors.fgSubtle, size: 16),
                ),
              ],
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
          child: _expanded
              ? _BookSessionPanel(
                  bookKey: widget.bookKey, events: widget.events, book: book)
              : const SizedBox.shrink(),
        ),
      ],
        ),
      ),
    );
  }
}

/// Book-absolute offset of a log event, or null when it can't be resolved.
///
/// An [AudioLogEvent] records a position inside one file, plus which file.
/// Placing it in the whole book needs that file's own offset: from the cached
/// track list when there is one, else from the saved position — which knows
/// exactly one file's offset (its own: absolute minus track-relative), so it
/// only helps when the event is on the same file.
int? _absoluteEventPositionMs(String bookKey, AudioLogEvent e) {
  final tracks = TrackCacheStore.load(bookKey);
  if (tracks != null) {
    final idx = tracks.indexWhere((t) => t.ratingKey == e.trackRatingKey);
    if (idx >= 0) {
      return absoluteFromTrack(
          [for (final t in tracks) t.durationMs], idx, e.positionMs);
    }
  }
  final saved = BookmarkStore.load(bookKey);
  if (saved != null && saved.trackRatingKey == e.trackRatingKey) {
    return saved.absolutePositionMs - saved.positionMs + e.positionMs;
  }
  return null;
}

// ── Book session panel (expanded book log) ────────────────────────────────────

class _BookSessionPanel extends ConsumerWidget {
  final String bookKey;
  final List<AudioLogEvent> events;
  final PlexBook? book;

  const _BookSessionPanel(
      {required this.bookKey, required this.events, required this.book});

  /// Lookup key for a logged event. Pairing runs over the *full* log while
  /// the rows render one day's slice, and `getLog` builds fresh instances on
  /// every call — so identity can't join the two; timestamp+track can.
  static String _eventKey(AudioLogEvent e) =>
      '${e.timestamp.millisecondsSinceEpoch}_${e.trackRatingKey}';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chrono = events
        .where((e) => e.type == 'play' || e.type == 'pause')
        .toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

    // Durations from the shared pairing rule, over the whole log rather than
    // this day's bucket: a session that crosses midnight has its pause in the
    // next day's slice, and pairing the day alone left its play row without
    // a "listened" label.
    final sessions = pairListeningSessions(PlaybackLogStore.getLog(bookKey));
    final durationLabels = <String, String>{
      for (final s in sessions)
        if (s.duration != null && s.duration!.inMinutes > 0)
          _eventKey(s.play): '${s.duration!.inMinutes}m listened',
    };
    final playCount = chrono.where((e) => e.type == 'play').length;

    return Container(
      margin: const EdgeInsets.only(top: 4, bottom: 4),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      decoration: BoxDecoration(
        color: SagaColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$playCount session${playCount == 1 ? '' : 's'}',
            style: TextStyle(color: SagaColors.fgMuted, fontSize: 12.5),
          ),
          ...List.generate(chrono.length, (i) => chrono.length - 1 - i).map((i) {
            final e = chrono[i];
            final isPlay = e.type == 'play';
            final dur = isPlay ? durationLabels[_eventKey(e)] : null;
            return InkWell(
              onTap: isPlay ? () => _jumpTo(context, ref, e) : null,
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.only(top: 9),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: isPlay
                            ? SagaColors.accent.withValues(alpha: 0.15)
                            : SagaColors.surface,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        isPlay ? Icons.play_arrow : Icons.pause,
                        color:
                            isPlay ? SagaColors.accent : SagaColors.fgSubtle,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isPlay ? 'Started' : 'Paused',
                            style: TextStyle(
                              color: SagaColors.fg,
                              fontSize: 14.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (dur != null)
                            Text(
                              dur,
                              style: TextStyle(
                                  color: SagaColors.fgSubtle, fontSize: 12.5),
                            ),
                        ],
                      ),
                    ),
                    Text(
                      fmtTime(e.timestamp),
                      style:
                          TextStyle(color: SagaColors.fgSubtle, fontSize: 13),
                    ),
                    if (isPlay) ...[
                      const SizedBox(width: 4),
                      Icon(Icons.chevron_right,
                          color: SagaColors.fgSubtle, size: 14),
                    ],
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Future<void> _jumpTo(
      BuildContext context, WidgetRef ref, AudioLogEvent event) async {
    if (book == null) return;
    // Each quiet exit says so — a tap that does nothing is indistinguishable
    // from a dead button. Same wording as the All Bookmarks jump.
    try {
      final tracks =
          await ref.read(tracksProvider(book!.ratingKey).future);
      if (!context.mounted) return;
      if (!tracks.any((t) => t.ratingKey == event.trackRatingKey)) {
        showSagaToast(
            context,
            'The file this session points into is no longer '
            'part of the book.',
            isError: true);
        return;
      }
      await openPlayerAndStart(
        context: context,
        service: ref.read(playerServiceProvider),
        bookRatingKey: book!.ratingKey,
        loadTracks: () async => tracks,
        from: BookStartPoint.atTrack(event.trackRatingKey,
            positionMs: event.positionMs),
      );
    } catch (e) {
      AppLog.log('playback', 'history session jump failed: $e');
      if (context.mounted) {
        showSagaToast(context,
            'Couldn\'t load this book — is the server reachable?',
            isError: true);
      }
    }
  }
}
