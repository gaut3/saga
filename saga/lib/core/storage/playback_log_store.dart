import 'package:hive_flutter/hive_flutter.dart';

import '../utils/date_math.dart';

class AudioLogEvent {
  final String type;
  final String trackRatingKey;
  final int positionMs;
  final DateTime timestamp;

  const AudioLogEvent({
    required this.type,
    required this.trackRatingKey,
    required this.positionMs,
    required this.timestamp,
  });

  Map<String, dynamic> toMap() => {
        't': type,
        'rk': trackRatingKey,
        'p': positionMs,
        'ts': timestamp.millisecondsSinceEpoch,
      };

  factory AudioLogEvent.fromMap(Map m) => AudioLogEvent(
        type: m['t'] as String,
        trackRatingKey: m['rk'] as String,
        positionMs: m['p'] as int,
        timestamp:
            DateTime.fromMillisecondsSinceEpoch(m['ts'] as int),
      );
}

class PlaybackLogStore {
  static late Box _box;
  static const _boxName = 'playback_log';
  static const _maxPerBook = 200;
  static const _retentionDays = 365;

  static Future<void> init(List<int> encKey) async {
    final cipher = HiveAesCipher(encKey);
    try {
      _box = await Hive.openBox(_boxName, encryptionCipher: cipher);
    } on HiveError {
      await Hive.deleteBoxFromDisk(_boxName);
      _box = await Hive.openBox(_boxName, encryptionCipher: cipher);
    }
  }

  static void log({
    required String bookRatingKey,
    required AudioLogEvent event,
  }) {
    final key = 'log_$bookRatingKey';
    final list =
        (_box.get(key) as List?)?.cast<Map>().toList() ?? <Map>[];
    list.add(event.toMap());
    if (list.length > _maxPerBook) list.removeAt(0);
    _box.put(key, list);
  }

  static List<AudioLogEvent> getLog(String bookRatingKey) {
    final key = 'log_$bookRatingKey';
    final list = (_box.get(key) as List?)?.cast<Map>() ?? [];
    return list.map(AudioLogEvent.fromMap).toList();
  }

  static Iterable<String> bookRatingKeys() => _box.keys
      .cast<String>()
      .where((k) => k.startsWith('log_'))
      .map((k) => k.substring(4));

  static void clearLog(String bookRatingKey) =>
      _box.delete('log_$bookRatingKey');

  static Future<void> clearAll() => _box.clear();

  /// Full `log_<key>` → [event maps] map for backup (the session history shown
  /// in the day/week tabs, which is not re-fetchable from Plex).
  static Map<String, dynamic> exportAll() {
    final out = <String, dynamic>{};
    for (final key in _box.keys) {
      final k = key.toString();
      if (k.startsWith('log_')) out[k] = _box.get(key);
    }
    return out;
  }

  /// Drops events older than [_retentionDays] — the per-book 200-event cap
  /// bounds each book, but a large library keeps 200 events per book forever;
  /// the History Day tab only renders recent days, so old events are dead
  /// weight in box size and init time. Events with a missing or invalid
  /// timestamp are dropped too (validate values, not just presence). A book's
  /// key is deleted entirely when nothing remains. Returns the number of
  /// events removed. Called once on app start.
  static Future<int> pruneOldEvents({DateTime? now}) async {
    final cutoff = addDays(dayOnly(now ?? DateTime.now()), -_retentionDays)
        .millisecondsSinceEpoch;
    var removed = 0;
    for (final key in _box.keys.toList()) {
      if (!key.toString().startsWith('log_')) continue;
      final list = (_box.get(key) as List?)?.cast<Map>() ?? const <Map>[];
      final kept = [
        for (final m in list)
          if (m['ts'] is int && (m['ts'] as int) >= cutoff) m
      ];
      if (kept.length == list.length) continue;
      removed += list.length - kept.length;
      if (kept.isEmpty) {
        await _box.delete(key);
      } else {
        await _box.put(key, kept);
      }
    }
    return removed;
  }

  /// Merges backed-up logs per book: events are deduped by (timestamp, type,
  /// track), sorted oldest → newest, and capped to the newest [_maxPerBook].
  static Future<void> importAll(Map<String, dynamic> raw) async {
    for (final entry in raw.entries) {
      if (!entry.key.startsWith('log_')) continue;
      final incoming = (entry.value as List?)?.cast<Map>() ?? const <Map>[];
      final existing =
          (_box.get(entry.key) as List?)?.cast<Map>() ?? const <Map>[];
      final seen = <String>{};
      final all = <Map>[];
      for (final m in [...existing, ...incoming]) {
        if (seen.add('${m['ts']}_${m['t']}_${m['rk']}')) all.add(m);
      }
      all.sort((a, b) => (a['ts'] as int).compareTo(b['ts'] as int));
      final capped =
          all.length > _maxPerBook ? all.sublist(all.length - _maxPerBook) : all;
      await _box.put(entry.key, capped);
    }
  }
}
