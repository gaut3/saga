import 'package:hive_flutter/hive_flutter.dart';

import 'server_scope.dart';
import 'user_box.dart';

const _boxName = 'positions';

class BookPosition {
  final String trackRatingKey;
  final int positionMs;
  /// Total elapsed ms across all tracks up to the current position.
  final int absolutePositionMs;
  /// Total book duration in ms (sum of all tracks). Stored so progress can be
  /// displayed even when the Plex album API omits the duration field.
  final int? totalDurationMs;
  final DateTime savedAt;

  const BookPosition({
    required this.trackRatingKey,
    required this.positionMs,
    required this.absolutePositionMs,
    this.totalDurationMs,
    required this.savedAt,
  });

  Map<String, dynamic> toMap() => {
        'trackRatingKey': trackRatingKey,
        'positionMs': positionMs,
        'absolutePositionMs': absolutePositionMs,
        if (totalDurationMs != null) 'totalDurationMs': totalDurationMs,
        'savedAt': savedAt.toIso8601String(),
      };

  factory BookPosition.fromMap(Map<dynamic, dynamic> map) => BookPosition(
        trackRatingKey: map['trackRatingKey'] as String,
        positionMs: map['positionMs'] as int,
        absolutePositionMs:
            map['absolutePositionMs'] as int? ?? map['positionMs'] as int,
        totalDurationMs: map['totalDurationMs'] as int?,
        savedAt: DateTime.parse(map['savedAt'] as String),
      );
}

class BookmarkStore {
  static late Box _box;

  // Wipe-on-open only for genuine corruption — the logic lives in
  // [openUserBox] now, shared with every other user-data box.
  static Future<void> init(List<int> encKey) async {
    _box = await openUserBox(_boxName, encKey);
  }

  // Keys go through ServerScope: a Plex rating key is only unique within one
  // server, so without it a second server's book 12345 resumes at the first
  // server's book 12345. See server_scope.dart for why the first server keeps
  // unprefixed keys.
  static Future<void> save(String bookRatingKey, BookPosition position) async {
    await _box.put(ServerScope.key(bookRatingKey), position.toMap());
  }

  static BookPosition? load(String bookRatingKey) {
    final raw = _box.get(ServerScope.key(bookRatingKey));
    if (raw == null) return null;
    return BookPosition.fromMap(raw as Map);
  }

  static Future<void> delete(String bookRatingKey) async {
    await _box.delete(ServerScope.key(bookRatingKey));
  }

  static Future<void> clearAll() => _box.clear();

  static Set<String> savedBookKeys() => allPositions().keys.toSet();

  static Map<String, BookPosition> allPositions() {
    final result = <String, BookPosition>{};
    for (final key in _box.keys) {
      // Null means the record belongs to another server — skipped rather than
      // listed, so Continue Listening never offers someone else's library.
      final bookKey = ServerScope.ratingKeyOf(key.toString());
      if (bookKey == null) continue;
      final raw = _box.get(key);
      if (raw != null) {
        result[bookKey] = BookPosition.fromMap(raw as Map);
      }
    }
    return result;
  }
}
