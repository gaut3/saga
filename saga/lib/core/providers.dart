import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'audio/m4b_chapter_reader.dart';
import 'diagnostics/app_log.dart';
import 'plex/models/plex_author.dart';
import 'plex/models/plex_book.dart';
import 'plex/models/plex_library.dart';
import 'plex/models/plex_server.dart';
import 'plex/models/plex_track.dart';
import 'plex/plex_api.dart';
import 'plex/plex_auth.dart';
import 'plex/plex_client.dart';
import 'plex/plex_server.dart';
import 'storage/book_download_store.dart';
import 'storage/book_metadata_store.dart';
import 'storage/bookmark_store.dart';
import 'storage/chapter_store.dart';
import 'storage/completed_books_store.dart';
import 'storage/custom_collection_store.dart';
import 'storage/named_bookmark_store.dart';
import 'storage/settings_store.dart';
import 'storage/track_cache_store.dart';
import 'theme/saga_theme.dart';

final plexClientProvider = Provider<PlexClient>((_) => PlexClient.instance);

/// Currently selected bottom-nav tab index (0=Home, 1=Browse, 2=Authors,
/// 3=Collections, 4=Settings). Lives here (not in the shell) so non-shell
/// screens — e.g. the home "create a collection" nudge — can switch tabs.
final tabIndexProvider = StateProvider<int>((_) => 0);

final plexApiProvider = Provider<PlexApi>((ref) {
  return PlexApi(ref.watch(plexClientProvider));
});

final plexAuthProvider = Provider<PlexAuth>((ref) {
  return PlexAuth(ref.watch(plexClientProvider));
});

final plexServerDiscoveryProvider = Provider<PlexServerDiscovery>((ref) {
  return PlexServerDiscovery(ref.watch(plexClientProvider));
});

final isAuthenticatedProvider = StateProvider<bool>((ref) {
  return ref.watch(plexClientProvider).isAuthenticated;
});

final serverListProvider = FutureProvider<List<PlexServer>>((ref) async {
  return ref.watch(plexServerDiscoveryProvider).fetchServers();
});

final activeServerUriProvider = StateProvider<String?>((ref) {
  return ref.watch(plexClientProvider).serverUri;
});

final librariesProvider = FutureProvider<List<PlexLibrary>>((ref) async {
  ref.watch(activeServerUriProvider);
  return ref.watch(plexApiProvider).fetchLibraries();
});

/// User-selected library override. Persisted via SettingsStore.
final selectedLibraryKeyProvider = StateProvider<String?>((ref) {
  return SettingsStore.selectedLibraryKey;
});

/// Active library key: uses the user's override when set, otherwise
/// auto-selects the first music library on the connected server.
final activeLibraryKeyProvider = FutureProvider<String?>((ref) async {
  ref.watch(activeServerUriProvider);

  final client = ref.read(plexClientProvider);

  Future<bool> discover() async {
    final discovery = ref.read(plexServerDiscoveryProvider);
    final servers = await discovery.fetchServers();
    final saved = client.machineIdentifier;
    final server = saved == null
        ? servers.firstOrNull
        : servers.where((s) => s.machineIdentifier == saved).firstOrNull;
    if (server != null) {
      await discovery.selectServer(server);
      ref.read(activeServerUriProvider.notifier).state = client.serverUri;
    } else if (servers.isNotEmpty) {
      // The saved server is missing from the account's list. Plex lists other
      // people's shared servers here too, so adopting whichever one comes
      // first would silently re-point the app — and every per-server store
      // behind ServerScope — at somebody else's library, possibly with a book
      // still playing. Re-selecting a server is the user's call.
      AppLog.log('server',
          'saved server not in account list — not adopting another');
    }
    return client.serverUri != null;
  }

  if (client.serverUri == null) {
    if (!await discover()) return null;
  }

  final override = ref.watch(selectedLibraryKeyProvider);
  if (override != null) return override;

  try {
    final libraries = await ref.watch(librariesProvider.future);
    return libraries.firstOrNull?.key;
  } on DioException catch (e) {
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.connectionError) {
      // Saved URI unreachable — clear it and re-discover. Probes every
      // connection in parallel and takes the best one that answers, by
      // priority (HTTPS on the LAN ahead of plaintext, plaintext ahead of
      // relay), not the first to reply. This is the path that runs when you
      // leave the house on a LAN-saved URI, so it is also the one that decides
      // whether the token travels encrypted for the rest of the trip.
      AppLog.log('server',
          'saved URI unreachable (${e.type.name}) — re-discovering');
      await client.clearServerUri();
      ref.read(activeServerUriProvider.notifier).state = null;
      if (!await discover()) return null;
      // Bypass cached librariesProvider — fetch directly with the new URI.
      final libraries = await ref.read(plexApiProvider).fetchLibraries();
      return libraries.firstOrNull?.key;
    }
    rethrow;
  }
});

