part of 'settings_screen.dart';

/// Settings › Downloads (handoff 13e without its sync row, which waits for
/// position sync to leave the flag; the page becomes "Downloads and sync"
/// then).
class _DownloadsPage extends ConsumerStatefulWidget {
  const _DownloadsPage();

  @override
  ConsumerState<_DownloadsPage> createState() => _DownloadsPageState();
}

class _DownloadsPageState extends ConsumerState<_DownloadsPage> {
  late bool _wifiOnly = SettingsStore.downloadWifiOnly;
  late bool _removeFinished = SettingsStore.removeFinishedDownloads;

  @override
  Widget build(BuildContext context) {
    ref.watch(sagaThemeVariantProvider);
    return _SettingsPage(
      title: 'Downloads',
      children: [
          _SwitchTile(
            icon: Icons.wifi_rounded,
            title: 'Download on Wi-Fi only',
            subtitle: 'Don\'t use mobile data for downloads',
            value: _wifiOnly,
            onChanged: (v) async {
              await SettingsStore.setDownloadWifiOnly(v);
              if (!mounted) return;
              setState(() => _wifiOnly = v);
            },
          ),
          _SwitchTile(
            icon: Icons.auto_delete_outlined,
            title: 'Remove finished downloads',
            subtitle: 'When you listen to the end of a book and move on to '
                'another, its download is deleted',
            value: _removeFinished,
            onChanged: (v) async {
              await SettingsStore.setRemoveFinishedDownloads(v);
              if (!mounted) return;
              setState(() => _removeFinished = v);
            },
          ),
          const _StorageTile(),
      ],
    );
  }
}

// ── Storage manager ───────────────────────────────────────────────────────────

class _StorageResult {
  final int bookCount;
  final int totalBytes;
  final List<_BookStorageInfo> books;
  const _StorageResult({
    required this.bookCount,
    required this.totalBytes,
    required this.books,
  });
}

class _BookStorageInfo {
  final String title;
  final String bookRatingKey;
  final Set<String> trackKeys;
  final int bytes;
  const _BookStorageInfo({
    required this.title,
    required this.bookRatingKey,
    required this.trackKeys,
    required this.bytes,
  });
}

class _StorageTile extends ConsumerStatefulWidget {
  const _StorageTile();

  @override
  ConsumerState<_StorageTile> createState() => _StorageTileState();
}

class _StorageTileState extends ConsumerState<_StorageTile> {
  late Future<_StorageResult> _future;

  @override
  void initState() {
    super.initState();
    _future = _scan();
  }

  Future<_StorageResult> _scan() async {
    // Scan the download STORES, not the filesystem: the stores are what
    // Browse's badge and "Downloaded" filter read, so building this list from
    // the same source keeps the two surfaces consistent by construction (the
    // old folder-based scan could disagree with Browse — issue reported July
    // 2026). reconcile() first drops metadata whose files are gone.
    await ref.read(downloadNotifierProvider.notifier).reconcile();
    final books = <_BookStorageInfo>[];
    for (final bookKey in BookDownloadStore.booksWithDownloads()) {
      final trackKeys = BookDownloadStore.trackKeys(bookKey);
      var size = 0;
      String? anyPath;
      for (final key in trackKeys) {
        final path = DownloadStore.getPath(key);
        if (path == null) continue;
        anyPath = path;
        final file = File(path);
        // Async stat, not the Sync variants: this loop touches every file of
        // every downloaded book on the UI isolate, and re-runs on each
        // completed download — hundreds of blocking syscalls per pass on a
        // well-stocked library, each one a chance to skip a frame. A missing
        // file stats as notFound (size -1) rather than throwing.
        final stat = await file.stat();
        if (stat.type != FileSystemEntityType.notFound) size += stat.size;
      }
      // Title from the track cache; for pre-cache downloads fall back to the
      // download folder's name (which was derived from the book title).
      final cached = TrackCacheStore.load(bookKey);
      final title = cached?.first.bookTitle ??
          (anyPath != null
              ? File(anyPath).parent.uri.pathSegments
                  .lastWhere((s) => s.isNotEmpty, orElse: () => 'Unknown book')
              : 'Unknown book');
      books.add(_BookStorageInfo(
        title: title,
        bookRatingKey: bookKey,
        trackKeys: trackKeys,
        bytes: size,
      ));
    }
    books.sort((a, b) => b.bytes.compareTo(a.bytes));
    final total = books.fold(0, (sum, b) => sum + b.bytes);
    return _StorageResult(bookCount: books.length, totalBytes: total, books: books);
  }

