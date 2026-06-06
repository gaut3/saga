import 'package:flutter/material.dart';
import '../../core/theme/saga_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/audio/m4b_chapter_reader.dart';
import '../../core/plex/models/plex_book.dart';
import '../../core/plex/models/plex_track.dart';
import '../../core/plex/plex_client.dart';
import '../../core/providers.dart';
import '../../shared/widgets/book_cover_image.dart';
import '../../core/storage/bookmark_store.dart';
import '../../core/storage/completed_books_store.dart';
import '../../core/storage/custom_collection_store.dart';
import '../../core/storage/settings_store.dart';
import '../player/player_provider.dart';
import '../player/player_screen.dart';
import '../../core/utils/format.dart';
import '../../shared/widgets/saga_mark.dart' show AnimatedSagaMark, SagaMarkState;
import '../../shared/widgets/saga_sheet.dart';
import '../../shared/widgets/saga_toast.dart';

class BookDetailScreen extends ConsumerStatefulWidget {
  final PlexBook book;
  const BookDetailScreen({super.key, required this.book});

  @override
  ConsumerState<BookDetailScreen> createState() => _BookDetailScreenState();
}

class _BookDetailScreenState extends ConsumerState<BookDetailScreen> {
  late bool _isCompleted;

  @override
  void initState() {
    super.initState();
    _isCompleted =
        CompletedBooksStore.isCompleted(widget.book.ratingKey);
  }

  Future<void> _toggleCompleted() async {
    if (_isCompleted) {
      await CompletedBooksStore.markIncomplete(widget.book.ratingKey);
    } else {
      await CompletedBooksStore.markCompleted(widget.book.ratingKey);
    }
    setState(() => _isCompleted = !_isCompleted);
    ref.read(completionRevisionProvider.notifier).state++;
  }

