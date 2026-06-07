import 'dart:async';

import 'package:flutter/material.dart';
import '../../core/theme/saga_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/plex/models/plex_book.dart';
import '../../core/providers.dart';
import '../../core/storage/custom_collection_store.dart';
import '../../shared/widgets/book_cover_image.dart';
import '../home/home_screen.dart' show BookProgressOverlay;
import '../library/book_detail_screen.dart';
import '../player/player_provider.dart';
import '../../core/utils/format.dart';
import '../../shared/widgets/saga_sheet.dart';
import '../../shared/widgets/saga_toast.dart';

enum _SortOption { defaultOrder, titleAsc, titleDesc, byAuthor, byDuration }

class BrowseScreen extends ConsumerWidget {
  const BrowseScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(sagaThemeVariantProvider);
    final libraryKeyAsync = ref.watch(activeLibraryKeyProvider);

    return Scaffold(
      backgroundColor: SagaColors.bg,
      body: libraryKeyAsync.when(
        loading: () => Center(
            child: CircularProgressIndicator(color: SagaColors.accent)),
        error: (_, _) => Center(
          child: Text('Could not load library',
              style: TextStyle(color: SagaColors.fgMuted)),
        ),
        data: (key) {
          if (key == null) {
            return Center(
              child: Text('No library found',
                  style: TextStyle(color: SagaColors.fgMuted)),
            );
          }
          return _BrowseContent(libraryKey: key);
        },
      ),
    );
  }
}

class _BrowseContent extends ConsumerStatefulWidget {
  final String libraryKey;
  const _BrowseContent({required this.libraryKey});

  @override
  ConsumerState<_BrowseContent> createState() => _BrowseContentState();
}

class _BrowseContentState extends ConsumerState<_BrowseContent> {
  String _query = '';
  String _debouncedQuery = '';
  Timer? _debounce;
  _SortOption _sort = _SortOption.defaultOrder;
  final _searchController = TextEditingController();

  bool _isList = false;
  bool _selectMode = false;
  final Set<String> _selectedKeys = {};

