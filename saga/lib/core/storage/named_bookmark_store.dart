import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';

import 'server_scope.dart';
import 'user_box.dart';

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

  /// The name a bookmark gets when the listener doesn't type one.
  ///
  /// The player pre-fills its text field with this and [create] falls back to
  /// it, so a bookmark saved without editing the field reads the same either
  /// way. The two used to build the string separately.
  static String defaultLabel(String trackTitle, int positionMs) {
    final mins = positionMs ~/ 60000;
    final secs =
        ((positionMs % 60000) / 1000).round().toString().padLeft(2, '0');
    return '$trackTitle • $mins:$secs';
  }

  static NamedBookmark create({
    required String bookRatingKey,
    required String trackRatingKey,
    required int positionMs,
    required String trackTitle,
  }) =>
      NamedBookmark(
        id: const Uuid().v4(),
        bookRatingKey: bookRatingKey,
        trackRatingKey: trackRatingKey,
        positionMs: positionMs,
        label: defaultLabel(trackTitle, positionMs),
        createdAt: DateTime.now(),
      );
}

class NamedBookmarkStore {
  static late Box _box;

  static Future<void> init(List<int> encKey) async {
    _box = await openUserBox(_boxName, encKey);
  }

  // Records are keyed by their UUID, so the server scope travels in the
  // `bookRatingKey` *field*: scoped on the way in, checked and bared on the way
  // out. Records written before scoping existed carry a bare key, which
  // [ServerScope.ratingKeyOf] files under the primary server — where they were
  // written — so there is no migration, same as every other scoped store.
  static Future<void> save(NamedBookmark bookmark) async {
    final map = bookmark.toMap();
    map['bookRatingKey'] = ServerScope.key(bookmark.bookRatingKey);
    await _box.put(bookmark.id, map);
  }

  /// The record with its `bookRatingKey` bared, or null when it belongs to
  /// another server — a second server's book 12345 must not list the first
  /// server's bookmarks for its own 12345.
  static NamedBookmark? _ownRecord(Map m) {
    final stored = m['bookRatingKey'];
    if (stored is! String) return null;
    final bare = ServerScope.ratingKeyOf(stored);
    if (bare == null) return null;
    return NamedBookmark.fromMap(
        Map<dynamic, dynamic>.from(m)..['bookRatingKey'] = bare);
  }

  static List<NamedBookmark> getForBook(String bookRatingKey) {
    return _box.values
        .whereType<Map>()
        .map(_ownRecord)
        .whereType<NamedBookmark>()
        .where((b) => b.bookRatingKey == bookRatingKey)
        .toList()
      ..sort((a, b) => a.positionMs.compareTo(b.positionMs));
  }

  static List<NamedBookmark> getAll() {
    return _box.values
        .whereType<Map>()
        .map(_ownRecord)
        .whereType<NamedBookmark>()
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  static Future<void> update(NamedBookmark bookmark) => save(bookmark);

  static Future<void> delete(String id) async {
    await _box.delete(id);
  }

  static Future<void> clearAll() => _box.clear();
}
