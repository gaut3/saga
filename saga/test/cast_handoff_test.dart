import 'package:flutter_test/flutter_test.dart';
import 'package:saga/core/cast/cast_service.dart';

/// The handoff is what makes a cast position mean anything: it names the book
/// and, per queue item, the track and where that track starts in the book. It
/// is persisted, so a session the Cast SDK resumes after a relaunch (or an app
/// update) still writes back to the right place.
void main() {
  const twoFiles = CastHandoff(
    bookRatingKey: '12345',
    tracks: [
      (trackRatingKey: '67890', startMs: 0),
      (trackRatingKey: '67891', startMs: 3600000),
    ],
    totalDurationMs: 7200000,
  );

  test('round-trips every queued track', () {
    final back = CastHandoff.tryParse(twoFiles.serialize())!;
    expect(back.bookRatingKey, '12345');
    expect(back.tracks, twoFiles.tracks);
    expect(back.totalDurationMs, 7200000);
  });

  test('round-trips a null total duration', () {
    const h = CastHandoff(
      bookRatingKey: '12345',
      tracks: [(trackRatingKey: '67890', startMs: 0)],
    );
    expect(CastHandoff.tryParse(h.serialize())!.totalDurationMs, isNull);
  });

  test('still reads a v1 handoff written before the queue', () {
    // A cast running across the upgrade: its stored handoff is v1, and its
    // writeback must keep landing on the same track (cardinal sin).
    final h = CastHandoff.tryParse('12345|67891|3600000|7200000')!;
    expect(h.bookRatingKey, '12345');
    expect(h.tracks, [(trackRatingKey: '67891', startMs: 3600000)]);
    expect(h.totalDurationMs, 7200000);
    expect(h.positionAt(0, 60000)!.absoluteMs, 3660000);
  });

  test('maps a queue item and its offset to a place in the book', () {
    final first = twoFiles.positionAt(0, 1000)!;
    expect(first.trackRatingKey, '67890');
    expect(first.absoluteMs, 1000);

    // The second file, i.e. across a file boundary. absorb sent absolute
    // positions to a file-relative receiver and skips jumped a chapter (#273).
    final second = twoFiles.positionAt(1, 30000)!;
    expect(second.trackRatingKey, '67891');
    expect(second.positionMs, 30000);
    expect(second.absoluteMs, 3630000);
  });

  test('an unknown queue item maps to nothing, never to another track', () {
    expect(twoFiles.positionAt(2, 1000), isNull);
    expect(twoFiles.positionAt(-1, 1000), isNull);
    // A negative device position (seen as -1 before the first status) is 0.
    expect(twoFiles.positionAt(0, -1)!.positionMs, 0);
  });

  test('rejects malformed values instead of half-parsing them', () {
    expect(CastHandoff.tryParse(''), isNull);
    expect(CastHandoff.tryParse('12345'), isNull);
    expect(CastHandoff.tryParse('12345|67890'), isNull);
    expect(CastHandoff.tryParse('|67890|0|'), isNull); // empty book key
    expect(CastHandoff.tryParse('12345||0|'), isNull); // empty track key
    expect(CastHandoff.tryParse('12345|67890|notanumber|'), isNull);
    expect(CastHandoff.tryParse('a|b|c|d|e'), isNull); // too many parts
    expect(CastHandoff.tryParse('v2|12345||'), isNull); // no tracks
    expect(CastHandoff.tryParse('v2|12345||67890'), isNull); // no start
    expect(CastHandoff.tryParse('v2|12345||67890:x'), isNull);
    expect(CastHandoff.tryParse('v2|12345||67890:-5'), isNull);
    expect(CastHandoff.tryParse('v2|12345||:0'), isNull);
  });
}
