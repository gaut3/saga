import 'package:flutter/material.dart';
import '../../core/theme/saga_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/audio/m4b_chapter_reader.dart';
import '../../core/book_progress.dart';
import '../../core/plex/models/plex_book.dart';
import '../../core/plex/models/plex_track.dart';
import '../../core/plex/plex_client.dart';
import '../../core/providers.dart';
import '../../shared/widgets/book_cover_image.dart';
import '../../shared/widgets/confirm_dialog.dart';
import '../../shared/widgets/meta_chip.dart';
import 'effective_chapter_count.dart';
import '../../core/storage/bookmark_store.dart';
import '../../core/storage/completed_books_store.dart';
import '../../core/storage/custom_collection_store.dart';
import '../../core/storage/want_to_read_store.dart';
import '../collections/collection_picker_sheet.dart';
import '../player/book_launch.dart';
import '../player/open_player.dart';
import '../player/player_provider.dart';
import '../player/track_position_math.dart';
import '../../core/utils/format.dart';
import '../../core/utils/text_measure.dart';
import '../../shared/widgets/saga_mark.dart' show AnimatedSagaMark, SagaMarkState;

class BookDetailScreen extends ConsumerStatefulWidget {
  final PlexBook book;
  const BookDetailScreen({super.key, required this.book});

  @override
  ConsumerState<BookDetailScreen> createState() => _BookDetailScreenState();
}

class _BookDetailScreenState extends ConsumerState<BookDetailScreen> {
  // Deliberately no completed-state field: the player also writes completions
  // (the 95% auto-complete) while this screen can sit alive in the tab stack,
  // and a mirror captured at open time went stale — tapping the still-stale
  // "mark completed" appended a second completion for one listen. The build
  // reads the store, watching completionRevisionProvider for changes.
  late bool _isWanted;

  @override
  void initState() {
    super.initState();
    _isWanted = WantToReadStore.isWanted(widget.book.ratingKey);
  }

  Future<void> _toggleWantToRead() async {
    await WantToReadStore.toggle(widget.book.ratingKey);
    setState(() => _isWanted = WantToReadStore.isWanted(widget.book.ratingKey));
    ref.read(wantToReadRevisionProvider.notifier).state++;
  }

  Future<void> _toggleCompleted() async {
    // Read the store at tap time, not a field cached at screen open — see the
    // note on the state class.
    if (CompletedBooksStore.isCompleted(widget.book.ratingKey)) {
      await CompletedBooksStore.markIncomplete(widget.book.ratingKey);
    } else {
      await CompletedBooksStore.markCompleted(widget.book.ratingKey);
    }
    ref.read(completionRevisionProvider.notifier).state++;
  }

