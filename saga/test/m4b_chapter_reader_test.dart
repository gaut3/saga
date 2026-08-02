import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:saga/core/audio/m4b_chapter_reader.dart';

/// MP4 atom: u32 big-endian size (header included) + fourcc + payload.
Uint8List atom(String type, List<int> payload) {
  final size = 8 + payload.length;
  return Uint8List.fromList([
    (size >> 24) & 0xFF,
    (size >> 16) & 0xFF,
    (size >> 8) & 0xFF,
    size & 0xFF,
    ...ascii.encode(type),
    ...payload,
  ]);
}

/// Nero chpl payload: version(1) + flags(3) + reserved(1) + count(4) +
/// entries of u64 start (100 ns units) + u8 title length + title bytes.
List<int> chplPayload(List<(int, String)> entries, {int? countOverride}) {
  final count = countOverride ?? entries.length;
  final bytes = <int>[
    0, 0, 0, 0, 0, // version + flags + reserved
    (count >> 24) & 0xFF,
    (count >> 16) & 0xFF,
    (count >> 8) & 0xFF,
    count & 0xFF,
  ];
  for (final (time100ns, title) in entries) {
    for (var i = 7; i >= 0; i--) {
      bytes.add((time100ns >> (8 * i)) & 0xFF);
    }
    final titleBytes = utf8.encode(title);
    bytes.add(titleBytes.length);
    bytes.addAll(titleBytes);
  }
  return bytes;
}

/// A minimal fast-start M4B: ftyp, then moov > udta > chpl.
Uint8List m4bWithChpl(List<int> chpl) {
  final ftyp = atom('ftyp', ascii.encode('M4B '));
  final moov = atom('moov', atom('udta', atom('chpl', chpl)));
  return Uint8List.fromList([...ftyp, ...moov]);
}