final booksProvider =
    FutureProvider.family<List<PlexBook>, String>((ref, sectionKey) async {
  // Server-sensitive: section keys are per-server integers, so without this a
  // server switch keeps serving the previous server's list for the same key.
  ref.watch(activeServerUriProvider);
  return ref.watch(plexApiProvider).fetchBooks(sectionKey);
});

/// The full record for one book, fetched lazily and cached forever.
///
/// The library listing is abbreviated: it has no `Style` (the narrator) and no
/// `Genre`. Those only exist on `/library/metadata/{ratingKey}`, so rather than
/// make the library load N times slower, the detail is fetched the first time a
/// book is actually opened and then read from the cache — which also means it
/// still fills in offline.
///
/// Returns null rather than throwing when the server is unreachable and nothing
/// is cached: the caller already has the abbreviated record and simply shows
/// less.
final bookMetadataProvider =
    FutureProvider.family<PlexBook?, String>((ref, bookRatingKey) async {
  // Server-sensitive: rating keys are per-server, and the family cache is not.
  ref.watch(activeServerUriProvider);
  final cached = BookMetadataStore.load(bookRatingKey);
  if (cached != null) return cached;
  try {
    final raw =
        await ref.watch(plexApiProvider).fetchBookMetadataRaw(bookRatingKey);
    if (raw == null) return null;
    await BookMetadataStore.save(bookRatingKey, raw);
    return PlexBook.fromJson(raw);
  } catch (e) {
    AppLog.log('plex', 'book metadata fetch failed for $bookRatingKey: $e');
    return null;
  }
});

/// [book] with anything the full record adds (narrator, genre) filled in.
///
/// Call from a `build`. Falls back to the passed-in record untouched while the
/// fetch is in flight or if it fails, so the screen never waits on it.
PlexBook enrichedBook(WidgetRef ref, PlexBook book) =>
    ref.watch(bookMetadataProvider(book.ratingKey)).valueOrNull ?? book;

final recentlyAddedProvider =
    FutureProvider.family<List<PlexBook>, String>((ref, sectionKey) async {
  ref.watch(activeServerUriProvider);
  ref.watch(completionRevisionProvider);
  final books = await ref.watch(plexApiProvider).fetchRecentlyAdded(sectionKey);
  final completed = CompletedBooksStore.allCompleted();
  return books.toList()
    ..sort((a, b) {
      final ac = completed.contains(a.ratingKey);
      final bc = completed.contains(b.ratingKey);
      if (ac == bc) return 0;
      return ac ? 1 : -1;
    });
});

final sagaThemeVariantProvider = StateProvider<SagaThemeVariant>(
  // Clamped: a stored index from a build with more variants must not crash.
  (_) => SagaThemeVariant.values[SettingsStore.themeIndex
      .clamp(0, SagaThemeVariant.values.length - 1)],
);

/// Increment to force continueListeningProvider + inProgressCountProvider to re-run.
final completionRevisionProvider = StateProvider<int>((_) => 0);

/// Incremented every time a bookmark is saved during playback, so progress
/// overlays across the UI can react without re-fetching book lists.
final bookmarkRevisionProvider = StateProvider<int>((_) => 0);

/// Incremented every time listening history is recorded, so the weekly bar
/// chart rebuilds during an active session without polling.
final historyRevisionProvider = StateProvider<int>((_) => 0);

/// Count of in-progress (started but not completed) books.
final inProgressCountProvider = Provider<int>((ref) {
  ref.watch(completionRevisionProvider);
  ref.watch(bookmarkRevisionProvider);
  return BookmarkStore.savedBookKeys()
      .difference(CompletedBooksStore.allCompleted())
      .length;
});

