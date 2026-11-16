// Sync design build step 3: which file Plex says you're in (rule 2), from
// the cases the 2026-11-12 probe found.

import 'package:flutter_test/flutter_test.dart';
import 'package:saga/features/player/server_position.dart';

const _min = 60 * 1000;
final _t0 = DateTime.utc(2026, 11, 12, 12);
DateTime _at(int seconds) => _t0.add(Duration(seconds: seconds));

ServerFileProgress _f(int durationMin, {int? offsetMs, int? seenAt}) => (
      durationMs: durationMin * _min,
      viewOffsetMs: offsetMs,
      lastViewedAt: seenAt == null ? null : _at(seenAt),
    );

void main() {
  test('a single file: its offset', () {
    final p = resolveServerPosition([_f(1260, offsetMs: 300 * _min, seenAt: 0)])!;
    expect(p.fileIndex, 0);
    expect(p.positionMs, 300 * _min);
    expect(p.absoluteMs, 300 * _min);
    expect(p.at, _at(0));
    expect(p.offsetErased, isFalse);
  });

  test('stale offsets on files left behind lose to the newest file', () {
    // The probe's 54-file book: file 1 at 50%, then file 2 at 10%. File 1
    // keeps its 50%, three seconds older.
    final p = resolveServerPosition([
      _f(20, offsetMs: 10 * _min, seenAt: 0),
      _f(20, offsetMs: 2 * _min, seenAt: 3),
      _f(20),
    ])!;
    expect(p.fileIndex, 1);
    expect(p.positionMs, 2 * _min);
    expect(p.absoluteMs, 22 * _min);
  });

  test('a rewind into an earlier file: the newest wins, not the highest', () {
    final p = resolveServerPosition([
      _f(20, offsetMs: 15 * _min, seenAt: 60),
      _f(20, offsetMs: 2 * _min, seenAt: 0),
    ])!;
    expect(p.fileIndex, 0);
    expect(p.absoluteMs, 15 * _min);
  });

  test('a tie in the same second goes to the later file', () {
    final p = resolveServerPosition([
      _f(20, offsetMs: 19 * _min, seenAt: 5),
      _f(20, offsetMs: 1 * _min, seenAt: 5),
    ])!;
    expect(p.fileIndex, 1);
    expect(p.absoluteMs, 21 * _min);
  });

  test('the newest file with no offset: its start', () {
    // A report under a minute erased it (0:30 → viewOffset gone).
    final p = resolveServerPosition([
      _f(20, offsetMs: 12 * _min, seenAt: 0),
      _f(20, seenAt: 30),
    ])!;
    expect(p.fileIndex, 1);
    expect(p.positionMs, 0);
    expect(p.absoluteMs, 20 * _min);
    expect(p.offsetErased, isTrue);
  });

  test('an offset with no lastViewedAt is ignored', () {
    final p = resolveServerPosition([
      _f(20, offsetMs: 12 * _min),
      _f(20, offsetMs: 3 * _min, seenAt: 0),
    ])!;
    expect(p.fileIndex, 1);
  });

  test('no file with a lastViewedAt: the server knows nothing', () {
    expect(resolveServerPosition([_f(20, offsetMs: 5 * _min), _f(20)]), isNull);
    expect(resolveServerPosition(const []), isNull);
  });

  test('an offset past the end of its file is no information', () {
    expect(
        resolveServerPosition([_f(20, offsetMs: 21 * _min, seenAt: 0)]), isNull);
    // A file Plex never analysed (no duration) still resolves.
    expect(resolveServerPosition([_f(0, offsetMs: 5 * _min, seenAt: 0)])!
        .positionMs, 5 * _min);
  });
}
