import 'package:hive_flutter/hive_flutter.dart';

import '../diagnostics/app_log.dart';
import 'server_scope.dart';
import 'user_box.dart';

/// What happened to the Plex report that came with a save.
enum ReportStatus {
  /// The report gate held it: playback hadn't passed the loaded place.
  held,

  /// Not sent: it repeated the last report (`isRepeatReport`).
  repeat,

  /// Sent; [SaveAuditEntry.outcomes] says how it landed.
  sent,
}

/// One position save, or a run of 10 s ticks folded into one row, as
/// Settings › Developer options lists them.
class SaveAuditEntry {
  /// The first save's time in ms since the epoch: the row's identity, which
  /// a report's outcome is filed against when it arrives.
  final int id;

  /// The newest save in the row.
  final DateTime at;

  /// What asked for the save: `tick`, `play`, `pause`, `stop`, a lifecycle
  /// state (`paused`, `hidden`, `detached`), `book switch`, a cast event.
  final String trigger;

  /// The book's storage key ([ServerScope.key]): what the save was filed
  /// under, which is the thing to check when a second server is involved.
  final String bookKey;

  /// Absolute positions in ms: the run's first save and its newest. The
  /// same for a single save.
  final int fromPositionMs;
  final int positionMs;

  /// Saves in the row: 1, or the length of a tick run.
  final int count;

  final ReportStatus report;

  /// For a held report, the place playback had to pass ([ReportGate]).
  final int? heldUntilMs;

  /// For sent reports: how many landed each way — `ok`, `queued` (no
  /// answer; kept for the offline queue), or `http 404` and the like (Plex
  /// answered and refused). Fewer than [count] means some are still on
  /// their way.
  final Map<String, int> outcomes;

  const SaveAuditEntry({
    required this.id,
    required this.at,
    required this.trigger,
    required this.bookKey,
    required this.fromPositionMs,
    required this.positionMs,
    required this.count,
    required this.report,
    this.heldUntilMs,
    this.outcomes = const {},
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'at': at.millisecondsSinceEpoch,
        'tr': trigger,
        'bk': bookKey,
        'from': fromPositionMs,
        'p': positionMs,
        'n': count,
        'rep': report.name,
        if (heldUntilMs != null) 'hold': heldUntilMs,
        if (outcomes.isNotEmpty) 'out': outcomes,
      };

  // Cold reads come back as Map<dynamic, dynamic>: parse with a bare Map.
  factory SaveAuditEntry.fromMap(Map m) => SaveAuditEntry(
        id: m['id'] as int,
        at: DateTime.fromMillisecondsSinceEpoch(m['at'] as int),
        trigger: m['tr'] as String,
        bookKey: m['bk'] as String,
        fromPositionMs: m['from'] as int,
        positionMs: m['p'] as int,
        count: m['n'] as int,
        report: ReportStatus.values.byName(m['rep'] as String),
        heldUntilMs: m['hold'] as int?,
        outcomes: {
          for (final e in ((m['out'] as Map?) ?? const {}).entries)
            e.key as String: e.value as int,
        },
      );
}

/// The last [maxEntries] position saves, for checking that saving works:
/// when, why, which book, where, and what Plex was told.
///
/// Runs of 10 s ticks fold into one row, so 20 rows cover a whole listen's
/// events (the hold, pauses, lifecycle saves) instead of its last three
/// minutes of ticks.
///
/// On disk, not in memory: the saves that matter come just before a kill,
/// and an in-memory list dies with the process. Bounded, with a test that
/// pins it. Written only with developer options on (beta and dev builds).
class SaveAuditStore {
  static const maxEntries = 20;
  static const _boxName = 'save_audit';
  static const _key = 'entries';
  static late Box _box;

  static Future<void> init(List<int> encKey) async {
    _box = await openUserBox(_boxName, encKey);
  }

  static List<Map> _raw() =>
      [for (final m in (_box.get(_key) as List? ?? const [])) m as Map];

  /// Records a save and returns its row's [SaveAuditEntry.id], for
  /// [recordOutcome]. A tick folds into the newest row when that is a tick
  /// run of the same book with the same report status. Never throws: it runs
  /// inside the save path.
  static Future<int?> record({
    required DateTime at,
    required String trigger,
    required String bookKey,
    required int positionMs,
    required ReportStatus report,
    int? heldUntilMs,
  }) async {
    try {
      final list = _raw();
      final last = list.isEmpty ? null : SaveAuditEntry.fromMap(list.last);
      final SaveAuditEntry entry;
      if (last != null &&
          trigger == 'tick' &&
          last.trigger == 'tick' &&
          last.bookKey == bookKey &&
          last.report == report) {
        entry = SaveAuditEntry(
          id: last.id,
          at: at,
          trigger: trigger,
          bookKey: bookKey,
          fromPositionMs: last.fromPositionMs,
          positionMs: positionMs,
          count: last.count + 1,
          report: report,
          heldUntilMs: heldUntilMs,
          outcomes: last.outcomes,
        );
        list.removeLast();
      } else {
        // Ids are the first save's time; two saves in one millisecond would
        // share one, so step past the newest.
        final id = at.millisecondsSinceEpoch;
        entry = SaveAuditEntry(
          id: last != null && id <= last.id ? last.id + 1 : id,
          at: at,
          trigger: trigger,
          bookKey: bookKey,
          fromPositionMs: positionMs,
          positionMs: positionMs,
          count: 1,
          report: report,
          heldUntilMs: heldUntilMs,
        );
      }
      list.add(entry.toMap());
      if (list.length > maxEntries) {
        list.removeRange(0, list.length - maxEntries);
      }
      await _box.put(_key, list);
      return entry.id;
    } catch (e) {
      AppLog.log('storage', 'save audit write failed: $e');
      return null;
    }
  }

  /// Files how a sent report landed against row [id]. A row that has
  /// already scrolled out is left alone.
  static Future<void> recordOutcome(int id, String outcome) async {
    try {
      final list = _raw();
      final i = list.indexWhere((m) => m['id'] == id);
      if (i < 0) return;
      final e = SaveAuditEntry.fromMap(list[i]);
      list[i] = SaveAuditEntry(
        id: e.id,
        at: e.at,
        trigger: e.trigger,
        bookKey: e.bookKey,
        fromPositionMs: e.fromPositionMs,
        positionMs: e.positionMs,
        count: e.count,
        report: e.report,
        heldUntilMs: e.heldUntilMs,
        outcomes: {...e.outcomes, outcome: (e.outcomes[outcome] ?? 0) + 1},
      ).toMap();
      await _box.put(_key, list);
    } catch (e) {
      AppLog.log('storage', 'save audit outcome failed: $e');
    }
  }

  /// Newest first.
  static List<SaveAuditEntry> entries() {
    try {
      return [for (final m in _raw().reversed) SaveAuditEntry.fromMap(m)];
    } catch (_) {
      // A row in the old shape (developer builds before tick runs): start
      // over rather than show nothing forever.
      _box.delete(_key);
      return const [];
    }
  }

  static Future<void> clear() => _box.delete(_key);
}
