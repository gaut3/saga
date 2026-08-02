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

/// Reads bytes from wherever the file lives — a local path or an HTTP range.
/// Returns null when the range can't be served.
typedef ByteRangeReader = Future<Uint8List?> Function(int start, int length);

/// One chapter-track sample: where its title bytes are, and when it starts.
class _ChapterSample {
  final int startMs;
  final int offset; // absolute file offset
  final int size;

  const _ChapterSample(
      {required this.startMs, required this.offset, required this.size});
}

/// Reads embedded chapters from M4B/MP4 files.
///
/// MP4 has no single chapter standard — it accumulated several conventions, and
/// a file may carry any one of them (or several, agreeing or not). Two are read
/// here, which between them cover the overwhelming majority of audiobooks:
///
///  * **Nero** — a `chpl` list in `moov/udta`. Self-contained: titles and times
///    sit together in one small atom.
///  * **QuickTime/MPEG-4 chapter track** — a text track in `moov/trak`, timed
///    by its own sample table, with the titles stored as media samples out in
///    `mdat`. This is what most taggers and converters write, and reading it
///    means following the sample table to byte offsets elsewhere in the file
///    (issue #8: files with only this form showed no chapters at all).
///
/// Known forms deliberately *not* read yet, in rough order of how likely they
/// are to turn up:
///
///  * **OverDrive MediaMarkers** — an XML blob in a freeform iTunes tag
///    (`moov/udta/meta/ilst/----` named `OverDrive MediaMarkers`). Common in
///    library-sourced audiobooks and the most likely next gap.
///  * **ID3v2 CHAP/CTOC frames** inside an `ID32` atom.
///  * **Fragmented MP4**, where samples live in `moof` fragments instead of a
///    flat sample table, so the offsets resolved here don't exist.
///
/// If a report arrives of a file with none of the supported forms, check for
/// those before assuming the parser is broken.
///
/// Handles both fast-start files (moov at start) and standard files (moov at
/// end), and never reads the whole file — an audiobook is routinely hundreds of
/// MB and loading it to find one atom risks an OOM kill on small devices.
///
/// Every attempt writes one line to the diagnostics log saying what it found
/// and where it gave up. A file with no chapters and a file we failed to read
/// look the same from the outside, and the difference is the entire content of
/// a useful bug report: the user can copy that line from Settings → About and
/// paste it into an issue. The line carries atom names, counts and sizes only
/// — no filename, no URL, nothing identifying the book or the server.
class M4bChapterReader {
  static const int _readSize = 8 * 1024 * 1024; // 8 MB

  /// Sample titles are tiny. If the span covering them is larger than this the
  /// file is doing something unusual, and one big read would be worse than no
  /// chapters.
  static const int _maxSampleSpan = 4 * 1024 * 1024;

  static Future<List<M4bChapter>> fromFile(String path) async {
    final notes = <String>[];
    var total = 0;
    try {
      final file = File(path);
      if (!await file.exists()) return [];
      total = await file.length();
      final raf = await file.open();
      try {
        Future<Uint8List?> readRange(int start, int length) async {
          if (start < 0 || start >= total) return null;
          await raf.setPosition(start);
          return raf.read(length.clamp(0, total - start));
        }

        // Head first (fast-start files), then the tail (moov after mdat).
        final head = await raf.read(_readSize.clamp(0, total));
        var result = await _chaptersIn(head, 0, readRange, notes, where: 'head');
        if (result.isNotEmpty) return result;

        if (total > _readSize) {
          final tailStart = total - _readSize;
          await raf.setPosition(tailStart);
          final tail = await raf.read(_readSize);
          result =
              await _chaptersIn(tail, tailStart, readRange, notes, where: 'tail');
          if (result.isNotEmpty) return result;
        }
        return [];
      } finally {
        await raf.close();
      }
    } catch (e) {
      // Silent "Chapter N missing" reports start here — one line per attempt.
      AppLog.log('chapters', 'parse failed for local file: $e');
      return [];
    } finally {
      if (notes.isNotEmpty) {
        AppLog.log('chapters', 'local, ${_size(total)}: ${notes.join('; ')}');
      }
    }
  }

