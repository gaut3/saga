// Sync design build step 4: decideSync (rules 3–4), one row per case and per
// trap in the research's table.

import 'package:flutter_test/flutter_test.dart';
import 'package:saga/features/player/server_position.dart';
import 'package:saga/features/player/sync_decision.dart';

const _s = 1000;
const _min = 60 * _s;
final _tl = DateTime.utc(2026, 11, 13, 10);

/// Local place L at [lMs], saved at Tl; server place S at [sMs], heard
/// [heardAfterTl] after Tl.
SyncAction _decide(int lMs, int sMs, Duration heardAfterTl,
    {bool finished = false, bool erased = false}) {
  final ServerPosition server = (
    fileIndex: 0,
    positionMs: sMs,
    absoluteMs: sMs,
    at: _tl.add(heardAfterTl),
    offsetErased: erased,
  );
  return decideSync(
    local: (absoluteMs: lMs, savedAt: _tl),
    server: server,
    localFinished: finished,
  ).action;
}

void main() {
  test('Plex knows nothing: nothing to do', () {
    final d = decideSync(local: (absoluteMs: 5 * _min, savedAt: _tl), server: null);
    expect(d.action, SyncAction.same);
  });

  group('rule 3', () {
    test('within 10 s is the same place, however new', () {
      expect(_decide(60 * _min, 60 * _min + 9 * _s, const Duration(hours: 2)),
          SyncAction.same);
      expect(_decide(60 * _min, 60 * _min - 10 * _s, const Duration(hours: 2)),
          SyncAction.same);
    });

    test('newer by more than the margin and ahead: apply', () {
      // Listened further on another device.
      expect(_decide(60 * _min, 95 * _min, const Duration(minutes: 40)),
          SyncAction.apply);
    });

    test('newer by more than the margin and behind: ask', () {
      // Another device was rewound, or opened an old place.
      expect(_decide(60 * _min, 20 * _min, const Duration(minutes: 40)),
          SyncAction.ask);
    });

    test('local is newer: keep, whatever the distance', () {
      expect(_decide(60 * _min, 95 * _min, -const Duration(minutes: 40)),
          SyncAction.keep);
      expect(_decide(60 * _min, 20 * _min, -const Duration(minutes: 40)),
          SyncAction.keep);
    });
  });

  group('rule 4: the two clocks', () {
    test('newer by less than 60 s is not newer', () {
      expect(_decide(60 * _min, 95 * _min, const Duration(seconds: 60)),
          SyncAction.keep);
      expect(_decide(60 * _min, 95 * _min, const Duration(seconds: 61)),
          SyncAction.apply);
    });

    test('the server clock 50 s ahead of the phone does not make it win', () {
      // Clock skew (ABS; absorb 30 s, Cue 60 s): this phone's own report,
      // stamped by a fast server clock.
      expect(_decide(60 * _min, 59 * _min, const Duration(seconds: 50)),
          SyncAction.keep);
    });

    test('times compare as instants, whatever their time zone', () {
      // AntennaPod #7453: timestamps with no zone.
      final ServerPosition server = (
        fileIndex: 0,
        positionMs: 95 * _min,
        absoluteMs: 95 * _min,
        at: _tl.add(const Duration(minutes: 5)), // UTC
        offsetErased: false,
      );
      final d = decideSync(
          local: (absoluteMs: 60 * _min, savedAt: _tl.toLocal()),
          server: server);
      expect(d.action, SyncAction.apply);
    });
  });

  group('traps from the research', () {
    test("this phone's own report, seconds after its save: never a prompt", () {
      // The common case: Plex's stamp is our own report arriving a few
      // seconds after the save it carries.
      expect(_decide(60 * _min, 60 * _min - 30 * _s, const Duration(seconds: 3)),
          SyncAction.keep);
      expect(_decide(60 * _min, 60 * _min, const Duration(seconds: 3)),
          SyncAction.same);
    });

    test('a resume rewind that reached Plex anyway does not walk us back', () {
      // absorb ab74d7cc: re-saving a rewound place stamps it new. The gate
      // stops Saga sending it; if another client does, it's older here
      // only if it really is newer, and then it's a question, not a seek.
      expect(_decide(60 * _min, 59 * _min, const Duration(minutes: 5)),
          SyncAction.ask);
    });

    test('a cold-start report near 0 from another device is asked, not taken',
        () {
      // ABS #1940, absorb #383/#430: a default 0 reported before restore.
      expect(_decide(60 * _min, 20 * _s, const Duration(minutes: 5)),
          SyncAction.ask);
    });

    test('a finished book is never moved on its own', () {
      // ABS #1945, absorb a035adee: a sync must not clear a finish.
      expect(
          _decide(600 * _min, 300 * _min, const Duration(minutes: 5),
              finished: true),
          SyncAction.ask);
      expect(
          _decide(300 * _min, 400 * _min, const Duration(minutes: 5),
              finished: true),
          SyncAction.ask);
    });
  });

  group('a server place with no offset is a guess', () {
    test('newer and ahead, but the offset is gone: ask, never apply', () {
      // The other device is in the last tenth of file 3, or the library
      // keeps no offsets: "start of file 3" may be most of a file short.
      expect(_decide(60 * _min, 120 * _min, const Duration(hours: 2),
              erased: true),
          SyncAction.ask);
    });

    test('it changes nothing else', () {
      expect(_decide(60 * _min, 0, const Duration(hours: 2), erased: true),
          SyncAction.ask);
      expect(_decide(60 * _min, 120 * _min, const Duration(seconds: 30),
              erased: true),
          SyncAction.keep);
      expect(_decide(60 * _min, 60 * _min + 5 * _s, const Duration(hours: 2),
              erased: true),
          SyncAction.same);
    });
  });

  group('no local place', () {
    ServerPosition at(int ms) => (
          fileIndex: 0,
          positionMs: ms,
          absoluteMs: ms,
          at: _tl,
          offsetErased: false,
        );

    test('a fresh install takes the server place', () {
      expect(decideSync(local: null, server: at(95 * _min)).action,
          SyncAction.apply);
    });

    test('but not one within the first 10 s', () {
      expect(decideSync(local: null, server: at(5 * _s)).action,
          SyncAction.same);
    });
  });

  test('the reason says what it was decided from', () {
    final ServerPosition server = (
      fileIndex: 0,
      positionMs: 95 * _min,
      absoluteMs: 95 * _min,
      at: _tl.add(const Duration(minutes: 4, seconds: 10)),
      offsetErased: false,
    );
    final d = decideSync(
        local: (absoluteMs: 60 * _min, savedAt: _tl), server: server);
    expect(d.reason, 'Plex 35 min 0 s ahead, newer by 4 min 10 s');
  });
}
