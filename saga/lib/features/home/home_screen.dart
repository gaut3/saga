import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/plex/models/plex_book.dart';
import '../../core/plex/models/plex_track.dart';
import '../../core/providers.dart';
import '../../core/storage/settings_store.dart';
import '../../shared/widgets/book_cover_image.dart';
import '../../core/storage/bookmark_store.dart';
import '../../core/storage/chapter_store.dart';
import '../../core/storage/completed_books_store.dart';
import '../../core/storage/custom_collection_store.dart';
import '../../core/storage/listening_history_store.dart';
import '../../core/theme/saga_theme.dart';
import '../../shared/widgets/saga_mark.dart'
    show SagaWordmark, AnimatedSagaMark, SagaMarkState;
import '../auth/server_selection_screen.dart';
import '../collections/collection_detail_screen.dart';
import '../library/book_detail_screen.dart';
import '../player/player_provider.dart';
import '../player/player_screen.dart';
import 'all_bookmarks_screen.dart';
import 'history_screen.dart';

class BookProgressOverlay extends ConsumerWidget {
  final PlexBook book;
  const BookProgressOverlay({super.key, required this.book});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(bookmarkRevisionProvider);
    ref.watch(completionRevisionProvider);

    if (CompletedBooksStore.isCompleted(book.ratingKey)) {
      return Positioned(
        top: 6,
        right: 6,
        child: Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: SagaColors.accent,
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.check, color: SagaColors.accentFg, size: 13),
        ),
      );
    }

    final pos = BookmarkStore.load(book.ratingKey);
    if (pos == null || pos.absolutePositionMs <= 0) return const SizedBox.shrink();

    final duration = book.totalDurationMs ?? pos.totalDurationMs;
    final progress = (duration != null && duration > 0)
        ? (pos.absolutePositionMs / duration).clamp(0.04, 1.0)
        : 0.08;

    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(8)),
        child: LinearProgressIndicator(
          value: progress,
          backgroundColor: Colors.black45,
          valueColor: AlwaysStoppedAnimation<Color>(SagaColors.accent),
          minHeight: 5,
        ),
      ),
    );
  }
}

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
        error: (e, _) => _ErrorView(error: e, onRetry: () => ref.invalidate(activeLibraryKeyProvider)),
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
          height: 170,
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            scrollDirection: Axis.horizontal,
            itemCount: books.length,
            itemBuilder: (context, index) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: _BookTile(book: books[index], width: 120),
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
          height: 170,
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
      width: 120,
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

class _BookTile extends ConsumerWidget {
  final PlexBook book;
  final double? width;

  const _BookTile({required this.book, this.width});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasDownload = ref
        .watch(downloadNotifierProvider)
        .downloadedBooks
        .contains(book.ratingKey);

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => BookDetailScreen(book: book)),
      ),
      child: SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 1.0,
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: BookCoverImage(thumbPath: book.thumbPath),
                  ),
                  BookProgressOverlay(book: book),
                  if (hasDownload)
                    Positioned(
                      bottom: 6,
                      right: 6,
                      child: Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          color: SagaColors.bg.withValues(alpha: 0.85),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.download_done_rounded,
                            color: SagaColors.accent, size: 12),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 5),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    book.title,
                    style: TextStyle(
                      color: SagaColors.fg,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (book.authorName != null)
                    Text(
                      book.authorName!,
                      style: TextStyle(color: SagaColors.fgSubtle, fontSize: 10),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

}


class _ErrorView extends StatelessWidget {
  final Object error;
  final VoidCallback onRetry;

  const _ErrorView({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
          const SizedBox(height: 12),
          Text('$error',
              textAlign: TextAlign.center,
              style: TextStyle(color: SagaColors.fgMuted)),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: onRetry,
            style: ElevatedButton.styleFrom(
              backgroundColor: SagaColors.accent,
              foregroundColor: SagaColors.accentFg,
            ),
            child: const Text('Retry'),
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
              backgroundColor: SagaColors.accent,
              foregroundColor: SagaColors.accentFg,
            ),
            child: const Text('Select Server'),
          ),
        ],
      ),
    );
  }
}

// ── Listening strip ───────────────────────────────────────────────────────────

String _homeFmtMs(int ms) {
  final h = ms ~/ 3600000;
  final m = (ms % 3600000) ~/ 60000;
  if (h > 0) return '${h}h ${m}m';
  if (m > 0) return '${m}m';
  return '<1m';
}

int _homeStreak() {
  final today = DateTime.now();
  final todayClean = DateTime(today.year, today.month, today.day);
  int streak = 0;
  var d = todayClean;
  while (ListeningHistoryStore.getMs(d) > 0) {
    streak++;
    d = d.subtract(const Duration(days: 1));
  }
  return streak;
}