  @override
  void didUpdateWidget(_BrowseContent old) {
    super.didUpdateWidget(old);
    if (old.libraryKey != widget.libraryKey) {
      _debounce?.cancel();
      _searchController.clear();
      _query = '';
      _debouncedQuery = '';
      _selectMode = false;
      _selectedKeys.clear();
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearch(String value) {
    _debounce?.cancel();
    setState(() => _query = value);
    _debounce = Timer(const Duration(milliseconds: 500), () {
      setState(() => _debouncedQuery = value.trim());
    });
  }

  void _clearSearch() {
    _searchController.clear();
    _debounce?.cancel();
    setState(() {
      _query = '';
      _debouncedQuery = '';
    });
  }

  void _enterSelectMode(String bookKey) {
    setState(() {
      _selectMode = true;
      _selectedKeys.add(bookKey);
    });
  }

  void _toggleSelect(String bookKey) {
    setState(() {
      if (_selectedKeys.contains(bookKey)) {
        _selectedKeys.remove(bookKey);
        if (_selectedKeys.isEmpty) _selectMode = false;
      } else {
        _selectedKeys.add(bookKey);
      }
    });
  }

  void _cancelSelect() {
    setState(() {
      _selectMode = false;
      _selectedKeys.clear();
    });
  }

  void _addSelectedToCollection(BuildContext context) {
    final keys = Set<String>.from(_selectedKeys);
    final collections = CustomCollectionStore.getAll();
    final bottomPad = MediaQuery.of(context).padding.bottom;
    showSagaSheet(context, (ctx) => Padding(
        padding: EdgeInsets.only(bottom: bottomPad),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                'Add ${keys.length} book${keys.length == 1 ? '' : 's'} to…',
                style: TextStyle(
                    color: SagaColors.fg,
                    fontWeight: FontWeight.bold,
                    fontSize: 16),
              ),
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
                  maxHeight: MediaQuery.of(ctx).size.height * 0.55 - bottomPad,
                ),
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    ...collections.map((col) => ListTile(
                          leading: Icon(Icons.folder_outlined,
                              color: SagaColors.fgMuted),
                          title: Text(col.name,
                              style: TextStyle(color: SagaColors.fg)),
                          subtitle: Text(
                              '${col.bookRatingKeys.length} ${col.bookRatingKeys.length == 1 ? 'book' : 'books'}',
                              style: TextStyle(
                                  color: SagaColors.fgSubtle, fontSize: 12)),
                          onTap: () async {
                            final navigator = Navigator.of(ctx);
                            for (final key in keys) {
                              await CustomCollectionStore.addBook(col.id, key);
                            }
                            ref
                                .read(customCollectionRevisionProvider.notifier)
                                .state++;
                            navigator.pop();
                            _cancelSelect();
                            if (mounted) {
                              showSagaToast(this.context,
                                  'Added ${keys.length} book${keys.length == 1 ? '' : 's'} to "${col.name}"');
                            }
                          },
                        )),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _downloadSelected() async {
    final keys = Set<String>.from(_selectedKeys);
    _cancelSelect();
    for (final key in keys) {
      try {
        final tracks = await ref.read(tracksProvider(key).future);
        for (final track in tracks) {
          ref.read(downloadNotifierProvider.notifier).downloadTrack(track, key);
        }
      } catch (_) {}
    }
    if (mounted) {
      showSagaToast(context,
          'Queued ${keys.length} book${keys.length == 1 ? '' : 's'} for download');
    }
  }

  List<PlexBook> _applySortAndFilter(List<PlexBook> books) {
    List<PlexBook> list = _debouncedQuery.isEmpty
        ? books
        : books
            .where((b) =>
                b.title.toLowerCase().contains(_debouncedQuery.toLowerCase()) ||
                (b.authorName
                        ?.toLowerCase()
                        .contains(_debouncedQuery.toLowerCase()) ??
                    false))
            .toList();

    switch (_sort) {
      case _SortOption.titleAsc:
        list = [...list]
          ..sort((a, b) => (a.sortTitle ?? a.title)
              .toLowerCase()
              .compareTo((b.sortTitle ?? b.title).toLowerCase()));
      case _SortOption.titleDesc:
        list = [...list]
          ..sort((a, b) => (b.sortTitle ?? b.title)
              .toLowerCase()
              .compareTo((a.sortTitle ?? a.title).toLowerCase()));
      case _SortOption.byAuthor:
        list = [...list]
          ..sort((a, b) => (a.authorName ?? '')
              .toLowerCase()
              .compareTo((b.authorName ?? '').toLowerCase()));
      case _SortOption.byDuration:
        list = [...list]
          ..sort((a, b) =>
              (a.totalDurationMs ?? 0).compareTo(b.totalDurationMs ?? 0));
      case _SortOption.defaultOrder:
        break;
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final booksAsync = ref.watch(booksProvider(widget.libraryKey));

    final bottomPad = MediaQuery.of(context).padding.bottom;

    return Stack(
      children: [
        CustomScrollView(
          slivers: [
            // ── Single pinned AppBar ───────────────────────────────────────
            // Non-select: toolbarHeight=0 so the 56px "Browse" title lives
            // inside the flexibleSpace flex area, fading as you scroll.
            // The flex area collapses from 56px to 0, leaving only the 96px
            // search+sort bottom pinned.  Select: normal toolbar.
            SliverAppBar(
              pinned: true,
              backgroundColor: Colors.transparent,
              elevation: 0,
              surfaceTintColor: Colors.transparent,
              shadowColor: Colors.transparent,
              automaticallyImplyLeading: false,
              toolbarHeight: _selectMode ? kToolbarHeight : 0,
              // expandedHeight must exceed minExtent (toolbarH + bottomH)
              // to create a collapsible flex region.
              // Non-select: 0 + 56(title) + 96(search) = 152; pinned = 0+96 = 96
              // Select: kToolbarHeight; pinned = kToolbarHeight
              expandedHeight: _selectMode ? kToolbarHeight : 152,
              flexibleSpace: LayoutBuilder(
                builder: (context, constraints) {
                  // Flutter adds MediaQuery.padding.top (status bar) to both
                  // minExtent and maxExtent automatically. Account for it here
                  // so the title sits below the notification bar, not behind it.
                  final topPad = MediaQuery.of(context).padding.top;
                  // minH = topPad + toolbarHeight(0) + bottomHeight(96)
                  final minH = topPad + 96.0;
                  const flexH = 56.0;
                  final opacity = _selectMode
                      ? 0.0
                      : ((constraints.maxHeight - minH) / flexH)
                          .clamp(0.0, 1.0);
                  return Stack(
                    children: [
                      Positioned.fill(
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                SagaColors.bg,
                                SagaColors.bg.withValues(alpha: 0.0),
                              ],
                              stops: [0.6, 1.0],
                            ),
                          ),
                        ),
                      ),
                      // Title below status bar, same vertical position as
                      // other screens' toolbar titles
                      if (!_selectMode)
                        Positioned(
                          top: topPad,
                          left: 16,
                          right: 0,
                          height: 56,
                          child: Opacity(
                            opacity: opacity,
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                'Browse',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 22,
                                  color: SagaColors.fg,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
              title: _selectMode
                  ? Text('${_selectedKeys.length} selected',
                      style: TextStyle(
                          color: SagaColors.fg, fontSize: 18))
                  : null,
              actions: _selectMode
                  ? [
                      TextButton(
                        onPressed: _cancelSelect,
                        child: Text('Cancel',
                            style: TextStyle(color: SagaColors.accent)),
                      ),
                    ]
                  : null,
              bottom: _selectMode
                  ? null
                  : PreferredSize(
                      preferredSize: const Size.fromHeight(96),
                      child: Column(
                        children: [
                          Padding(
                            padding:
                                const EdgeInsets.fromLTRB(16, 0, 16, 6),
                            child: TextField(
                              controller: _searchController,
                              style:
                                  TextStyle(color: SagaColors.fg),
                              decoration: InputDecoration(
                                hintText:
                                    'Search by title or author…',
                                hintStyle: TextStyle(
                                    color: SagaColors.fgSubtle),
                                prefixIcon: Icon(Icons.search,
                                    color: SagaColors.fgSubtle),
                                suffixIcon: _query.isNotEmpty
                                    ? IconButton(
                                        icon: Icon(Icons.clear,
                                            color: SagaColors.fgSubtle),
                                        onPressed: _clearSearch,
                                      )
                                    : null,
                                filled: true,
                                fillColor: SagaColors.surface,
                                border: OutlineInputBorder(
                                  borderRadius:
                                      BorderRadius.circular(12),
                                  borderSide: BorderSide.none,
                                ),
                                contentPadding: EdgeInsets.zero,
                              ),
                              onChanged: _onSearch,
                            ),
                          ),
                          Row(
                            children: [
                              Expanded(
                                child: SizedBox(
                                  height: 36,
                                  child: ListView(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12),
                                    scrollDirection: Axis.horizontal,
                                    children: [
                                      _SortChip(
                                        label: 'Default',
                                        selected: _sort ==
                                            _SortOption.defaultOrder,
                                        onTap: () => setState(() =>
                                            _sort = _SortOption.defaultOrder),
                                      ),
                                      _SortChip(
                                        label: 'A → Z',
                                        selected:
                                            _sort == _SortOption.titleAsc,
                                        onTap: () => setState(() =>
                                            _sort = _SortOption.titleAsc),
                                      ),
                                      _SortChip(
                                        label: 'Z → A',
                                        selected:
                                            _sort == _SortOption.titleDesc,
                                        onTap: () => setState(() =>
                                            _sort = _SortOption.titleDesc),
                                      ),
                                      _SortChip(
                                        label: 'Author',
                                        selected:
                                            _sort == _SortOption.byAuthor,
                                        onTap: () => setState(() =>
                                            _sort = _SortOption.byAuthor),
                                      ),
                                      _SortChip(
                                        label: 'Duration',
                                        selected:
                                            _sort == _SortOption.byDuration,
                                        onTap: () => setState(() =>
                                            _sort = _SortOption.byDuration),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              IconButton(
                                icon: Icon(
                                  _isList ? Icons.grid_view : Icons.list,
                                  color: SagaColors.fgMuted,
                                  size: 20,
                                ),
                                onPressed: () =>
                                    setState(() => _isList = !_isList),
                                padding: const EdgeInsets.only(right: 12),
                                constraints: const BoxConstraints(),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
            ),

            if (_debouncedQuery.isNotEmpty && _query != _debouncedQuery)
              SliverToBoxAdapter(
                child: LinearProgressIndicator(
                  color: SagaColors.accent,
                  backgroundColor: Colors.transparent,
                ),
              ),

            booksAsync.when(
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
                  child: Text('Could not load books',
                      style: TextStyle(color: SagaColors.fgMuted)),
                ),
              ),
              data: (books) {
                final filtered = _applySortAndFilter(books);
                if (filtered.isEmpty) {
                  return SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(48),
                      child: Center(
                        child: Text(
                          _debouncedQuery.isNotEmpty
                              ? 'No results for "$_debouncedQuery"'
                              : 'No books found',
                          style:
                              TextStyle(color: SagaColors.fgSubtle),
                        ),
                      ),
                    ),
                  );
                }
                if (_isList) {
                  final listBottom = (_selectMode && _selectedKeys.isNotEmpty)
                      ? bottomPad + 72
                      : bottomPad + 16;
                  return SliverPadding(
                    padding: EdgeInsets.fromLTRB(0, 4, 0, listBottom),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, i) => _BookListTile(
                          book: filtered[i],
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) =>
                                    BookDetailScreen(book: filtered[i])),
                          ),
                        ),
                        childCount: filtered.length,
                      ),
                    ),
                  );
                }
                // Add extra space when the selection action bar is floating above
                // the nav area so the bottom grid row doesn't hide behind it.
                final gridBottom = (_selectMode && _selectedKeys.isNotEmpty)
                    ? bottomPad + 72
                    : bottomPad + 16;
                return SliverPadding(
                  padding: EdgeInsets.fromLTRB(16, 8, 16, gridBottom),
                  sliver: SliverGrid(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      childAspectRatio: 0.75,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, i) {
                        final book = filtered[i];
                        final selected =
                            _selectedKeys.contains(book.ratingKey);
                        return _BookTile(
                          book: book,
                          selectMode: _selectMode,
                          selected: selected,
                          onTap: _selectMode
                              ? () => _toggleSelect(book.ratingKey)
                              : null,
                          onLongPress: () =>
                              _enterSelectMode(book.ratingKey),
                        );
                      },
                      childCount: filtered.length,
                    ),
                  ),
                );
              },
            ),
          ],
        ),

        // ── Action bar — sits just above the nav area ────────────────────
        if (_selectMode && _selectedKeys.isNotEmpty)
          Positioned(
            bottom: bottomPad + 8,
            left: 16,
            right: 16,
            child: Row(
              children: [
                Expanded(
                  child: Material(
                    color: SagaColors.surface,
                    borderRadius: BorderRadius.circular(30),
                    elevation: 8,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(30),
                      onTap: _downloadSelected,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 14),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.download_rounded,
                                color: SagaColors.accent),
                            const SizedBox(width: 8),
                            Text(
                              'Download',
                              style: TextStyle(
                                color: SagaColors.fg,
                                fontWeight: FontWeight.w600,
                                fontSize: 15,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Material(
                    color: SagaColors.surface,
                    borderRadius: BorderRadius.circular(30),
                    elevation: 8,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(30),
                      onTap: () => _addSelectedToCollection(context),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 14),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.folder_outlined,
                                color: SagaColors.accent),
                            const SizedBox(width: 8),
                            Text(
                              'Collect',
                              style: TextStyle(
                                color: SagaColors.fg,
                                fontWeight: FontWeight.w600,
                                fontSize: 15,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _SortChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _SortChip(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          alignment: Alignment.center,
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: selected
                ? SagaColors.accent
                : SagaColors.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
                color:
                    selected ? SagaColors.accent : SagaColors.border),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? SagaColors.accentFg : SagaColors.fgMuted,
              fontSize: 12,
              fontWeight:
                  selected ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }
}

class _BookTile extends ConsumerWidget {
  final PlexBook book;
  final bool selectMode;
  final bool selected;
  final VoidCallback? onTap;
  final VoidCallback onLongPress;

  const _BookTile({
    required this.book,
    required this.onLongPress,
    this.selectMode = false,
    this.selected = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasDownload = ref
        .watch(downloadNotifierProvider)
        .downloadedBooks
        .contains(book.ratingKey);

    return GestureDetector(
      onTap: onTap ??
          () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => BookDetailScreen(book: book)),
              ),
      onLongPress: onLongPress,
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
                if (!selectMode && hasDownload)
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
                if (selectMode)
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        color: selected
                            ? SagaColors.accent.withValues(alpha: 0.3)
                            : SagaColors.accentFg.withValues(alpha: 0.3),
                      ),
                      child: selected
                          ? Icon(Icons.check_circle_rounded,
                              color: SagaColors.accent, size: 28)
                          : Icon(Icons.radio_button_unchecked,
                              color: SagaColors.fgMuted, size: 28),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(book.title,
              style: TextStyle(color: SagaColors.fg, fontSize: 12),
              maxLines: 2,
              overflow: TextOverflow.ellipsis),
          if (book.authorName != null)
            Text(book.authorName!,
                style:
                    TextStyle(color: SagaColors.fgSubtle, fontSize: 11),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }

}

class _BookListTile extends StatelessWidget {
  final PlexBook book;
  final VoidCallback onTap;

  const _BookListTile({required this.book, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final duration = fmtDurationMs(book.totalDurationMs);

    return InkWell(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                // Cover thumbnail
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: SizedBox(
                    width: 56,
                    height: 60,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        BookCoverImage(thumbPath: book.thumbPath, cacheWidth: 112),
                        BookProgressOverlay(book: book),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                // Text info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        book.title,
                        style: TextStyle(
                          color: SagaColors.fg,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (book.authorName != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          book.authorName!,
                          style: TextStyle(
                            color: SagaColors.fgSubtle,
                            fontSize: 12,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      if (duration.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          duration,
                          style: TextStyle(
                            color: SagaColors.fgMuted,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          Divider(
            height: 1,
            thickness: 1,
            color: SagaColors.border,
            indent: 86,
          ),
        ],
      ),
    );
  }

}