  static Future<List<M4bChapter>> fromUrl(
    String url, {
    Map<String, String>? headers,
  }) async {
    final notes = <String>[];
    int? total;
    try {
      final dio =
          Dio(BaseOptions(connectTimeout: const Duration(seconds: 10)));

      // Probe the first bytes for the file size and the moov/mdat order.
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

      // Prefer Content-Range, but fall back to Content-Length: a server that
      // ignores the Range header (or answers 200) still tells us the size, and
      // without it the moov-at-end path used to be skipped entirely.
      total = _parseTotal(probe.headers.value('content-range')) ??
          int.tryParse(probe.headers.value('content-length') ?? '');
      final header = Uint8List.fromList(probe.data!);
      final moovFirst = _moovBeforeMdat(header);

      Future<Uint8List?> readRange(int start, int length) =>
          _fetchRange(dio, url, start, start + length, headers: headers);

      final firstBlock = await readRange(0, _readSize);
      if (firstBlock != null) {
        final result =
            await _chaptersIn(firstBlock, 0, readRange, notes, where: 'head');
        if (result.isNotEmpty) return result;
      } else {
        notes.add('head: server refused the first range request');
      }

      // moov may still be at the end — and when the probe couldn't tell us the
      // order, try anyway rather than give up.
      if (!moovFirst && total != null && total > _readSize) {
        final start = total - _readSize;
        final lastBlock = await readRange(start, _readSize);
        if (lastBlock != null) {
          return _chaptersIn(lastBlock, start, readRange, notes, where: 'tail');
        }
        notes.add('tail: server refused the closing range request');
      } else if (total == null) {
        notes.add('tail: skipped, server never reported the file size');
      }

      return [];
    } catch (e) {
      AppLog.log('chapters', 'parse failed for stream: $e');
      return [];
    } finally {
      if (notes.isNotEmpty) {
        AppLog.log('chapters', 'stream, ${_size(total)}: ${notes.join('; ')}');
      }
    }
  }

  // ── chapter extraction ──────────────────────────────────────────────────────

  /// Finds chapters in [buf], which begins at [bufOffset] in the file.
  ///
  /// Nero first: it needs no extra reads, and when a file has both forms they
  /// agree. Falls back to the chapter track, whose titles live outside `moov`
  /// and are fetched through [read].
  ///
  /// Every dead end appends to [notes], tagged with [where] (which of the two
  /// windows this is); the caller writes them out as one diagnostics line.
  static Future<List<M4bChapter>> _chaptersIn(
    Uint8List buf,
    int bufOffset,
    ByteRangeReader read,
    List<String> notes, {
    required String where,
  }) async {
    final moov = _locateMoov(buf);
    if (moov == null) {
      notes.add('$where: no moov in ${_size(buf.length)}');
      return [];
    }
    if (moov.declaredEnd > moov.end) {
      // Chapters sit after the audio track's sample tables, which for a long
      // book run to megabytes. A moov that overruns the window is therefore
      // the whole explanation: nothing worth reading was ever in the buffer.
      notes.add('$where: moov ${_size(moov.declaredEnd - moov.start)} '
          'overruns the ${_size(buf.length)} window');
    }

    final nero = _chplIn(buf, moov.start, moov.end);
    if (nero.isNotEmpty) {
      notes.add('$where: ${nero.length} from chpl');
      return nero;
    }

    final samples =
        _chapterTrackSamples(buf, moov.start, moov.end, notes, where);
    if (samples == null || samples.isEmpty) return [];

    final titles = await _readSampleTitles(samples, buf, bufOffset, read, notes, where);
    if (titles.isNotEmpty) {
      notes.add('$where: ${titles.length} from a chapter track');
    }
    return titles;
  }

