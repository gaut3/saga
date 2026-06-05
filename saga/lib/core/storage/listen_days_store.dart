import 'package:hive_flutter/hive_flutter.dart';

/// Durable, per-read-through record of which calendar days a book was listened
/// to. Unlike the 200-event [PlaybackLogStore] it's never purged, and it's
/// **cycle-aware**: a relisten starts a fresh cycle, so its day-count / start
/// date never inherit the first read-through.
///
/// Each book maps to its CURRENT cycle: `{ 's': startDay, 'd': [dayStrings] }`.
class ListenDaysStore {
  static late Box _box;
  static const _boxName = 'listen_days';

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

  static DateTime? _parse(String s) {
    final p = s.split('-');
    if (p.length != 3) return null;
    final y = int.tryParse(p[0]);
    final m = int.tryParse(p[1]);
    final d = int.tryParse(p[2]);
    if (y == null || m == null || d == null) return null;
    return DateTime(y, m, d);
  }

  /// Records that [bookRatingKey] was listened to today. Starts a **fresh cycle**
  /// when there's no cycle yet, or when [lastCompletedAt] falls on/after the
  /// current cycle's start — i.e. the previous read-through was completed, so
  /// this is a relisten (the relisten guard). During an active, uncompleted
  /// cycle the only completions predate the start, so the cycle keeps growing.
  static void markListenedToday(String bookRatingKey,
      {DateTime? lastCompletedAt}) {
    final today = _dk(DateTime.now());
    final raw = _box.get(bookRatingKey) as Map?;
    final start = raw?['s'] as String?;
    final days = (raw?['d'] as List?)?.cast<String>().toList();

    var startNew = start == null || days == null;
    if (!startNew && lastCompletedAt != null) {
      final startDate = _parse(start);
      if (startDate != null) {
        final completedDay = DateTime(
            lastCompletedAt.year, lastCompletedAt.month, lastCompletedAt.day);
        if (!completedDay.isBefore(startDate)) startNew = true;
      }
    }

    if (startNew) {
      _box.put(bookRatingKey, {'s': today, 'd': [today]});
      return;
    }
    if (!days!.contains(today)) {
      days.add(today);
      _box.put(bookRatingKey, {'s': start, 'd': days});
    }
  }

  /// Distinct days listened in the current read-through.
  static int daysListened(String bookRatingKey) {
    final raw = _box.get(bookRatingKey) as Map?;
    return (raw?['d'] as List?)?.length ?? 0;
  }

  /// First day of the current read-through.
  static DateTime? startDate(String bookRatingKey) {
    final raw = _box.get(bookRatingKey) as Map?;
    final s = raw?['s'] as String?;
    return s == null ? null : _parse(s);
  }

  static Future<void> clearAll() => _box.clear();

  /// Full ratingKey → `{ s, d }` cycle map for backup.
  static Map<String, dynamic> exportAll() {
    final out = <String, dynamic>{};
    for (final key in _box.keys) {
      final raw = _box.get(key) as Map?;
      if (raw == null) continue;
      final s = raw['s'] as String?;
      final d = (raw['d'] as List?)?.cast<String>();
      if (s == null || d == null) continue;
      out[key.toString()] = {'s': s, 'd': d};
    }
    return out;
  }

  /// Merges backed-up cycles. Keeps the most recent read-through: when the
  /// incoming cycle starts on/after the local one (or there is none) it wins and
  /// the day lists are unioned; an older incoming cycle is ignored so a restore
  /// never resurrects a superseded read-through.
  static Future<void> importAll(Map<String, dynamic> raw) async {
    for (final entry in raw.entries) {
      final incoming = entry.value as Map?;
      final inStart = incoming?['s'] as String?;
      final inDays = (incoming?['d'] as List?)?.cast<String>();
      if (inStart == null || inDays == null) continue;

      final existing = _box.get(entry.key) as Map?;
      final exStart = existing?['s'] as String?;
      final exDays = (existing?['d'] as List?)?.cast<String>();

      if (exStart == null || exDays == null) {
        await _box.put(entry.key, {'s': inStart, 'd': inDays});
        continue;
      }
      final inDate = _parse(inStart);
      final exDate = _parse(exStart);
      if (inDate != null && exDate != null && inDate.isBefore(exDate)) {
        continue; // local cycle is newer — keep it
      }
      if (inStart == exStart) {
        final union = <String>{...exDays, ...inDays}.toList()..sort();
        await _box.put(entry.key, {'s': exStart, 'd': union});
      } else {
        await _box.put(entry.key, {'s': inStart, 'd': inDays});
      }
    }
  }
}
