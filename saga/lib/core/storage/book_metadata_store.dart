import 'package:hive_flutter/hive_flutter.dart';

import '../plex/models/plex_book.dart';

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
    final cipher = HiveAesCipher(encKey);
    _decoded.clear();
    try {
      _box = await Hive.openBox(_boxName, encryptionCipher: cipher);
    } on HiveError {
      await Hive.deleteBoxFromDisk(_boxName);
      _box = await Hive.openBox(_boxName, encryptionCipher: cipher);
    }
  }

  static void _remember(String key, PlexBook? value) {
    if (_decoded.length >= _maxCached) {
      _decoded.remove(_decoded.keys.first);
    }
    _decoded[key] = value;
  }

  static PlexBook? load(String bookRatingKey) {
    if (_decoded.containsKey(bookRatingKey)) return _decoded[bookRatingKey];
    final raw = _box.get(bookRatingKey);
    PlexBook? result;
    if (raw != null) {
      try {
        result = PlexBook.fromJson(Map<String, dynamic>.from(raw as Map));
      } catch (_) {
        // Malformed entry — treat as absent rather than crashing the caller.
        result = null;
      }
    }
    _remember(bookRatingKey, result);
    return result;
  }

  static Future<void> save(
      String bookRatingKey, Map<String, dynamic> raw) async {
    await _box.put(bookRatingKey, raw);
    try {
      _remember(bookRatingKey, PlexBook.fromJson(raw));
    } catch (_) {
      _decoded.remove(bookRatingKey);
    }
  }

  static bool has(String bookRatingKey) => _box.containsKey(bookRatingKey);
}
