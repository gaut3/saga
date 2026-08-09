import 'package:hive_flutter/hive_flutter.dart';

import '../audio/m4b_chapter_reader.dart';

import 'server_scope.dart';

const _boxName = 'chapters';

class ChapterStore {
  static late Box _box;

  /// Decoded chapter lists, keyed by track.
  ///
  /// [load] sits on a hot path: the player service resolves the current chapter
  /// on *every* position emission, so without this each tick rebuilt the whole
  /// list — an `M4bChapter` and a `Duration` per chapter, hundreds of
  /// allocations a second on the same isolate that drives the animated mark and
  /// receives the RMS tap. The home screen also calls it once per in-progress
  /// book while building.
  ///
  /// Entries are decoded once and reused. Misses are cached too (as null), so a
  /// book without chapters doesn't hit the box every tick either.
  static final Map<String, List<M4bChapter>?> _decoded = {};

  /// Plenty for the current book plus everything Home lists, and small enough
  /// that a large library can't grow this without bound.
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

  static void _remember(String key, List<M4bChapter>? value) {
    if (_decoded.length >= _maxCached) {
      // Dart maps keep insertion order, so this drops the oldest entry.
      _decoded.remove(_decoded.keys.first);
    }
    _decoded[key] = value;
  }

  /// The track's chapters, or null if it has none.
  ///
  /// The returned list is unmodifiable and shared between callers — it is a
  /// cache entry, not a copy.
  static List<M4bChapter>? load(String trackRatingKey) {
    if (_decoded.containsKey(trackRatingKey)) return _decoded[trackRatingKey];

    final raw = _box.get(ServerScope.key(trackRatingKey));
    List<M4bChapter>? result;
    if (raw != null) {
      try {
        result = List<M4bChapter>.unmodifiable((raw as List<dynamic>).map((e) {
          final map = e as Map;
          return M4bChapter(
            title: map['title'] as String,
            start: Duration(milliseconds: map['startMs'] as int),
          );
        }));
      } catch (_) {
        result = null;
      }
    }
    _remember(trackRatingKey, result);
    return result;
  }

  static Future<void> save(
      String trackRatingKey, List<M4bChapter> chapters) async {
    await _box.put(
      ServerScope.key(trackRatingKey),
      chapters
          .map((c) => {'title': c.title, 'startMs': c.start.inMilliseconds})
          .toList(),
    );
    // Keep the cache honest: chapters are often written *after* the book has
    // started playing, so a stale "no chapters" entry would otherwise stick for
    // the rest of the session.
    _remember(trackRatingKey, List<M4bChapter>.unmodifiable(chapters));
  }

  static bool has(String trackRatingKey) =>
      _box.containsKey(ServerScope.key(trackRatingKey));

  /// Drops decoded entries. Called by [ServerScope.configure] on a server
  /// switch: the map is keyed by bare track key, so a stale entry would serve
  /// the previous server's chapters for the new server's same-numbered track.
  static void clearDecodedCache() => _decoded.clear();
}
