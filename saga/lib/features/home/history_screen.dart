import 'dart:math' show max;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/plex/models/plex_book.dart';
import '../../core/providers.dart';
import '../../core/storage/bookmark_store.dart';
import '../../core/storage/completed_books_store.dart';
import '../../core/storage/listening_history_store.dart';
import '../../core/storage/named_bookmark_store.dart';
import '../../core/storage/playback_log_store.dart';
import '../../shared/widgets/saga_sheet.dart';
import '../../core/theme/saga_theme.dart';
import '../../shared/widgets/book_cover_image.dart';
import '../library/book_detail_screen.dart';
import '../player/player_provider.dart';
import '../player/player_screen.dart';
import '../../core/utils/format.dart';

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
                _DayTab(libraryKey: widget.libraryKey),
                _MonthTab(
                    key: const PageStorageKey('month'),
                    libraryKey: widget.libraryKey),
                _TotalTab(libraryKey: widget.libraryKey),
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
          return GestureDetector(
            onTap: () => onChanged(t),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
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

// ── Shared helpers ────────────────────────────────────────────────────────────

String _fmtMs(int ms) {
  final h = ms ~/ 3600000;
  final m = (ms % 3600000) ~/ 60000;
  if (h > 0) return '${h}h ${m}m';
  if (m > 0) return '${m}m';
  return '<1m';
}

String _weekdayShort(DateTime d) =>
    const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][d.weekday - 1];

Color _heatColor(int ms) {
  if (ms == 0) return SagaColors.heatEmpty;
  final m = ms ~/ 60000;
  if (m < 15) return SagaColors.heat1;
  if (m < 30) return SagaColors.heat2;
  if (m < 60) return SagaColors.heat3;
  if (m < 120) return SagaColors.heat4;
  return SagaColors.heatMax;
}

/// Readable day-number colour for a heat cell. The cell colour already encodes
/// the theme (terra's ramp runs to cream, ink/cream's max cells get bright), so
/// we contrast against the cell itself — muted ink on light cells, muted cream
/// on dark ones — rather than a single fixed tone that vanishes at one end.
Color _heatTextColor(int ms) =>
    _heatColor(ms).computeLuminance() > 0.42
        ? const Color(0xCC1E1410) // muted ink
        : const Color(0xCCF4EAD8); // muted cream

({int current, int longest}) _computeStreak() {
  final today = DateTime.now();
  final todayClean = DateTime(today.year, today.month, today.day);

  // If today has no listening yet the streak is still alive — it just hasn't
  // been extended yet. Start counting from yesterday in that case.
  final startRaw = ListeningHistoryStore.getMs(todayClean) > 0
      ? todayClean
      : todayClean.subtract(const Duration(days: 1));
  final start = DateTime(startRaw.year, startRaw.month, startRaw.day);

  int current = 0;
  var d = start;
  while (ListeningHistoryStore.getMs(d) > 0) {
    current++;
    // Renormalize to midnight after each subtraction — Duration(days:1) is
    // exactly 24h and lands at 23:00 across the spring-forward DST boundary,
    // causing the history store lookup to miss and the streak to end early.
    final prev = d.subtract(const Duration(days: 1));
    d = DateTime(prev.year, prev.month, prev.day);
  }

  int longest = 0;
  int run = 0;
  for (int i = 0; i < 365; i++) {
    final raw = todayClean.subtract(Duration(days: i));
    final day = DateTime(raw.year, raw.month, raw.day);
    if (ListeningHistoryStore.getMs(day) > 0) {
      run++;
      if (run > longest) longest = run;
    } else {
      run = 0;
    }
  }
  if (current > longest) longest = current;
  return (current: current, longest: longest);
}

const TextStyle _monoLabel = TextStyle(
  fontSize: 11,
  letterSpacing: 2.0,
  fontWeight: FontWeight.w500,
);

// ── DAY TAB ───────────────────────────────────────────────────────────────────

