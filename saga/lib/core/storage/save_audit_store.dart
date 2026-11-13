import 'package:hive_flutter/hive_flutter.dart';

import '../diagnostics/app_log.dart';
import 'server_scope.dart';
import 'user_box.dart';

/// One position save, as Settings › Developer options lists it.
class SaveAuditEntry {
  final DateTime at;

  /// What asked for the save: `tick`, `play`, `pause`, `stop`, a lifecycle
  /// state (`paused`, `hidden`, `detached`), `book switch`, a cast event.
  final String trigger;

  /// The book's storage key ([ServerScope.key]): what the save was filed
  /// under, which is the thing to check when a second server is involved.
  final String bookKey;

  /// Absolute position saved, in ms.
  final int positionMs;

  /// Whether the Plex report went out; if not, the hold it waited behind
  /// ([ReportGate]).
  final bool reported;
  final int? heldUntilMs;

  const SaveAuditEntry({
    required this.at,
    required this.trigger,
    required this.bookKey,
    required this.positionMs,
    required this.reported,
    this.heldUntilMs,
  });

  Map<String, dynamic> toMap() => {
        'at': at.millisecondsSinceEpoch,
        'tr': trigger,
        'bk': bookKey,
        'p': positionMs,
        'rep': reported,
        if (heldUntilMs != null) 'hold': heldUntilMs,
      };

  // Cold reads come back as Map<dynamic, dynamic>: parse with a bare Map.
  factory SaveAuditEntry.fromMap(Map m) => SaveAuditEntry(
        at: DateTime.fromMillisecondsSinceEpoch(m['at'] as int),
        trigger: m['tr'] as String,
        bookKey: m['bk'] as String,
        positionMs: m['p'] as int,
        reported: m['rep'] as bool,
        heldUntilMs: m['hold'] as int?,
      );
}

/// The last [maxEntries] position saves, for checking that saving works:
/// when, why, which book, where, and whether Plex was told.
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

  /// Appends [entry], dropping the oldest past [maxEntries]. Never throws:
  /// it runs inside the save path.
  static Future<void> record(SaveAuditEntry entry) async {
    try {
      final list = [...(_box.get(_key) as List? ?? const []), entry.toMap()];
      if (list.length > maxEntries) {
        list.removeRange(0, list.length - maxEntries);
      }
      await _box.put(_key, list);
    } catch (e) {
      AppLog.log('storage', 'save audit write failed: $e');
    }
  }

  /// Newest first.
  static List<SaveAuditEntry> entries() {
    try {
      return [
        for (final m in (_box.get(_key) as List? ?? const []).reversed)
          SaveAuditEntry.fromMap(m as Map),
      ];
    } catch (_) {
      return const [];
    }
  }

  static Future<void> clear() => _box.delete(_key);
}