  /// Pulls each sample's title from the file.
  ///
  /// The samples are normally contiguous, so this reads the whole span once
  /// rather than issuing a request per chapter — which over HTTP would be one
  /// round trip per chapter.
  static Future<List<M4bChapter>> _readSampleTitles(
    List<_ChapterSample> samples,
    Uint8List buf,
    int bufOffset,
    ByteRangeReader read,
    List<String> notes,
    String where,
  ) async {
    final lo = samples.map((s) => s.offset).reduce((a, b) => a < b ? a : b);
    final hi = samples
        .map((s) => s.offset + s.size)
        .reduce((a, b) => a > b ? a : b);
    if (hi <= lo || hi - lo > _maxSampleSpan) {
      notes.add('$where: ${samples.length} chapter titles spread over '
          '${_size(hi - lo)}, past the ${_size(_maxSampleSpan)} limit');
      return [];
    }

    Uint8List? span;
    var spanStart = lo;
    // Often the samples are already in the block we parsed moov from.
    if (lo >= bufOffset && hi <= bufOffset + buf.length) {
      span = buf;
      spanStart = bufOffset;
    } else {
      span = await read(lo, hi - lo);
    }
    if (span == null) {
      notes.add('$where: could not read the ${_size(hi - lo)} '
          'holding the chapter titles');
      return [];
    }

    final chapters = <M4bChapter>[];
    for (var i = 0; i < samples.length; i++) {
      final s = samples[i];
      final from = s.offset - spanStart;
      if (from < 0 || from + s.size > span.length) continue;
      final title = _decodeTextSample(span.sublist(from, from + s.size));
      chapters.add(M4bChapter(
        title: title.isNotEmpty ? title : 'Chapter ${i + 1}',
        start: Duration(milliseconds: s.startMs),
      ));
    }
    return chapters;
  }

  /// QuickTime text sample: u16 length, then the text.
  ///
  /// Encoders vary — some omit the length prefix, and some write UTF-16 with a
  /// BOM — so this trusts the prefix only when it's consistent with the sample
  /// size, and sniffs the BOM.
  static String _decodeTextSample(Uint8List sample) {
    var bytes = sample;
    if (bytes.length >= 2) {
      final declared = (bytes[0] << 8) | bytes[1];
      if (declared <= bytes.length - 2) {
        bytes = bytes.sublist(2, 2 + declared);
      }
    }
    if (bytes.length >= 2) {
      final b0 = bytes[0], b1 = bytes[1];
      if ((b0 == 0xFE && b1 == 0xFF) || (b0 == 0xFF && b1 == 0xFE)) {
        return _decodeUtf16(bytes).trim();
      }
    }
    return utf8.decode(bytes, allowMalformed: true).trim();
  }

  static String _decodeUtf16(Uint8List b) {
    final big = b[0] == 0xFE;
    final units = <int>[];
    for (var i = 2; i + 1 < b.length; i += 2) {
      units.add(big ? (b[i] << 8) | b[i + 1] : (b[i + 1] << 8) | b[i]);
    }
    return String.fromCharCodes(units);
  }

  // ── atom navigation ─────────────────────────────────────────────────────────

  /// The moov payload bounds, whether it sits at an atom boundary or has to be
  /// found by scanning (a truncated or unusual leading atom breaks the walk).
  ///
  /// `end` is clamped to the buffer, `declaredEnd` is what the atom header
  /// claims. They differ when moov is larger than the window that was read,
  /// which is worth knowing: everything after the cut is unreachable.
  static ({int start, int end, int declaredEnd})? _locateMoov(Uint8List d) {
    final walked = _moovByWalk(d);
    if (walked != null) return walked;
    return _scanMoovBounds(d);
  }

  static ({int start, int end, int declaredEnd})? _moovByWalk(Uint8List d) {
    int o = 0;
    while (o + 8 <= d.length) {
      final size = _u32(d, o);
      if (size < 8) return null;
      if (_cc(d, o + 4) == 'moov') {
        return (
          start: o + 8,
          end: (o + size).clamp(0, d.length),
          declaredEnd: o + size,
        );
      }
      if (o + size > d.length) return null;
      o += size;
    }
    return null;
  }

