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

  /// Un-marking a book stores *when* it was reopened under this prefix,
  /// beside its completion dates instead of deleting them: the dates are the
  /// history ("finished 3 times", the Month tab), and losing them to fix a
  /// list was the bug. Rating keys are numeric, so the prefix can't collide.
  static const _reopenedPrefix = 'reopened:';

  static bool _isMarker(String ratingKey) =>
      ratingKey.startsWith(_reopenedPrefix);

  static List<int> _timestampsAt(String storageKey) {
    final v = _box.get(storageKey);
    if (v == null) return [];
    if (v is List) return v.cast<int>();
    return [];
  }

  /// Whether the book was *ever* finished — history, not state. A book shown
  /// as finished is `isBookFinished` (`book_status.dart`): this stays true
  /// through a re-read and after being marked not finished.
  static bool isCompleted(String ratingKey) =>
      _timestamps(ratingKey).isNotEmpty;

  /// Number of times the book has been completed (each finished listen adds one).
  static int completionCount(String ratingKey) =>
      _timestamps(ratingKey).length;

  static Future<void> markCompleted(String ratingKey) async {
    final existing = _timestamps(ratingKey);
    existing.add(DateTime.now().millisecondsSinceEpoch);
    await _box.put(ServerScope.key(ratingKey), existing);
    await _box.delete(ServerScope.prefixed(_reopenedPrefix, ratingKey));
  }

  /// "Not finished" — takes back the most recent finish (the one being
  /// disputed: usually a mistaken tap) and leaves every earlier one.
  ///
  /// It used to delete them all, wiping a book's history to fix a list; the
  /// first fix for that kept them all, which made a mistaken "mark finished"
  /// permanent and counted a finish/unfinish/finish toggle as two listens.
  /// When earlier finishes remain, a reopen marker ([_reopenedPrefix]) keeps
  /// the book out of the finished state.
  static Future<void> markIncomplete(String ratingKey) async {
    final ts = _timestamps(ratingKey)..sort();
    if (ts.isNotEmpty) ts.removeLast();
    final marker = ServerScope.prefixed(_reopenedPrefix, ratingKey);
    if (ts.isEmpty) {
      await _box.delete(ServerScope.key(ratingKey));
      await _box.delete(marker);
    } else {
      await _box.put(ServerScope.key(ratingKey), ts);
      await _box.put(marker, DateTime.now().millisecondsSinceEpoch);
    }
  }

  /// The most recent completion, or null when the book was never finished.
  static DateTime? lastCompletion(String ratingKey) {
    final ts = _timestamps(ratingKey);
    if (ts.isEmpty) return null;
    return DateTime.fromMillisecondsSinceEpoch(
        ts.reduce((a, b) => a > b ? a : b));
  }

  /// When the book was last marked not finished, or null.
  static DateTime? reopenedAt(String ratingKey) {
    final v = _box.get(ServerScope.prefixed(_reopenedPrefix, ratingKey));
    return v is int ? DateTime.fromMillisecondsSinceEpoch(v) : null;
  }

  /// Every book with at least one recorded completion — the history. For
  /// "is it finished *now*" (reopened, or being re-read) see
  /// `book_status.dart`.
  static Set<String> allCompleted() => {
        for (final key in _box.keys)
          if (ServerScope.ratingKeyOf(key.toString()) case final rk?)
            if (!_isMarker(rk) && _timestampsAt(key.toString()).isNotEmpty) rk,
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
  ///
  /// Reopen markers are not exported: the backup format is ratingKey → dates,
  /// and a marker read back as a "book" would count as one. A restore can
  /// therefore show an un-marked book as finished again — one tap to fix,
  /// against a format change for every older backup.
  static Map<String, dynamic> exportAll() => {
        for (final key in _box.keys)
          if (ServerScope.ratingKeyOf(key.toString()) case final rk?)
            if (!_isMarker(rk)) rk: _timestampsAt(key.toString()),
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
}