class _DayTab extends ConsumerWidget {
  final String? libraryKey;
  const _DayTab({this.libraryKey});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Rebuild when history ticks or a new book starts playing.
    ref.watch(historyRevisionProvider);
    ref.watch(nowPlayingKeyProvider);

    final today = DateTime.now();
    final todayClean = DateTime(today.year, today.month, today.day);

    // Book map for cover/title lookup
    final booksAsync = libraryKey != null
        ? ref.watch(booksProvider(libraryKey!))
        : const AsyncValue<List<PlexBook>>.data([]);
    final bookMap = <String, PlexBook>{
      for (final b in (booksAsync.valueOrNull ?? [])) b.ratingKey: b,
    };

    // Pre-build day → { bookRatingKey → events for that day }
    final allDayLogs = <DateTime, Map<String, List<AudioLogEvent>>>{};
    for (final bookKey in PlaybackLogStore.bookRatingKeys()) {
      for (final e in PlaybackLogStore.getLog(bookKey)) {
        final day = DateTime(e.timestamp.year, e.timestamp.month, e.timestamp.day);
        (allDayLogs.putIfAbsent(day, () => {})[bookKey] ??= []).add(e);
      }
    }

    final monday = todayClean.subtract(Duration(days: today.weekday - 1));
    final weekDays = List.generate(7, (i) => monday.add(Duration(days: i)));
    final weekMs = weekDays.map(ListeningHistoryStore.getMs).toList();
    final weekTotalMs = weekMs.fold(0, (a, b) => a + b);
    final weekListenedDays = weekMs.where((m) => m > 0).length;

    // 90 days matches the take(90) display cap — no need to scan a full year.
    final start = todayClean.subtract(const Duration(days: 90));
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

