import 'package:hive_flutter/hive_flutter.dart';

const _boxName = 'book_downloads';

/// Tracks which tracks have been downloaded for each book.
/// Maps bookRatingKey to a list of downloaded trackRatingKeys.
class BookDownloadStore {
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

  static void recordDownload(String bookRatingKey, String trackRatingKey) {
    final existing = _getSet(bookRatingKey);
    existing.add(trackRatingKey);
    _box.put(bookRatingKey, existing.toList());
  }

  static void removeDownload(String bookRatingKey, String trackRatingKey) {
    final existing = _getSet(bookRatingKey);
    existing.remove(trackRatingKey);
    if (existing.isEmpty) {
      _box.delete(bookRatingKey);
    } else {
      _box.put(bookRatingKey, existing.toList());
    }
  }

  static int downloadedCount(String bookRatingKey) =>
      _getSet(bookRatingKey).length;

  static bool hasDownload(String bookRatingKey) =>
      _getSet(bookRatingKey).isNotEmpty;

  static Set<String> booksWithDownloads() =>
      _box.keys.cast<String>().toSet();

  static Set<String> _getSet(String bookRatingKey) {
    final val = _box.get(bookRatingKey);
    if (val == null) return {};
    return (val as List<dynamic>).cast<String>().toSet();
  }
}
