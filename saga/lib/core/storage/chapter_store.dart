import 'package:hive_flutter/hive_flutter.dart';

import '../audio/m4b_chapter_reader.dart';

const _boxName = 'chapters';

class ChapterStore {
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

  static List<M4bChapter>? load(String trackRatingKey) {
    final raw = _box.get(trackRatingKey);
    if (raw == null) return null;
    try {
      return (raw as List<dynamic>).map((e) {
        final map = e as Map;
        return M4bChapter(
          title: map['title'] as String,
          start: Duration(milliseconds: map['startMs'] as int),
        );
      }).toList();
    } catch (_) {
      return null;
    }
  }

  static Future<void> save(
      String trackRatingKey, List<M4bChapter> chapters) async {
    await _box.put(
      trackRatingKey,
      chapters
          .map((c) => {'title': c.title, 'startMs': c.start.inMilliseconds})
          .toList(),
    );
  }

  static bool has(String trackRatingKey) => _box.containsKey(trackRatingKey);
}
