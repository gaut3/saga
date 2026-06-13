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
}
