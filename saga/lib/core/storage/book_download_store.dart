import 'package:hive_flutter/hive_flutter.dart';

import 'server_scope.dart';

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

  // Scoped by server — see server_scope.dart. Without it, a second server's
  // book 12345 would report the first server's downloaded tracks, and the
  // player would resolve a local file belonging to a different book.
  static void recordDownload(String bookRatingKey, String trackRatingKey) {
    final existing = _getSet(bookRatingKey);
    existing.add(trackRatingKey);
    _box.put(ServerScope.key(bookRatingKey), existing.toList());
  }

  static void removeDownload(String bookRatingKey, String trackRatingKey) {
    final existing = _getSet(bookRatingKey);
    existing.remove(trackRatingKey);
    if (existing.isEmpty) {
      _box.delete(ServerScope.key(bookRatingKey));
    } else {
      _box.put(ServerScope.key(bookRatingKey), existing.toList());
    }
  }

  static int downloadedCount(String bookRatingKey) =>
      _getSet(bookRatingKey).length;

  static Set<String> trackKeys(String bookRatingKey) => _getSet(bookRatingKey);

  static bool hasDownload(String bookRatingKey) =>
      _getSet(bookRatingKey).isNotEmpty;

  static Set<String> booksWithDownloads() => {
        for (final key in _box.keys)
          if (ServerScope.ratingKeyOf(key.toString()) case final rk?) rk,
      };

  static Set<String> _getSet(String bookRatingKey) {
    final val = _box.get(ServerScope.key(bookRatingKey));
    if (val == null) return {};
    return (val as List<dynamic>).cast<String>().toSet();
  }
}
