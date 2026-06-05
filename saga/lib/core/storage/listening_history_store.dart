import 'package:hive_flutter/hive_flutter.dart';

class CompletedBook {
  final String ratingKey;
  final String? title;
  final String? thumbPath;

  const CompletedBook({required this.ratingKey, this.title, this.thumbPath});
}

const _boxName = 'listening_history';

class ListeningHistoryStore {
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

  static String _dk(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static void recordListening(int ms) {
    if (ms <= 0) return;
    final k = 't_${_dk(DateTime.now())}';
    _box.put(k, (_box.get(k, defaultValue: 0) as num).toInt() + ms);
  }

  static void recordCompleted({
    required String ratingKey,
    String? title,
    String? thumbPath,
  }) {
    final k = 'd_${_dk(DateTime.now())}';
    final list = (_box.get(k) as List?)?.cast<Map>() ?? <Map>[];
    if (list.any((m) => m['rk'] == ratingKey)) return;
    _box.put(k, [
      ...list,
      {
        'rk': ratingKey,
        if (title != null) 't': title,
        if (thumbPath != null) 'p': thumbPath,
      }
    ]);
  }

  static int getMs(DateTime date) =>
      (_box.get('t_${_dk(date)}', defaultValue: 0) as num).toInt();

  static List<CompletedBook> getCompleted(DateTime date) {
    final list = (_box.get('d_${_dk(date)}') as List?)?.cast<Map>() ?? [];
    return list
        .map((m) => CompletedBook(
              ratingKey: m['rk'] as String,
              title: m['t'] as String?,
              thumbPath: m['p'] as String?,
            ))
        .toList();
  }

  /// Returns every day in [start..end] mapped to ms listened (0 if none).
  static Map<DateTime, int> getRange(DateTime start, DateTime end) {
    final result = <DateTime, int>{};
    var d = DateTime(start.year, start.month, start.day);
    final last = DateTime(end.year, end.month, end.day);
    while (!d.isAfter(last)) {
      result[d] = getMs(d);
      // Renormalize to midnight after each add — Duration arithmetic crosses
      // DST boundaries and can leave d at 01:00 or 23:00 local time.
      final next = d.add(const Duration(days: 1));
      d = DateTime(next.year, next.month, next.day);
    }
    return result;
  }

  /// Returns all raw key→value pairs for backup (keys starting with 't_' or 'd_').
  static Map<String, dynamic> exportAll() {
    final result = <String, dynamic>{};
    for (final key in _box.keys) {
      if (key is String && (key.startsWith('t_') || key.startsWith('d_'))) {
        result[key] = _box.get(key);
      }
    }
    return result;
  }

  /// Restores raw key→value pairs from a backup without overwriting newer data.
  static Future<void> importAll(Map<String, dynamic> raw) async {
    for (final entry in raw.entries) {
      final key = entry.key;
      if (!key.startsWith('t_') && !key.startsWith('d_')) continue;
      if (key.startsWith('t_')) {
        final existing = (_box.get(key, defaultValue: 0) as num).toInt();
        final incoming = (entry.value as num).toInt();
        // Keep the higher value (don't overwrite local data with older backup)
        if (incoming > existing) await _box.put(key, incoming);
      } else {
        // For 'd_' (completed books), merge lists without duplicates
        final existing = (_box.get(key) as List?)?.cast<Map>() ?? <Map>[];
        final incoming = (entry.value as List?)?.cast<Map>() ?? <Map>[];
        final merged = [...existing];
        for (final item in incoming) {
          if (!merged.any((m) => m['rk'] == item['rk'])) {
            merged.add(Map<String, dynamic>.from(item));
          }
        }
        await _box.put(key, merged);
      }
    }
  }

  /// Returns all days with activity in [start..end], newest first.
  static List<DateTime> activeDays(DateTime start, DateTime end) {
    final days = <DateTime>[];
    var d = DateTime(start.year, start.month, start.day);
    final last = DateTime(end.year, end.month, end.day);
    while (!d.isAfter(last)) {
      if (getMs(d) > 0 || getCompleted(d).isNotEmpty) days.add(d);
      final next = d.add(const Duration(days: 1));
      d = DateTime(next.year, next.month, next.day);
    }
    return days.reversed.toList();
  }
}
