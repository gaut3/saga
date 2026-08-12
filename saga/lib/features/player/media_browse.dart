import 'package:audio_service/audio_service.dart';

import '../../core/local_library.dart';
import '../../core/storage/artwork_cache.dart';
import '../../core/storage/bookmark_store.dart';
import '../../core/storage/completed_books_store.dart';
import '../../core/storage/custom_collection_store.dart';
import 'session_restore.dart';

/// The media IDs Android walks when it browses Saga — Android Auto's library,
/// the assistant's "play X in Saga", and the lock screen's resumption card.
///
/// [root] and [recent] are not ours to name: they are audio_service's
/// `BROWSABLE_ROOT_ID` and `RECENT_ROOT_ID`, and Android decides which of the
/// two it asks for. Everything below them is this app's own namespace.
class BrowseId {
  BrowseId._();

  static const root = 'root';
  static const recent = 'recent';
  static const continuing = 'continue';
  static const downloaded = 'downloaded';
  static const collections = 'collections';

  static const _collectionPrefix = 'collection/';
  static const _bookPrefix = 'book/';

  static String collection(String collectionId) =>
      '$_collectionPrefix$collectionId';
  static String book(String bookRatingKey) => '$_bookPrefix$bookRatingKey';

  /// The collection id inside a browsable collection node, else null.
  static String? collectionIdOf(String mediaId) =>
      mediaId.startsWith(_collectionPrefix)
          ? mediaId.substring(_collectionPrefix.length)
          : null;

  /// A rating key shape: what Plex actually mints, and nothing that could be
  /// read as a path.
  ///
  /// Plex rating keys are integers; this is deliberately looser than that, so a
  /// server with an unusual key doesn't lose the ability to play. What it does
  /// exclude is the punctuation that makes a key stop being a key — dots,
  /// slashes, `?`, `%` — because the key is interpolated into a server URL
  /// (`/library/metadata/$key/children`), and this is the one value in that URL
  /// that arrives from outside the app.
  static final _ratingKeyShape = RegExp(r'^[A-Za-z0-9_-]+$');

  /// The book rating key inside a playable node, else null.
  ///
  /// The one place a media id handed back by Android becomes something to
  /// play, so an id we didn't mint can't be mistaken for a book. Anything can
  /// call this: the browse service is exported and `audio_service` hands a
  /// browsable root to every caller, so the id is untrusted input even though
  /// it usually comes straight back from a list we built.
  static String? bookKeyOf(String mediaId) {
    if (!mediaId.startsWith(_bookPrefix)) return null;
    final key = mediaId.substring(_bookPrefix.length);
    return _ratingKeyShape.hasMatch(key) ? key : null;
  }
}

/// How many books "Continue listening" offers.
///
/// Not a technical limit. A car list is read at a glance and Android Auto caps
/// what it will show while moving anyway; past a couple of dozen entries the
/// list stops being "what I'm in the middle of". Downloaded books and
/// collections are deliberate choices by the listener, so those aren't capped.
const _continueLimit = 25;

/// The children of [parentMediaId], or an empty list for an id with none.
///
/// Reads only local stores — bookmarks, cached metadata, cached tracks,
/// downloads, collections. Nothing here touches the network: browsing happens
/// in a car, where the listener's Plex server is usually a building away, and
/// a browse tree that empties out when the server is unreachable would be
/// worse than useless. It also means this is safe to call synchronously from
/// the audio handler.
List<MediaItem> browseChildren(String parentMediaId) {
  switch (parentMediaId) {
    case BrowseId.root:
      return [
        _category(BrowseId.continuing, 'Continue listening'),
        _category(BrowseId.downloaded, 'Downloaded'),
        _category(BrowseId.collections, 'Collections'),
      ];

    case BrowseId.recent:
      // Android's media-resumption card asks for this and shows the first item
      // only, so there is nothing to gain by returning more.
      final key = mostRecentBookRatingKey(BookmarkStore.allPositions(),
          completed: CompletedBooksStore.allCompleted());
      final item = key == null ? null : bookItem(key);
      return item == null ? const [] : [item];

    case BrowseId.continuing:
      return _books(localInProgressKeys().take(_continueLimit));

    case BrowseId.downloaded:
      return _books(localDownloadedKeys());

    case BrowseId.collections:
      return [
        for (final c in CustomCollectionStore.getAll())
          MediaItem(
            id: BrowseId.collection(c.id),
            title: c.name,
            playable: false,
            artUri: _artUri(c.thumbPath),
          ),
      ];
  }

  final collectionId = BrowseId.collectionIdOf(parentMediaId);
  if (collectionId != null) {
    // Collection order is the listener's own drag-to-reorder — reading order.
    // Keep it exactly as stored.
    final collection = CustomCollectionStore.get(collectionId);
    return collection == null ? const [] : _books(collection.bookRatingKeys);
  }

  return const [];
}

