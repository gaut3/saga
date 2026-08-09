import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/diagnostics/app_log.dart';
import '../../core/plex/models/plex_book.dart';
import '../../core/providers.dart';
import '../../core/storage/named_bookmark_store.dart';
import '../../core/theme/saga_theme.dart';
import '../../core/utils/format.dart';
import '../../shared/widgets/saga_toast.dart';
import '../player/book_launch.dart';
import '../player/bookmark_edit_sheet.dart';
import '../player/open_player.dart';
import '../player/player_provider.dart';

class AllBookmarksScreen extends ConsumerStatefulWidget {
  const AllBookmarksScreen({super.key});

  @override
  ConsumerState<AllBookmarksScreen> createState() => _AllBookmarksScreenState();
}

class _AllBookmarksScreenState extends ConsumerState<AllBookmarksScreen> {
  String _query = '';
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Pushed on a tab stack — rebuilds come from nowhere else on a theme
    // switch, so watch it here.
    ref.watch(sagaThemeVariantProvider);
    ref.watch(bookmarkRevisionProvider);
    final all = NamedBookmarkStore.getAll();
    final bookmarks = _query.isEmpty
        ? all
        : all.where((b) {
            final q = _query.toLowerCase();
            return b.label.toLowerCase().contains(q) ||
                (b.note?.toLowerCase().contains(q) ?? false);
          }).toList();

    return Scaffold(
      backgroundColor: SagaColors.bg,
      appBar: AppBar(
        title: const Text('All Bookmarks',
            style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: SagaColors.bg,
        foregroundColor: SagaColors.fg,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: TextField(
              controller: _searchController,
              style: TextStyle(color: SagaColors.fg),
              decoration: InputDecoration(
                hintText: 'Search bookmarks…',
                hintStyle: TextStyle(color: SagaColors.fgSubtle),
                prefixIcon: Icon(Icons.search, color: SagaColors.fgSubtle),
                suffixIcon: _query.isNotEmpty
                    ? IconButton(
                        icon: Icon(Icons.clear, color: SagaColors.fgSubtle),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _query = '');
                        },
                      )
                    : null,
                filled: true,
                fillColor: SagaColors.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: EdgeInsets.zero,
              ),
              onChanged: (v) => setState(() => _query = v.trim()),
            ),
          ),
          Expanded(
            child: bookmarks.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.bookmark_border,
                            size: 56, color: SagaColors.fgSubtle),
                        const SizedBox(height: 12),
                        Text(
                          _query.isEmpty
                              ? 'No bookmarks yet'
                              : 'No results for "$_query"',
                          style: TextStyle(
                              color: SagaColors.fgMuted, fontSize: 16),
                        ),
                      ],
                    ),
                  )
                : _BookmarkList(bookmarks: bookmarks),
          ),
        ],
      ),
    );
  }
}

class _BookmarkList extends ConsumerWidget {
  final List<NamedBookmark> bookmarks;
  const _BookmarkList({required this.bookmarks});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final libraryKeyAsync = ref.watch(activeLibraryKeyProvider);
    final bookLookup = libraryKeyAsync.whenOrNull(
      data: (key) {
        if (key == null) return <String, PlexBook>{};
        final booksAsync = ref.watch(booksProvider(key));
        return booksAsync.whenOrNull(
          data: (books) => {for (final b in books) b.ratingKey: b},
        );
      },
    );

    return ListView.builder(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).padding.bottom + 160),
      itemCount: bookmarks.length,
      itemBuilder: (context, i) {
        final bm = bookmarks[i];
        final book = bookLookup?[bm.bookRatingKey];
        return _BookmarkTile(bookmark: bm, book: book);
      },
    );
  }
}

class _BookmarkTile extends ConsumerWidget {
  final NamedBookmark bookmark;
  final PlexBook? book;

  const _BookmarkTile({required this.bookmark, this.book});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Dismissible(
      key: Key(bookmark.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: Colors.redAccent,
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      onDismissed: (_) => _delete(ref),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: SagaColors.surface,
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.bookmark, color: SagaColors.accent, size: 20),
        ),
        title: Text(
          bookmark.label,
          style: TextStyle(
              color: SagaColors.fg,
              fontSize: 14,
              fontWeight: FontWeight.w500),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (book != null)
              Text(book!.title,
                  style:
                      TextStyle(color: SagaColors.fgMuted, fontSize: 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            if (bookmark.note != null && bookmark.note!.isNotEmpty)
              Text(bookmark.note!,
                  style: TextStyle(
                      color: SagaColors.fgSubtle,
                      fontSize: 11,
                      fontStyle: FontStyle.italic),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),
          ],
        ),
        trailing: Text(
          relativeDayLabel(bookmark.createdAt),
          style: TextStyle(color: SagaColors.fgSubtle, fontSize: 11),
        ),
        onTap: () => _showBookmarkSheet(context, ref),
      ),
    );
  }

  void _delete(WidgetRef ref) {
    // Through the notifier, never the store directly: the player's bookmark
    // sheet renders from bookmarkNotifierProvider's cached list, which reads
    // the store once and never re-reads it. A store-only delete left the
    // record in that cache, so editing any bookmark in the player wrote the
    // deleted one straight back to disk.
    ref
        .read(bookmarkNotifierProvider(bookmark.bookRatingKey).notifier)
        .remove(bookmark.id);
    ref.read(bookmarkRevisionProvider.notifier).state++;
  }

  Future<void> _jumpTo(BuildContext context, WidgetRef ref) async {
    // Both quiet exits used to be exactly that — quiet. A tap that does
    // nothing is indistinguishable from a dead button (the finished screen's
    // next-book button shipped that way once already), so each failure now
    // says so.
    try {
      final tracks =
          await ref.read(tracksProvider(bookmark.bookRatingKey).future);
      if (!context.mounted) return;
      if (!tracks.any((t) => t.ratingKey == bookmark.trackRatingKey)) {
        showSagaToast(
            context, 'The file this bookmark points into is no longer '
            'part of the book.',
            isError: true);
        return;
      }
      // Shared helper: pops the player again if the launch fails, instead of
      // leaving the previous book's player on screen.
      await openPlayerAndStart(
        context: context,
        service: ref.read(playerServiceProvider),
        bookRatingKey: bookmark.bookRatingKey,
        loadTracks: () async => tracks,
        from: BookStartPoint.atTrack(bookmark.trackRatingKey,
            positionMs: bookmark.positionMs),
      );
    } catch (e) {
      AppLog.log('playback', 'bookmark jump failed: $e');
      if (context.mounted) {
        showSagaToast(context,
            'Couldn\'t load this book — is the server reachable?',
            isError: true);
      }
    }
  }

  void _showBookmarkSheet(BuildContext context, WidgetRef ref) {
    showBookmarkEditSheet(
      context,
      title: 'Bookmark',
      positionMs: bookmark.positionMs,
      initialLabel: bookmark.label,
      initialNote: bookmark.note,
      onSave: (label, note) {
        // Same rule as _delete: mutate via the notifier so the player's
        // cached list stays in step with the store.
        ref
            .read(bookmarkNotifierProvider(bookmark.bookRatingKey).notifier)
            .update(bookmark.copyWith(label: label, note: note));
        ref.read(bookmarkRevisionProvider.notifier).state++;
      },
      onJumpTo: () => _jumpTo(context, ref),
    );
  }

}
