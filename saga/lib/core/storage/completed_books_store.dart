import 'package:hive_flutter/hive_flutter.dart';

import 'server_scope.dart';
import 'user_box.dart';

class CompletedBooksStore {
  static late Box _box;
  static const _boxName = 'completed_books';

  static Future<void> init(List<int> encKey) async {
    _box = await openUserBox(_boxName, encKey);
    await _migrate();
  }

  // Migrate old boolean storage (ratingKey → true) to timestamp lists.
  // Books completed before this update get DateTime(0) as a sentinel meaning
  // "completed at an unknown date before per-completion tracking began".
  static Future<void> _migrate() async {
    final toUpdate = <String, List<int>>{};
    for (final key in _box.keys) {
      final v = _box.get(key);
      if (v == true || v == 1) {
        toUpdate[key.toString()] = [0];
      }
    }
    for (final entry in toUpdate.entries) {
      await _box.put(entry.key, entry.value);
    }
  }

  // Rating keys are scoped by server — see server_scope.dart. [_timestamps]
  // takes a rating key and scopes it; [_timestampsAt] takes an already-scoped
  // storage key, for the loops below that walk the box directly.
  static List<int> _timestamps(String ratingKey) =>
      _timestampsAt(ServerScope.key(ratingKey));

  static List<int> _timestampsAt(String storageKey) {
    final v = _box.get(storageKey);
    if (v == null) return [];
    if (v is List) return v.cast<int>();
    return [];
  }

  static bool isCompleted(String ratingKey) =>
      _timestamps(ratingKey).isNotEmpty;

  /// Number of times the book has been completed (each finished listen adds one).
  static int completionCount(String ratingKey) =>
      _timestamps(ratingKey).length;

  static Future<void> markCompleted(String ratingKey) async {
    final existing = _timestamps(ratingKey);
    existing.add(DateTime.now().millisecondsSinceEpoch);
    await _box.put(ServerScope.key(ratingKey), existing);
  }

  static Future<void> markIncomplete(String ratingKey) =>
      _box.delete(ServerScope.key(ratingKey));

  static Set<String> allCompleted() => {
        for (final key in _box.keys)
          if (ServerScope.ratingKeyOf(key.toString()) case final rk?)
            if (_timestampsAt(key.toString()).isNotEmpty) rk,
      };

  /// All completion timestamps for a book, sorted oldest → newest.
  /// Returns an empty list if the book has never been completed.
  /// A DateTime of epoch (millisecondsSinceEpoch == 0) means the completion
  /// was recorded before per-completion date tracking was added.
  static List<DateTime> completionDates(String ratingKey) =>
      _timestamps(ratingKey)
          .map((ms) => DateTime.fromMillisecondsSinceEpoch(ms))
          .toList()
        ..sort();

  /// Full ratingKey → [timestampMs...] map for backup. Preserves per-completion
  /// dates and the times-finished count (the plain [allCompleted] set loses both).
  static Map<String, dynamic> exportAll() => {
        for (final key in _box.keys)
          if (ServerScope.ratingKeyOf(key.toString()) case final rk?)
            rk: _timestampsAt(key.toString()),
      };

  /// Merges a backed-up ratingKey → [timestampMs...] map. Completion timestamps
  /// are unioned (deduped) so a restore never double-counts a completion already
  /// present locally, and never drops dates recorded on either side.
  static Future<void> clearAll() => _box.clear();

  static Future<void> importAll(Map<String, dynamic> raw) async {
    for (final entry in raw.entries) {
      final incoming = (entry.value as List?)
              ?.map((e) => (e as num).toInt())
              .toList() ??
          const <int>[];
      if (incoming.isEmpty) continue;
      final merged = <int>{..._timestamps(entry.key), ...incoming}.toList()
        ..sort();
      await _box.put(ServerScope.key(entry.key), merged);
    }
  }

  /// All books that were completed on [day] (year/month/day match).
  /// Ignores epoch-sentinel entries (no known date).
  static List<String> completedOn(DateTime day) {
    final d = DateTime(day.year, day.month, day.day);
    final result = <String>[];
    for (final key in _box.keys) {
      final ratingKey = ServerScope.ratingKeyOf(key.toString());
      if (ratingKey == null) continue;
      for (final ms in _timestampsAt(key.toString())) {
        if (ms == 0) continue;
        final dt = DateTime.fromMillisecondsSinceEpoch(ms);
        if (DateTime(dt.year, dt.month, dt.day) == d) {
          result.add(ratingKey);
          break;
        }
      }
    }
    return result;
  }
}
