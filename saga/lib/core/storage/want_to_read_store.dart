import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

class WantToReadStore {
  static const _boxName = 'want_to_read';
  static late Box _box;

  static final _revision = ValueNotifier<int>(0);
  static ValueNotifier<int> get revisionNotifier => _revision;

  static Future<void> init(List<int> encKey) async {
    final cipher = HiveAesCipher(encKey);
    try {
      _box = await Hive.openBox(_boxName, encryptionCipher: cipher);
    } on HiveError {
      await Hive.deleteBoxFromDisk(_boxName);
      _box = await Hive.openBox(_boxName, encryptionCipher: cipher);
    }
  }

  static bool isWanted(String ratingKey) => _box.get(ratingKey) == true;

  static Future<void> toggle(String ratingKey) async {
    if (isWanted(ratingKey)) {
      await _box.delete(ratingKey);
    } else {
      await _box.put(ratingKey, true);
    }
    _revision.value++;
  }

  static Set<String> get all => {
        for (final key in _box.keys)
          if (_box.get(key) == true) key.toString(),
      };
}