  void _refresh() => setState(() => _future = _scan());

  void _showSheet(BuildContext context, _StorageResult result) {
    final bottomPad = MediaQuery.of(context).padding.bottom;
    showSagaSheet(context, (ctx) => StatefulBuilder(
      builder: (ctx, setSheet) => Padding(
        padding: EdgeInsets.only(bottom: bottomPad),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SagaSheetTitle('Downloaded books',
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8)),
            ConstrainedBox(
              constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(ctx).size.height * 0.55),
              child: ListView(
                primary: false,
                shrinkWrap: true,
                children: sagaDivided(result.books.map((book) {
                  final mb = (book.bytes / 1048576).toStringAsFixed(1);
                  return ListTile(
                    title: Text(book.title,
                        style: TextStyle(color: SagaColors.fg, fontSize: 14)),
                    subtitle: Text('$mb MB',
                        style: TextStyle(
                            color: SagaColors.fgSubtle, fontSize: 12)),
                    trailing: IconButton(
                      icon: Icon(Icons.delete_outline,
                          color: SagaColors.fgSubtle),
                      tooltip: 'Delete download',
                      onPressed: () async {
                        if (!ctx.mounted) return;
                        final confirmed = await confirmDialog(
                          context,
                          title: 'Delete download',
                          message: 'Remove "${book.title}" from this device?',
                          confirmLabel: 'Delete',
                          confirmColor: Colors.redAccent,
                        );
                        if (!confirmed) return;
                        // Through the notifier so files, store metadata,
                        // track cache, and the Browse badge all update
                        // together — never delete download files directly.
                        await ref
                            .read(downloadNotifierProvider.notifier)
                            .deleteBookByKeys(
                                book.bookRatingKey, book.trackKeys);
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (mounted) _refresh();
                      },
                    ),
                  );
                })),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    // Const-constructed by the parent, so its theme-driven rebuild never
    // reaches us — watch the theme directly.
    ref.watch(sagaThemeVariantProvider);
    // Re-scan when downloads complete or books are deleted. The settings tab
    // lives in an IndexedStack, so this state survives the whole app session —
    // without this, the list only refreshed on a full app restart (issue #2).
    // Listen (not watch) so per-byte progress ticks don't trigger disk scans.
    ref.listen(downloadNotifierProvider, (prev, next) {
      if (prev == null) return;
      if (prev.completed.length != next.completed.length ||
          prev.downloadedBooks.length != next.downloadedBooks.length) {
        _refresh();
      }
    });
    return FutureBuilder<_StorageResult>(
      future: _future,
      builder: (context, snap) {
        final String subtitle;
        final VoidCallback onTap;

        if (snap.connectionState == ConnectionState.waiting) {
          subtitle = 'Scanning…';
          onTap = () {};
        } else {
          final result = snap.data;
          if (result == null || result.bookCount == 0) {
            subtitle = 'No books downloaded';
            onTap = () {};
          } else {
            final mb = (result.totalBytes / 1048576).toStringAsFixed(1);
            subtitle =
                '${result.bookCount} ${result.bookCount == 1 ? 'book' : 'books'} · $mb MB';
            onTap = () => _showSheet(context, result);
          }
        }

        return _SettingsTile(
          icon: Icons.storage_outlined,
          title: 'Downloaded books',
          subtitle: subtitle,
          onTap: onTap,
        );
      },
    );
  }
}