  void _showAddToCollectionSheet(BuildContext context) {
    final collections = CustomCollectionStore.getAll();
    // Captured from the tab-navigator context where padding.bottom already
    // includes the full Saga nav bar + mini player height.
    final bottomPad = MediaQuery.of(context).padding.bottom;

    showSagaSheet(context, (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          return Padding(
            padding: EdgeInsets.only(bottom: bottomPad),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Text('Add to collection',
                      style: TextStyle(
                          color: SagaColors.fg,
                          fontWeight: FontWeight.bold,
                          fontSize: 16)),
                ),
                if (collections.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                        'No collections yet — create one in the Collections tab.',
                        style: TextStyle(color: SagaColors.fgMuted)),
                  )
                else
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(ctx).size.height * 0.55,
                    ),
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        ...collections.map((col) {
                          final inCollection =
                              col.bookRatingKeys.contains(widget.book.ratingKey);
                          return ListTile(
                            leading: Icon(
                              inCollection
                                  ? Icons.check_circle
                                  : Icons.folder_outlined,
                              color: inCollection
                                  ? SagaColors.accent
                                  : SagaColors.fgMuted,
                            ),
                            title: Text(col.name,
                                style: TextStyle(color: SagaColors.fg)),
                            subtitle: Text(
                                '${col.bookRatingKeys.length} '
                                '${col.bookRatingKeys.length == 1 ? 'book' : 'books'}',
                                style: TextStyle(
                                    color: SagaColors.fgSubtle, fontSize: 12)),
                            onTap: () async {
                              if (inCollection) {
                                await CustomCollectionStore.removeBook(
                                    col.id, widget.book.ratingKey);
                              } else {
                                await CustomCollectionStore.addBook(
                                    col.id, widget.book.ratingKey);
                              }
                              ref
                                  .read(customCollectionRevisionProvider.notifier)
                                  .state++;
                              if (ctx.mounted) Navigator.pop(ctx);
                            },
                          );
                        }),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final book = widget.book;
    final tracksAsync = ref.watch(tracksProvider(book.ratingKey));
    final savedPosition = BookmarkStore.load(book.ratingKey);

    // Resolve effective chapter count: prefer M4B embedded chapters over Plex
    // leafCount (which is always 1 for a single M4B file regardless of chapters).
    int? effectiveChapterCount;
    final resolvedTracks = tracksAsync.valueOrNull;
    if (resolvedTracks == null) {
      effectiveChapterCount = book.leafCount;
    } else if (resolvedTracks.length != 1) {
      effectiveChapterCount = resolvedTracks.length;
    } else {
      final track = resolvedTracks[0];
      final m4bParam = PlexClient.instance.resolveM4bParam(track);
      if (m4bParam != null) {
        final m4bAsync =
            ref.watch(m4bChaptersProvider(m4bParam));
        final m4bChapters = m4bAsync.valueOrNull;
        if (m4bChapters != null && m4bChapters.isNotEmpty) {
          effectiveChapterCount = m4bChapters.length;
        } else if (!m4bAsync.isLoading) {
          effectiveChapterCount = 1;
        }
        // still loading → keep null so the chip stays hidden until resolved
      } else {
        effectiveChapterCount = 1;
      }
    }

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
                        BookCoverImage(thumbPath: book.thumbPath, cacheWidth: 400),
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
                  : const _CoverPlaceholder(),
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
                          color: SagaColors.accent,
                          fontSize: 15,
                          fontWeight: FontWeight.w500),
                    ),
                  const SizedBox(height: 8),

                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      if (book.year != null)
                        _MetaChip(Icons.calendar_today_outlined,
                            '${book.year}'),
                      if (book.totalDurationMs != null)
                        _MetaChip(Icons.schedule_outlined,
                            fmtDurationMs(book.totalDurationMs!)),
                      if (effectiveChapterCount != null)
                        _MetaChip(
                          Icons.format_list_numbered_outlined,
                          effectiveChapterCount == 1
                              ? '1 chapter'
                              : '$effectiveChapterCount chapters',
                        ),
                      if (book.studio != null)
                        _MetaChip(
                            Icons.business_outlined, book.studio!),
                      if (CompletedBooksStore.completionCount(
                              book.ratingKey) >
                          0)
                        _MetaChip(
                            Icons.replay_rounded,
                            'Listened ${CompletedBooksStore.completionCount(book.ratingKey)}×'),
                    ],
                  ),

                  if (savedPosition != null &&
                      book.totalDurationMs != null &&
                      book.totalDurationMs! > 0) ...[
                    const SizedBox(height: 14),
                    _ProgressInfo(
                        positionMs: savedPosition.positionMs,
                        totalMs: book.totalDurationMs!),
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
                                      resumePosition: savedPosition,
                                    ),
                                    icon: const Icon(Icons.play_arrow),
                                    label: const Text('Resume'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: SagaColors.accent,
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
                                  icon: Icon(_isCompleted
                                      ? Icons.replay
                                      : savedPosition != null
                                          ? Icons.restart_alt
                                          : Icons.play_arrow),
                                  label: Text(_isCompleted
                                      ? 'Listen again'
                                      : savedPosition != null
                                          ? 'From start'
                                          : 'Play'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: savedPosition != null
                                        ? SagaColors.surfaceAlt
                                        : SagaColors.accent,
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
                          foregroundColor: _isCompleted
                              ? SagaColors.fgMuted
                              : SagaColors.accent,
                          side: BorderSide(
                            color: _isCompleted
                                ? SagaColors.fgSubtle
                                : SagaColors.accent,
                          ),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                        child: Icon(
                          _isCompleted
                              ? Icons.bookmark_remove_outlined
                              : Icons.bookmark_added_outlined,
                          size: 20,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 8),

                  // Row 2: add to collection + download
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
          const SliverPadding(padding: EdgeInsets.only(bottom: 32)),
        ],
      ),
    );
  }

  Future<void> _openPlayer(
    BuildContext context,
    List<PlexTrack> tracks, {
    BookPosition? resumePosition,
    int startIndex = 0,
  }) async {
    int trackIndex = startIndex;
    int positionMs = 0;

    if (resumePosition != null) {
      final idx = tracks.indexWhere(
          (t) => t.ratingKey == resumePosition.trackRatingKey);
      if (idx >= 0) {
        trackIndex = idx;
        positionMs = resumePosition.positionMs;
      }
    }

    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: true)
        .push(MaterialPageRoute(builder: (_) => const PlayerScreen()));

    try {
      final service = ref.read(playerServiceProvider);
      await service.loadBook(
        bookRatingKey: widget.book.ratingKey,
        tracks: tracks,
        startTrackIndex: trackIndex,
        startPositionMs: positionMs,
        applyResumeRewind: resumePosition != null,
      );
      // Restore the speed saved for this book.
      final savedSpeed =
          SettingsStore.getBookSpeed(widget.book.ratingKey);
      await service.setSpeed(savedSpeed);
      ref.read(playbackSpeedProvider.notifier).state = savedSpeed;
      await service.play();
    } catch (_) {
      if (context.mounted) {
        showSagaToast(context, 'Playback error — check your connection',
            isError: true, duration: const Duration(seconds: 4));
      }
    }
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
      return SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: null,
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
            : () {
                for (final track in tracks) {
                  if (!downloadState.completed.contains(track.ratingKey)) {
                    ref
                        .read(downloadNotifierProvider.notifier)
                        .downloadTrack(track, book.ratingKey);
                  }
                }
              },
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