  void _showAddToCollectionSheet(BuildContext context) {
    showCollectionPickerSheet(
      context,
      title: 'Add to collection',
      isSelected: (col) =>
          col.bookRatingKeys.contains(widget.book.ratingKey),
      onPick: (col) async {
        if (col.bookRatingKeys.contains(widget.book.ratingKey)) {
          await CustomCollectionStore.removeBook(
              col.id, widget.book.ratingKey);
        } else {
          await CustomCollectionStore.addBook(col.id, widget.book.ratingKey,
              coverThumbPath: widget.book.thumbPath);
        }
        ref.read(customCollectionRevisionProvider.notifier).state++;
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // This screen lives pushed on a tab stack, which survives in the
    // IndexedStack while other tabs are visited — nothing rebuilds it from
    // above, so it watches theme changes itself (the project's standing rule
    // for exactly this situation).
    ref.watch(sagaThemeVariantProvider);
    // And the position: without this, the progress bar, "resume at" figure and
    // current-chapter highlight below froze at open-time values while the same
    // book's card on Home ticked along off the mini player.
    ref.watch(bookmarkRevisionProvider);
    // Completed-state is read fresh each build (the player writes completions
    // too); watching the revision is what makes that read re-run.
    ref.watch(completionRevisionProvider);
    final isCompleted = CompletedBooksStore.isCompleted(widget.book.ratingKey);
    // The library listing is abbreviated — narrator and genre only exist on the
    // per-book record, fetched lazily the first time a book is opened. Until it
    // lands (or if it fails) this is the listing record unchanged.
    final book = enrichedBook(ref, widget.book);
    final tracksAsync = ref.watch(tracksProvider(book.ratingKey));
    final savedPosition = BookmarkStore.load(book.ratingKey);
    // Falls back to the length recorded in the saved position when Plex hasn't
    // reported one. This screen used to read Plex's field alone, so a book Home
    // was drawing a progress bar for showed neither a length nor a bar here.
    final bookLengthMs = bookTotalDurationMs(book, savedPosition);

    // Prefers M4B embedded chapters over Plex leafCount (which is always 1 for
    // a single M4B file regardless of how many chapters it holds).
    final chapterCount = effectiveChapterCount(ref, book);

    return Scaffold(
      backgroundColor: SagaColors.bg,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 280,
            pinned: true,
            backgroundColor: SagaColors.surface,
            foregroundColor: SagaColors.fg,
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: const EdgeInsetsDirectional.only(
                  start: 56, end: 16, bottom: 14),
              title: Text(
                book.title,
                style: const TextStyle(fontSize: 14),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              background: book.thumbPath != null
                  ? Stack(
                      fit: StackFit.expand,
                      children: [
                        BookCoverImage(
                            thumbPath: book.thumbPath,
                            cacheWidth: kCoverCacheWidthDetail,
                            letterboxed: true),
                        // Gradient scrim — stronger at the bottom where title sits
                        DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.black.withValues(alpha: 0.15),
                                Colors.black.withValues(alpha: 0.75),
                              ],
                              stops: const [0.4, 1.0],
                            ),
                          ),
                        ),
                      ],
                    )
                  : const CoverPlaceholder(),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (book.authorName != null)
                    Text(
                      book.authorName!,
                      style: TextStyle(
                          color: SagaColors.accentText,
                          fontSize: 15,
                          fontWeight: FontWeight.w500),
                    ),
                  // Who reads it matters as much as who wrote it, so it sits
                  // with the author rather than in the chip row.
                  if (book.narratorLabel != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      'Narrated by ${book.narratorLabel}',
                      style:
                          TextStyle(color: SagaColors.fgMuted, fontSize: 13),
                    ),
                  ],
                  const SizedBox(height: 8),

                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      ...bookMetaChips(book,
                          lengthMs: bookLengthMs, chapterCount: chapterCount),
                      if (CompletedBooksStore.completionCount(
                              book.ratingKey) >
                          0)
                        MetaChip(
                            Icons.replay_rounded,
                            'Listened ${CompletedBooksStore.completionCount(book.ratingKey)}×'),
                      GestureDetector(
                        onTap: _toggleWantToRead,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: _isWanted
                                ? SagaColors.amber.withValues(alpha: 0.15)
                                : SagaColors.surface,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _isWanted
                                    ? Icons.star_rounded
                                    : Icons.star_border_rounded,
                                size: 12,
                                color: _isWanted
                                    ? SagaColors.amber
                                    : SagaColors.fgSubtle,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Want to read',
                                style: TextStyle(
                                  color: _isWanted
                                      ? SagaColors.amber
                                      : SagaColors.fgMuted,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),

                  if (savedPosition != null && bookLengthMs != null) ...[
                    const SizedBox(height: 14),
                    // The book-absolute position, not the position within the
                    // current file: on a twenty-file book the per-track figure
                    // read as 2% while every other surface showed the truth.
                    _ProgressInfo(
                        positionMs: savedPosition.absolutePositionMs,
                        totalMs: bookLengthMs),
                  ],

                  if (book.summary != null &&
                      book.summary!.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    _ExpandableSummary(summary: book.summary!),
                  ],

                  const SizedBox(height: 16),

                  // Row 1: play buttons + compact completed toggle
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: tracksAsync.when(
                          loading: () => const SizedBox.shrink(),
                          error: (_, _) => const SizedBox.shrink(),
                          data: (tracks) => Row(
                            children: [
                              if (savedPosition != null) ...[
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed: () => _openPlayer(
                                      context,
                                      tracks,
                                      resume: true,
                                    ),
                                    icon: const Icon(Icons.play_arrow),
                                    label: const Text('Resume'),
                                    style: ElevatedButton.styleFrom(
                                      // Half-width filled button — accentDim.
                                      backgroundColor: SagaColors.accentDim,
                                      foregroundColor: SagaColors.accentFg,
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 12),
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(10)),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                              ],
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: () =>
                                      _openPlayer(context, tracks),
                                  icon: Icon(isCompleted
                                      ? Icons.replay
                                      : savedPosition != null
                                          ? Icons.restart_alt
                                          : Icons.play_arrow),
                                  label: Text(isCompleted
                                      ? 'Listen again'
                                      : savedPosition != null
                                          ? 'From start'
                                          : 'Play'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: savedPosition != null
                                        ? SagaColors.surfaceAlt
                                        : SagaColors.accentDim,
                                    foregroundColor: savedPosition != null
                                        ? SagaColors.fg
                                        : SagaColors.accentFg,
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 12),
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(10)),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton(
                        onPressed: _toggleCompleted,
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(48, 48),
                          padding:
                              const EdgeInsets.symmetric(horizontal: 14),
                          foregroundColor: isCompleted
                              ? SagaColors.fgMuted
                              : SagaColors.accent,
                          side: BorderSide(
                            color: isCompleted
                                ? SagaColors.fgSubtle
                                : SagaColors.accent,
                          ),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                        child: Icon(
                          isCompleted
                              ? Icons.bookmark_remove_outlined
                              : Icons.bookmark_added_outlined,
                          size: 20,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 8),

                  // Row 2: add to collection + want to read + download
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () =>
                              _showAddToCollectionSheet(context),
                          icon:
                              const Icon(Icons.folder_outlined, size: 18),
                          label: const Text('Collection'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: SagaColors.fgMuted,
                            side:
                                BorderSide(color: SagaColors.fgSubtle),
                            padding:
                                const EdgeInsets.symmetric(vertical: 10),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: tracksAsync.when(
                          loading: () => const SizedBox.shrink(),
                          error: (_, _) => const SizedBox.shrink(),
                          data: (tracks) => _DownloadBookButton(
                            book: book,
                            tracks: tracks,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text(
                'Chapters',
                style: TextStyle(
                  color: SagaColors.fgMuted,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          tracksAsync.when(
            loading: () => SliverToBoxAdapter(
              child: Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: CircularProgressIndicator(
                      color: SagaColors.accent),
                ),
              ),
            ),
            error: (_, _) => SliverToBoxAdapter(
              child: Center(
                child: Text('Could not load chapters',
                    style: const TextStyle(color: Colors.redAccent)),
              ),
            ),
            data: (tracks) => _ChapterListSliver(
              book: book,
              tracks: tracks,
              savedPosition: savedPosition,
            ),
          ),
          SliverPadding(padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom + 16)),
        ],
      ),
    );
  }

  Future<void> _openPlayer(
    BuildContext context,
    List<PlexTrack> tracks, {
    bool resume = false,
  }) async {
    if (!context.mounted) return;
    // Shared helper: pushes the player, and takes it back down on failure —
    // the inline version left the *previous* book's player on screen behind
    // a 4-second toast when the launch failed.
    await openPlayerAndStart(
      context: context,
      service: ref.read(playerServiceProvider),
      bookRatingKey: widget.book.ratingKey,
      loadTracks: () async => tracks,
      from: resume
          ? const BookStartPoint.resume()
          : const BookStartPoint.beginning(),
    );
  }
}

// ── Download entire book button ───────────────────────────────────────────────

class _DownloadBookButton extends ConsumerWidget {
  final PlexBook book;
  final List<PlexTrack> tracks;