    final streak = _computeStreak();
    final last7 = List.generate(7, (i) => todayClean.subtract(Duration(days: 6 - i)));
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
        Text('RECENT DAYS', style: _monoLabel.copyWith(color: SagaColors.fgSubtle)),
        const SizedBox(height: 12),
        if (activeDays.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 24),
            child: Center(
              child: Text('No listening history yet.',
                  style: TextStyle(color: SagaColors.fgSubtle)),
            ),
          )
        else
          ...activeDays.take(90).map((d) {
            final ms = ListeningHistoryStore.getMs(d);
            final dayBooks = allDayLogs[d] ?? {};
            final isToday = d == todayClean;
            return _DayRow(
              date: d,
              ms: ms,
              bestDayMs: bestDayMs,
              dayBooks: dayBooks,
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
    final todayClean = DateTime(today.year, today.month, today.day);
    final maxMs = widget.weekMs.fold(0, max);
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
          Text('THIS WEEK', style: _monoLabel.copyWith(color: SagaColors.fgSubtle)),
          const SizedBox(height: 4),
          Text(
            widget.totalMs == 0 ? '0m' : _fmtMs(widget.totalMs),
            style: TextStyle(
              color: SagaColors.fg,
              fontSize: 30,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.8,
            ),
          ),
          if (widget.listenedDays > 0)
            Text(
              '${widget.listenedDays} day${widget.listenedDays == 1 ? '' : 's'} · ${_fmtMs(avgMs)} / day',
              style: TextStyle(color: SagaColors.fgMuted, fontSize: 12),
            ),
          const SizedBox(height: 26),
          AnimatedBuilder(
            animation: _anim,
            builder: (context2, child2) {
              return SizedBox(
                height: 90,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: List.generate(7, (i) {
                    final ms = widget.weekMs[i];
                    final day = widget.weekDays[i];
                    final isToday = day == todayClean;
                    final isFuture = day.isAfter(todayClean);
                    final fraction = maxMs > 0 ? ms / maxMs : 0.0;
                    final staggerProgress = ((_anim.value - i * 0.04) /
                            (1.0 - i * 0.04))
                        .clamp(0.0, 1.0);
                    final barH = ms > 0
                        ? max(4.0, 74.0 * fraction * staggerProgress)
                        : 4.0;

                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Expanded(
                              child: Align(
                                alignment: Alignment.bottomCenter,
                                child: Container(
                                  width: double.infinity,
                                  height: barH,
                                  decoration: BoxDecoration(
                                    color: isFuture
                                        ? SagaColors.heatEmpty
                                        : isToday
                                            ? SagaColors.accent
                                            : ms > 0
                                                ? SagaColors.accent
                                                    .withValues(alpha: 0.42)
                                                : SagaColors.heatEmpty,
                                    borderRadius: BorderRadius.circular(7),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              ['M', 'T', 'W', 'T', 'F', 'S', 'S'][i],
                              style: TextStyle(
                                color: isToday
                                    ? SagaColors.accent
                                    : SagaColors.fgSubtle,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
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

class _DayRow extends StatefulWidget {
  final DateTime date;
  final int ms;
  final int bestDayMs;
  final Map<String, List<AudioLogEvent>> dayBooks;
  final Map<String, PlexBook> bookMap;
  final bool isToday;
  final bool initialExpanded;

  const _DayRow({
    required this.date,
    required this.ms,
    required this.bestDayMs,
    required this.dayBooks,
    required this.bookMap,
    required this.isToday,
    this.initialExpanded = false,
  });

  @override
  State<_DayRow> createState() => _DayRowState();
}

class _DayRowState extends State<_DayRow> {
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = widget.initialExpanded;
  }

  @override
  Widget build(BuildContext context) {
    final empty = widget.ms == 0;
    final hasDetail = widget.dayBooks.isNotEmpty;

    // Primary book: most events that day
    String? primaryKey;
    int maxEvents = 0;
    for (final entry in widget.dayBooks.entries) {
      if (entry.value.length > maxEvents) {
        maxEvents = entry.value.length;
        primaryKey = entry.key;
      }
    }
    final primaryBook = primaryKey != null ? widget.bookMap[primaryKey] : null;

    // Book completion % for progress bar.
    // Today: use current bookmark (absolutePositionMs is accurate and reflects
    // any ongoing session). Past days: use the last logged event's intra-track
    // positionMs as a proxy — exact for single-file M4B, approximate for
    // multi-track books (no absolute position is stored in the event log).
    double bookPct = 0.0;
    if (primaryKey != null) {
      final total = primaryBook?.totalDurationMs ??
          BookmarkStore.load(primaryKey)?.totalDurationMs;
      if (total != null && total > 0) {
        if (widget.isToday) {
          final saved = BookmarkStore.load(primaryKey);
          if (saved != null) {
            bookPct = (saved.absolutePositionMs / total).clamp(0.0, 1.0);
          }
        } else {
          final events = widget.dayBooks[primaryKey] ?? [];
          if (events.isNotEmpty) {
            final last = events.reduce(
              (a, b) => a.timestamp.isAfter(b.timestamp) ? a : b,
            );
            bookPct = (last.positionMs / total).clamp(0.0, 1.0);
          }
        }
      }
    }

    return Opacity(
      opacity: empty ? 0.5 : 1.0,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: !empty && hasDetail
                ? () => setState(() => _expanded = !_expanded)
                : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Date column
                  SizedBox(
                    width: 42,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${widget.date.day}',
                          style: TextStyle(
                            color: widget.isToday
                                ? SagaColors.accent
                                : SagaColors.fg,
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            height: 1,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          _weekdayShort(widget.date).toUpperCase(),
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
                    ClipRRect(
                      borderRadius: BorderRadius.circular(7),
                      child: SizedBox(
                        width: 38,
                        height: 38,
                        child: primaryBook != null
                            ? BookCoverImage(
                                thumbPath: primaryBook.thumbPath,
                                cacheWidth: 76)
                            : Container(color: SagaColors.heatEmpty),
                      ),
                    ),
                    const SizedBox(width: 13),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            primaryBook?.title ?? 'Unknown',
                            style: TextStyle(
                              color: SagaColors.fg,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Expanded(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(3),
                                  child: LinearProgressIndicator(
                                    value: bookPct,
                                    backgroundColor: SagaColors.heatEmpty,
                                    valueColor: AlwaysStoppedAnimation(
                                        SagaColors.accent),
                                    minHeight: 5,
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
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      _fmtMs(widget.ms),
                      style: TextStyle(
                        color: SagaColors.fg,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (hasDetail)
                      AnimatedRotation(
                        turns: _expanded ? 0.5 : 0,
                        duration: const Duration(milliseconds: 200),
                        child: Icon(Icons.expand_more,
                            color: SagaColors.fgSubtle, size: 16),
                      ),
                  ],
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
            child: _expanded && hasDetail
                ? _SessionPanel(
                    dayBooks: widget.dayBooks,
                    bookMap: widget.bookMap,
                  )
                : const SizedBox.shrink(),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

// ── Session panel (expanded day log) ─────────────────────────────────────────

class _SessionPanel extends ConsumerWidget {
  final Map<String, List<AudioLogEvent>> dayBooks;
  final Map<String, PlexBook> bookMap;
  const _SessionPanel({required this.dayBooks, required this.bookMap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // One group per book played that day (ordered by each book's first event),
    // so two different books on the same day don't get merged under one title.
    final entries = dayBooks.entries
        .where((e) =>
            e.value.any((ev) => ev.type == 'play' || ev.type == 'pause'))
        .toList()
      ..sort((a, b) => _firstEventMs(a.value).compareTo(_firstEventMs(b.value)));

    return Container(
      margin: const EdgeInsets.only(top: 6, bottom: 2),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      decoration: BoxDecoration(
        color: SagaColors.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var g = 0; g < entries.length; g++) ...[
            if (g > 0)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Divider(color: SagaColors.border, height: 1),
              ),
            _bookGroup(context, ref, entries[g].key, entries[g].value),
          ],
        ],
      ),
    );
  }

  int _firstEventMs(List<AudioLogEvent> events) {
    var min = 1 << 62;
    for (final e in events) {
      if (e.type == 'play' || e.type == 'pause') {
        final t = e.timestamp.millisecondsSinceEpoch;
        if (t < min) min = t;
      }
    }
    return min;
  }

  Widget _bookGroup(BuildContext context, WidgetRef ref, String bookKey,
      List<AudioLogEvent> events) {
    final book = bookMap[bookKey];
    final chrono = events
        .where((e) => e.type == 'play' || e.type == 'pause')
        .toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

    // Duration for each play = gap to the next pause within THIS book.
    final durations = List<String?>.filled(chrono.length, null);
    for (var i = 0; i < chrono.length - 1; i++) {
      if (chrono[i].type == 'play' && chrono[i + 1].type == 'pause') {
        final mins =
            chrono[i + 1].timestamp.difference(chrono[i].timestamp).inMinutes;
        if (mins > 0) durations[i] = '${mins}m listened';
      }
    }
    final playCount = chrono.where((e) => e.type == 'play').length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$playCount session${playCount == 1 ? '' : 's'}'
          '${book != null ? ' · ${book.title}' : ''}',
          style: TextStyle(color: SagaColors.fgSubtle, fontSize: 12),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        // Newest first
        ...List.generate(chrono.length, (i) => chrono.length - 1 - i).map((i) {
          final e = chrono[i];
          final isPlay = e.type == 'play';
          final dur = durations[i];
          return InkWell(
            onTap: isPlay ? () => _jumpTo(context, ref, e, book) : null,
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
                      color: isPlay ? SagaColors.accent : SagaColors.fgSubtle,
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
                    style: TextStyle(color: SagaColors.fgSubtle, fontSize: 13),
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
    );
  }

  Future<void> _jumpTo(BuildContext context, WidgetRef ref,
      AudioLogEvent event, PlexBook? book) async {
    if (book == null) return;
    try {
      final tracks = await ref.read(tracksProvider(book.ratingKey).future);
      if (!context.mounted) return;
      final idx =
          tracks.indexWhere((t) => t.ratingKey == event.trackRatingKey);
      if (idx < 0) return;
      Navigator.of(context, rootNavigator: true)
          .push(MaterialPageRoute(builder: (_) => const PlayerScreen()));
      final service = ref.read(playerServiceProvider);
      await service.loadBook(
        bookRatingKey: book.ratingKey,
        tracks: tracks,
        startTrackIndex: idx,
        startPositionMs: event.positionMs,
      );
      await service.play();
    } catch (_) {}
  }
}

// ── MONTH TAB ─────────────────────────────────────────────────────────────────

class _MonthTab extends ConsumerStatefulWidget {
  final String? libraryKey;
  const _MonthTab({super.key, this.libraryKey});

  @override
  ConsumerState<_MonthTab> createState() => _MonthTabState();
}

class _MonthTabState extends ConsumerState<_MonthTab> {
  late DateTime _month;
  late final DateTime _maxMonth;

  static const _monthNames = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month);
    _maxMonth = _month;
  }

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final todayClean = DateTime(today.year, today.month, today.day);

    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    // Mon-first calendar: Mon=0, Tue=1, … Sun=6
    final calOffset =
        (DateTime(_month.year, _month.month, 1).weekday - 1) % 7;

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

    // Books listened this month, keyed by day for calendar indicators + sheet.
    final booksPlayedByDay = <DateTime, Set<String>>{};
    for (final bookKey in PlaybackLogStore.bookRatingKeys()) {
      for (final e in PlaybackLogStore.getLog(bookKey)) {
        if (e.timestamp.year == _month.year &&
            e.timestamp.month == _month.month) {
          final d = DateTime(
              e.timestamp.year, e.timestamp.month, e.timestamp.day);
          booksPlayedByDay.putIfAbsent(d, () => {}).add(bookKey);
        }
      }
    }
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
        final d = DateTime(dt.year, dt.month, dt.day);
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
    final avgDayMs = daysInMonth > 0 ? monthMs ~/ daysInMonth : 0;

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
    final canGoBack = _month.isAfter(DateTime(_month.year - 1, _month.month));
    final canGoForward = _month.isBefore(_maxMonth);

    // Grid cell count (pad to multiple of 7)
    final totalCells = calOffset + daysInMonth;
    final gridCount = totalCells + (7 - totalCells % 7) % 7;

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
                    '${_fmtMs(monthMs)} · $listenedDays day${listenedDays == 1 ? '' : 's'}',
                    style: TextStyle(color: SagaColors.fgMuted, fontSize: 12),
                  ),
              ],
            ),
            IconButton(
              icon: Icon(Icons.chevron_right,
                  color: canGoForward
                      ? SagaColors.fg
                      : SagaColors.fgSubtle.withValues(alpha: 0.3)),
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
                      color: isFuture ? Colors.transparent : _heatColor(ms),
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
                child: _StatCard(
                    label: 'Days listened', value: '$listenedDays')),
            const SizedBox(width: 10),
            Expanded(
                child: _StatCard(
                    label: 'Best day',
                    value: bestDayMs > 0 ? _fmtMs(bestDayMs) : '–')),
            const SizedBox(width: 10),
            Expanded(
                child: _StatCard(
                    label: 'Avg / day',
                    value: avgDayMs > 0 ? _fmtMs(avgDayMs) : '–')),
          ],
        ),

        // By week
        if (weekTotals.any((w) => w > 0)) ...[
          const SizedBox(height: 20),
          Text('BY WEEK',
              style: _monoLabel.copyWith(color: SagaColors.fgSubtle)),
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
                      e.value > 0 ? _fmtMs(e.value) : '–',
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
              style: _monoLabel.copyWith(color: SagaColors.fgSubtle)),
          const SizedBox(height: 10),
          ...booksThisMonth.map((b) {
            final saved = BookmarkStore.load(b.ratingKey);
            final total = b.totalDurationMs ?? saved?.totalDurationMs;
            final pct = (saved != null && total != null && total > 0)
                ? (saved.absolutePositionMs / total).clamp(0.0, 1.0)
                : 0.0;
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
                            thumbPath: b.thumbPath, cacheWidth: 96),
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
                            ? SagaColors.accent
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
        padding: EdgeInsets.fromLTRB(20, 20, 20, bottom + 20),
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
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (ms > 0)
                  Text(_fmtMs(ms),
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
                color: SagaColors.accent,
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

// ── Stat card ─────────────────────────────────────────────────────────────────

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  const _StatCard({required this.label, required this.value});

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

// ── TOTAL TAB ─────────────────────────────────────────────────────────────────

class _TotalTab extends ConsumerWidget {
  final String? libraryKey;
  const _TotalTab({this.libraryKey});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = DateTime.now();
    final todayClean = DateTime(today.year, today.month, today.day);

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
    int longestStreak = 0;
    int run = 0;
    for (int i = 0; i < 365; i++) {
      final day = todayClean.subtract(Duration(days: i));
      if (ListeningHistoryStore.getMs(day) > 0) {
        run++;
        if (run > longestStreak) longestStreak = run;
      } else {
        run = 0;
      }
    }
    final currentStreak = _computeStreak().current;
    if (currentStreak > longestStreak) longestStreak = currentStreak;

    // 13-week heatmap — normalize heatStart to midnight (subtract can land on
    // 23:00 or 01:00 local time when crossing a DST boundary).
    final rawHeatStart =
        todayClean.subtract(Duration(days: today.weekday - 1 + 7 * 12));
    final heatStart =
        DateTime(rawHeatStart.year, rawHeatStart.month, rawHeatStart.day);
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
            style: _monoLabel.copyWith(color: SagaColors.fgSubtle)),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
                child: _StatCard(
                    label: 'Books finished',
                    value: '${completedBooks.length}')),
            const SizedBox(width: 10),
            Expanded(
                child:
                    _StatCard(label: 'Total hours', value: '$totalHours')),
            const SizedBox(width: 10),
            Expanded(
                child: _StatCard(
                    label: 'Avg / day',
                    value: avgDayMs > 0 ? _fmtMs(avgDayMs) : '–')),
          ],
        ),

        // Finished books horizontal shelf
        if (completedBooks.isNotEmpty) ...[
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('FINISHED BOOKS',
                  style: _monoLabel.copyWith(color: SagaColors.fgSubtle)),
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
                                cacheWidth: 164),
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
            style: _monoLabel.copyWith(color: SagaColors.fgSubtle)),
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
                value: bestMs > 0 ? _fmtMs(bestMs) : '–',
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
              style: _monoLabel.copyWith(color: SagaColors.fgSubtle)),
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
                      final rawDate =
                          heatStart.add(Duration(days: col * 7 + row));
                      // Normalize to midnight so the lookup matches getRange keys.
                      final date = DateTime(
                          rawDate.year, rawDate.month, rawDate.day);
                      final isFuture = date.isAfter(todayClean);
                      final isToday = date == todayClean;
                      final ms =
                          isFuture ? 0 : (data[date] ?? 0);
                      return Padding(
                        padding: EdgeInsets.only(
                            bottom: row < _rows - 1 ? _gap : 0),
                        child: Container(
                          width: cellW,
                          height: cellH,
                          decoration: BoxDecoration(
                            color: isFuture
                                ? Colors.transparent
                                : _heatColor(ms),
                            borderRadius: BorderRadius.circular(3),
                            border: isToday
                                ? Border.all(
                                    color: SagaColors.accent, width: 1.5)
                                : null,
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
              Text('Less ',
                  style: TextStyle(
                      color: SagaColors.fgSubtle, fontSize: 10)),
              ...[
                SagaColors.heatEmpty,
                SagaColors.heat1,
                SagaColors.heat2,
                SagaColors.heat3,
                SagaColors.heatMax,
              ].map((c) => Container(
                    width: 11,
                    height: 11,
                    margin: const EdgeInsets.only(left: 3),
                    decoration: BoxDecoration(
                        color: c,
                        borderRadius: BorderRadius.circular(2)),
                  )),
              Text(' More',
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
