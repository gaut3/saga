import 'package:flutter/material.dart';

import '../../shared/widgets/saga_error_view.dart';
import '../../core/theme/saga_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/plex/models/plex_book.dart';
import '../../core/providers.dart';
import '../../shared/widgets/book_cover_image.dart';
import '../../core/storage/bookmark_store.dart';
import '../../core/storage/playback_log_store.dart';
import '../library/book_detail_screen.dart';
import '../player/player_provider.dart';
import '../player/player_screen.dart';
import '../../core/utils/format.dart';

class InProgressScreen extends ConsumerWidget {
  final String libraryKey;
  const InProgressScreen({super.key, required this.libraryKey});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final booksAsync = ref.watch(continueListeningProvider(libraryKey));
    final completedAsync = ref.watch(completedBooksListProvider(libraryKey));

    return Scaffold(
      backgroundColor: SagaColors.bg,
      appBar: AppBar(
        title: const Text('In Progress'),
        backgroundColor: SagaColors.bg,
        foregroundColor: SagaColors.fg,
      ),
      body: booksAsync.when(
        loading: () => Center(
            child: CircularProgressIndicator(color: SagaColors.accent)),
        error: (e, _) => SagaErrorView(
          message: 'Could not load your books',
          error: e,
          onRetry: () => ref.invalidate(continueListeningProvider(libraryKey)),
        ),
        data: (books) {
          return CustomScrollView(
            slivers: [
              if (books.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(48),
                    child: Center(
                      child: Text('No books in progress',
                          style: TextStyle(color: SagaColors.fgSubtle)),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (_, i) => _BookLogCard(book: books[i]),
                      childCount: books.length,
                    ),
                  ),
                ),
              SliverToBoxAdapter(
                child: completedAsync.whenOrNull(
                  data: (completed) => completed.isEmpty
                      ? const SizedBox.shrink()
                      : _CompletedSection(
                          books: completed, libraryKey: libraryKey),
                ),
              ),
              SliverPadding(
                padding: EdgeInsets.only(
                    bottom: MediaQuery.of(context).padding.bottom + 160),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ── Completed section ─────────────────────────────────────────────────────────

class _CompletedSection extends StatefulWidget {
  final List<PlexBook> books;
  final String libraryKey;
  const _CompletedSection({required this.books, required this.libraryKey});

  @override
  State<_CompletedSection> createState() => _CompletedSectionState();
}

class _CompletedSectionState extends State<_CompletedSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Icon(Icons.check_circle_outline,
                      color: SagaColors.accent, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    'Completed (${widget.books.length})',
                    style: TextStyle(
                        color: SagaColors.fg,
                        fontSize: 16,
                        fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    color: SagaColors.fgSubtle,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded)
            ...widget.books.map((b) => _CompletedTile(book: b)),
        ],
      ),
    );
  }
}

class _CompletedTile extends StatelessWidget {
  final PlexBook book;
  const _CompletedTile({required this.book});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 0, vertical: 2),
      leading: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              width: 46,
              height: 46,
              child: BookCoverImage(thumbPath: book.thumbPath, cacheWidth: 92),
            ),
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: SagaColors.accent,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.check, color: SagaColors.accentFg, size: 10),
            ),
          ),
        ],
      ),
      title: Text(book.title,
          style: TextStyle(
              color: SagaColors.fg,
              fontSize: 14,
              fontWeight: FontWeight.w500),
          maxLines: 1,
          overflow: TextOverflow.ellipsis),
      subtitle: book.authorName != null
          ? Text(book.authorName!,
              style: TextStyle(color: SagaColors.fgMuted, fontSize: 12),
              maxLines: 1,
              overflow: TextOverflow.ellipsis)
          : null,
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => BookDetailScreen(book: book)),
      ),
    );
  }

}

// ── In-progress book card (unchanged) ────────────────────────────────────────

class _BookLogCard extends ConsumerStatefulWidget {
  final PlexBook book;
  const _BookLogCard({required this.book});

  @override
  ConsumerState<_BookLogCard> createState() => _BookLogCardState();
}