final continueListeningProvider =
    FutureProvider.family<List<PlexBook>, String>((ref, sectionKey) async {
  ref.watch(completionRevisionProvider);
  ref.watch(bookmarkRevisionProvider);
  final savedKeys = BookmarkStore.savedBookKeys();
  final inProgressKeys = savedKeys.difference(CompletedBooksStore.allCompleted());
  if (inProgressKeys.isEmpty) return [];
  final allBooks = await ref.watch(booksProvider(sectionKey).future);
  return allBooks.where((b) => inProgressKeys.contains(b.ratingKey)).toList()
    ..sort((a, b) {
      final posA = BookmarkStore.load(a.ratingKey)?.savedAt ?? DateTime(0);
      final posB = BookmarkStore.load(b.ratingKey)?.savedAt ?? DateTime(0);
      return posB.compareTo(posA);
    });
});

final authorsProvider =
    FutureProvider.family<List<PlexAuthor>, String>((ref, sectionKey) async {
  ref.watch(activeServerUriProvider);
  return ref.watch(plexApiProvider).fetchAuthors(sectionKey);
});

final booksByAuthorProvider =
    FutureProvider.family<List<PlexBook>, String>((ref, authorRatingKey) async {
  ref.watch(activeServerUriProvider);
  return ref.watch(plexApiProvider).fetchBooksByAuthor(authorRatingKey);
});

final collectionsProvider =
    FutureProvider.family<List<PlexBook>, String>((ref, sectionKey) async {
  ref.watch(activeServerUriProvider);
  return ref.watch(plexApiProvider).fetchCollections(sectionKey);
});

final collectionBooksProvider =
    FutureProvider.family<List<PlexBook>, String>((ref, param) async {
  ref.watch(activeServerUriProvider);
  // param format: "sectionKey|collectionRatingKey|encodedTitle"
  final parts = param.split('|');
  if (parts.length < 2) return [];
  final sectionKey = parts[0];
  final collectionRatingKey = parts[1];
  final collectionTitle = parts.length > 2 ? Uri.decodeComponent(parts[2]) : '';

  final apiBooks = await ref.watch(plexApiProvider)
      .fetchBooksInCollection(sectionKey, collectionRatingKey);
  if (apiBooks.isNotEmpty) return apiBooks;

  // Fallback: filter all books by the collection tag stored in each book's metadata
  if (collectionTitle.isEmpty) return [];
  final allBooks = await ref.watch(booksProvider(sectionKey).future);
  return allBooks
      .where((b) => b.collectionTags.contains(collectionTitle))
      .toList();
});

final tracksProvider =
    FutureProvider.family<List<PlexTrack>, String>((ref, bookRatingKey) async {
  // Re-run when the server URI changes (e.g. after auto-discovery completes).
  final serverUri = ref.watch(activeServerUriProvider);
  try {
    if (serverUri == null) {
      // Discovery is still running; wait for it to set a server before fetching.
      await ref.watch(activeLibraryKeyProvider.future);
    }
    final tracks = await ref.watch(plexApiProvider).fetchTracks(bookRatingKey);
    // Lazy backfill: keep the offline track cache fresh for downloaded books,
    // including ones downloaded before the cache existed.
    if (tracks.isNotEmpty && BookDownloadStore.hasDownload(bookRatingKey)) {
      await TrackCacheStore.save(bookRatingKey, tracks);
    }
    return tracks;
  } catch (e) {
    // Server unreachable (offline, dead server). Downloaded books have their
    // track list cached at download time — serve it so they stay playable.
    final cached = TrackCacheStore.load(bookRatingKey);
    if (cached != null) {
      AppLog.log('library',
          'tracks fetch failed for $bookRatingKey, using offline cache: $e');
      return cached;
    }
    rethrow;
  }
});

// Named bookmarks for a specific book
class BookmarkNotifier extends StateNotifier<List<NamedBookmark>> {
  final String bookRatingKey;

  BookmarkNotifier(this.bookRatingKey)
      : super(NamedBookmarkStore.getForBook(bookRatingKey));

