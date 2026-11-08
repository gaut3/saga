import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path_provider/path_provider.dart';

import 'server_scope.dart';

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

  /// Downloads in flight, by final path. `loadBook` and the track-change
  /// listener both prefetch the book's cover, and two writers into one file is
  /// how a cover gets corrupted — and a cover on disk is served forever.
  static final Map<String, Future<Uri?>> _inFlight = {};

  static Future<void> init() async {
    final base = await getApplicationDocumentsDirectory();
    _dir = Directory('${base.path}/artwork_cache');
    await _dir!.create(recursive: true);
    // Nothing is in flight yet, so any `.part` here is a download the process
    // died during. Never served (no reader asks for that name), but it would
    // sit there counting against the ceiling.
    unawaited(_sweepPartials());
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
        // A `.part` is a download in flight — deleting it would fail that
        // download's rename. Dead ones are swept at [init].
        if (entry is! File || entry.path.endsWith('.part')) continue;
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

  static Future<void> _sweepPartials() async {
    final dir = _dir;
    if (dir == null) return;
    try {
      await for (final entry in dir.list()) {
        if (entry is File && entry.path.endsWith('.part')) {
          await entry.delete();
        }
      }
    } catch (_) {
      // Leftovers are harmless; prune still bounds the directory.
    }
  }

  // Stable filename from the thumb path using a simple djb2-style hash. The
  // thumb path carries a per-server rating key, so it goes through
  // [ServerScope] like every per-book store: the primary server hashes the
  // bare path (existing covers keep their names), a second server's doesn't
  // collide with it.
  static String _filename(String thumbPath) {
    var h = 5381;
    for (final c in ServerScope.key(thumbPath).codeUnits) {
      h = ((h << 5) + h + c) & 0xFFFFFFFF;
    }
    return '${h.toRadixString(16)}.art';
  }

  /// Where [thumbPath]'s cover lives, cached or not — so a test can put one
  /// there without a server.
  @visibleForTesting
  static File debugFileFor(String thumbPath) =>
      File('${_dir!.path}/${_filename(thumbPath)}');

  /// Returns a local [file://] URI if the artwork is already on disk.
  static Uri? getLocalUri(String? thumbPath) {
    if (thumbPath == null || _dir == null) return null;
    final f = File('${_dir!.path}/${_filename(thumbPath)}');
    return f.existsSync() ? f.uri : null;
  }

  /// Where `CoverProvider.kt` serves this directory to other processes — the
  /// `android:authorities` of its `<provider>` in the manifest
  /// (`media_browse_test` holds the two together).
  static const sharedAuthority = 'com.gaut3.saga.covers';

  /// The cached cover as a `content://` URI another app can open, or null.
  ///
  /// For what Android draws in its own process — Android Auto's shelves, the
  /// resumption card. A [getLocalUri] path names a file in Saga's private
  /// storage that those processes can't read, so it showed as a blank tile.
  /// Saga's own MediaSession art doesn't need this: audio_service decodes the
  /// `file://` itself and hands over the bitmap.
  static Uri? getSharedUri(String? thumbPath) {
    if (thumbPath == null || _dir == null) return null;
    final name = _filename(thumbPath);
    if (!File('${_dir!.path}/$name').existsSync()) return null;
    return Uri(scheme: 'content', host: sharedAuthority, path: '/$name');
  }

  /// The file behind a cover URI this cache handed out — a [getLocalUri]
  /// `file://` or a [getSharedUri] `content://` — so Saga's own screens can
  /// draw the now-playing cover without a content resolver. Null for any other
  /// URI.
  static File? fileOf(Uri uri) {
    if (uri.scheme == 'file') return File(uri.toFilePath());
    final dir = _dir;
    if (uri.scheme != 'content' ||
        uri.host != sharedAuthority ||
        uri.pathSegments.length != 1 ||
        dir == null) {
      return null;
    }
    return File('${dir.path}/${uri.pathSegments.single}');
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
    return _inFlight[filePath] ??=
        _download('$serverUri$thumbPath', filePath, authHeaders)
            .whenComplete(() => _inFlight.remove(filePath));
  }

  /// Writes to `<path>.part` and renames on success, so the final name only
  /// ever holds a whole cover — a cut-off download leaves a `.part`, never a
  /// half image under the name readers trust.
  static Future<Uri?> _download(
    String url,
    String filePath,
    Map<String, String> authHeaders,
  ) async {
    final part = File('$filePath.part');
    try {
      await _dio.download(
        url,
        part.path,
        options: Options(
          headers: authHeaders,
          receiveTimeout: const Duration(seconds: 15),
          sendTimeout: const Duration(seconds: 10),
        ),
      );
      final file = await part.rename(filePath);
      // Hold the ceiling here too, not only at launch: [init] was the sole
      // caller, so a long run that opened many books stayed oversized until the
      // next cold start. Cheap to do per download — a cover is only downloaded
      // once per book ever (the `exists` check above is the common path), so
      // this is one directory listing per *new* cover, unawaited, never on the
      // read path.
      unawaited(prune());
      return file.uri;
    } catch (_) {
      try {
        if (await part.exists()) await part.delete();
      } catch (_) {}
      return null;
    }
  }
}
