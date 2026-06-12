import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/plex/models/plex_book.dart';
import '../../core/providers.dart';
import '../../core/storage/named_bookmark_store.dart';
import '../../core/theme/saga_theme.dart';
import '../../core/utils/format.dart';
import '../../shared/widgets/saga_sheet.dart';
import '../player/player_provider.dart';
import '../player/player_screen.dart';

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
          _fmtDate(bookmark.createdAt),
          style: TextStyle(color: SagaColors.fgSubtle, fontSize: 11),
        ),
        onTap: () => _showBookmarkSheet(context, ref),
      ),
    );
  }

  void _delete(WidgetRef ref) {
    NamedBookmarkStore.delete(bookmark.id);
    ref.read(bookmarkRevisionProvider.notifier).state++;
  }

  Future<void> _jumpTo(BuildContext context, WidgetRef ref) async {
    try {
      final tracks =
          await ref.read(tracksProvider(bookmark.bookRatingKey).future);
      if (!context.mounted) return;
      final idx =
          tracks.indexWhere((t) => t.ratingKey == bookmark.trackRatingKey);
      if (idx < 0) return;
      Navigator.of(context, rootNavigator: true)
          .push(MaterialPageRoute(builder: (_) => const PlayerScreen()));
      final service = ref.read(playerServiceProvider);
      await service.loadBook(
        bookRatingKey: bookmark.bookRatingKey,
        tracks: tracks,
        startTrackIndex: idx,
        startPositionMs: bookmark.positionMs,
      );
      await service.play();
    } catch (_) {}
  }

  void _showBookmarkSheet(BuildContext context, WidgetRef ref) {
    final labelCtrl = TextEditingController(text: bookmark.label);
    final noteCtrl = TextEditingController(text: bookmark.note ?? '');
    final bottomPad = MediaQuery.of(context).padding.bottom;

    showSagaSheet<void>(context, (_) => StatefulBuilder(
      builder: (sheetCtx, _) {
        final keyboardInset = MediaQuery.of(sheetCtx).viewInsets.bottom;
        return Padding(
          padding: EdgeInsets.only(bottom: bottomPad + keyboardInset),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SagaSheetTitle('Bookmark',
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0)),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: Text(
                  fmtDuration(Duration(milliseconds: bookmark.positionMs)),
                  style: TextStyle(color: SagaColors.fgSubtle, fontSize: 13),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: TextField(
                  controller: labelCtrl,
                  autofocus: false,
                  style: TextStyle(color: SagaColors.fg),
                  decoration: InputDecoration(
                    labelText: 'Label',
                    labelStyle: TextStyle(color: SagaColors.fgMuted),
                    enabledBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: SagaColors.border)),
                    focusedBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: SagaColors.accent)),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: TextField(
                  controller: noteCtrl,
                  minLines: 1,
                  maxLines: 3,
                  style: TextStyle(color: SagaColors.fg),
                  decoration: InputDecoration(
                    labelText: 'Note (optional)',
                    labelStyle: TextStyle(color: SagaColors.fgMuted),
                    enabledBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: SagaColors.border)),
                    focusedBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: SagaColors.accent)),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Row(
                  children: [
                    OutlinedButton(
                      onPressed: () {
                        Navigator.pop(sheetCtx);
                        _jumpTo(context, ref);
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: SagaColors.accent,
                        side: BorderSide(color: SagaColors.accent),
                      ),
                      child: const Text('Jump to'),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () => Navigator.pop(sheetCtx),
                      child: Text('Cancel',
                          style: TextStyle(color: SagaColors.fgMuted)),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () {
                        final label = labelCtrl.text.trim();
                        if (label.isEmpty) return;
                        final note = noteCtrl.text.trim();
                        final updated = bookmark.copyWith(
                          label: label,
                          note: note.isEmpty ? null : note,
                        );
                        NamedBookmarkStore.update(updated);
                        ref.read(bookmarkRevisionProvider.notifier).state++;
                        Navigator.pop(sheetCtx);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: SagaColors.accent,
                        foregroundColor: SagaColors.bg,
                      ),
                      child: const Text('Save'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    ));
  }

  String _fmtDate(DateTime dt) {
    final today = DateTime.now();
    final d = DateTime(dt.year, dt.month, dt.day);
    final t = DateTime(today.year, today.month, today.day);
    final diff = t.difference(d).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    return '${dt.day}/${dt.month}/${dt.year}';
  }
}
