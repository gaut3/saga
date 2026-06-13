import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../plex/plex_client.dart';
import 'bookmark_store.dart';
import 'completed_books_store.dart';
import 'custom_collection_store.dart';
import 'listen_days_store.dart';
import 'listening_history_store.dart';
import 'named_bookmark_store.dart';
import 'playback_log_store.dart';

class ProgressBackupData {
  final Map<String, BookPosition> positions;
  final Set<String> completed;
  final List<NamedBookmark> namedBookmarks;
  final List<CustomCollection> collections;
  final Map<String, dynamic> listeningHistory;
  // v3+: full per-completion timestamps (count + dates), per-read-through listen
  // days, and the session log behind the history day/week tabs.
  final Map<String, dynamic> completedDetailed;
  final Map<String, dynamic> listenDays;
  final Map<String, dynamic> playbackLog;
  // Identifies which Plex server produced the backup. Null for pre-v4 backups.
  final String? serverMachineIdentifier;

  const ProgressBackupData({
    required this.positions,
    required this.completed,
    required this.namedBookmarks,
    required this.collections,
    this.listeningHistory = const {},
    this.completedDetailed = const {},
    this.listenDays = const {},
    this.playbackLog = const {},
    this.serverMachineIdentifier,
  });
}

/// A backup position that is older than the locally stored one. Surfaces in
/// the restore confirmation UI so the user can decide per-book.
class PositionConflict {
  final String bookKey;
  final BookPosition local;
  final BookPosition backup;
  const PositionConflict({
    required this.bookKey,
    required this.local,
    required this.backup,
  });
}

class ProgressBackup {
  static const _version = 4;

  /// Serializes all stores into the backup map. Pure store reads — no file
  /// IO and no [PlexClient] dependency, so the round-trip is unit-testable.
  static Map<String, dynamic> buildBackupMap(
      {String? serverMachineIdentifier}) {
    final positions = BookmarkStore.allPositions();
    final completed = CompletedBooksStore.allCompleted().toList();
    final namedBookmarks = NamedBookmarkStore.getAll();
    final collections = CustomCollectionStore.getAll();
    final history = ListeningHistoryStore.exportAll();

    return {
      'version': _version,
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      if (serverMachineIdentifier != null)
        'serverMachineIdentifier': serverMachineIdentifier,
      'positions': {
        for (final e in positions.entries) e.key: e.value.toMap(),
      },
      // Flat key set kept for older app versions reading a new backup; v3 readers
      // prefer the detailed map below (preserves counts + dates).
      'completed': completed,
      'completedDetailed': CompletedBooksStore.exportAll(),
      'namedBookmarks': namedBookmarks.map((b) => b.toMap()).toList(),
      'collections': collections.map((c) => c.toMap()).toList(),
      'listeningHistory': history,
      'listenDays': ListenDaysStore.exportAll(),
      'playbackLog': PlaybackLogStore.exportAll(),
    };
  }

  static Future<void> export() async {
    final data = buildBackupMap(
        serverMachineIdentifier: PlexClient.instance.machineIdentifier);

    final json = jsonEncode(data);
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/saga_progress.json');
    await file.writeAsString(json);
    await Share.shareXFiles([XFile(file.path)], subject: 'Saga progress backup');
    try { await file.delete(); } catch (_) {}
  }

  static Future<ProgressBackupData?> pickAndParse() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
      withData: false,
    );
    if (result == null || result.files.isEmpty) return null;

    final picked = result.files.first;
    final String content;
    if (picked.path != null) {
      content = await File(picked.path!).readAsString();
    } else if (picked.bytes != null) {
      content = utf8.decode(picked.bytes!);
    } else {
      throw StateError('File picker returned a file with no readable path or bytes.');
    }

    return parseBackupJson(content);
  }

  /// Parses backup JSON into [ProgressBackupData]. Returns null for unknown
  /// versions. Pure — no file IO, so the round-trip is unit-testable.
  static ProgressBackupData? parseBackupJson(String content) {
    final Map<String, dynamic> json =
        jsonDecode(content) as Map<String, dynamic>;
    final version = json['version'] as int? ?? 0;
    if (version < 1 || version > _version) return null;
    final serverMachineIdentifier =
        json['serverMachineIdentifier'] as String?;

    final positionsRaw =
        (json['positions'] as Map<String, dynamic>?) ?? {};
    final positions = {
      for (final e in positionsRaw.entries)
        e.key: BookPosition.fromMap(e.value as Map),
    };

    final completed = ((json['completed'] as List<dynamic>?) ?? [])
        .map((e) => e as String)
        .toSet();

    final namedBookmarks =
        ((json['namedBookmarks'] as List<dynamic>?) ?? [])
            .map((e) => NamedBookmark.fromMap(e as Map))
            .toList();

    final collections =
        ((json['collections'] as List<dynamic>?) ?? [])
            .map((e) => CustomCollection.fromMap(e as Map))
            .toList();

    final history =
        (json['listeningHistory'] as Map<String, dynamic>?) ?? {};
    final completedDetailed =
        (json['completedDetailed'] as Map<String, dynamic>?) ?? {};
    final listenDays = (json['listenDays'] as Map<String, dynamic>?) ?? {};
    final playbackLog = (json['playbackLog'] as Map<String, dynamic>?) ?? {};

    return ProgressBackupData(
      positions: positions,
      completed: completed,
      namedBookmarks: namedBookmarks,
      collections: collections,
      listeningHistory: history,
      completedDetailed: completedDetailed,
      listenDays: listenDays,
      playbackLog: playbackLog,
      serverMachineIdentifier: serverMachineIdentifier,
    );
  }

  /// Returns positions in [data] where the locally stored position is newer
  /// than the backup's. Used to surface per-book choices in the restore UI.
  static List<PositionConflict> detectConflicts(ProgressBackupData data) {
    final result = <PositionConflict>[];
    for (final e in data.positions.entries) {
      final local = BookmarkStore.load(e.key);
      if (local != null && local.savedAt.isAfter(e.value.savedAt)) {
        result.add(PositionConflict(
          bookKey: e.key,
          local: local,
          backup: e.value,
        ));
      }
    }
    return result;
  }

  /// Restores [data]. Positions whose key is in [skipPositionKeys] are not
  /// written — used to preserve locally-newer positions the user chose to keep.
  static Future<void> restore(
    ProgressBackupData data, {
    Set<String> skipPositionKeys = const {},
  }) async {
    for (final e in data.positions.entries) {
      if (skipPositionKeys.contains(e.key)) continue;
      await BookmarkStore.save(e.key, e.value);
    }
    // v3+ backups carry full per-completion timestamps (count + dates); older
    // backups only have the flat key set, which we restore as a single completion.
    if (data.completedDetailed.isNotEmpty) {
      await CompletedBooksStore.importAll(data.completedDetailed);
    } else {
      for (final key in data.completed) {
        await CompletedBooksStore.markCompleted(key);
      }
    }
    if (data.listenDays.isNotEmpty) {
      await ListenDaysStore.importAll(data.listenDays);
    }
    if (data.playbackLog.isNotEmpty) {
      await PlaybackLogStore.importAll(data.playbackLog);
    }
    for (final bookmark in data.namedBookmarks) {
      await NamedBookmarkStore.save(bookmark);
    }
    for (final col in data.collections) {
      await CustomCollectionStore.restoreCollection(col);
    }
    if (data.listeningHistory.isNotEmpty) {
      await ListeningHistoryStore.importAll(data.listeningHistory);
    }
  }
}
