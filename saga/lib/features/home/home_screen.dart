import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/book_progress.dart';
import '../../core/diagnostics/app_log.dart';
import '../../core/plex/models/plex_book.dart';
import '../../core/plex/models/plex_track.dart';
import '../../core/providers.dart';
import '../../core/stats/streak.dart';
import '../../core/storage/settings_store.dart';
import '../../shared/widgets/book_card.dart';
import '../../shared/widgets/book_cover_image.dart';
import '../../shared/widgets/saga_error_view.dart';
import '../../shared/widgets/saga_toast.dart';
import '../../core/storage/bookmark_store.dart';
import '../../core/storage/chapter_store.dart';
import '../../core/storage/custom_collection_store.dart';
import '../../core/storage/listening_history_store.dart';
import '../../core/storage/want_to_read_store.dart';
import '../../core/theme/saga_theme.dart';
import '../../core/utils/date_math.dart';
import '../../core/utils/format.dart';
import '../../shared/widgets/saga_mark.dart'
    show SagaWordmark, AnimatedSagaMark, SagaMarkState;
import '../auth/server_selection_screen.dart';
import '../collections/collection_detail_screen.dart';
import '../../shared/widgets/week_bars.dart';
import '../player/book_launch.dart';
import '../player/open_player.dart';
import '../player/player_provider.dart';
import '../player/player_screen.dart';
import '../player/track_position_math.dart';
import 'all_bookmarks_screen.dart';
import 'history_screen.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(sagaThemeVariantProvider);
    final libraryKeyAsync = ref.watch(activeLibraryKeyProvider);

    return Scaffold(
      backgroundColor: SagaColors.bg,
      body: libraryKeyAsync.when(
        loading: () => Center(
          child: CircularProgressIndicator(color: SagaColors.accent),
        ),
        error: (e, _) => SagaErrorView(
            message: 'Could not load your library',
            error: e,
            onRetry: () => ref.invalidate(activeLibraryKeyProvider)),
        data: (key) {
          if (key == null) {
            return _NoServerView(onSelectServer: () => _openServerSelection(context, ref));
          }
          return _HomeContent(libraryKey: key);
        },
      ),
    );
  }

  void _openServerSelection(BuildContext context, WidgetRef ref) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ServerSelectionScreen()),
    ).then((_) => ref.invalidate(activeLibraryKeyProvider));
  }
}

class _HomeContent extends ConsumerWidget {
  final String libraryKey;
  const _HomeContent({required this.libraryKey});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(sagaThemeVariantProvider);
    ref.watch(wantToReadRevisionProvider);
    final continueAsync = ref.watch(continueListeningProvider(libraryKey));
    final upNextAsync = ref.watch(upNextSeriesQueuesProvider(libraryKey));
    final recentAsync = ref.watch(recentlyAddedProvider(libraryKey));

    // Keys already shown above — exclude from Recently Added to avoid duplicates.
    final shownKeys = {
      ...?continueAsync.valueOrNull?.map((b) => b.ratingKey),
      ...?upNextAsync.valueOrNull
          ?.expand((p) => p.$2.map((b) => b.ratingKey)),
    };

    return CustomScrollView(
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
          title: SagaWordmark(fontSize: 24),
          actions: [
            IconButton(
              icon: const Icon(Icons.bookmark_border),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AllBookmarksScreen()),
              ),
            ),
          ],
        ),

        SliverToBoxAdapter(child: const _ListeningStrip()),

        // valueOrNull returns the previous list while the provider is
        // refreshing (e.g. on every bookmark save), so the section never
        // flickers away during an active session.
        Builder(builder: (_) {
          final books = continueAsync.valueOrNull;
          if (books == null || books.isEmpty) {
            return const SliverToBoxAdapter(child: SizedBox.shrink());
          }
          return SliverToBoxAdapter(child: _ContinueListeningSection(books: books));
        }),

        SliverToBoxAdapter(
          child: _UpNextSection(libraryKey: libraryKey),
        ),

        recentAsync.when(
          loading: () => const SliverToBoxAdapter(
            child: _SkeletonSection(title: 'Recently Added'),
          ),
          error: (_, _) => const SliverToBoxAdapter(child: SizedBox.shrink()),
          data: (books) {
            final filtered = shownKeys.isEmpty
                ? books
                : books.where((b) => !shownKeys.contains(b.ratingKey)).toList();
            if (filtered.isEmpty) return const SliverToBoxAdapter(child: SizedBox.shrink());
            return SliverToBoxAdapter(
              child: _Section(title: 'Recently Added', books: filtered),
            );
          },
        ),

        Builder(builder: (_) {
          final wantedKeys = WantToReadStore.all;
          if (wantedKeys.isEmpty) {
            return const SliverToBoxAdapter(child: SizedBox.shrink());
          }
          final allBooks = recentAsync.valueOrNull ?? [];
          // Pull from booksProvider if recently-added doesn't cover all wanted
          final booksAsync = ref.watch(booksProvider(libraryKey));
          final fullList = booksAsync.valueOrNull ?? allBooks;
          final wanted = fullList
              .where((b) => wantedKeys.contains(b.ratingKey))
              .toList();
          if (wanted.isEmpty) {
            return const SliverToBoxAdapter(child: SizedBox.shrink());
          }
          return SliverToBoxAdapter(
            child: _Section(title: 'Want to Read', books: wanted),
          );
        }),

        SliverPadding(
            padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).padding.bottom + 16)),
      ],
    );
  }

}