  /// The first child atom of [type] between [s] and [e], as payload bounds.
  static ({int start, int end})? _child(
      Uint8List d, int s, int e, String type) {
    int o = s;
    while (o + 8 <= e) {
      final size = _u32(d, o);
      // size 1 means a 64-bit largesize follows the fourcc; size 0 means "to
      // end of file". Neither is walkable here, so stop and let the caller
      // fall back to scanning.
      if (size < 8) return null;
      if (_cc(d, o + 4) == type) {
        return (start: o + 8, end: (o + size).clamp(0, e));
      }
      if (o + size > e) return null;
      o += size;
    }
    return null;
  }

  /// Every child atom of [type], for containers that repeat (`trak`).
  static List<({int start, int end})> _children(
      Uint8List d, int s, int e, String type) {
    final out = <({int start, int end})>[];
    int o = s;
    while (o + 8 <= e) {
      final size = _u32(d, o);
      if (size < 8) break;
      if (_cc(d, o + 4) == type) {
        out.add((start: o + 8, end: (o + size).clamp(0, e)));
      }
      if (o + size > e) break;
      o += size;
    }
    return out;
  }

  /// Follows a path of nested atoms, e.g. mdia → minf → stbl.
  static ({int start, int end})? _path(
      Uint8List d, int s, int e, List<String> types) {
    var cur = (start: s, end: e);
    for (final t in types) {
      final next = _child(d, cur.start, cur.end, t);
      if (next == null) return null;
      cur = next;
    }
    return cur;
  }

  static ({int start, int end, int declaredEnd})? _scanMoovBounds(Uint8List d) {
    for (int i = 0; i + 8 <= d.length; i++) {
      if (d[i + 4] == 0x6D &&
          d[i + 5] == 0x6F &&
          d[i + 6] == 0x6F &&
          d[i + 7] == 0x76) {
        final size = _u32(d, i);
        if (size >= 8) {
          return (
            start: i + 8,
            end: (i + size).clamp(0, d.length),
            declaredEnd: i + size,
          );
        }
      }
    }
    return null;
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

  // ── Nero chpl ───────────────────────────────────────────────────────────────

  static List<M4bChapter> _chplIn(Uint8List d, int s, int e) {
    final udta = _child(d, s, e, 'udta');
    if (udta == null) return [];
    final chpl = _child(d, udta.start, udta.end, 'chpl');
    if (chpl == null) return [];
    return _chpl(d, chpl.start, chpl.end);
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
      final title =
          utf8.decode(d.sublist(o, o + titleLen), allowMalformed: true);
      o += titleLen;
      chapters.add(M4bChapter(
        title: title.isNotEmpty ? title : 'Chapter ${i + 1}',
        start: Duration(milliseconds: time100ns ~/ 10000),
      ));
    }
    return chapters;
  }

  // ── QuickTime chapter track ─────────────────────────────────────────────────

