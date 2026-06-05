import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';

const _boxName = 'named_bookmarks';
const _noteUnset = Object();

class NamedBookmark {
  final String id;
  final String bookRatingKey;
  final String trackRatingKey;
  final int positionMs;
  final String label;
  final String? note;
  final DateTime createdAt;

  const NamedBookmark({
    required this.id,
    required this.bookRatingKey,
    required this.trackRatingKey,
    required this.positionMs,
    required this.label,
    this.note,
    required this.createdAt,
  });

  NamedBookmark copyWith({String? label, Object? note = _noteUnset}) =>
      NamedBookmark(
        id: id,
        bookRatingKey: bookRatingKey,
        trackRatingKey: trackRatingKey,
        positionMs: positionMs,
        label: label ?? this.label,
        note: note == _noteUnset ? this.note : note as String?,
        createdAt: createdAt,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'bookRatingKey': bookRatingKey,
        'trackRatingKey': trackRatingKey,
        'positionMs': positionMs,
        'label': label,
        if (note != null) 'note': note,
        'createdAt': createdAt.toIso8601String(),
      };

  factory NamedBookmark.fromMap(Map<dynamic, dynamic> map) => NamedBookmark(
        id: map['id'] as String,
        bookRatingKey: map['bookRatingKey'] as String,
        trackRatingKey: map['trackRatingKey'] as String,
        positionMs: map['positionMs'] as int,
        label: map['label'] as String,
        note: map['note'] as String?,
        createdAt: DateTime.parse(map['createdAt'] as String),
      );

  static NamedBookmark create({
    required String bookRatingKey,
    required String trackRatingKey,
    required int positionMs,
    required String trackTitle,
  }) {
    final mins = positionMs ~/ 60000;
    final secs = ((positionMs % 60000) / 1000).round().toString().padLeft(2, '0');
    return NamedBookmark(
      id: const Uuid().v4(),
      bookRatingKey: bookRatingKey,
      trackRatingKey: trackRatingKey,
      positionMs: positionMs,
      label: '$trackTitle • $mins:$secs',
      createdAt: DateTime.now(),
    );
  }
}

class NamedBookmarkStore {
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

  static Future<void> save(NamedBookmark bookmark) async {
    await _box.put(bookmark.id, bookmark.toMap());
  }

  static List<NamedBookmark> getForBook(String bookRatingKey) {
    return _box.values
        .whereType<Map>()
        .map((m) => NamedBookmark.fromMap(m))
        .where((b) => b.bookRatingKey == bookRatingKey)
        .toList()
      ..sort((a, b) => a.positionMs.compareTo(b.positionMs));
  }

  static List<NamedBookmark> getAll() {
    return _box.values
        .whereType<Map>()
        .map((m) => NamedBookmark.fromMap(m))
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  static Future<void> update(NamedBookmark bookmark) async {
    await _box.put(bookmark.id, bookmark.toMap());
  }

  static Future<void> delete(String id) async {
    await _box.delete(id);
  }
}