class _Section extends StatelessWidget {
  final String title;
  final List<PlexBook> books;

  const _Section({required this.title, required this.books});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Text(
            title,
            style: TextStyle(
              color: SagaColors.fg,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        SizedBox(
          height: kBookStripHeight,
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            scrollDirection: Axis.horizontal,
            itemCount: books.length,
            itemBuilder: (context, index) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: BookCard(book: books[index], width: kBookStripCoverWidth),
            ),
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _SkeletonSection extends StatelessWidget {
  final String title;
  const _SkeletonSection({required this.title});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Text(
            title,
            style: TextStyle(
              color: SagaColors.fg,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        SizedBox(
          height: kBookStripHeight,
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            scrollDirection: Axis.horizontal,
            itemCount: 6,
            itemBuilder: (_, i) => const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4),
              child: _SkeletonTile(),
            ),
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _SkeletonTile extends StatelessWidget {
  const _SkeletonTile();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: kBookStripCoverWidth,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 1.0,
            child: Container(
              decoration: BoxDecoration(
                color: SagaColors.surfaceAlt,
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          const SizedBox(height: 5),
          Container(
            height: 12,
            width: 90,
            decoration: BoxDecoration(
              color: SagaColors.surfaceAlt,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 4),
          Container(
            height: 10,
            width: 60,
            decoration: BoxDecoration(
              color: SagaColors.surfaceAlt,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ],
      ),
    );
  }
}

class _NoServerView extends StatelessWidget {
  final VoidCallback onSelectServer;
  const _NoServerView({required this.onSelectServer});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.dns_outlined, size: 64, color: SagaColors.fgSubtle),
          const SizedBox(height: 16),
          Text('Could not connect to a Plex server.',
              style: TextStyle(color: SagaColors.fgMuted, fontSize: 16),
              textAlign: TextAlign.center),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: onSelectServer,
            style: ElevatedButton.styleFrom(
              backgroundColor: SagaColors.accentDim,
              foregroundColor: SagaColors.accentFg,
            ),
            child: const Text('Select server'),
          ),
        ],
      ),
    );
  }
}

// ── Listening strip ───────────────────────────────────────────────────────────

int _homeStreak() =>
    computeStreak(msForDay: ListeningHistoryStore.getMs).current;

class _ListeningStrip extends ConsumerWidget {
  const _ListeningStrip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(sagaThemeVariantProvider);
    ref.watch(historyRevisionProvider);
    final libraryKey = ref.watch(activeLibraryKeyProvider).valueOrNull;