  const _DownloadBookButton({required this.book, required this.tracks});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (tracks.isEmpty) return const SizedBox.shrink();

    final downloadState = ref.watch(downloadNotifierProvider);
    final downloadedCount =
        tracks.where((t) => downloadState.completed.contains(t.ratingKey)).length;
    final inProgressCount = tracks
        .where((t) => downloadState.progress.containsKey(t.ratingKey))
        .length;
    final total = tracks.length;
    final allDone = downloadedCount == total;

    // Byte-level progress across all in-flight/queued tracks for this book.
    final bytesInFlight = tracks
        .map((t) => downloadState.progress[t.ratingKey] ?? 0.0)
        .fold(0.0, (a, b) => a + b);
    final markProgress =
        total > 0 ? (downloadedCount + bytesInFlight) / total : 0.0;

    if (allDone) {
      Future<void> confirmDelete() async {
        final confirmed = await confirmDialog(
          context,
          title: 'Delete offline copy?',
          message: 'Remove the downloaded audio from your device. '
              'You can download it again any time.',
          confirmLabel: 'Delete',
          confirmColor: Colors.redAccent,
        );
        if (confirmed && context.mounted) {
          await ref
              .read(downloadNotifierProvider.notifier)
              .deleteBook(book.ratingKey, tracks);
        }
      }

      return SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: confirmDelete,
          icon: const Icon(Icons.download_done, size: 18),
          label: const Text('Downloaded'),
          style: OutlinedButton.styleFrom(
            foregroundColor: SagaColors.accent,
            side: BorderSide(color: SagaColors.accent.withValues(alpha: 0.5)),
            padding: const EdgeInsets.symmetric(vertical: 10),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
      );
    }

