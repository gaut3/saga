import 'package:hive_flutter/hive_flutter.dart';

import '../plex/models/plex_book.dart';

import 'book_download_store.dart';
import 'bookmark_store.dart';
import 'server_scope.dart';
import 'user_box.dart';

const _boxName = 'book_metadata';

/// Full per-book metadata from `/library/metadata/{ratingKey}`.
///
/// Plex's *list* endpoints return an abbreviated record — notably without
/// `Style`, which is where audiobook libraries keep the narrator. The full
/// record only comes from the per-item endpoint, so it's fetched lazily when a
/// book is opened and cached here: one request per book ever, rather than one
/// per book in the library, and the detail still fills in with the server
/// unreachable.
///
/// The raw Plex map is stored rather than a serialised [PlexBook], so adding a
/// field to the model later picks it up from already-cached entries instead of
/// needing a cache version bump.
class BookMetadataStore {
  static late Box _box;

  /// Decoded entries, so repeated reads during a build don't re-parse.
  static final Map<String, PlexBook?> _decoded = {};
  static const _maxCached = 64;

  static Future<void> init(List<int> encKey) async {
    _decoded.clear();
    _box = await openCacheBox(_boxName, encKey);
  }

  static PlexBook? load(String bookRatingKey) {
    if (_decoded.containsKey(bookRatingKey)) return _decoded[bookRatingKey];
    final raw = _box.get(ServerScope.key(bookRatingKey));
    PlexBook? result;
    if (raw != null) {
      try {
        result = PlexBook.fromJson(Map<String, dynamic>.from(raw as Map));
      } catch (_) {
        // Malformed entry — treat as absent rather than crashing the caller.
        result = null;
      }
    }
    rememberCapped(_decoded, _maxCached, bookRatingKey, result);
    return result;
  }

  static Future<void> save(
      String bookRatingKey, Map<String, dynamic> raw) async {
    await _box.put(ServerScope.key(bookRatingKey), raw);
    try {
      rememberCapped(_decoded, _maxCached, bookRatingKey, PlexBook.fromJson(raw));
    } catch (_) {
      _decoded.remove(bookRatingKey);
    }
  }

  /// Drops decoded entries. Called by [ServerScope.configure] on a server
  /// switch: the map is keyed by bare rating key, so a stale entry would serve
  /// the previous server's book for the new server's same-numbered one.
  static void clearDecodedCache() => _decoded.clear();

  /// Deletes every record whose book has neither a saved position nor a
  /// download, on any server. Returns how many went.
  ///
  /// Called on sign-out. This box holds one raw Plex record per book ever
  /// *opened* — titles, authors, summaries: a picture of the account's library
  /// that would otherwise outlive the account, exactly like the covers
  /// [PlexClient.purgeCachedArtwork] exists to remove. What survives is what
  /// sign-out deliberately keeps (positions, downloads — signing back in must
  /// never lose anything), so those books keep their names and covers on the
  /// offline shelves and in the car.
  ///
  /// Raw keys compare across boxes because every per-book store files under
  /// the same [ServerScope.key]; no scope is consulted, so a secondary
  /// server's kept books are kept too.
  static Future<int> pruneOrphans() async {
    final keep = <String>{
      ...BookmarkStore.rawKeys(),
      ...BookDownloadStore.rawKeys(),
    };
    final doomed = [
      for (final k in _box.keys)
        if (!keep.contains(k.toString())) k,
    ];
    await _box.deleteAll(doomed);
    _decoded.clear();
    return doomed.length;
  }
}
