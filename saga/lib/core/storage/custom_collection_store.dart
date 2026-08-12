import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';

import 'user_box.dart';

const _boxName = 'custom_collections';

class CustomCollection {
  final String id;
  final String name;
  final List<String> bookRatingKeys;
  final String? thumbPath;

  const CustomCollection({
    required this.id,
    required this.name,
    required this.bookRatingKeys,
    this.thumbPath,
  });

  CustomCollection copyWith({
    String? name,
    List<String>? bookRatingKeys,
    Object? thumbPath = _unset,
  }) =>
      CustomCollection(
        id: id,
        name: name ?? this.name,
        bookRatingKeys: bookRatingKeys ?? this.bookRatingKeys,
        thumbPath: thumbPath == _unset ? this.thumbPath : thumbPath as String?,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'bookRatingKeys': bookRatingKeys,
        if (thumbPath != null) 'thumbPath': thumbPath,
      };

  factory CustomCollection.fromMap(Map<dynamic, dynamic> map) =>
      CustomCollection(
        id: map['id'] as String,
        name: map['name'] as String,
        bookRatingKeys: (map['bookRatingKeys'] as List<dynamic>)
            .map((e) => e.toString())
            .toList(),
        thumbPath: map['thumbPath'] as String?,
      );
}

const _unset = Object();

class CustomCollectionStore {
  static late Box _box;

  static Future<void> init(List<int> encKey) async {
    _box = await openUserBox(_boxName, encKey);
  }

  static List<CustomCollection> getAll() {
    return _box.values
        .whereType<Map>()
        .map(CustomCollection.fromMap)
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
  }

  static CustomCollection? get(String id) {
    final raw = _box.get(id);
    if (raw == null) return null;
    return CustomCollection.fromMap(raw as Map);
  }

  static Future<CustomCollection> create(String name) async {
    final col = CustomCollection(
      id: const Uuid().v4(),
      name: name,
      bookRatingKeys: [],
    );
    await _box.put(col.id, col.toMap());
    return col;
  }

  static Future<void> rename(String id, String newName) async {
    final col = get(id);
    if (col == null) return;
    await _box.put(id, col.copyWith(name: newName).toMap());
  }

  static Future<void> delete(String id) async {
    await _box.delete(id);
  }

  /// Adds a book, and — when this is the collection's *first* book and it has
  /// no cover yet — adopts that book's artwork as the collection cover.
  ///
  /// Gated on the collection being empty rather than just `thumbPath == null`
  /// so that a user who deliberately picked "None" in Set cover doesn't get
  /// artwork silently re-applied on the next add.
  static Future<void> addBook(String collectionId, String bookRatingKey,
      {String? coverThumbPath}) async {
    final col = get(collectionId);
    if (col == null) return;
    if (col.bookRatingKeys.contains(bookRatingKey)) return;
    final adoptCover = col.bookRatingKeys.isEmpty &&
        col.thumbPath == null &&
        coverThumbPath != null;
    await _box.put(
        collectionId,
        col
            .copyWith(
              bookRatingKeys: [...col.bookRatingKeys, bookRatingKey],
              // _unset, not null — null would *clear* an existing cover.
              thumbPath: adoptCover ? coverThumbPath : _unset,
            )
            .toMap());
  }

  static Future<void> removeBook(
      String collectionId, String bookRatingKey) async {
    final col = get(collectionId);
    if (col == null) return;
    await _box.put(
        collectionId,
        col
            .copyWith(
                bookRatingKeys: col.bookRatingKeys
                    .where((k) => k != bookRatingKey)
                    .toList())
            .toMap());
  }

  /// Applies [visibleOrder] — the keys the reorder UI could actually show, in
  /// their new order — without touching stored keys that weren't visible.
  ///
  /// The detail screen's list is filtered to books resolvable in the current
  /// library, so a collection can hold keys the screen can't see: a book
  /// re-imported in Plex under a new rating key, or one that lives on another
  /// server. Writing the visible list back verbatim silently deleted those on
  /// the first drag. Instead, invisible keys keep their original slots and the
  /// visible slots are refilled in the new order.
  static Future<void> reorder(
      String collectionId, List<String> visibleOrder) async {
    final col = get(collectionId);
    if (col == null) return;
    final visible = visibleOrder.toSet();
    final queue = List<String>.from(visibleOrder);
    final merged = <String>[
      for (final k in col.bookRatingKeys)
        if (visible.contains(k) && queue.isNotEmpty) queue.removeAt(0) else k,
    ];
    // Keys in the new order the store didn't know (shouldn't happen) — keep
    // them rather than drop a book the user just arranged.
    merged.addAll(queue);
    await _box.put(collectionId, col.copyWith(bookRatingKeys: merged).toMap());
  }

  static Future<void> restoreCollection(CustomCollection col) async {
    await _box.put(col.id, col.toMap());
  }

  static Future<void> setCover(String collectionId, String? thumbPath) async {
    final col = get(collectionId);
    if (col == null) return;
    await _box.put(collectionId, col.copyWith(thumbPath: thumbPath).toMap());
  }
}
