import 'dart:async';

import 'package:flutter/material.dart';
import '../../core/theme/saga_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/book_progress.dart';
import '../../core/diagnostics/app_log.dart';
import '../../core/plex/models/plex_book.dart';
import '../../core/plex/narrator_index.dart';
import '../../core/providers.dart';
import '../../core/storage/bookmark_store.dart';
import '../../core/storage/custom_collection_store.dart';
import '../../core/storage/want_to_read_store.dart';
import '../../shared/widgets/book_card.dart';
import '../../shared/widgets/book_cover_image.dart';
import '../collections/collection_picker_sheet.dart';
import '../library/book_detail_screen.dart';
import '../player/player_provider.dart';
import '../../core/utils/format.dart';
import '../../shared/widgets/saga_error_view.dart';
import '../../shared/widgets/saga_sheet.dart';
import '../../shared/widgets/saga_toast.dart';

enum _SortOption {
  defaultOrder,
  titleAsc,
  titleDesc,
  byAuthorAsc,
  byAuthorDesc,
  byDurationAsc,
  byDurationDesc,
  byNarratorAsc,
  byNarratorDesc,
}

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
        error: (e, _) => SagaErrorView(
          message: 'Could not load your library',
          error: e,
          onRetry: () => ref.invalidate(activeLibraryKeyProvider),
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
  bool _onlyWanted = false;
  bool _onlyDownloaded = false;
  bool _selectMode = false;
  final Set<String> _selectedKeys = {};

  String _sortChipLabel() => switch (_sort) {
        _SortOption.defaultOrder => 'Sort',
        _SortOption.titleAsc => 'Title A→Z',
        _SortOption.titleDesc => 'Title Z→A',
        _SortOption.byAuthorAsc => 'Author A→Z',
        _SortOption.byAuthorDesc => 'Author Z→A',
        _SortOption.byDurationAsc => 'Duration ↑',
        _SortOption.byDurationDesc => 'Duration ↓',
        _SortOption.byNarratorAsc => 'Narrator A→Z',
        _SortOption.byNarratorDesc => 'Narrator Z→A',
      };

  void _showSortSheet() {
    // Sheets on the tab navigator paint under the nav pill/mini player —
    // pad by the calling context's bottom inset (standing convention).
    final bottomPad = MediaQuery.of(context).padding.bottom;
    showSagaSheet(context, (ctx) {
      Widget option({
        required String label,
        required _SortOption asc,
        _SortOption? desc,
        String ascLabel = 'A → Z',
        String descLabel = 'Z → A',
      }) {
        final active = _sort == asc || (desc != null && _sort == desc);
        final isAsc = _sort == asc;
        return ListTile(
          dense: true,
          leading: Icon(
            active
                ? Icons.radio_button_checked
                : Icons.radio_button_unchecked,
            color: active ? SagaColors.accent : SagaColors.fgMuted,
            size: 20,
          ),
          title: Text(label,
              style: TextStyle(
                  color: active ? SagaColors.accent : SagaColors.fg,
                  fontSize: 14,
                  fontWeight:
                      active ? FontWeight.w600 : FontWeight.normal)),
          trailing: active && desc != null
              ? Text(isAsc ? ascLabel : descLabel,
                  style:
                      TextStyle(color: SagaColors.accent, fontSize: 12.5))
              : null,
          onTap: () {
            // Tapping the active option flips its direction; an inactive one
            // selects it (ascending first).
            setState(() {
              _sort = active && desc != null ? (isAsc ? desc : asc) : asc;
            });
            // Choosing narrator is the "first use" that earns the index.
            if (_sort == _SortOption.byNarratorAsc ||
                _sort == _SortOption.byNarratorDesc) {
              _ensureNarratorIndex();
            }
            Navigator.pop(ctx);
          },
        );
      }

      return Padding(
        padding: EdgeInsets.only(bottom: bottomPad + 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SagaSheetTitle('Sort',
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 4)),
            option(
                label: 'Default (library order)',
                asc: _SortOption.defaultOrder),
            option(
                label: 'Title',
                asc: _SortOption.titleAsc,
                desc: _SortOption.titleDesc),
            option(
                label: 'Author',
                asc: _SortOption.byAuthorAsc,
                desc: _SortOption.byAuthorDesc),
            option(
                label: 'Duration',
                asc: _SortOption.byDurationAsc,
                desc: _SortOption.byDurationDesc,
                ascLabel: 'Shortest first',
                descLabel: 'Longest first'),
            option(
                label: 'Narrator',
                asc: _SortOption.byNarratorAsc,
                desc: _SortOption.byNarratorDesc),
          ],
        ),
      );
    });
  }

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

  /// Narrators for a book, from the index. Empty until it has been built.
  List<String> _narratorsOf(String bookRatingKey) =>
      ref.read(narratorIndexProvider(widget.libraryKey)).index[bookRatingKey] ??
      const [];

  String _narratorKey(PlexBook b) {
    final n = _narratorsOf(b.ratingKey);
    return n.isEmpty ? '' : n.first.toLowerCase();
  }

  /// Kicks off the one-time index build. Cheap to call repeatedly — the
  /// notifier ignores it while building or once ready.
  void _ensureNarratorIndex() {
    ref.read(narratorIndexProvider(widget.libraryKey).notifier).build();
  }

  bool get _narratorSortActive =>
      _sort == _SortOption.byNarratorAsc ||
      _sort == _SortOption.byNarratorDesc;

  /// Shown only when narrator is actually being used: while the one-time index
  /// builds, if it failed, or to offer it when a search could match narrators
  /// but can't yet.
  Widget _narratorIndexBanner() {
    final state = ref.watch(narratorIndexProvider(widget.libraryKey));
    final searching = _debouncedQuery.isNotEmpty;
    final wantsNarrators = _narratorSortActive || searching;
    if (!wantsNarrators) return const SizedBox.shrink();

    Widget wrap(Widget child) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: child,
        );

    if (state.building) {
      return wrap(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              state.total == 0
                  ? 'Finding narrators…'
                  : 'Indexing narrators… ${state.done}/${state.total}',
              style: TextStyle(color: SagaColors.fgMuted, fontSize: 12),
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: state.total == 0 ? null : state.progress,
                minHeight: 3,
                color: SagaColors.accent,
                backgroundColor: SagaColors.surfaceAlt,
              ),
            ),
          ],
        ),
      );
    }

    if (state.error != null) {
      return wrap(Row(
        children: [
          Expanded(
            child: Text(state.error!,
                style: TextStyle(color: SagaColors.fgMuted, fontSize: 12)),
          ),
          TextButton(
            onPressed: () => ref
                .read(narratorIndexProvider(widget.libraryKey).notifier)
                .build(force: true),
            child: Text('Retry',
                style: TextStyle(color: SagaColors.accent, fontSize: 12.5)),
          ),
        ],
      ));
    }

    // Searching is the one case worth offering the index unprompted: the user
    // may well be typing a narrator's name and getting nothing back.
    if (!state.isReady && searching) {
      return wrap(Row(
        children: [
          Expanded(
            child: Text('Narrators aren\'t indexed yet.',
                style: TextStyle(color: SagaColors.fgMuted, fontSize: 12)),
          ),
          TextButton(
            onPressed: _ensureNarratorIndex,
            child: Text('Search narrators too',
                style: TextStyle(color: SagaColors.accent, fontSize: 12.5)),
          ),
        ],
      ));
    }

    return const SizedBox.shrink();
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
    showCollectionPickerSheet(
      context,
      title: 'Add ${keys.length} book${keys.length == 1 ? '' : 's'} to…',
      onPick: (col) async {
        // Thumbs so an empty collection can adopt a cover from the first
        // book added.
        final loaded =
            ref.read(booksProvider(widget.libraryKey)).valueOrNull ??
                const <PlexBook>[];
        final thumbs = {for (final b in loaded) b.ratingKey: b.thumbPath};
        for (final key in keys) {
          await CustomCollectionStore.addBook(col.id, key,
              coverThumbPath: thumbs[key]);
        }
        if (!mounted) return;
        ref.read(customCollectionRevisionProvider.notifier).state++;
        _cancelSelect();
        showSagaToast(this.context,
            'Added ${keys.length} book${keys.length == 1 ? '' : 's'} to "${col.name}"');
      },
    );
  }

  Future<void> _downloadSelected() async {
    final keys = Set<String>.from(_selectedKeys);
    _cancelSelect();
    // Count failures instead of swallowing them: this used to catch
    // everything and claim "Queued N books" even fully offline, when
    // nothing had been queued at all.
    var failed = 0;
    for (final key in keys) {
      try {
        final tracks = await ref.read(tracksProvider(key).future);
        await ref
            .read(downloadNotifierProvider.notifier)
            .downloadBook(key, tracks);
      } catch (e) {
        failed++;
        AppLog.log('download', 'bulk queue failed for book $key: $e');
      }
    }
    if (!mounted) return;
    final queued = keys.length - failed;
    if (failed == 0) {
      showSagaToast(context,
          'Queued $queued book${queued == 1 ? '' : 's'} for download');
    } else if (queued == 0) {
      showSagaToast(context,
          'Couldn\'t queue the download — is the server reachable?',
          isError: true);
    } else {
      showSagaToast(context,
          'Queued $queued of ${keys.length} books — '
          '$failed couldn\'t be loaded',
          isError: true);
    }
  }

  List<PlexBook> _applySortAndFilter(List<PlexBook> books) {
    final q = _debouncedQuery.toLowerCase();
    List<PlexBook> list = _debouncedQuery.isEmpty
        ? books
        : books
            .where((b) =>
                b.title.toLowerCase().contains(q) ||
                (b.authorName?.toLowerCase().contains(q) ?? false) ||
                // Narrator only matches once the index exists; before that it
                // simply doesn't contribute, rather than silently excluding
                // books.
                _narratorsOf(b.ratingKey)
                    .any((n) => n.toLowerCase().contains(q)))
            .toList();

    if (_onlyWanted) {
      final wanted = WantToReadStore.all;
      list = list.where((b) => wanted.contains(b.ratingKey)).toList();
    }

    if (_onlyDownloaded) {
      // Any download counts (not just fully downloaded) — a partially
      // downloaded book is one the user likely wants to find and finish.
      final downloaded =
          ref.read(downloadNotifierProvider).downloadedBooks;
      list = list.where((b) => downloaded.contains(b.ratingKey)).toList();
    }

    switch (_sort) {
      case _SortOption.titleAsc:
        list = _sortedByKey(
            list, (b) => (b.sortTitle ?? b.title).toLowerCase());
      case _SortOption.titleDesc:
        list = _sortedByKey(
            list, (b) => (b.sortTitle ?? b.title).toLowerCase(),
            descending: true);
      case _SortOption.byAuthorAsc:
        list = _sortedByKey(list, (b) => (b.authorName ?? '').toLowerCase());
      case _SortOption.byAuthorDesc:
        list = _sortedByKey(list, (b) => (b.authorName ?? '').toLowerCase(),
            descending: true);
      case _SortOption.byDurationAsc:
        list = _sortedByKey(list, _durationMs);
      case _SortOption.byDurationDesc:
        list = _sortedByKey(list, _durationMs, descending: true);
      case _SortOption.byNarratorAsc:
        list = _sortedByKey(list, _narratorKeyOrNull);
      case _SortOption.byNarratorDesc:
        list = _sortedByKey(list, _narratorKeyOrNull, descending: true);
      case _SortOption.defaultOrder:
        break;
    }
    return list;
  }

  /// Decorate-sort-undecorate: [keyOf] runs once per book, not once per
  /// comparison. The duration key is a Hive read and the narrator key a
  /// provider lookup, so comparator-time keys cost ~n·log n of them — on a
  /// 2000-book library roughly 44,000 deserialisations per sort, re-run on
  /// every keystroke and every download-progress tick.
  ///
  /// Null keys sink to the bottom in *both* directions — an unknown isn't
  /// "before A" or "after Z", it's just unknown.
  List<PlexBook> _sortedByKey<K extends Comparable<dynamic>>(
      List<PlexBook> books, K? Function(PlexBook) keyOf,
      {bool descending = false}) {
    final keys = <String, K?>{for (final b in books) b.ratingKey: keyOf(b)};
    return [...books]..sort((a, b) {
        final ak = keys[a.ratingKey];
        final bk = keys[b.ratingKey];
        if (ak == null || bk == null) {
          return ak == null && bk == null ? 0 : (ak == null ? 1 : -1);
        }
        final cmp = ak.compareTo(bk);
        return descending ? -cmp : cmp;
      });
  }

  String? _narratorKeyOrNull(PlexBook book) {
    final key = _narratorKey(book);
    return key.isEmpty ? null : key;
  }

  static int? _durationMs(PlexBook book) =>
      bookTotalDurationMs(book, BookmarkStore.load(book.ratingKey));

  @override
  Widget build(BuildContext context) {
    ref.watch(wantToReadRevisionProvider);
    // The "Downloaded" filter reads the download stores in
    // _applySortAndFilter, so the list must rebuild when they change —
    // otherwise a finished download never appears and a deleted one never
    // leaves (its card would even drop its badge while staying in the list).
    // Same pairing as wantToReadRevisionProvider above for the "Saved" chip.
    ref.watch(downloadNotifierProvider);
    // Narrator sort and search read the index in _applySortAndFilter, so the
    // list must rebuild when the one-time build finishes — otherwise it would
    // stay sorted by an index that has since arrived. Same pairing again.
    ref.watch(narratorIndexProvider(widget.libraryKey));
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
                                // Names narrator even before the index exists:
                                // the prompt under the field offers to build it
                                // the moment a search is typed, so the hint is
                                // what makes the feature findable at all.
                                hintText:
                                    'Search by title, author or narrator…',
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
                              const SizedBox(width: 8),
                              // Filters (independent toggles) live left; the
                              // mutually-exclusive sort collapses into one chip
                              // opening a sheet — no more scrolling row mixing
                              // two kinds of control with identical styling.
                              _SortChip(
                                label: 'Saved',
                                selected: _onlyWanted,
                                onTap: () => setState(
                                    () => _onlyWanted = !_onlyWanted),
                              ),
                              _SortChip(
                                label: 'Downloaded',
                                selected: _onlyDownloaded,
                                onTap: () => setState(() =>
                                    _onlyDownloaded = !_onlyDownloaded),
                              ),
                              const Spacer(),
                              _SortChip(
                                label: _sortChipLabel(),
                                selected: _sort != _SortOption.defaultOrder,
                                onTap: _showSortSheet,
                              ),
                              // Same pill treatment as the chips so it reads
                              // as part of the control row, not loose
                              // furniture. Outer 44dp box keeps the touch
                              // target at the accessibility floor; the visible
                              // circle matches the chips' height.
                              GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () =>
                                    setState(() => _isList = !_isList),
                                child: Semantics(
                                  button: true,
                                  label: _isList
                                      ? 'Switch to grid view'
                                      : 'Switch to list view',
                                  child: Container(
                                    width: 44,
                                    height: 44,
                                    alignment: Alignment.center,
                                    margin:
                                        const EdgeInsets.only(right: 8),
                                    child: Container(
                                      width: 38,
                                      height: 38,
                                      decoration: BoxDecoration(
                                        color: SagaColors.surface,
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                            color: SagaColors.border),
                                      ),
                                      child: Icon(
                                        _isList
                                            ? Icons.grid_view
                                            : Icons.list,
                                        color: SagaColors.fgMuted,
                                        size: 18,
                                      ),
                                    ),
                                  ),
                                ),
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

            SliverToBoxAdapter(child: _narratorIndexBanner()),

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
              error: (e, _) => SliverToBoxAdapter(
                child: SagaErrorView(
                  message: 'Could not load books',
                  error: e,
                  onRetry: () =>
                      ref.invalidate(booksProvider(widget.libraryKey)),
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
                        (context, i) {
                          final book = filtered[i];
                          return _BookListTile(
                            book: book,
                            selectMode: _selectMode,
                            selected: _selectedKeys.contains(book.ratingKey),
                            onTap: _selectMode
                                ? () => _toggleSelect(book.ratingKey)
                                : () => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                          builder: (_) =>
                                              BookDetailScreen(book: book)),
                                    ),
                            onLongPress: () =>
                                _enterSelectMode(book.ratingKey),
                          );
                        },
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
                    gridDelegate: bookGridDelegate(),
                    delegate: SliverChildBuilderDelegate(
                      (context, i) {
                        final book = filtered[i];
                        final selected =
                            _selectedKeys.contains(book.ratingKey);
                        return BookCard(
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
              const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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

class _BookListTile extends StatelessWidget {
  final PlexBook book;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  // Same selection contract as [BookCard] — the list view used to ignore
  // selection mode entirely, so with books already selected in the grid a
  // switch to list view showed no checkmarks and every tap navigated away.
  final bool selectMode;
  final bool selected;

  const _BookListTile({
    required this.book,
    required this.onTap,
    this.onLongPress,
    this.selectMode = false,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    final duration = fmtDurationMs(
        bookTotalDurationMs(book, BookmarkStore.load(book.ratingKey)));

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            color: selectMode && selected
                ? SagaColors.accent.withValues(alpha: 0.12)
                : Colors.transparent,
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
                        BookCoverImage(
                            thumbPath: book.thumbPath,
                            cacheWidth: kCoverCacheWidthThumb),
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
                if (selectMode) ...[
                  const SizedBox(width: 8),
                  Icon(
                    selected
                        ? Icons.check_circle_rounded
                        : Icons.radio_button_unchecked,
                    color: selected ? SagaColors.accent : SagaColors.fgSubtle,
                    size: 22,
                  ),
                ],
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