    final failedCount =
        tracks.where((t) => downloadState.failed.contains(t.ratingKey)).length;
    final isDownloading = inProgressCount > 0;
    final pct = (markProgress * 100).round();
    final label = isDownloading
        ? 'Downloading $pct%…'
        : failedCount > 0
            ? 'Retry $failedCount failed'
            : downloadedCount > 0
                ? 'Download remaining (${total - downloadedCount})'
                : 'Download book';

    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: isDownloading
            ? null
            : () => ref
                .read(downloadNotifierProvider.notifier)
                .downloadBook(book.ratingKey, tracks),
        icon: isDownloading
            ? AnimatedSagaMark(
                size: 18,
                state: SagaMarkState.downloading,
                progress: markProgress,
              )
            : Icon(failedCount > 0 ? Icons.refresh : Icons.download_outlined,
                size: 18),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          foregroundColor:
              failedCount > 0 ? Colors.orangeAccent : SagaColors.fgMuted,
          side: BorderSide(
              color: failedCount > 0 ? Colors.orangeAccent : SagaColors.border),
          padding: const EdgeInsets.symmetric(vertical: 10),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
    );
  }
}

class _ProgressInfo extends StatelessWidget {
  final int positionMs;
  final int totalMs;
  const _ProgressInfo(
      {required this.positionMs, required this.totalMs});

  @override
  Widget build(BuildContext context) {
    final pct = (positionMs / totalMs).clamp(0.0, 1.0);
    final pctLabel = '${(pct * 100).round()}%';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(fmtDurationMs(positionMs),
                style: TextStyle(
                    color: SagaColors.fgMuted, fontSize: 12)),
            Text('$pctLabel · ${fmtDurationMs(totalMs - positionMs)} left',
                style: TextStyle(
                    color: SagaColors.fgSubtle, fontSize: 12)),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: LinearProgressIndicator(
            value: pct,
            backgroundColor: SagaColors.surfaceAlt,
            valueColor: AlwaysStoppedAnimation<Color>(
                SagaColors.accent),
            minHeight: 4,
          ),
        ),
      ],
    );
  }
}

class _ExpandableSummary extends StatefulWidget {
  final String summary;
  const _ExpandableSummary({required this.summary});

  @override
  State<_ExpandableSummary> createState() => _ExpandableSummaryState();
}

