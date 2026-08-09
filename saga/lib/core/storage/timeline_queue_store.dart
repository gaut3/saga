import 'package:hive_flutter/hive_flutter.dart';

import 'server_scope.dart';

/// A position update that failed to reach the Plex server and is waiting to be
/// retried. One pending entry per book (last-write-wins) — there's no point
/// replaying intermediate positions, only the latest matters.
class PendingTimeline {
  final String ratingKey; // track ratingKey
  final String key; // track part key (Plex `key`)
  final int positionMs;
  final int durationMs;
  final String state; // 'playing' | 'paused' | 'stopped'
  final DateTime savedAt;

  const PendingTimeline({
    required this.ratingKey,
    required this.key,
    required this.positionMs,
    required this.durationMs,
    required this.state,
    required this.savedAt,
  });

  Map<String, dynamic> toMap() => {
        'rk': ratingKey,
        'k': key,
        'p': positionMs,
        'd': durationMs,
        's': state,
        't': savedAt.millisecondsSinceEpoch,
      };

  static PendingTimeline fromMap(Map<dynamic, dynamic> m) => PendingTimeline(
        ratingKey: m['rk'] as String,
        key: m['k'] as String,
        positionMs: (m['p'] as num).toInt(),
        durationMs: (m['d'] as num).toInt(),
        state: m['s'] as String? ?? 'paused',
        savedAt: DateTime.fromMillisecondsSinceEpoch((m['t'] as num).toInt()),
      );
}

/// Persists position updates that couldn't be reported to Plex (server
/// unreachable). Survives app restarts and collapses to the latest position per
/// book. Flushed on the next successful report or when the app returns to the
/// foreground — the first slice of cross-device sync.
class TimelineQueueStore {
  static late Box _box;
  static const _boxName = 'timeline_queue';

  static Future<void> init(List<int> encKey) async {
    final cipher = HiveAesCipher(encKey);
    try {
      _box = await Hive.openBox(_boxName, encryptionCipher: cipher);
    } on HiveError {
      await Hive.deleteBoxFromDisk(_boxName);
      _box = await Hive.openBox(_boxName, encryptionCipher: cipher);
    }
  }

  /// Stores [pending] for [bookRatingKey], overwriting any earlier pending
  /// update for the same book (last-write-wins).
  ///
  /// Keys go through [ServerScope]: the queue fills precisely when a server is
  /// unreachable, which is precisely when a listener switches to their other
  /// server — and a flush must never replay server A's positions against
  /// server B's identically-numbered tracks.
  static Future<void> enqueue(
          String bookRatingKey, PendingTimeline pending) =>
      _box.put(ServerScope.key(bookRatingKey), pending.toMap());

  static Future<void> remove(String bookRatingKey) =>
      _box.delete(ServerScope.key(bookRatingKey));

  static bool get isEmpty => _box.isEmpty;

  /// The current server's pending updates, keyed by bookRatingKey. Another
  /// server's entries stay queued until that server is selected again.
  static Map<String, PendingTimeline> all() {
    final result = <String, PendingTimeline>{};
    for (final k in _box.keys) {
      if (k is! String) continue;
      final bookKey = ServerScope.ratingKeyOf(k);
      if (bookKey == null) continue;
      final v = _box.get(k);
      if (v is Map) result[bookKey] = PendingTimeline.fromMap(v);
    }
    return result;
  }
}