  void add(NamedBookmark bookmark) {
    NamedBookmarkStore.save(bookmark);
    state = [...state, bookmark]
      ..sort((a, b) => a.positionMs.compareTo(b.positionMs));
  }

  void update(NamedBookmark bookmark) {
    NamedBookmarkStore.update(bookmark);
    state = state.map((b) => b.id == bookmark.id ? bookmark : b).toList();
  }

  void remove(String id) {
    NamedBookmarkStore.delete(id);
    state = state.where((b) => b.id != id).toList();
  }
}

final bookmarkNotifierProvider = StateNotifierProvider.family<BookmarkNotifier,
    List<NamedBookmark>, String>(
  (ref, bookRatingKey) => BookmarkNotifier(bookRatingKey),
);

final completedBooksListProvider =
    FutureProvider.family<List<PlexBook>, String>((ref, sectionKey) async {
  ref.watch(completionRevisionProvider);
  final completedKeys = CompletedBooksStore.allCompleted();
  if (completedKeys.isEmpty) return [];
  final allBooks = await ref.watch(booksProvider(sectionKey).future);
  return allBooks.where((b) => completedKeys.contains(b.ratingKey)).toList();
});

/// Incremented every time a book is added to / removed from the Want to Read list.
final wantToReadRevisionProvider = StateProvider<int>((_) => 0);

/// Incremented when any custom collection is created, deleted, or modified.
final customCollectionRevisionProvider = StateProvider<int>((_) => 0);

/// All custom collections, re-evaluated whenever one changes.
final customCollectionsProvider = Provider<List<CustomCollection>>((ref) {
  ref.watch(customCollectionRevisionProvider);
  return CustomCollectionStore.getAll();
});

/// Books in a specific custom collection, filtered from the full library.
/// param format: "sectionKey|collectionId"
final customCollectionBooksProvider =
    FutureProvider.family<List<PlexBook>, String>((ref, param) async {
  ref.watch(customCollectionRevisionProvider);
  final sep = param.indexOf('|');
  if (sep < 0) return [];
  final sectionKey = param.substring(0, sep);
  final collectionId = param.substring(sep + 1);
  final col = CustomCollectionStore.get(collectionId);
  if (col == null || col.bookRatingKeys.isEmpty) return [];
  final allBooks = await ref.watch(booksProvider(sectionKey).future);
  final keyIndex = {for (var i = 0; i < col.bookRatingKeys.length; i++) col.bookRatingKeys[i]: i};
  return allBooks
      .where((b) => keyIndex.containsKey(b.ratingKey))
      .toList()
    ..sort((a, b) => keyIndex[a.ratingKey]!.compareTo(keyIndex[b.ratingKey]!));
});

/// The next up-to-[limit] unstarted, library-resolvable books after the last
/// book the user has touched in [keys] — THE "up next" rule, shared by both
/// providers below so their idea of "next in the series" can't drift (they
/// were two hand-written copies of this scan). Empty when the collection was
/// never started. A key the library can't resolve (re-imported book, other
/// server) is skipped rather than counted.
List<PlexBook> _upcomingInCollection(
    List<String> keys, Map<String, PlexBook> bookByKey,
    {required int limit}) {
  var lastTouched = -1;
  for (var i = 0; i < keys.length; i++) {
    if (BookmarkStore.load(keys[i]) != null ||
        CompletedBooksStore.isCompleted(keys[i])) {
      lastTouched = i;
    }
  }
  if (lastTouched < 0) return const [];

  final upcoming = <PlexBook>[];
  for (var i = lastTouched + 1;
      i < keys.length && upcoming.length < limit;
      i++) {
    final key = keys[i];
    if (BookmarkStore.load(key) != null ||
        CompletedBooksStore.isCompleted(key)) {
      continue;
    }
    final book = bookByKey[key];
    if (book != null) upcoming.add(book);
  }
  return upcoming;
}

/// Next unstarted book in each custom collection where the user has already
/// started or completed at least one book. Returns one (collection, book) pair
/// per qualifying collection, in collection-name order.
final upNextInSeriesProvider =
    FutureProvider.family<List<(CustomCollection, PlexBook)>, String>(
        (ref, sectionKey) async {
  ref.watch(customCollectionRevisionProvider);
  ref.watch(completionRevisionProvider);
  ref.watch(bookmarkRevisionProvider);

  final collections = CustomCollectionStore.getAll();
  if (collections.isEmpty) return [];

  final allBooks = await ref.watch(booksProvider(sectionKey).future);
  final bookByKey = {for (final b in allBooks) b.ratingKey: b};
  return [
    for (final col in collections)
      if (_upcomingInCollection(col.bookRatingKeys, bookByKey, limit: 1)
          case [final next, ...])
        (col, next),
  ];
});

