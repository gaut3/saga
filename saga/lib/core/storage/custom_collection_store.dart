import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';

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
    final cipher = HiveAesCipher(encKey);
    try {
      _box = await Hive.openBox(_boxName, encryptionCipher: cipher);
    } on HiveError {
      await Hive.deleteBoxFromDisk(_boxName);
      _box = await Hive.openBox(_boxName, encryptionCipher: cipher);
    }
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

  static Future<void> addBook(String collectionId, String bookRatingKey) async {
    final col = get(collectionId);
    if (col == null) return;
    if (col.bookRatingKeys.contains(bookRatingKey)) return;
    await _box.put(
        collectionId,
        col
            .copyWith(bookRatingKeys: [...col.bookRatingKeys, bookRatingKey])
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

  static Future<void> reorder(
      String collectionId, List<String> orderedKeys) async {
    final col = get(collectionId);
    if (col == null) return;
    await _box.put(collectionId, col.copyWith(bookRatingKeys: orderedKeys).toMap());
  }

  static Future<void> restoreCollection(CustomCollection col) async {
    await _box.put(col.id, col.toMap());
  }

  static Future<void> setCover(String collectionId, String? thumbPath) async {
    final col = get(collectionId);
    if (col == null) return;
    await _box.put(collectionId, col.copyWith(thumbPath: thumbPath).toMap());
  }

  static bool contains(String collectionId, String bookRatingKey) {
    return get(collectionId)?.bookRatingKeys.contains(bookRatingKey) ?? false;
  }
}