    final todayClean = dayOnly(DateTime.now());
    final weekDays = mondayWeek(todayClean);
    final weekMs = weekDays.map(ListeningHistoryStore.getMs).toList();
    final weekTotal = weekMs.fold(0, (a, b) => a + b);
    final streak = _homeStreak();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: GestureDetector(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
              builder: (ctx) => HistoryScreen(libraryKey: libraryKey)),
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          decoration: BoxDecoration(
            color: SagaColors.surface,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Icon(Icons.local_fire_department,
                  color: SagaColors.accent, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      streak > 0 ? '$streak-day streak' : 'Start your streak',
                      style: TextStyle(
                        color: SagaColors.fg,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      weekTotal > 0
                          ? '${fmtListenedMs(weekTotal)} this week'
                          : 'No listening this week',
                      style:
                          TextStyle(color: SagaColors.fgMuted, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 52,
                height: 32,
                child: _Sparkline(
                    weekMs: weekMs,
                    weekDays: weekDays,
                    todayClean: todayClean),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right, color: SagaColors.fgSubtle, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

class _Sparkline extends StatelessWidget {
  final List<int> weekMs;
  final List<DateTime> weekDays;
  final DateTime todayClean;
  const _Sparkline(
      {required this.weekMs,
      required this.weekDays,
      required this.todayClean});

  @override
  Widget build(BuildContext context) {
    // Shared chart, small palette: at 28 px the full accent reads fine.
    return WeekBars(
      weekMs: weekMs,
      weekDays: weekDays,
      todayClean: todayClean,
      maxBarHeight: 28,
      minBarHeight: 3,
      barPadding: 1,
      cornerRadius: 2,
      todayColor: SagaColors.accent,
      activeColor: SagaColors.accent.withValues(alpha: 0.42),
    );
  }
}

// ── Continue Listening section with resume card ───────────────────────────────

class _ContinueListeningSection extends StatelessWidget {
  final List<PlexBook> books;
  const _ContinueListeningSection({required this.books});

  @override
  Widget build(BuildContext context) {
    final rest = books.length > 1 ? books.sublist(1) : const <PlexBook>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle('Continue Listening'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _ResumeCard(book: books.first),
        ),
        if (rest.isNotEmpty) ...[
          const SizedBox(height: 18),
          const _SectionTitle('Also in progress'),
          SizedBox(
            height: kBookStripHeight,
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              scrollDirection: Axis.horizontal,
              itemCount: rest.length,
              itemBuilder: (context, index) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: BookCard(book: rest[index], width: kBookStripCoverWidth),
              ),
            ),
          ),
        ],
        const SizedBox(height: 8),
      ],
    );
  }
}

/// Shared section header used across the home screen.
class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Text(
        title,
        style: TextStyle(
          color: SagaColors.fg,
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

// ── Resume card ───────────────────────────────────────────────────────────────

class _ResumeCard extends ConsumerStatefulWidget {
  final PlexBook book;
  const _ResumeCard({required this.book});

  @override
  ConsumerState<_ResumeCard> createState() => _ResumeCardState();
}

class _ResumeCardState extends ConsumerState<_ResumeCard> {
  bool _loading = false;

  @override
  Widget build(BuildContext context) {
    // Clear loading state the moment this book actually starts playing,
    // so we jump straight from loading animation to playing animation
    // without a flash of the paused/resume state.
    ref.listen(nowPlayingKeyProvider, (_, next) {
      if (next.valueOrNull == widget.book.ratingKey && _loading) {
        setState(() => _loading = false);
      }
    });

    final savedPos = BookmarkStore.load(widget.book.ratingKey);
    final total = bookTotalDurationMs(widget.book, savedPos);
    final absolute = savedPos?.absolutePositionMs ?? 0;
    final pct = bookProgressFraction(widget.book, savedPos) ?? 0.0;
    final remainingMs = total != null ? (total - absolute).clamp(0, total) : null;

    final nowPlayingKey = ref.watch(nowPlayingKeyProvider).valueOrNull;
    final isNowPlaying = nowPlayingKey == widget.book.ratingKey;

    // Tracks are fetched lazily for the hero book so we can label the current
    // chapter; the result is cached and reused when the player opens.
    final tracks = ref.watch(tracksProvider(widget.book.ratingKey)).valueOrNull;
    final chapterLabel = _chapterLabel(tracks, savedPos);

    return Container(
      decoration: BoxDecoration(
        color: SagaColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: isNowPlaying
                ? SagaColors.accent
                : SagaColors.accent.withValues(alpha: 0.4),
            width: 1.5),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Column(
          children: [
            // ── Tap the body to open the player ──
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _openPlayerView,
              child: SizedBox(
                height: 152,
                child: Row(
                  children: [
                    // Square footprint so square covers aren't cropped on the
                    // sides (BoxFit.cover in a portrait box clipped left/right).
                    SizedBox(
                      width: 152,
                      height: 152,
                      child: BookCoverImage(
                          thumbPath: widget.book.thumbPath,
                          cacheWidth: kCoverCacheWidthCard),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.book.title,
                              style: TextStyle(
                                  color: SagaColors.fg,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (chapterLabel != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                chapterLabel,
                                style: TextStyle(
                                    color: SagaColors.fgMuted, fontSize: 12.5),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                            const Spacer(),
                            Row(
                              children: [
                                if (remainingMs != null)
                                  Text(
                                    '${fmtListenedMs(remainingMs)} left',
                                    style: TextStyle(
                                        color: SagaColors.fg,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700),
                                  ),
                                const Spacer(),
                                Text(
                                  '${(pct * 100).round()}%',
                                  style: TextStyle(
                                      color: SagaColors.fgSubtle, fontSize: 13),
                                ),
                              ],
                            ),
                            const SizedBox(height: 7),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: pct,
                                backgroundColor: SagaColors.surfaceAlt,
                                valueColor:
                                    AlwaysStoppedAnimation(SagaColors.accent),
                                minHeight: 7,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // ── Accent footer: the primary play/pause action ──
            // accentDim, not accent: this is the widest amber area in the app
            // (see SagaColors.accentDim). Identical outside Onyx.
            Material(
              color: SagaColors.accentDim,
              child: InkWell(
                onTap: _loading ? null : (isNowPlaying ? _pause : _resume),
                child: SizedBox(
                  height: 50,
                  // Label is centred and the mark is pinned to a fixed spot, so
                  // neither jumps as the label changes width.
                  child: Stack(
                    children: [
                      Center(
                        child: Text(
                          _loading
                              ? 'Loading…'
                              : isNowPlaying
                                  ? 'Pause'
                                  : 'Resume listening',
                          style: TextStyle(
                              color: SagaColors.accentFg,
                              fontSize: 15,
                              fontWeight: FontWeight.w700),
                        ),
                      ),
                      Positioned(
                        left: 24,
                        top: 0,
                        bottom: 0,
                        // Our own mark, monochrome on the accent button: the
                        // play triangle morphs to/from the pause bars, and the
                        // bars shimmer (converging into the pause glyph) while
                        // loading — no 4-spine flash in between.
                        child: Center(
                          child: AnimatedSagaMark(
                            size: 24,
                            monoColor: SagaColors.accentFg,
                            playPauseControl: true,
                            loading: _loading,
                            state: (isNowPlaying || _loading)
                                ? SagaMarkState.playing
                                : SagaMarkState.paused,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// "Ch. N · Title" for the saved position, or null if unknown. Single-file
  /// M4B books use the cached embedded chapters; multi-track books use the
  /// track at the saved position.
  String? _chapterLabel(List<PlexTrack>? tracks, BookPosition? pos) {
    if (tracks == null || tracks.isEmpty || pos == null) return null;
    if (tracks.length == 1) {
      final chaps = ChapterStore.load(pos.trackRatingKey);
      if (chaps == null || chaps.isEmpty) return null;
      // Through the shared [chapterIndexAt], like the player, the mini player,
      // the notification and both chapter lists — this card was the seventh
      // hand-rolled copy of the same loop.
      final ci = chapterIndexAt(
          [for (final c in chaps) c.start.inMilliseconds], pos.positionMs);
      return 'Ch. ${ci + 1} · ${chaps[ci].title}';
    }
    final idx = tracks.indexWhere((t) => t.ratingKey == pos.trackRatingKey);
    if (idx < 0) return null;
    return 'Ch. ${idx + 1} · ${tracks[idx].title}';
  }

  /// Tapping the card body opens the player. When the card's book is already
  /// the loaded one (playing or paused) that's a plain push; otherwise the
  /// book is loaded without starting audio, through the shared helper — the
  /// silent inline version left a blank "Now Playing" with no title and no
  /// error when the load failed, while the footer button right below
  /// explained itself.
  Future<void> _openPlayerView() async {
    final service = ref.read(playerServiceProvider);
    if (service.currentBookRatingKey == widget.book.ratingKey) {
      Navigator.of(context, rootNavigator: true)
          .push(MaterialPageRoute(builder: (_) => const PlayerScreen()));
      return;
    }
    await openPlayerAndStart(
      context: context,
      service: service,
      bookRatingKey: widget.book.ratingKey,
      loadTracks: () => ref.read(tracksProvider(widget.book.ratingKey).future),
      from: const BookStartPoint.resume(),
      playback: LaunchPlayback.none,
    );
  }

  Future<void> _resume() async {
    if (_loading) return;
    final service = ref.read(playerServiceProvider);
    // If this book is already loaded (paused), just play without reloading.
    if (service.currentBookRatingKey == widget.book.ratingKey) {
      await service.play();
      return;
    }
    setState(() => _loading = true);
    try {
      final tracks =
          await ref.read(tracksProvider(widget.book.ratingKey).future);
      if (!mounted) return;
      await startBook(
        service: service,
        bookRatingKey: widget.book.ratingKey,
        tracks: tracks,
        from: const BookStartPoint.resume(),
      );
    } catch (e) {
      // "Loading…" quietly reverting to "Resume listening" reads as a dead
      // button — say what happened instead.
      AppLog.log('playback', 'home resume failed: $e');
      if (mounted) {
        showSagaToast(context,
            'Couldn\'t load this book — is the server reachable?',
            isError: true);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pause() async {
    await ref.read(playerServiceProvider).pause();
  }
}

// ── Up Next in Series ─────────────────────────────────────────────────────────

class _UpNextSection extends ConsumerStatefulWidget {
  final String libraryKey;
  const _UpNextSection({required this.libraryKey});

  @override
  ConsumerState<_UpNextSection> createState() => _UpNextSectionState();
}

class _UpNextSectionState extends ConsumerState<_UpNextSection> {
  late bool _nudgeDismissed;

  @override
  void initState() {
    super.initState();
    _nudgeDismissed = SettingsStore.upNextNudgeDismissed;
  }

  @override
  Widget build(BuildContext context) {
    final upNextAsync = ref.watch(upNextSeriesQueuesProvider(widget.libraryKey));
    // Keep the last data during background refreshes (the provider re-runs on
    // every bookmark save, ~10 s) so the section doesn't flicker to a skeleton.
    final queues = upNextAsync.valueOrNull;
    if (queues == null) {
      return upNextAsync.hasError
          ? const SizedBox.shrink()
          : const _SkeletonSection(title: 'Up Next in Series');
    }
    if (queues.isEmpty) {
      if (_nudgeDismissed) return const SizedBox.shrink();
      return _UpNextNudge(
        onCreate: () => ref.read(tabIndexProvider.notifier).state = 3,
        onDismiss: () async {
          await SettingsStore.setUpNextNudgeDismissed(true);
          if (!mounted) return;
          setState(() => _nudgeDismissed = true);
        },
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (col, books) in queues)
          _SeriesQueueRow(
            libraryKey: widget.libraryKey,
            collection: col,
            books: books,
          ),
      ],
    );
  }
}

/// One series' upcoming queue: a tappable header (`Up next · series` + chevron
/// into the collection) above a row of the next few books.
class _SeriesQueueRow extends StatelessWidget {
  final String libraryKey;
  final CustomCollection collection;
  final List<PlexBook> books;

  const _SeriesQueueRow({
    required this.libraryKey,
    required this.collection,
    required this.books,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => CollectionDetailScreen(
                collection: collection,
                libraryKey: libraryKey,
              ),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 12, 12),
            child: Row(
              children: [
                Text(
                  'Up next in ',
                  style: TextStyle(
                    color: SagaColors.accent,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Expanded(
                  child: Text(
                    collection.name,
                    style: TextStyle(
                      color: SagaColors.fg,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(Icons.chevron_right, color: SagaColors.fgSubtle, size: 22),
              ],
            ),
          ),
        ),
        SizedBox(
          height: kBookStripHeight,
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            scrollDirection: Axis.horizontal,
            itemCount: books.length,
            itemBuilder: (context, i) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: BookCard(book: books[i], width: kBookStripCoverWidth),
            ),
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _UpNextNudge extends StatelessWidget {
  final VoidCallback onCreate;
  final VoidCallback onDismiss;
  const _UpNextNudge({required this.onCreate, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Material(
        color: SagaColors.surface,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onCreate,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
            child: Row(
              children: [
                Icon(Icons.auto_stories_outlined,
                    color: SagaColors.fgMuted, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Add books to a Collection to track your series',
                    style: TextStyle(color: SagaColors.fgMuted, fontSize: 13),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.close, color: SagaColors.fgSubtle, size: 18),
                  onPressed: onDismiss,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