class _ExpandableSummaryState extends State<_ExpandableSummary> {
  static const _collapsedLines = 3;

  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final style =
        TextStyle(color: SagaColors.fgMuted, fontSize: 14, height: 1.5);
    // Measured against the real maxWidth, not an assumed one — the whole reason
    // the toggle used to appear on summaries with nothing to expand.
    return LayoutBuilder(
      builder: (context, constraints) {
        final overflows = textOverflows(
          text: widget.summary,
          style: style,
          maxWidth: constraints.maxWidth,
          maxLines: _collapsedLines,
          textScaler: MediaQuery.textScalerOf(context),
        );
        return GestureDetector(
          onTap: overflows
              ? () => setState(() => _expanded = !_expanded)
              : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.summary,
                style: style,
                maxLines: _expanded ? null : _collapsedLines,
                overflow:
                    _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
              ),
              if (overflows) ...[
                const SizedBox(height: 4),
                Text(
                  _expanded ? 'Show less' : 'Show more',
                  style: TextStyle(color: SagaColors.accentText, fontSize: 12),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

// ── Chapter list sliver ────────────────────────────────────────────────────────

class _ChapterListSliver extends ConsumerWidget {
  final PlexBook book;
  final List<PlexTrack> tracks;
  final BookPosition? savedPosition;

  const _ChapterListSliver({
    required this.book,
    required this.tracks,
    required this.savedPosition,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (tracks.length == 1) {
      final track = tracks[0];
      final m4bParam = PlexClient.instance.resolveM4bParam(track);

      if (m4bParam == null) return _plexList(context, ref);

      final chaptersAsync = ref.watch(m4bChaptersProvider(m4bParam));
      return chaptersAsync.when(
        loading: () => _plexList(context, ref),
        error: (_, _) => _plexList(context, ref),
        data: (chapters) => chapters.isNotEmpty
            ? _m4bList(context, ref, chapters)
            : _plexList(context, ref),
      );
    }
    return _plexList(context, ref);
  }

  Widget _m4bList(
      BuildContext context, WidgetRef ref, List<M4bChapter> chapters) {
    // Resolved once for the whole list rather than per row.
    final activeIdx = _activeChapterIndex(chapters);
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, i) {
          final chapter = chapters[i];
          final active = i == activeIdx;
          return ListTile(
            leading: CircleAvatar(
              backgroundColor: active
                  ? SagaColors.accent
                  : SagaColors.surfaceAlt,
              child: Text('${i + 1}',
                  style: TextStyle(
                      color: active ? SagaColors.accentFg : SagaColors.fgMuted,
                      fontSize: 12)),
            ),
            title: Text(chapter.title,
                style: TextStyle(
                    color: active
                        ? SagaColors.accentText
                        : SagaColors.fg,
                    fontSize: 14)),
            subtitle: Text(fmtDuration(chapter.start),
                style: TextStyle(color: SagaColors.fgMuted)),
            onTap: () =>
                _openAt(context, ref, chapter.start.inMilliseconds),
          );
        },
        childCount: chapters.length,
      ),
    );
  }

  Widget _plexList(BuildContext context, WidgetRef ref) {
    final downloadState = ref.watch(downloadNotifierProvider);
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, i) {
          final track = tracks[i];
          final isCurrent =
              savedPosition?.trackRatingKey == track.ratingKey;
          final isDownloaded =
              downloadState.completed.contains(track.ratingKey);
          final dlProgress =
              downloadState.progress[track.ratingKey];
          final mins = track.durationMs ~/ 60000;
          final secs =
              ((track.durationMs % 60000) / 1000).round();
          return ListTile(
            leading: CircleAvatar(
              backgroundColor: isCurrent
                  ? SagaColors.accent
                  : SagaColors.surfaceAlt,
              child: Text('${track.index}',
                  style: TextStyle(
                      color: isCurrent ? SagaColors.accentFg : SagaColors.fgMuted,
                      fontSize: 12)),
            ),
            title: Text(track.title,
                style: TextStyle(
                    color: isCurrent
                        ? SagaColors.accentText
                        : SagaColors.fg,
                    fontSize: 14)),
            subtitle: Text(
                '${mins}m ${secs.toString().padLeft(2, '0')}s',
                style: TextStyle(color: SagaColors.fgMuted)),
            trailing: dlProgress != null
                ? Semantics(
                    label: 'Downloading, ${(dlProgress * 100).round()}%',
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                          value: dlProgress,
                          strokeWidth: 2,
                          color: SagaColors.accent),
                    ),
                  )
                : IconButton(
                    icon: Icon(
                        isDownloaded
                            ? Icons.download_done
                            : Icons.download_outlined,
                        color: isDownloaded
                            ? SagaColors.accent
                            : SagaColors.fgSubtle),
                    tooltip: isDownloaded ? 'Downloaded' : 'Download',
                    onPressed: isDownloaded
                        ? null
                        : () => ref
                            .read(downloadNotifierProvider.notifier)
                            .downloadTrack(track, book.ratingKey, tracks),
                  ),
            onTap: () => _openAt(context, ref, 0, trackIndex: i),
          );
        },
        childCount: tracks.length,
      ),
    );
  }

  /// Chapter the saved position sits in, or -1 when there's nothing to mark
  /// (no saved position, or it belongs to a different track). Resolved through
  /// the shared [chapterIndexAt] so this list agrees with the player's chapter
  /// list, the mini player and the notification — its own start/end window
  /// used to highlight nothing when the position preceded the first chapter
  /// mark, where the player highlighted chapter 1.
  int _activeChapterIndex(List<M4bChapter> chapters) {
    if (savedPosition == null || tracks.isEmpty) return -1;
    if (savedPosition!.trackRatingKey != tracks[0].ratingKey) return -1;
    return chapterIndexAt(
        [for (final c in chapters) c.start.inMilliseconds],
        savedPosition!.positionMs);
  }

  Future<void> _openAt(BuildContext context, WidgetRef ref,
      int positionMs,
      {int trackIndex = 0}) async {
    if (!context.mounted) return;
    await openPlayerAndStart(
      context: context,
      service: ref.read(playerServiceProvider),
      bookRatingKey: book.ratingKey,
      loadTracks: () async => tracks,
      from: BookStartPoint.atTrackIndex(trackIndex, positionMs: positionMs),
    );
  }

}