List<int> _u32(int v) =>
    [(v >> 24) & 0xFF, (v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF];

List<int> _u64(int v) => [
      for (var i = 7; i >= 0; i--) (v >> (8 * i)) & 0xFF,
    ];

/// QuickTime text sample: u16 length, then the bytes.
List<int> _textSample(String title, {required bool utf16}) {
  final body = utf16
      ? [0xFE, 0xFF, for (final u in title.codeUnits) ...[(u >> 8) & 0xFF, u & 0xFF]]
      : utf8.encode(title);
  return [(body.length >> 8) & 0xFF, body.length & 0xFF, ...body];
}

/// A minimal M4B carrying a QuickTime chapter track.
///
/// Built in two passes because `stco` holds *absolute file offsets*: the layout
/// is laid out once to learn where mdat lands, then rebuilt with the real
/// offsets. Getting this wrong is exactly the bug the tests are guarding.
Uint8List m4bWithChapterTrack(
  List<(int, String)> chapters, {
  int timescale = 1000,
  bool utf16 = false,
  bool co64 = false,
  String handler = 'text',
  int chunkCount = 1,
  List<Uint8List> extraMoovChildren = const [],
}) {
  final samples = [
    for (final (_, title) in chapters) _textSample(title, utf16: utf16)
  ];
  final sizes = samples.map((s) => s.length).toList();

  // stts deltas: the gap to the next chapter (the last one gets a nominal
  // tail), expressed in the track timescale.
  final deltas = <int>[];
  for (var i = 0; i < chapters.length; i++) {
    final startTicks = chapters[i].$1 * timescale ~/ 1000;
    final nextTicks = i + 1 < chapters.length
        ? chapters[i + 1].$1 * timescale ~/ 1000
        : startTicks + timescale;
    deltas.add(nextTicks - startTicks);
  }

  // Spread samples over chunkCount chunks, as evenly as the count allows.
  final perChunk = chapters.isEmpty
      ? 0
      : (chapters.length / chunkCount).ceil();
  final chunks = <List<int>>[]; // sample indices per chunk
  for (var i = 0; i < chapters.length; i += perChunk == 0 ? 1 : perChunk) {
    chunks.add([
      for (var j = i; j < i + perChunk && j < chapters.length; j++) j
    ]);
  }

  Uint8List build(List<int> chunkOffsets) {
    final stts = atom('stts', [
      ...[0, 0, 0, 0],
      ..._u32(deltas.length),
      for (var i = 0; i < deltas.length; i++) ...[..._u32(1), ..._u32(deltas[i])],
    ]);
    final stsz = atom('stsz', [
      ...[0, 0, 0, 0],
      ..._u32(0), // per-sample sizes follow
      ..._u32(sizes.length),
      for (final s in sizes) ..._u32(s),
    ]);
    final stsc = atom('stsc', [
      ...[0, 0, 0, 0],
      ..._u32(chunks.isEmpty ? 0 : 1),
      if (chunks.isNotEmpty) ...[
        ..._u32(1), // first_chunk (1-based)
        ..._u32(perChunk),
        ..._u32(1),
      ],
    ]);
    final offsetsAtom = co64
        ? atom('co64', [
            ...[0, 0, 0, 0],
            ..._u32(chunkOffsets.length),
            for (final o in chunkOffsets) ..._u64(o),
          ])
        : atom('stco', [
            ...[0, 0, 0, 0],
            ..._u32(chunkOffsets.length),
            for (final o in chunkOffsets) ..._u32(o),
          ]);

    final stbl = atom('stbl', [
      ...atom('stsd', [0, 0, 0, 0, ..._u32(0)]),
      ...stts,
      ...stsc,
      ...stsz,
      ...offsetsAtom,
    ]);
    final minf = atom('minf', stbl);
    final mdhd = atom('mdhd', [
      0, 0, 0, 0, // version 0 + flags
      ..._u32(0), // creation
      ..._u32(0), // modification
      ..._u32(timescale),
      ..._u32(0), // duration
    ]);
    final hdlr = atom('hdlr', [
      0, 0, 0, 0,
      ..._u32(0),
      ...ascii.encode(handler),
      ...List.filled(12, 0),
    ]);
    final mdia = atom('mdia', [...mdhd, ...hdlr, ...minf]);
    final trak = atom('trak', [...atom('tkhd', List.filled(84, 0)), ...mdia]);

    final moov = atom('moov', [
      ...trak,
      for (final extra in extraMoovChildren) ...extra,
    ]);
    final ftyp = atom('ftyp', ascii.encode('M4B '));
    final mdat = atom('mdat', [for (final s in samples) ...s]);
    return Uint8List.fromList([...ftyp, ...moov, ...mdat]);
  }

  // Pass 1: lay it out with placeholder offsets to measure where mdat starts.
  final probe = build(List.filled(chunks.length, 0));
  final mdatPayloadStart = probe.length -
      samples.fold<int>(0, (a, s) => a + s.length);

  // Pass 2: real offsets. Chunk n begins after every sample before it.
  final chunkOffsets = <int>[];
  var cursor = mdatPayloadStart;
  for (final chunk in chunks) {
    chunkOffsets.add(cursor);
    for (final i in chunk) {
      cursor += sizes[i];
    }
  }
  return build(chunkOffsets);
}

void main() {
  group('parseBytes', () {
    test('valid two-chapter file, UTF-8 Norwegian titles, 100ns to ms', () {
      // 60 s = 600_000_000 units of 100 ns.
      final data = m4bWithChpl(chplPayload([
        (0, 'Innledning'),
        (600000000, 'Kapittel én — Bokmål øving'),
      ]));
      final chapters = M4bChapterReader.parseBytes(data);
      expect(chapters.length, 2);
      expect(chapters[0].title, 'Innledning');
      expect(chapters[0].start, Duration.zero);
      expect(chapters[1].title, 'Kapittel én — Bokmål øving');
      expect(chapters[1].start, const Duration(seconds: 60));
    });

    test('empty title falls back to "Chapter N"', () {
      final data = m4bWithChpl(chplPayload([
        (0, ''),
        (600000000, 'Named'),
      ]));
      final chapters = M4bChapterReader.parseBytes(data);
      expect(chapters[0].title, 'Chapter 1');
      expect(chapters[1].title, 'Named');
    });

    test('chapter count of zero returns no chapters', () {
      final data = m4bWithChpl(chplPayload([]));
      expect(M4bChapterReader.parseBytes(data), isEmpty);
    });

    test('absurd chapter count (>5000) is rejected as malformed', () {
      final data = m4bWithChpl(chplPayload([(0, 'A')], countOverride: 5001));
      expect(M4bChapterReader.parseBytes(data), isEmpty);
    });

    test('truncated entry mid-title keeps the chapters parsed so far', () {
      // Second entry's declared title length runs past the atom end.
      final good = chplPayload([(0, 'First')]);
      final bad = <int>[
        ...good.sublist(0, 5),
        0, 0, 0, 2, // count = 2 but only ~1.5 entries follow
        ...good.sublist(9), // entry 1 (intact)
        0, 0, 0, 0, 0, 0, 0, 1, // entry 2 start
        200, // title length 200 with no bytes behind it
      ];
      final chapters = M4bChapterReader.parseBytes(m4bWithChpl(bad));
      expect(chapters.length, 1);
      expect(chapters[0].title, 'First');
    });

    test('timestamp with the top bit set is clamped to 0, not negative', () {
      final data = m4bWithChpl(chplPayload([
        (0x8000000000000000, 'Overflow'),
        (600000000, 'Fine'),
      ]));
      final chapters = M4bChapterReader.parseBytes(data);
      expect(chapters.length, 2);
      expect(chapters[0].start, Duration.zero);
      expect(chapters[0].start.isNegative, isFalse);
      expect(chapters[1].start, const Duration(seconds: 60));
    });

    test('no chpl atom anywhere returns empty', () {
      final data = Uint8List.fromList([
        ...atom('ftyp', ascii.encode('M4B ')),
        ...atom('moov', atom('udta', atom('meta', [1, 2, 3]))),
      ]);
      expect(M4bChapterReader.parseBytes(data), isEmpty);
    });

    test('garbage input does not throw', () {
      expect(M4bChapterReader.parseBytes(Uint8List(0)), isEmpty);
      expect(M4bChapterReader.parseBytes(Uint8List.fromList([1, 2, 3])),
          isEmpty);
      expect(
          M4bChapterReader.parseBytes(Uint8List.fromList(
              List.generate(64, (i) => i * 7 % 256))),
          isEmpty);
    });
  });

  group('scanForMoov', () {
    test('finds a moov atom that does not start at offset 0', () {
      final moov = atom(
          'moov', atom('udta', atom('chpl', chplPayload([(0, 'Found')]))));
      // Junk prefix that is not a clean atom boundary.
      final data = Uint8List.fromList([9, 9, 9, 9, 9, 9, 9, ...moov]);
      expect(M4bChapterReader.parseBytes(data), isEmpty,
          reason: 'top-level walk must fail on the junk prefix');
      final chapters = M4bChapterReader.scanForMoov(data);
      expect(chapters.length, 1);
      expect(chapters[0].title, 'Found');
    });
  });

  // ── QuickTime / MPEG-4 chapter track (issue #8) ────────────────────────────
  //
  // The other way an M4B carries chapters: a text track whose sample table
  // points at title bytes living out in mdat. Files with only this form used to
  // report no chapters at all.

  group('chapter track', () {
    test('reads titles and times from a text track', () async {
      final data = m4bWithChapterTrack(const [
        (0, 'Opening Credits'),
        (30000, 'Chapter One'),
        (95500, 'Chapter Two'),
      ]);
      final chapters = await M4bChapterReader.parseBuffer(data);
      expect(chapters.map((c) => c.title).toList(),
          ['Opening Credits', 'Chapter One', 'Chapter Two']);
      expect(chapters.map((c) => c.start.inMilliseconds).toList(),
          [0, 30000, 95500]);
    });

    test('a non-1000 timescale still yields milliseconds', () async {
      // 600 is QuickTime's traditional timescale; getting this wrong shifts
      // every chapter by a factor.
      final data = m4bWithChapterTrack(
          const [(0, 'A'), (1000, 'B')], timescale: 600);
      final chapters = await M4bChapterReader.parseBuffer(data);
      expect(chapters[1].start.inMilliseconds, 1000);
    });

    test('Nero wins when a file carries both', () async {
      // Both forms should agree; if they don't, the self-contained one needs no
      // extra reads and is the safer answer.
      final data = m4bWithChapterTrack(
        const [(0, 'From track')],
        extraMoovChildren: [
          atom('udta', atom('chpl', chplPayload([(0, 'From chpl')]))),
        ],
      );
      final chapters = await M4bChapterReader.parseBuffer(data);
      expect(chapters.single.title, 'From chpl');
    });

    test('a UTF-16 title with a BOM decodes', () async {
      final data = m4bWithChapterTrack(const [(0, 'Æresgjesten')], utf16: true);
      final chapters = await M4bChapterReader.parseBuffer(data);
      expect(chapters.single.title, 'Æresgjesten');
    });

    test('a UTF-8 title with non-ASCII decodes', () async {
      final data = m4bWithChapterTrack(const [(0, 'Kapittel én — så')]);
      final chapters = await M4bChapterReader.parseBuffer(data);
      expect(chapters.single.title, 'Kapittel én — så');
    });

    test('an audio-only file yields nothing', () async {
      final data = m4bWithChapterTrack(const [(0, 'X')], handler: 'soun');
      expect(await M4bChapterReader.parseBuffer(data), isEmpty);
    });

    test('an empty title falls back to "Chapter N"', () async {
      final data = m4bWithChapterTrack(const [(0, ''), (5000, '')]);
      final chapters = await M4bChapterReader.parseBuffer(data);
      expect(chapters.map((c) => c.title).toList(), ['Chapter 1', 'Chapter 2']);
    });

    test('a 64-bit co64 offset table works like stco', () async {
      final data = m4bWithChapterTrack(const [(0, 'Wide')], co64: true);
      final chapters = await M4bChapterReader.parseBuffer(data);
      expect(chapters.single.title, 'Wide');
    });

    test('samples split across two chunks are all found', () async {
      // stsc runs are where a naive reader silently drops the tail.
      final data = m4bWithChapterTrack(
          const [(0, 'A'), (1000, 'B'), (2000, 'C'), (3000, 'D')],
          chunkCount: 2);
      final chapters = await M4bChapterReader.parseBuffer(data);
      expect(chapters.map((c) => c.title).toList(), ['A', 'B', 'C', 'D']);
    });

    test('a truncated sample table does not throw', () async {
      final good = m4bWithChapterTrack(const [(0, 'A'), (1000, 'B')]);
      for (final cut in [good.length ~/ 2, good.length - 4, 12]) {
        final data = Uint8List.fromList(good.sublist(0, cut));
        expect(() async => M4bChapterReader.parseBuffer(data),
            returnsNormally);
      }
    });

    test('a chapter track with no samples yields nothing', () async {
      expect(await M4bChapterReader.parseBuffer(m4bWithChapterTrack(const [])),
          isEmpty);
    });
  });

  // ── diagnostics ────────────────────────────────────────────────────────────
  //
  // These notes are what a user pastes into a bug report, so they have to name
  // the actual dead end. "No chapters" on its own is the report we already
  // can't act on.

  group('diagnostics', () {
    test('a successful read says which form it came from', () async {
      final notes = <String>[];
      await M4bChapterReader.parseBuffer(
          m4bWithChapterTrack(const [(0, 'A')]), notes: notes);
      expect(notes.join(), contains('1 from a chapter track'));

      final chplNotes = <String>[];
      await M4bChapterReader.parseBuffer(
          m4bWithChpl(chplPayload([(0, 'A')])), notes: chplNotes);
      expect(chplNotes.join(), contains('1 from chpl'));
    });

    test('an audio-only file names the tracks it did see', () async {
      final notes = <String>[];
      await M4bChapterReader.parseBuffer(
          m4bWithChapterTrack(const [(0, 'X')], handler: 'soun'),
          notes: notes);
      expect(notes.join(), contains('no chapter track'));
      expect(notes.join(), contains('soun'),
          reason: 'a rejected handler is the likeliest cause, so name it');
    });

    test('a moov larger than the window says so', () async {
      // The failure that looks identical to every other one from the outside:
      // on a long book the audio track alone can outgrow the read window, so
      // the chapter data after it is never in the buffer.
      final full = m4bWithChapterTrack(const [(0, 'A'), (1000, 'B')]);
      final cut = Uint8List.fromList(full.sublist(0, 60));
      final notes = <String>[];
      expect(await M4bChapterReader.parseBuffer(cut, notes: notes), isEmpty);
      expect(notes.join(), contains('overruns'));
    });

    test('a file with no moov at all says that instead', () async {
      final notes = <String>[];
      await M4bChapterReader.parseBuffer(
          Uint8List.fromList(atom('ftyp', ascii.encode('M4B '))),
          notes: notes);
      expect(notes.single, contains('no moov'));
    });

    test('an unprintable handler fourcc cannot mangle the log', () async {
      final notes = <String>[];
      await M4bChapterReader.parseBuffer(
          m4bWithChapterTrack(const [(0, 'X')], handler: ' \nZ'),
          notes: notes);
      expect(notes.join(), contains('???Z'));
      expect(notes.join(), isNot(contains('\n')));
    });
  });
}