/// The playable item for a book, or null when it can't be named.
///
/// Public because [getMediaItem] answers with the same row the browse tree
/// shows, and the two disagreeing is exactly the kind of drift that makes a
/// car list and a now-playing screen show different books.
///
/// The book itself comes from [localBook], which is also what Home falls back
/// to with no server — the naming and length rules used to live here alone,
/// which is how the car could describe a downloaded book that the phone's own
/// screens could not.
MediaItem? bookItem(String bookRatingKey) {
  final book = localBook(bookRatingKey);
  if (book == null) return null;

  final durationMs = book.totalDurationMs;
  return MediaItem(
    id: BrowseId.book(bookRatingKey),
    title: book.title,
    album: book.title,
    artist: book.authorName,
    duration: durationMs != null ? Duration(milliseconds: durationMs) : null,
    artUri: _artUri(book.thumbPath),
    playable: true,
  );
}

/// Books matching [query] in title or author, most recently listened first.
///
/// Searches what's cached locally — the books the listener has actually
/// touched — for the same reason [browseChildren] does. Voice is the only safe
/// way to pick a book while driving, so this answering nothing when the server
/// is out of reach would defeat the point.
List<MediaItem> searchBooks(String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return const [];

  // Recently-listened first, then everything else the app knows about, with
  // duplicates dropped by the LinkedHashSet's insertion order.
  final keys = <String>{
    ...localInProgressKeys(),
    ...localDownloadedKeys(),
    for (final c in CustomCollectionStore.getAll()) ...c.bookRatingKeys,
  };

  return [
    for (final item in _books(keys))
      if (item.title.toLowerCase().contains(q) ||
          (item.artist?.toLowerCase().contains(q) ?? false))
        item,
  ];
}

List<MediaItem> _books(Iterable<String> bookRatingKeys) => [
      for (final key in bookRatingKeys)
        if (bookItem(key) case final item?) item,
    ];

MediaItem _category(String id, String title) =>
    MediaItem(id: id, title: title, playable: false);

/// The cached cover for [thumbPath], or null — **never an authenticated URL.**
///
/// Everything this function returns leaves the app. Android's browse API is
/// served by an exported `MediaBrowserService`, and `audio_service` hands a
/// browsable root to every caller that asks: its `onGetRoot` cannot consult
/// Dart synchronously, so the package check upstream is commented out. Any
/// installed app can therefore bind and read these items back, having declared
/// no permission at all.
///
/// A URL carrying a credential must not appear here — the Plex token is
/// account-wide, not audiobook-scoped. A `file://` URI into app-private
/// storage is safe by contrast: another app can read the path and not the
/// bytes.
///
/// The cost is a cover missing from a car list until that book has been played
/// once ([AudioPlayerService._prefetchArtwork] caches it with header auth on
/// load). A row still browses and plays without one. Fetching it here isn't an
/// option regardless — see [browseChildren] on why this stays local and
/// synchronous.
Uri? _artUri(String? thumbPath) =>
    thumbPath == null ? null : ArtworkCache.getLocalUri(thumbPath);