class _ListeningStrip extends ConsumerWidget {
  const _ListeningStrip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(sagaThemeVariantProvider);
    ref.watch(historyRevisionProvider);
    final libraryKey = ref.watch(activeLibraryKeyProvider).valueOrNull;

    final today = DateTime.now();
    final todayClean = DateTime(today.year, today.month, today.day);
    final mondayRaw = todayClean.subtract(Duration(days: today.weekday - 1));
    // Renormalize: Duration subtraction lands at 23:00 on a DST spring-forward
    // Sunday, shifting every weekday entry one hour early and zeroing bar data.
    final monday = DateTime(mondayRaw.year, mondayRaw.month, mondayRaw.day);
    final weekDays = List.generate(7, (i) => monday.add(Duration(days: i)));
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
                          ? '${_homeFmtMs(weekTotal)} this week'
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
    final maxMs = weekMs.fold(0, (a, b) => b > a ? b : a);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: List.generate(7, (i) {
        final isToday = weekDays[i] == todayClean;
        final isFuture = weekDays[i].isAfter(todayClean);
        final fraction = maxMs > 0 ? weekMs[i] / maxMs : 0.0;
        final h = weekMs[i] > 0 ? (28.0 * fraction).clamp(3.0, 28.0) : 3.0;
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 1),
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                height: h,
                decoration: BoxDecoration(
                  color: isFuture
                      ? SagaColors.heatEmpty
                      : isToday
                          ? SagaColors.accent
                          : weekMs[i] > 0
                              ? SagaColors.accent.withValues(alpha: 0.42)
                              : SagaColors.heatEmpty,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
        );
      }),
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
            height: 170,
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              scrollDirection: Axis.horizontal,
              itemCount: rest.length,
              itemBuilder: (context, index) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: _BookTile(book: rest[index], width: 120),
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
    final total = widget.book.totalDurationMs ?? savedPos?.totalDurationMs;
    final absolute = savedPos?.absolutePositionMs ?? 0;
    final pct = (total != null && total > 0)
        ? (absolute / total).clamp(0.0, 1.0)
        : 0.0;
    final remainingMs =
        (total != null && total > 0) ? (total - absolute).clamp(0, total) : null;

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
              onTap: () {
                Navigator.of(context, rootNavigator: true)
                    .push(MaterialPageRoute(builder: (_) => const PlayerScreen()));
                if (!isNowPlaying) _loadOnly();
              },
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
                          thumbPath: widget.book.thumbPath, cacheWidth: 320),
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
                                    '${_homeFmtMs(remainingMs)} left',
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
            Material(
              color: SagaColors.accent,
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
      var ci = 0;
      for (var i = 0; i < chaps.length; i++) {
        if (pos.positionMs >= chaps[i].start.inMilliseconds) ci = i;
      }
      return 'Ch. ${ci + 1} · ${chaps[ci].title}';
    }
    final idx = tracks.indexWhere((t) => t.ratingKey == pos.trackRatingKey);
    if (idx < 0) return null;
    return 'Ch. ${idx + 1} · ${tracks[idx].title}';
  }

  Future<void> _loadOnly() async {
    final service = ref.read(playerServiceProvider);
    if (service.currentBookRatingKey == widget.book.ratingKey) return;
    try {
      final tracks =
          await ref.read(tracksProvider(widget.book.ratingKey).future);
      if (!mounted) return;
      final savedPos = BookmarkStore.load(widget.book.ratingKey);
      final idx = savedPos != null
          ? tracks.indexWhere((t) => t.ratingKey == savedPos.trackRatingKey)
          : -1;
      await service.loadBook(
        bookRatingKey: widget.book.ratingKey,
        tracks: tracks,
        startTrackIndex: idx < 0 ? 0 : idx,
        startPositionMs: savedPos?.positionMs ?? 0,
        applyResumeRewind: true,
      );
    } catch (_) {}
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
      final savedPos = BookmarkStore.load(widget.book.ratingKey);
      final idx = savedPos != null
          ? tracks.indexWhere((t) => t.ratingKey == savedPos.trackRatingKey)
          : -1;
      await service.loadBook(
        bookRatingKey: widget.book.ratingKey,
        tracks: tracks,
        startTrackIndex: idx < 0 ? 0 : idx,
        startPositionMs: savedPos?.positionMs ?? 0,
        applyResumeRewind: true,
      );
      await service.play();
    } catch (_) {
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
          height: 170,
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            scrollDirection: Axis.horizontal,
            itemCount: books.length,
            itemBuilder: (context, i) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: _BookTile(book: books[i], width: 120),
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
