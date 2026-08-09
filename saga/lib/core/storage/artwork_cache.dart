import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path_provider/path_provider.dart';

class ArtworkCache {
  static Directory? _dir;

  /// One client for every cover, not one per fetch. A fresh [Dio] carries its
  /// own connection pool, so downloading a book's covers used to open a pool
  /// per file and leave each to fall idle separately, reusing no connection to
  /// a server it was about to call again.
  static final Dio _dio =
      Dio(BaseOptions(connectTimeout: const Duration(seconds: 10)));

  /// Ceiling for the whole cache.
  ///
  /// Covers are written here and never overwritten, so without a ceiling this
  /// directory only ever grows: one file per book ever played, kept long after
  /// the book leaves the listener's Plex library, in app-private storage the
  /// user can only reclaim by clearing all of Saga's data — which would take
  /// their positions and history with it. A few hundred covers is the realistic
  /// worst case; 64 MB holds far more than that and is small enough not to
  /// matter on any phone that can install the app.
  static const _maxBytes = 64 * 1024 * 1024;

  static Future<void> init() async {
    final base = await getApplicationDocumentsDirectory();
    _dir = Directory('${base.path}/artwork_cache');
    await _dir!.create(recursive: true);
    // Deliberately not awaited: a cover cache is not worth delaying the first
    // frame for, and a failure here must never keep the app from starting.
    unawaited(prune());
  }

  /// Points the cache at [dir] without touching `path_provider`, so [prune]
  /// can be exercised against a temp directory. Pass null to reset.
  @visibleForTesting
  static void debugSetDirectory(Directory? dir) => _dir = dir;

  /// Deletes the oldest covers until the cache is back under [_maxBytes].
  ///
  /// Oldest by write time, not by last read — an evicted cover costs one
  /// re-fetch the next time its book is opened, which `prefetch` already does
  /// silently, so the cheap approximation is the right one here.
  static Future<void> prune() async {
    final dir = _dir;
    if (dir == null) return;
    try {
      final files = <({File file, int size, DateTime modified})>[];
      var total = 0;
      await for (final entry in dir.list()) {
        if (entry is! File) continue;
        final stat = await entry.stat();
        total += stat.size;
        files.add((file: entry, size: stat.size, modified: stat.modified));
      }
      if (total <= _maxBytes) return;

      files.sort((a, b) => a.modified.compareTo(b.modified));
      for (final f in files) {
        if (total <= _maxBytes) break;
        try {
          await f.file.delete();
          total -= f.size;
        } catch (_) {
          // A cover we can't delete is not worth failing over; the next run
          // tries again.
        }
      }
    } catch (_) {
      // Listing failed (permissions, a racing delete). The cache stays as it
      // is — oversized at worst, never broken.
    }
  }

  /// Deletes every cached cover. Used on sign-out — the covers are a picture of
  /// the account's library, so they go when the account does.
  static Future<void> clear() async {
    final dir = _dir;
    if (dir == null) return;
    try {
      await for (final entry in dir.list()) {
        if (entry is File) {
          try {
            await entry.delete();
          } catch (_) {
            // A cover we can't delete is not worth failing a sign-out over.
          }
        }
      }
    } catch (_) {
      // Listing failed; nothing here is worth surfacing to the user.
    }
  }

  // Stable filename from the thumb path using a simple djb2-style hash.
  static String _filename(String thumbPath) {
    var h = 5381;
    for (final c in thumbPath.codeUnits) {
      h = ((h << 5) + h + c) & 0xFFFFFFFF;
    }
    return '${h.toRadixString(16)}.art';
  }

  /// Returns a local [file://] URI if the artwork is already on disk.
  static Uri? getLocalUri(String? thumbPath) {
    if (thumbPath == null || _dir == null) return null;
    final f = File('${_dir!.path}/${_filename(thumbPath)}');
    return f.existsSync() ? f.uri : null;
  }

  /// Downloads artwork using header-based auth (no token in URL).
  /// Returns the local [file://] URI on success, null on failure.
  static Future<Uri?> prefetch(
    String thumbPath,
    String serverUri,
    Map<String, String> authHeaders,
  ) async {
    if (_dir == null) return null;
    final filePath = '${_dir!.path}/${_filename(thumbPath)}';
    final file = File(filePath);
    if (await file.exists()) return file.uri;
    try {
      await _dio.download(
        '$serverUri$thumbPath',
        filePath,
        options: Options(
          headers: authHeaders,
          receiveTimeout: const Duration(seconds: 15),
          sendTimeout: const Duration(seconds: 10),
        ),
      );
      return File(filePath).uri;
    } catch (_) {
      return null;
    }
  }
}
