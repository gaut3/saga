import 'package:hive_flutter/hive_flutter.dart';

const _boxName = 'downloads';

class DownloadStore {
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

  static Future<void> save(String trackRatingKey, String localPath) async {
    await _box.put(trackRatingKey, localPath);
  }

  static String? getPath(String trackRatingKey) {
    return _box.get(trackRatingKey) as String?;
  }

  static bool isDownloaded(String trackRatingKey) {
    return _box.containsKey(trackRatingKey);
  }

  static Future<void> remove(String trackRatingKey) async {
    await _box.delete(trackRatingKey);
  }

  static Map<String, String> allDownloads() {
    return {
      for (final key in _box.keys) key.toString(): _box.get(key) as String,
    };
  }
}
