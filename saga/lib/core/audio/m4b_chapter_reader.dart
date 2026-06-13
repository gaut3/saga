import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import '../diagnostics/app_log.dart';

class M4bChapter {
  final String title;
  final Duration start;

  const M4bChapter({required this.title, required this.start});
}

/// Reads embedded Nero-style chapters from M4B/MP4 files.
/// Handles both fast-start files (moov at start) and standard files (moov at end).
class M4bChapterReader {
  static const int _readSize = 8 * 1024 * 1024; // 8 MB

  static Future<List<M4bChapter>> fromFile(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) return [];
      // Read at most 8 MB from the head (fast-start files, moov first) and, if
      // needed, 8 MB from the tail (standard files, moov after mdat) — never
      // the whole file. An M4B audiobook is routinely hundreds of MB; loading
      // it all into RAM to find one atom risks an OOM kill on small devices.
      final total = await file.length();
      final raf = await file.open();
      try {
        final head = await raf.read(_readSize.clamp(0, total));
        final result = parseBytes(head);
        if (result.isNotEmpty) return result;
        var scanned = scanForMoov(head);
        if (scanned.isNotEmpty) return scanned;
        if (total > _readSize) {
          await raf.setPosition(total - _readSize);
          final tail = await raf.read(_readSize);
          scanned = scanForMoov(tail);
          if (scanned.isNotEmpty) return scanned;
        }
        return [];
      } finally {
        await raf.close();
      }
    } catch (e) {
      // Silent "Chapter N missing" reports start here — one line per attempt.
      AppLog.log('chapters', 'parse failed for local file: $e');
      return [];
    }
  }

  static Future<List<M4bChapter>> fromUrl(
    String url, {
    Map<String, String>? headers,
  }) async {
    try {
      final dio =
          Dio(BaseOptions(connectTimeout: const Duration(seconds: 10)));

      // Probe first 512 bytes to determine moov/mdat order and get file size
      final probe = await dio.get<List<int>>(
        url,
        options: Options(
          responseType: ResponseType.bytes,
          headers: {'Range': 'bytes=0-511', ...?headers},
          receiveTimeout: const Duration(seconds: 10),
          sendTimeout: const Duration(seconds: 10),
        ),
      );
      if (probe.data == null) return [];

      final total = _parseTotal(probe.headers.value('content-range'));
      final header = Uint8List.fromList(probe.data!);
      final moovFirst = _moovBeforeMdat(header);

      // Always fetch the first block
      final firstBlock = await _fetchRange(dio, url, 0, _readSize, headers: headers);
      if (firstBlock != null) {
        final result = parseBytes(firstBlock);
        if (result.isNotEmpty) return result;
      }

      // If file is bigger and moov wasn't at the start, scan from the end
      if (!moovFirst && total != null && total > _readSize) {
        final start = (total - _readSize).clamp(0, total);
        final lastBlock = await _fetchRange(dio, url, start, total, headers: headers);
        if (lastBlock != null) return scanForMoov(lastBlock);
      }

      return [];
    } catch (e) {
      AppLog.log('chapters', 'parse failed for stream: $e');
      return [];
    }
  }

  // ── helpers ──────────────────────────────────────────────────────────────────

  static bool _moovBeforeMdat(Uint8List d) {
    int off = 0;
    while (off + 8 <= d.length) {
      final sz = _u32(d, off);
      if (sz < 8) break;
      final tp = _cc(d, off + 4);
      if (tp == 'moov') return true;
      if (tp == 'mdat') return false;
      if (off + sz > d.length) break;
      off += sz;
    }
    return false;
  }

  static Future<Uint8List?> _fetchRange(
    Dio dio,
    String url,
    int from,
    int to, {
    Map<String, String>? headers,
  }) async {
    try {
      final resp = await dio.get<List<int>>(
        url,
        options: Options(
          responseType: ResponseType.bytes,
          headers: {'Range': 'bytes=$from-${to - 1}', ...?headers},
          receiveTimeout: const Duration(seconds: 30),
          sendTimeout: const Duration(seconds: 10),
        ),
      );
      if (resp.data == null) return null;
      return Uint8List.fromList(resp.data!);
    } catch (_) {
      return null;
    }
  }

  static int? _parseTotal(String? contentRange) {
    if (contentRange == null) return null;
    final slash = contentRange.lastIndexOf('/');
    if (slash < 0) return null;
    return int.tryParse(contentRange.substring(slash + 1));
  }

  /// Scan a chunk for a moov atom that doesn't start at offset 0.
  @visibleForTesting
  static List<M4bChapter> scanForMoov(Uint8List d) {
    for (int i = 0; i + 8 <= d.length; i++) {
      if (d[i + 4] == 0x6D && d[i + 5] == 0x6F &&
          d[i + 6] == 0x6F && d[i + 7] == 0x76) {
        final size = _u32(d, i);
        if (size >= 8) {
          final end = (i + size).clamp(0, d.length);
          final result = _moov(d, i + 8, end);
          if (result.isNotEmpty) return result;
        }
      }
    }
    return [];
  }

  // ── atom parsers ──────────────────────────────────────────────────────────────

  /// Parse a chunk that starts at an atom boundary (top-level entry point;
  /// public for tests — production callers are [fromFile] and [fromUrl]).
  @visibleForTesting
  static List<M4bChapter> parseBytes(Uint8List d) {
    int offset = 0;
    while (offset + 8 <= d.length) {
      final size = _u32(d, offset);
      if (size < 8) break;
      final type = _cc(d, offset + 4);
      if (type == 'moov') {
        return _moov(d, offset + 8, (offset + size).clamp(0, d.length));
      }
      if (offset + size > d.length) break;
      offset += size;
    }
    return [];
  }

  static List<M4bChapter> _moov(Uint8List d, int s, int e) {
    int o = s;
    while (o + 8 <= e) {
      final size = _u32(d, o);
      if (size < 8) break;
      final type = _cc(d, o + 4);
      if (type == 'udta') return _udta(d, o + 8, (o + size).clamp(0, e));
      if (o + size > e) break;
      o += size;
    }
    return [];
  }

  static List<M4bChapter> _udta(Uint8List d, int s, int e) {
    int o = s;
    while (o + 8 <= e) {
      final size = _u32(d, o);
      if (size < 8) break;
      final type = _cc(d, o + 4);
      if (type == 'chpl') return _chpl(d, o + 8, (o + size).clamp(0, e));
      if (o + size > e) break;
      o += size;
    }
    return [];
  }

  /// Nero chapter list: version(1)+flags(3)+reserved(1)+count(4)+entries
  static List<M4bChapter> _chpl(Uint8List d, int s, int e) {
    if (s + 9 > e) return [];
    int o = s + 5; // skip version+flags+reserved
    final count = _u32(d, o);
    o += 4;
    if (count == 0 || count > 5000) return [];

    final chapters = <M4bChapter>[];
    for (int i = 0; i < count; i++) {
      if (o + 9 > e) break;
      final time100ns = _u64(d, o);
      o += 8;
      final titleLen = d[o];
      o += 1;
      if (o + titleLen > e) break;
      // Nero chpl titles are UTF-8; decode as such so accented/non-ASCII
      // chapter names (e.g. Norwegian) don't mojibake. allowMalformed guards
      // against the occasional bad byte rather than throwing.
      final title = utf8.decode(d.sublist(o, o + titleLen), allowMalformed: true);
      o += titleLen;
      chapters.add(M4bChapter(
        title: title.isNotEmpty ? title : 'Chapter ${i + 1}',
        start: Duration(milliseconds: time100ns ~/ 10000),
      ));
    }
    return chapters;
  }

  static int _u32(Uint8List d, int o) =>
      (d[o] << 24) | (d[o + 1] << 16) | (d[o + 2] << 8) | d[o + 3];

  static int _u64(Uint8List d, int o) {
    var v = 0;
    for (var i = 0; i < 8; i++) {
      v = (v << 8) | d[o + i];
    }
    // A timestamp with the top bit set overflows Dart's signed 64-bit int into
    // a negative value; treat it as malformed rather than producing a negative
    // chapter start.
    return v < 0 ? 0 : v;
  }

  static String _cc(Uint8List d, int o) =>
      String.fromCharCodes(d.sublist(o, o + 4));
}
