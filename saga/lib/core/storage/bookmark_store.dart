import 'package:hive_flutter/hive_flutter.dart';

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

  static Future<void> init(List<int> encKey) async {
    final cipher = HiveAesCipher(encKey);
    try {
      _box = await Hive.openBox(_boxName, encryptionCipher: cipher);
    } on HiveError catch (e) {
      // Only wipe and recreate for decryption/corruption failures (wrong key on
      // first run after re-install). Rethrow anything else (I/O errors, truncated
      // files from an unclean OS kill) so the caller can surface a real error
      // rather than silently deleting every saved position.
      final msg = e.message.toLowerCase();
      if (!msg.contains('wrong key') && !msg.contains('corrupt')) rethrow;
      await Hive.deleteBoxFromDisk(_boxName);
      _box = await Hive.openBox(_boxName, encryptionCipher: cipher);
    }
  }

  static Future<void> save(String bookRatingKey, BookPosition position) async {
    await _box.put(bookRatingKey, position.toMap());
  }

  static BookPosition? load(String bookRatingKey) {
    final raw = _box.get(bookRatingKey);
    if (raw == null) return null;
    return BookPosition.fromMap(raw as Map);
  }

  static Future<void> delete(String bookRatingKey) async {
    await _box.delete(bookRatingKey);
  }

  static Future<void> clearAll() => _box.clear();

  static Set<String> savedBookKeys() {
    return _box.keys.map((k) => k.toString()).toSet();
  }

  static Map<String, BookPosition> allPositions() {
    final result = <String, BookPosition>{};
    for (final key in _box.keys) {
      final raw = _box.get(key);
      if (raw != null) {
        result[key.toString()] = BookPosition.fromMap(raw as Map);
      }
    }
    return result;
  }
}