class _CoverPlaceholder extends StatelessWidget {
  const _CoverPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: SagaColors.surface,
      child: Center(
        child: Icon(Icons.book, size: 80, color: SagaColors.fgSubtle),
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _MetaChip(this.icon, this.label);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: SagaColors.surface,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: SagaColors.fgSubtle),
          const SizedBox(width: 4),
          Text(label,
              style:
                  TextStyle(color: SagaColors.fgMuted, fontSize: 12)),
        ],
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
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => setState(() => _expanded = !_expanded),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.summary,
            style: TextStyle(
                color: SagaColors.fgMuted, fontSize: 14, height: 1.5),
            maxLines: _expanded ? null : 3,
            overflow:
                _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            _expanded ? 'Show less' : 'Show more',
            style:
                TextStyle(color: SagaColors.accent, fontSize: 12),
          ),
        ],
      ),
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
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, i) {
          final chapter = chapters[i];
          final active = _isActive(chapters, i);
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
                        ? SagaColors.accent
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
                        ? SagaColors.accent
                        : SagaColors.fg,
                    fontSize: 14)),
            subtitle: Text(
                '${mins}m ${secs.toString().padLeft(2, '0')}s',
                style: TextStyle(color: SagaColors.fgMuted)),
            trailing: dlProgress != null
                ? SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                        value: dlProgress,
                        strokeWidth: 2,
                        color: SagaColors.accent),
                  )
                : IconButton(
                    icon: Icon(
                        isDownloaded
                            ? Icons.download_done
                            : Icons.download_outlined,
                        color: isDownloaded
                            ? SagaColors.accent
                            : SagaColors.fgSubtle),
                    onPressed: isDownloaded
                        ? null
                        : () => ref
                            .read(downloadNotifierProvider.notifier)
                            .downloadTrack(track, book.ratingKey),
                  ),
            onTap: () => _openAt(context, ref, 0, trackIndex: i),
          );
        },
        childCount: tracks.length,
      ),
    );
  }

  bool _isActive(List<M4bChapter> chapters, int i) {
    if (savedPosition == null || tracks.isEmpty) return false;
    if (savedPosition!.trackRatingKey != tracks[0].ratingKey) {
      return false;
    }
    final pos = savedPosition!.positionMs;
    final start = chapters[i].start.inMilliseconds;
    final end = i + 1 < chapters.length
        ? chapters[i + 1].start.inMilliseconds
        : 999999999;
    return pos >= start && pos < end;
  }

  Future<void> _openAt(BuildContext context, WidgetRef ref,
      int positionMs,
      {int trackIndex = 0}) async {
    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: true)
        .push(MaterialPageRoute(builder: (_) => const PlayerScreen()));
    try {
      final service = ref.read(playerServiceProvider);
      await service.loadBook(
        bookRatingKey: book.ratingKey,
        tracks: tracks,
        startTrackIndex: trackIndex,
        startPositionMs: positionMs,
      );
      await service.play();
    } catch (_) {
      if (context.mounted) {
        showSagaToast(context, 'Playback error — check your connection',
            isError: true, duration: const Duration(seconds: 4));
      }
    }
  }

}
