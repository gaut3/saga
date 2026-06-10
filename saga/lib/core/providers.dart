import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'audio/m4b_chapter_reader.dart';
import 'plex/models/plex_author.dart';
import 'plex/models/plex_book.dart';
import 'plex/models/plex_library.dart';
import 'plex/models/plex_server.dart';
import 'plex/models/plex_track.dart';
import 'plex/plex_api.dart';
import 'plex/plex_auth.dart';
import 'plex/plex_client.dart';
import 'plex/plex_server.dart';
import 'storage/bookmark_store.dart';
import 'storage/chapter_store.dart';
import 'storage/completed_books_store.dart';
import 'storage/custom_collection_store.dart';
import 'storage/named_bookmark_store.dart';
import 'storage/settings_store.dart';
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
    if (servers.isNotEmpty) {
      await discovery.selectServer(servers.first);
      ref.read(activeServerUriProvider.notifier).state = client.serverUri;
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
      // Saved URI unreachable — clear it and re-discover (tries local and
      // relay in parallel, picks whichever answers first).
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
  return ref.watch(plexApiProvider).fetchBooks(sectionKey);
});

final recentlyAddedProvider =
    FutureProvider.family<List<PlexBook>, String>((ref, sectionKey) async {
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
  (_) => SagaThemeVariant.values[SettingsStore.themeIndex],
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
  return ref.watch(plexApiProvider).fetchAuthors(sectionKey);
});

final booksByAuthorProvider =
    FutureProvider.family<List<PlexBook>, String>((ref, authorRatingKey) async {
  return ref.watch(plexApiProvider).fetchBooksByAuthor(authorRatingKey);
});

final collectionsProvider =
    FutureProvider.family<List<PlexBook>, String>((ref, sectionKey) async {
  return ref.watch(plexApiProvider).fetchCollections(sectionKey);
});

final collectionBooksProvider =
    FutureProvider.family<List<PlexBook>, String>((ref, param) async {
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
  if (serverUri == null) {
    // Discovery is still running; wait for it to set a server before fetching.
    await ref.watch(activeLibraryKeyProvider.future);
  }
  return ref.watch(plexApiProvider).fetchTracks(bookRatingKey);
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
  final result = <(CustomCollection, PlexBook)>[];

  for (final col in collections) {
    final keys = col.bookRatingKeys;
    if (keys.isEmpty) continue;

    // Find the last book in the collection the user has touched
    int lastTouchedIndex = -1;
    for (int i = 0; i < keys.length; i++) {
      if (BookmarkStore.load(keys[i]) != null ||
          CompletedBooksStore.isCompleted(keys[i])) {
        lastTouchedIndex = i;
      }
    }
    if (lastTouchedIndex < 0) continue; // Never started this collection

    // First unstarted book after the last touched one
    for (int i = lastTouchedIndex + 1; i < keys.length; i++) {
      final key = keys[i];
      if (BookmarkStore.load(key) == null &&
          !CompletedBooksStore.isCompleted(key)) {
        final book = bookByKey[key];
        if (book != null) {
          result.add((col, book));
          break;
        }
      }
    }
  }
  return result;
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
  final result = <(CustomCollection, List<PlexBook>)>[];

  for (final col in collections) {
    final keys = col.bookRatingKeys;
    if (keys.isEmpty) continue;

    int lastTouchedIndex = -1;
    for (int i = 0; i < keys.length; i++) {
      if (BookmarkStore.load(keys[i]) != null ||
          CompletedBooksStore.isCompleted(keys[i])) {
        lastTouchedIndex = i;
      }
    }
    if (lastTouchedIndex < 0) continue; // Never started this collection

    final upcoming = <PlexBook>[];
    for (int i = lastTouchedIndex + 1;
        i < keys.length && upcoming.length < 3;
        i++) {
      final key = keys[i];
      if (BookmarkStore.load(key) == null &&
          !CompletedBooksStore.isCompleted(key)) {
        final book = bookByKey[key];
        if (book != null) upcoming.add(book);
      }
    }
    if (upcoming.isNotEmpty) result.add((col, upcoming));
  }
  return result;
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

  return chapters;
});
