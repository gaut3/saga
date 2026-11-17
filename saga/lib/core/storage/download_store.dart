import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:hive_flutter/hive_flutter.dart';

import 'server_scope.dart';
import 'user_box.dart';

const _boxName = 'downloads';

/// Where each downloaded track's file is, by track rating key.
///
/// Stored as absolute paths, which iOS breaks: it can move the app's data
/// folder when a new build is installed (`…/Application/<UUID>/Documents`),
/// taking the files along but not the stored paths. On the next start every
/// download looked deleted and `reconcile()` dropped it (iPhone, 2026-11-16).
/// So a stored path that's gone is re-based onto the current documents
/// folder by its `/downloads/…` tail before anything calls it missing, and
/// written back once found.
class DownloadStore {
  static late Box _box;
  static String? _documentsDir;

  static Future<void> init(List<int> encKey, {String? documentsDir}) async {
    _box = await openCacheBox(_boxName, encKey);
    _documentsDir = documentsDir;
  }

  static Future<void> save(String trackRatingKey, String localPath) async {
    await _box.put(ServerScope.key(trackRatingKey), localPath);
  }

  /// The file's path now: as stored, or re-based when the app's folder has
  /// moved. The stored path when neither exists (the caller checks).
  static String? getPath(String trackRatingKey) {
    final key = ServerScope.key(trackRatingKey);
    final stored = _box.get(key) as String?;
    if (stored == null) return null;
    return _resolve(key, stored);
  }

  static String _resolve(Object key, String stored) {
    if (File(stored).existsSync()) return stored;
    final docs = _documentsDir;
    if (docs == null) return stored;
    final moved = rebaseDownloadPath(stored, docs);
    if (moved == null || moved == stored || !File(moved).existsSync()) {
      return stored;
    }
    _box.put(key, moved);
    return moved;
  }

  static bool isDownloaded(String trackRatingKey) {
    return _box.containsKey(ServerScope.key(trackRatingKey));
  }

  static Future<void> remove(String trackRatingKey) async {
    await _box.delete(ServerScope.key(trackRatingKey));
  }

  /// Every raw storage key in the box, all servers: for cache housekeeping
  /// across boxes, as `BookmarkStore.rawKeys`.
  static Set<String> rawKeys() => {for (final k in _box.keys) k.toString()};

  static Map<String, String> allDownloads() {
    return {
      for (final key in _box.keys)
        if (ServerScope.ratingKeyOf(key.toString()) case final rk?)
          rk: _resolve(key, _box.get(key) as String),
    };
  }
}

/// [stored] moved under [documentsDir]: its `/downloads/…` tail on the new
/// folder, or null when it has none (not a download path).
@visibleForTesting
String? rebaseDownloadPath(String stored, String documentsDir) {
  final i = stored.indexOf('/downloads/');
  if (i < 0) return null;
  return '$documentsDir${stored.substring(i)}';
}
