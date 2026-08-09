import 'package:hive_flutter/hive_flutter.dart';

import 'server_scope.dart';

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
    await _box.put(ServerScope.key(trackRatingKey), localPath);
  }

  static String? getPath(String trackRatingKey) {
    return _box.get(ServerScope.key(trackRatingKey)) as String?;
  }

  static bool isDownloaded(String trackRatingKey) {
    return _box.containsKey(ServerScope.key(trackRatingKey));
  }

  static Future<void> remove(String trackRatingKey) async {
    await _box.delete(ServerScope.key(trackRatingKey));
  }

  static Map<String, String> allDownloads() {
    return {
      for (final key in _box.keys)
        if (ServerScope.ratingKeyOf(key.toString()) case final rk?)
          rk: _box.get(key) as String,
    };
  }
}