/// Like [upNextInSeriesProvider] but returns the next up-to-3 unstarted books
/// per qualifying collection (the upcoming queue), so the home screen can show
/// one row per series. Ordered by collection name.
final upNextSeriesQueuesProvider =
    FutureProvider.family<List<(CustomCollection, List<PlexBook>)>, String>(
        (ref, sectionKey) async {
  ref.watch(customCollectionRevisionProvider);
  ref.watch(completionRevisionProvider);
  ref.watch(bookmarkRevisionProvider);

  final collections = CustomCollectionStore.getAll();
  if (collections.isEmpty) return [];

  final allBooks = await ref.watch(booksProvider(sectionKey).future);
  final bookByKey = {for (final b in allBooks) b.ratingKey: b};
  return [
    for (final col in collections)
      if (_upcomingInCollection(col.bookRatingKeys, bookByKey, limit: 3)
          case final upcoming when upcoming.isNotEmpty)
        (col, upcoming),
  ];
});

/// The next book after [bookRatingKey] in the first custom collection that
/// contains it — used by the finished panel's "Next in series".
/// param format: "sectionKey|bookRatingKey".
final nextInSeriesProvider =
    FutureProvider.family<(CustomCollection, PlexBook)?, String>(
        (ref, param) async {
  ref.watch(customCollectionRevisionProvider);
  final sep = param.indexOf('|');
  if (sep < 0) return null;
  final sectionKey = param.substring(0, sep);
  final bookKey = param.substring(sep + 1);

  for (final col in CustomCollectionStore.getAll()) {
    final idx = col.bookRatingKeys.indexOf(bookKey);
    if (idx < 0 || idx + 1 >= col.bookRatingKeys.length) continue;
    final nextKey = col.bookRatingKeys[idx + 1];
    final allBooks = await ref.watch(booksProvider(sectionKey).future);
    final book = allBooks.where((b) => b.ratingKey == nextKey).firstOrNull;
    if (book != null) return (col, book);
  }
  return null;
});

final searchBooksProvider =
    FutureProvider.family<List<PlexBook>, String>((ref, param) async {
  ref.watch(activeServerUriProvider);
  // param format: "sectionKey|query"
  final sep = param.indexOf('|');
  if (sep < 0) return [];
  final sectionKey = param.substring(0, sep);
  final query = param.substring(sep + 1);
  if (query.isEmpty) return [];
  return ref.watch(plexApiProvider).searchBooks(sectionKey, query);
});

/// Reads embedded M4B chapters, with persistent cache.
/// Pass param as "trackRatingKey|urlOrPath".
/// On cache hit the network/file is skipped entirely.
final m4bChaptersProvider =
    FutureProvider.family<List<M4bChapter>, String>((ref, param) async {
  final sep = param.indexOf('|');
  final ratingKey = sep > 0 ? param.substring(0, sep) : '';
  final urlOrPath = sep > 0 ? param.substring(sep + 1) : param;

  // Return cached chapters if available
  if (ratingKey.isNotEmpty) {
    final cached = ChapterStore.load(ratingKey);
    if (cached != null) return cached;
  }

  if (urlOrPath.isEmpty) return [];

  final chapters = urlOrPath.startsWith('file://')
      ? await M4bChapterReader.fromFile(urlOrPath.substring(7))
      : await M4bChapterReader.fromUrl(urlOrPath, headers: PlexClient.instance.authHeaders);

  if (ratingKey.isNotEmpty && chapters.isNotEmpty) {
    await ChapterStore.save(ratingKey, chapters);
  }

  // Unmodifiable on both paths. The cache hit above already returns a shared,
  // unmodifiable list, and a provider whose result is mutable only on the first
  // run is the kind of thing that works in testing and throws in the field.
  return List<M4bChapter>.unmodifiable(chapters);
});
