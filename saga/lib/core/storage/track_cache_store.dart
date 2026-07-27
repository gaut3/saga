import 'package:hive_flutter/hive_flutter.dart';

import '../plex/models/plex_track.dart';

const _boxName = 'track_cache';

/// Persisted track metadata per book, written when a book is downloaded (and
/// lazily backfilled on any online track fetch for a downloaded book). Lets
/// downloaded books be opened and played with the Plex server unreachable, and
/// lets the audio service restore the last session after process death without
/// a network round-trip. Not a general cache: entries exist only for books
/// with downloads and are deleted with them.
class TrackCacheStore {
  static late Box _box;

  static Future<void> init(List<int> encKey) async {
    final cipher = HiveAesCipher(encKey);
    try {
      _box = await Hive.openBox(_boxName, encryptionCipher: cipher);
    } on HiveError {
      await Hive.deleteBoxFromDisk(_boxName);
      _box = await Hive.openBox(_boxName, encryptionCipher: cipher);
    }
  }

  static List<PlexTrack>? load(String bookRatingKey) {
    final raw = _box.get(bookRatingKey);
    if (raw == null) return null;
    try {
      final tracks = (raw as List<dynamic>)
          .map((e) => PlexTrack.fromMap(e as Map))
          .toList();
      return tracks.isEmpty ? null : tracks;
    } catch (_) {
      // Malformed entry — treat as absent rather than crashing the caller.
      return null;
    }
  }

  static Future<void> save(
      String bookRatingKey, List<PlexTrack> tracks) async {
    if (tracks.isEmpty) return;
    await _box.put(bookRatingKey, tracks.map((t) => t.toMap()).toList());
  }

  static Future<void> delete(String bookRatingKey) async {
    await _box.delete(bookRatingKey);
  }

  static bool has(String bookRatingKey) => _box.containsKey(bookRatingKey);

  /// Expected number of tracks for a downloaded book, or null when unknown
  /// (book downloaded before the cache existed and not yet backfilled).
  static int? trackCount(String bookRatingKey) {
    final raw = _box.get(bookRatingKey);
    return raw == null ? null : (raw as List<dynamic>).length;
  }
}
