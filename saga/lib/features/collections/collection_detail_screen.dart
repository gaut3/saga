import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/plex/models/plex_book.dart';
import '../../core/providers.dart';
import '../../shared/widgets/book_cover_image.dart';
import '../../core/storage/custom_collection_store.dart';
import '../../core/theme/saga_theme.dart';
import '../library/book_detail_screen.dart';
import '../../shared/widgets/saga_error_view.dart';
import '../../shared/widgets/saga_search_field.dart';
import '../../shared/widgets/saga_sheet.dart';

class CollectionDetailScreen extends ConsumerStatefulWidget {
  final CustomCollection collection;
  final String libraryKey;

  const CollectionDetailScreen({
    super.key,
    required this.collection,
    required this.libraryKey,
  });

  @override
  ConsumerState<CollectionDetailScreen> createState() =>
      _CollectionDetailScreenState();
}

class _CollectionDetailScreenState
    extends ConsumerState<CollectionDetailScreen> {
  String _query = '';
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _showSetCoverSheet(BuildContext context) {
    final booksAsync = ref.read(customCollectionBooksProvider(
        '${widget.libraryKey}|${widget.collection.id}'));
    final books = booksAsync.valueOrNull ?? [];
    // A fetch still in flight is not an empty collection — telling the owner
    // of ten books to "add books first" because the server was slow is a lie.
    final stillLoading = books.isEmpty && booksAsync.isLoading;

    final bottomPad = MediaQuery.of(context).padding.bottom;
    showSagaSheet(context, (ctx) => Padding(
        padding: EdgeInsets.only(bottom: bottomPad),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SagaSheetTitle('Set cover',
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8)),
            if (books.isEmpty)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                    stillLoading
                        ? 'Still loading this collection — try again in a '
                            'moment.'
                        : 'Add books to this collection first.',
                    style: TextStyle(color: SagaColors.fgMuted)),
              )
            else
              SizedBox(
                // 90 px square tiles + the list's 16 px bottom padding.
                height: 106,
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  scrollDirection: Axis.horizontal,
                  itemCount: books.length + 1,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (_, i) {
                    if (i == 0) {
                      // "None" option
                      return GestureDetector(
                        onTap: () async {
                          await CustomCollectionStore.setCover(
                              widget.collection.id, null);
                          ref
                              .read(customCollectionRevisionProvider.notifier)
                              .state++;
                          if (ctx.mounted) Navigator.pop(ctx);
                        },
                        child: Container(
                          width: 90,
                          height: 90,
                          decoration: BoxDecoration(
                            color: SagaColors.surfaceAlt,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: SagaColors.border),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.folder_rounded,
                                  color: SagaColors.fgSubtle, size: 28),
                              const SizedBox(height: 4),
                              Text('None',
                                  style: TextStyle(
                                      color: SagaColors.fgSubtle,
                                      fontSize: 11)),
                            ],
                          ),
                        ),
                      );
                    }
                    final book = books[i - 1];
                    return GestureDetector(
                      onTap: () async {
                        await CustomCollectionStore.setCover(
                            widget.collection.id, book.thumbPath);
                        ref
                            .read(customCollectionRevisionProvider.notifier)
                            .state++;
                        if (ctx.mounted) Navigator.pop(ctx);
                      },
                      // Square: a 90×120 box cropped the sides off the very
                      // covers the user is picking between.
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: SizedBox(
                          width: 90,
                          height: 90,
                          child: BookCoverImage(
                              thumbPath: book.thumbPath,
                              cacheWidth: kCoverCacheWidthThumb),
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ), scrollable: false);
  }



  @override
  Widget build(BuildContext context) {
    // Pushed on a tab stack — rebuilds come from nowhere else on a theme
    // switch, so watch it here.
    ref.watch(sagaThemeVariantProvider);
    final booksAsync = ref.watch(customCollectionBooksProvider(
        '${widget.libraryKey}|${widget.collection.id}'));

    return Scaffold(
      backgroundColor: SagaColors.bg,
      appBar: AppBar(
        title: Text(widget.collection.name,
            style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: SagaColors.bg,
        foregroundColor: SagaColors.fg,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        actions: [
          IconButton(
            icon: const Icon(Icons.image_outlined),
            tooltip: 'Set cover',
            onPressed: () => _showSetCoverSheet(context),
          ),
        ],
      ),
      body: booksAsync.when(
        loading: () =>
            Center(child: CircularProgressIndicator(color: SagaColors.accent)),
        // Never render the raw exception: DioException prints the request URI,
        // i.e. the user's server address, straight onto a screen that ends up
        // in bug-report screenshots. The details go to the diagnostics log.
        error: (e, _) => SagaErrorView(
          message: 'Could not load this collection',
          error: e,
          onRetry: () => ref.invalidate(customCollectionBooksProvider(
              '${widget.libraryKey}|${widget.collection.id}')),
        ),
        data: (rawBooks) {
          final q = _query.toLowerCase();
          final books = _query.isEmpty
              ? rawBooks
              : rawBooks
                  .where((b) =>
                      b.title.toLowerCase().contains(q) ||
                      (b.authorName?.toLowerCase().contains(q) ?? false))
                  .toList();

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: SagaSearchField(
                  controller: _searchController,
                  hintText: 'Search in collection…',
                  showClear: _query.isNotEmpty,
                  onClear: () {
                    _searchController.clear();
                    setState(() => _query = '');
                  },
                  onChanged: (v) => setState(() => _query = v.trim()),
                ),
              ),
              Expanded(
                child: books.isEmpty
                    ? Center(
                        child: Text(
                          _query.isEmpty
                              ? 'No books in this collection'
                              : 'No results for "$_query"',
                          style: TextStyle(
                              color: SagaColors.fgMuted, fontSize: 16),
                        ),
                      )
                    : _query.isNotEmpty
                        ? ListView.builder(
                            padding: EdgeInsets.only(
                                bottom: MediaQuery.of(context).padding.bottom +
                                    160),
                            itemCount: books.length,
                            itemBuilder: (context, i) => _BookTile(
                                book: books[i],
                                collectionId: widget.collection.id,
                                total: rawBooks.length),
                          )
                        : ReorderableListView.builder(
                            buildDefaultDragHandles: false,
                            padding: EdgeInsets.only(
                                bottom: MediaQuery.of(context).padding.bottom +
                                    160),
                            itemCount: books.length,
                            itemBuilder: (context, i) {
                              final book = books[i];
                              return _BookTile(
                                key: ValueKey(book.ratingKey),
                                book: book,
                                collectionId: widget.collection.id,
                                index: i,
                                total: rawBooks.length,
                                trailing: ReorderableDragStartListener(
                                  index: i,
                                  child: Icon(Icons.drag_handle,
                                      color: SagaColors.fgSubtle),
                                ),
                              );
                            },
                            // onReorderItem (unlike the deprecated onReorder)
                            // delivers newIdx already adjusted for the removed
                            // item, so no manual index fixup.
                            onReorderItem: (oldIdx, newIdx) async {
                              final reordered = List<PlexBook>.from(rawBooks);
                              final item = reordered.removeAt(oldIdx);
                              reordered.insert(newIdx, item);
                              final newOrder =
                                  reordered.map((b) => b.ratingKey).toList();
                              await CustomCollectionStore.reorder(
                                  widget.collection.id, newOrder);
                              ref
                                  .read(customCollectionRevisionProvider
                                      .notifier)
                                  .state++;
                            },
                          ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _BookTile extends ConsumerWidget {
  final PlexBook book;
  final String collectionId;
  final Widget? trailing;
  final int? index;
  final int? total;

  // A ConsumerWidget with its own ref, not a WidgetRef passed down from the
  // parent state: the old field outlived the parent across the await in
  // remove, so a quick back-swipe after a removal threw "cannot use ref
  // after the widget was disposed" as an unhandled async error.
  const _BookTile({
    super.key,
    required this.book,
    required this.collectionId,
    this.trailing,
    this.index,
    this.total,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cover = ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        width: 40,
        height: 40,
        child: BookCoverImage(
            thumbPath: book.thumbPath, cacheWidth: kCoverCacheWidthThumb),
      ),
    );
    // Swipe-to-remove in both branches (reorder and search) — the drag handle
    // owns the trailing slot in reorder mode, so without the swipe, removing
    // a book was only reachable by first typing something into the search
    // box. Same gesture, same look as deleting a bookmark in All Bookmarks.
    return Dismissible(
      key: Key('remove_${book.ratingKey}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: Colors.redAccent,
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      onDismissed: (_) => _removeBook(ref),
      child: ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: index != null
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 48,
                  child: Text(
                    total != null ? '${index! + 1} / $total' : '${index! + 1}',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: SagaColors.fgSubtle,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                cover,
              ],
            )
          : cover,
      title: Text(
        book.title,
        style: TextStyle(
            color: SagaColors.fg,
            fontSize: 14,
            fontWeight: FontWeight.w500),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: book.authorName != null
          ? Text(book.authorName!,
              style: TextStyle(color: SagaColors.fgMuted, fontSize: 12),
              maxLines: 1,
              overflow: TextOverflow.ellipsis)
          : null,
      trailing: trailing ??
          IconButton(
            icon: Icon(Icons.remove_circle_outline, color: SagaColors.fgSubtle),
            tooltip: 'Remove from collection',
            onPressed: () => _removeBook(ref),
          ),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => BookDetailScreen(book: book)),
      ),
      ),
    );
  }

  void _removeBook(WidgetRef ref) {
    // No await before the ref use: the Hive put lands in the in-memory box
    // synchronously (the future only confirms the disk flush), and this runs
    // from a dismiss callback on a widget already leaving the tree — an
    // awaited version used ref after dispose.
    unawaited(CustomCollectionStore.removeBook(collectionId, book.ratingKey));
    ref.read(customCollectionRevisionProvider.notifier).state++;
  }
}
