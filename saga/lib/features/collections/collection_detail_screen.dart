import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/plex/models/plex_book.dart';
import '../../core/providers.dart';
import '../../shared/widgets/book_cover_image.dart';
import '../../core/storage/custom_collection_store.dart';
import '../../core/theme/saga_theme.dart';
import '../library/book_detail_screen.dart';
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

    final bottomPad = MediaQuery.of(context).padding.bottom;
    showSagaSheet(context, (ctx) => Padding(
        padding: EdgeInsets.only(bottom: bottomPad),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text('Set cover',
                  style: TextStyle(
                      color: SagaColors.fg,
                      fontWeight: FontWeight.bold,
                      fontSize: 16)),
            ),
            if (books.isEmpty)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text('Add books to this collection first.',
                    style: TextStyle(color: SagaColors.fgMuted)),
              )
            else
              SizedBox(
                height: 120,
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
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: SizedBox(
                          width: 90,
                          child: BookCoverImage(thumbPath: book.thumbPath, cacheWidth: 180),
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
        error: (e, _) => Center(
            child: Text('$e', style: TextStyle(color: SagaColors.fgMuted))),
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
                child: TextField(
                  controller: _searchController,
                  style: TextStyle(color: SagaColors.fg),
                  decoration: InputDecoration(
                    hintText: 'Search in collection…',
                    hintStyle: TextStyle(color: SagaColors.fgSubtle),
                    prefixIcon:
                        Icon(Icons.search, color: SagaColors.fgSubtle),
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
                            itemBuilder: (context, i) =>
                                _BookTile(book: books[i], collectionId: widget.collection.id, ref: ref),
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
                                ref: ref,
                                index: i,
                                trailing: ReorderableDragStartListener(
                                  index: i,
                                  child: Icon(Icons.drag_handle,
                                      color: SagaColors.fgSubtle),
                                ),
                              );
                            },
                            onReorder: (oldIdx, newIdx) async {
                              if (newIdx > oldIdx) newIdx--;
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

class _BookTile extends StatelessWidget {
  final PlexBook book;
  final String collectionId;
  final WidgetRef ref;
  final Widget? trailing;
  final int? index;

  const _BookTile({
    super.key,
    required this.book,
    required this.collectionId,
    required this.ref,
    this.trailing,
    this.index,
  });

  @override
  Widget build(BuildContext context) {
    final cover = ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        width: 40,
        height: 40,
        child: BookCoverImage(thumbPath: book.thumbPath, cacheWidth: 80),
      ),
    );
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: index != null
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 24,
                  child: Text(
                    '${index! + 1}',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: SagaColors.fgSubtle,
                      fontSize: 13,
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
            onPressed: () => _removeBook(context),
          ),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => BookDetailScreen(book: book)),
      ),
    );
  }

  Future<void> _removeBook(BuildContext context) async {
    await CustomCollectionStore.removeBook(collectionId, book.ratingKey);
    ref.read(customCollectionRevisionProvider.notifier).state++;
  }

}