  /// Locates the text track and resolves its samples to (time, offset, size).
  ///
  /// Returns null when the file has no chapter track, so the caller can tell
  /// "no such track" from "a track with no usable samples".
  static List<_ChapterSample>? _chapterTrackSamples(
      Uint8List d, int moovStart, int moovEnd, List<String> notes, String where) {
    // Every handler seen, so a file whose chapter track is tagged with some
    // fourcc we don't accept says so in the log instead of looking identical
    // to a file with no chapter track at all.
    final handlers = <String>[];
    for (final trak in _children(d, moovStart, moovEnd, 'trak')) {
      final mdia = _child(d, trak.start, trak.end, 'mdia');
      if (mdia == null) continue;

      // Handler: version+flags(4) + pre_defined(4) + handler_type(4).
      final hdlr = _child(d, mdia.start, mdia.end, 'hdlr');
      if (hdlr == null || hdlr.start + 12 > hdlr.end) continue;
      final handler = _cc(d, hdlr.start + 8);
      handlers.add(_printable(handler));
      if (handler != 'text' && handler != 'sbtl') continue;

      final timescale = _timescale(d, mdia);
      if (timescale == null || timescale == 0) {
        notes.add('$where: $handler track has no usable timescale');
        continue;
      }

      final stbl = _path(d, mdia.start, mdia.end, ['minf', 'stbl']);
      if (stbl == null) {
        notes.add('$where: $handler track has no sample table');
        continue;
      }

      final starts = _sampleStarts(d, stbl, timescale);
      final sizes = _sampleSizes(d, stbl);
      final offsets = _sampleOffsets(d, stbl, sizes);
      if (starts.isEmpty || sizes.isEmpty || offsets.isEmpty) {
        notes.add('$where: $handler track sample table incomplete '
            '(${starts.length} times, ${sizes.length} sizes, '
            '${offsets.length} offsets)');
        continue;
      }

      final n = [starts.length, sizes.length, offsets.length]
          .reduce((a, b) => a < b ? a : b);
      if (n == 0 || n > 5000) {
        notes.add('$where: $handler track claims $n chapters, ignored');
        continue;
      }
      return [
        for (var i = 0; i < n; i++)
          _ChapterSample(
              startMs: starts[i], offset: offsets[i], size: sizes[i])
      ];
    }
    notes.add('$where: no chapter track '
        '(tracks: ${handlers.isEmpty ? 'none' : handlers.join(' ')})');
    return null;
  }

  /// mdhd: version+flags(4), then v0 creation/modification(4+4) or v1 (8+8),
  /// followed by the timescale.
  static int? _timescale(Uint8List d, ({int start, int end}) mdia) {
    final mdhd = _child(d, mdia.start, mdia.end, 'mdhd');
    if (mdhd == null) return null;
    final version = d[mdhd.start];
    final off = mdhd.start + (version == 1 ? 4 + 16 : 4 + 8);
    if (off + 4 > mdhd.end) return null;
    return _u32(d, off);
  }

  /// stts (time-to-sample) accumulated into per-sample start times in ms.
  static List<int> _sampleStarts(
      Uint8List d, ({int start, int end}) stbl, int timescale) {
    final stts = _child(d, stbl.start, stbl.end, 'stts');
    if (stts == null || stts.start + 8 > stts.end) return const [];
    var o = stts.start + 4;
    final entries = _u32(d, o);
    o += 4;
    if (entries > 5000) return const [];

    final starts = <int>[];
    var ticks = 0;
    for (var i = 0; i < entries; i++) {
      if (o + 8 > stts.end) break;
      final count = _u32(d, o);
      final delta = _u32(d, o + 4);
      o += 8;
      for (var j = 0; j < count; j++) {
        if (starts.length > 5000) return starts;
        starts.add(ticks * 1000 ~/ timescale);
        ticks += delta;
      }
    }
    return starts;
  }

  /// stsz: a single size for every sample, or a table of them.
  static List<int> _sampleSizes(Uint8List d, ({int start, int end}) stbl) {
    final stsz = _child(d, stbl.start, stbl.end, 'stsz');
    if (stsz == null || stsz.start + 12 > stsz.end) return const [];
    final uniform = _u32(d, stsz.start + 4);
    final count = _u32(d, stsz.start + 8);
    if (count > 5000) return const [];
    if (uniform != 0) return List<int>.filled(count, uniform);

    var o = stsz.start + 12;
    final sizes = <int>[];
    for (var i = 0; i < count; i++) {
      if (o + 4 > stsz.end) break;
      sizes.add(_u32(d, o));
      o += 4;
    }
    return sizes;
  }