class _BookLogCardState extends ConsumerState<_BookLogCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final savedPos = BookmarkStore.load(widget.book.ratingKey);
    final total = widget.book.totalDurationMs ?? savedPos?.totalDurationMs;
    final pct = (savedPos != null && total != null && total > 0)
        ? (savedPos.absolutePositionMs / total).clamp(0.0, 1.0)
        : 0.0;

    final log = PlaybackLogStore.getLog(widget.book.ratingKey);
    final Map<String, List<AudioLogEvent>> byDay = {};
    for (final e in log.reversed) {
      byDay.putIfAbsent(_dayLabel(e.timestamp), () => []).add(e);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: SagaColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: SizedBox(
                    width: 52,
                    height: 52,
                    child: BookCoverImage(thumbPath: widget.book.thumbPath, cacheWidth: 104),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.book.title,
                          style: TextStyle(
                              color: SagaColors.fg,
                              fontSize: 14,
                              fontWeight: FontWeight.w600),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis),
                      if (widget.book.authorName != null)
                        Text(widget.book.authorName!,
                            style: TextStyle(
                                color: SagaColors.fgMuted, fontSize: 12)),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                          value: pct,
                          backgroundColor: SagaColors.surfaceAlt,
                          valueColor: AlwaysStoppedAnimation(
                              SagaColors.accent),
                          minHeight: 3,
                        ),
                      ),
                      Text('${(pct * 100).round()}%',
                          style: TextStyle(
                              color: SagaColors.fgSubtle, fontSize: 11)),
                    ],
                  ),
                ),
                if (log.isNotEmpty)
                  IconButton(
                    icon: Icon(
                        _expanded ? Icons.expand_less : Icons.expand_more,
                        color: SagaColors.fgSubtle),
                    onPressed: () =>
                        setState(() => _expanded = !_expanded),
                  ),
              ],
            ),
          ),
          if (_expanded && log.isNotEmpty) ...[
            Divider(color: SagaColors.surfaceAlt, height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: byDay.entries
                    .map((e) => _DayGroup(
                          label: e.key,
                          events: e.value,
                          book: widget.book,
                        ))
                    .toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }



  String _dayLabel(DateTime dt) {
    final today = DateTime.now();
    final todayClean = DateTime(today.year, today.month, today.day);
    final day = DateTime(dt.year, dt.month, dt.day);
    final diff = todayClean.difference(day).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    return '${dt.day}/${dt.month}/${dt.year}';
  }
}

class _DayGroup extends StatelessWidget {
  final String label;
  final List<AudioLogEvent> events;
  final PlexBook book;
  const _DayGroup(
      {required this.label, required this.events, required this.book});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Text(label,
              style: TextStyle(
                  color: SagaColors.fgSubtle,
                  fontSize: 11,
                  fontWeight: FontWeight.w600)),
        ),
        ...events.map((e) => _EventTile(event: e, book: book)),
      ],
    );
  }
}

class _EventTile extends ConsumerWidget {
  final AudioLogEvent event;
  final PlexBook book;
  const _EventTile({required this.event, required this.book});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        _iconFor(event.type),
        color: event.type == 'play' ? Colors.amber : SagaColors.fgSubtle,
        size: 18,
      ),
      title: Text(_labelFor(event.type),
          style: TextStyle(color: SagaColors.fgMuted, fontSize: 13)),
      subtitle: Text(fmtPositionMs(event.positionMs),
          style: TextStyle(color: SagaColors.fgSubtle, fontSize: 11)),
      trailing: Text(fmtTime(event.timestamp),
          style: TextStyle(color: SagaColors.fgSubtle, fontSize: 11)),
      onTap: () => _jumpTo(context, ref),
    );
  }

  Future<void> _jumpTo(BuildContext context, WidgetRef ref) async {
    try {
      final tracks =
          await ref.read(tracksProvider(book.ratingKey).future);
      if (!context.mounted) return;
      final idx = tracks
          .indexWhere((t) => t.ratingKey == event.trackRatingKey);
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

  IconData _iconFor(String t) => switch (t) {
        'play' => Icons.play_arrow,
        'pause' => Icons.pause,
        'seek' => Icons.fast_forward,
        'sleepTimer' => Icons.bedtime_outlined,
        'skipNext' => Icons.skip_next,
        'skipPrev' => Icons.skip_previous,
        _ => Icons.radio_button_unchecked,
      };

  String _labelFor(String t) => switch (t) {
        'play' => 'Started',
        'pause' => 'Paused',
        'seek' => 'Jumped to',
        'sleepTimer' => 'Sleep timer set',
        'skipNext' => 'Skipped forward',
        'skipPrev' => 'Skipped back',
        _ => t,
      };

}
