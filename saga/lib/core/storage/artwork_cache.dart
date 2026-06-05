import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

class ArtworkCache {
  static Directory? _dir;

  static Future<void> init() async {
    final base = await getApplicationDocumentsDirectory();
    _dir = Directory('${base.path}/artwork_cache');
    await _dir!.create(recursive: true);
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
      await Dio().download(
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