  /// Absolute file offset of each sample, from the chunk offsets (stco/co64)
  /// and the sample-to-chunk map (stsc). Samples within a chunk are stored
  /// back to back, so each one starts after the sizes of those before it.
  static List<int> _sampleOffsets(
      Uint8List d, ({int start, int end}) stbl, List<int> sizes) {
    final chunkOffsets = _chunkOffsets(d, stbl);
    if (chunkOffsets.isEmpty || sizes.isEmpty) return const [];

    // stsc: version+flags(4), entry_count(4), then (first_chunk,
    // samples_per_chunk, sample_description_index) runs.
    final stsc = _child(d, stbl.start, stbl.end, 'stsc');
    if (stsc == null || stsc.start + 8 > stsc.end) return const [];
    var o = stsc.start + 4;
    final entries = _u32(d, o);
    o += 4;
    if (entries == 0 || entries > 5000) return const [];

    final runs = <({int firstChunk, int perChunk})>[];
    for (var i = 0; i < entries; i++) {
      if (o + 12 > stsc.end) break;
      runs.add((firstChunk: _u32(d, o), perChunk: _u32(d, o + 4)));
      o += 12;
    }
    if (runs.isEmpty) return const [];

    final offsets = <int>[];
    var sampleIndex = 0;
    for (var chunk = 0; chunk < chunkOffsets.length; chunk++) {
      // The run that applies is the last one whose first_chunk (1-based) is at
      // or before this chunk.
      var perChunk = runs.first.perChunk;
      for (final r in runs) {
        if (r.firstChunk <= chunk + 1) {
          perChunk = r.perChunk;
        } else {
          break;
        }
      }
      var cursor = chunkOffsets[chunk];
      for (var i = 0; i < perChunk; i++) {
        if (sampleIndex >= sizes.length) return offsets;
        offsets.add(cursor);
        cursor += sizes[sampleIndex];
        sampleIndex++;
      }
    }
    return offsets;
  }

  static List<int> _chunkOffsets(Uint8List d, ({int start, int end}) stbl) {
    final stco = _child(d, stbl.start, stbl.end, 'stco');
    if (stco != null && stco.start + 8 <= stco.end) {
      var o = stco.start + 4;
      final count = _u32(d, o);
      o += 4;
      if (count > 5000) return const [];
      final out = <int>[];
      for (var i = 0; i < count; i++) {
        if (o + 4 > stco.end) break;
        out.add(_u32(d, o));
        o += 4;
      }
      return out;
    }
    final co64 = _child(d, stbl.start, stbl.end, 'co64');
    if (co64 != null && co64.start + 8 <= co64.end) {
      var o = co64.start + 4;
      final count = _u32(d, o);
      o += 4;
      if (count > 5000) return const [];
      final out = <int>[];
      for (var i = 0; i < count; i++) {
        if (o + 8 > co64.end) break;
        out.add(_u64(d, o));
        o += 8;
      }
      return out;
    }
    return const [];
  }

  // ── test entry points ───────────────────────────────────────────────────────

  /// Parses a buffer that begins at file offset 0 and contains everything the
  /// chapters need — both the atom tables and, for a chapter track, the sample
  /// bytes. Production goes through [fromFile] / [fromUrl].
  @visibleForTesting
  static Future<List<M4bChapter>> parseBuffer(Uint8List d,
          {List<String>? notes}) =>
      _chaptersIn(d, 0, (_, _) async => null, notes ?? <String>[],
          where: 'buffer');

  /// Synchronous Nero-only parse, kept for the tests that predate chapter-track
  /// support and for callers that only have a moov-sized buffer.
  @visibleForTesting
  static List<M4bChapter> parseBytes(Uint8List d) {
    final moov = _child(d, 0, d.length, 'moov');
    if (moov == null) return [];
    return _chplIn(d, moov.start, moov.end);
  }

  @visibleForTesting
  static List<M4bChapter> scanForMoov(Uint8List d) {
    final moov = _scanMoovBounds(d);
    if (moov == null) return [];
    return _chplIn(d, moov.start, moov.end);
  }

  // ── primitives ──────────────────────────────────────────────────────────────

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

  /// A fourcc read from a file is arbitrary bytes, and it ends up in a log the
  /// user pastes into a comment. Keep control characters out of it.
  static String _printable(String cc) => cc.replaceAll(
      RegExp(r'[^\x20-\x7E]'), '?');

  static String _size(int? bytes) {
    if (bytes == null) return 'size unknown';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
