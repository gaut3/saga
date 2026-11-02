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
    loadId: '1762000000000-1',
  );

  test('round-trips every queued track and the load id', () {
    final back = CastHandoff.tryParse(twoFiles.serialize())!;
    expect(back.bookRatingKey, '12345');
    expect(back.tracks, twoFiles.tracks);
    expect(back.totalDurationMs, 7200000);
    expect(back.loadId, '1762000000000-1');
  });

  test('still reads a v2 handoff written before load ids', () {
    final h = CastHandoff.tryParse('v2|12345|7200000|67890:0,67891:3600000')!;
    expect(h.tracks, twoFiles.tracks);
    expect(h.loadId, isNull);
  });

  test('knows each item\'s length, the last one from the total', () {
    expect(twoFiles.itemDurationMs(0), 3600000);
    expect(twoFiles.itemDurationMs(1), 3600000);
    expect(twoFiles.itemDurationMs(2), isNull);
    const noTotal = CastHandoff(
      bookRatingKey: '1',
      tracks: [(trackRatingKey: 'a', startMs: 0)],
    );
    expect(noTotal.itemDurationMs(0), isNull);
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

  group('which receiver statuses may move the saved place', () {
    final t0 = DateTime(2026, 11, 2, 20);
    CastStatus status(CastPlayerState state,
            {int item = 1,
            int pos = 600000,
            String load = '1762000000000-1',
            String idle = 'none'}) =>
        CastStatus(
          state: state,
          item: item,
          positionMs: pos,
          loadId: load,
          idleReason: idle,
          receivedAt: t0,
        );

    test('nothing counts until the receiver has played or paused', () {
      // While it loads, and on its first buffering report, a receiver
      // reports the item's start, not where the load asked it to begin.
      final t = CastPositionTracker(twoFiles);
      expect(t.accept(status(CastPlayerState.loading, pos: 0)), isNull);
      expect(t.accept(status(CastPlayerState.buffering, pos: 0)), isNull);
      expect(t.last, isNull);
      expect(t.accept(status(CastPlayerState.playing)),
          (item: 1, positionMs: 600000));
      // Settled: buffering mid-play is a real place now.
      expect(t.accept(status(CastPlayerState.buffering, pos: 601000)),
          (item: 1, positionMs: 601000));
    });

    test('a status from another load never counts', () {
      // Switching books mid-cast: the old queue keeps playing until the new
      // one lands, and its item 1 at 10:00 is not the new book's.
      final t = CastPositionTracker(twoFiles);
      expect(t.accept(status(CastPlayerState.playing, load: 'old')), isNull);
      expect(t.accept(status(CastPlayerState.playing, load: '')), isNull);
      expect(t.last, isNull);
    });

    test('a handoff from before load ids takes statuses as they come', () {
      const legacy = CastHandoff(
        bookRatingKey: '12345',
        tracks: [(trackRatingKey: '67890', startMs: 0)],
        totalDurationMs: 3600000,
      );
      final t = CastPositionTracker(legacy);
      expect(t.accept(status(CastPlayerState.paused, item: 0, load: '')),
          (item: 0, positionMs: 600000));
    });

    test('idle, unknown items and impossible positions keep the last place',
        () {
      final t = CastPositionTracker(twoFiles);
      t.accept(status(CastPlayerState.playing));
      expect(t.accept(status(CastPlayerState.idle, pos: 0, idle: 'error')),
          isNull);
      expect(t.accept(status(CastPlayerState.playing, item: -1)), isNull);
      expect(t.accept(status(CastPlayerState.playing, item: 2)), isNull);
      expect(t.accept(status(CastPlayerState.playing, pos: -5)), isNull);
      // Past the item's end by more than the slack.
      expect(t.accept(status(CastPlayerState.playing, pos: 3700000)), isNull);
      expect(t.last, (item: 1, positionMs: 600000));
    });

    test('parses a native status and moves the position on while playing',
        () {
      final s = CastStatus.fromMap({
        'state': 'playing',
        'idleReason': 'none',
        'item': 1,
        'load': '1762000000000-1',
        'positionMs': 1000,
        'rate': 1.5,
        'deviceVolume': 0.4,
      }, now: t0)!;
      expect(s.state, CastPlayerState.playing);
      expect(s.item, 1);
      expect(s.deviceVolume, 0.4);
      expect(s.positionNowMs(t0.add(const Duration(seconds: 2))), 4000);
      expect(CastStatus.fromMap('nonsense'), isNull);
      expect(CastStatus.fromMap({'state': 'what'})!.state,
          CastPlayerState.unknown);
      expect(
          CastStatus.fromMap({'state': 'idle', 'idleReason': 'finished'})!
              .finished,
          isTrue);
    });
  });
}
