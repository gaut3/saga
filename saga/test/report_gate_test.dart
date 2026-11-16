// Rule 5 of the position-sync design: Saga reports to Plex only positions the
// listener reached. The gate's rules are tested directly; the wiring in the
// player is pinned against the source, as architecture_test.dart does,
// because the service needs a real player to run.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:saga/core/storage/bookmark_store.dart';
import 'package:saga/features/player/book_launch.dart';
import 'package:saga/features/player/report_gate.dart';

const _s = 1000;
const _min = 60 * _s;
int _t(int h, int m, int s) => ((h * 60 + m) * 60 + s) * _s;

void main() {
  group('ReportGate', () {
    test('a cold start sends nothing before a book loads', () {
      final gate = ReportGate();
      expect(gate.allows(0), isFalse);
      expect(gate.allows(10 * _min), isFalse);
      expect(gate.heldUntilMs, isNull);
    });

    test('a load sends nothing at the loaded spot', () {
      final gate = ReportGate()..load(60 * _min);
      // A paused or lifecycle save right after opening the book.
      expect(gate.allows(60 * _min), isFalse);
      expect(gate.heldUntilMs, 60 * _min);
    });

    test('playback past the loaded spot opens it, and it stays open', () {
      final gate = ReportGate()..load(60 * _min);
      expect(gate.allows(60 * _min + 10 * _s), isTrue);
      expect(gate.isOpen, isTrue);
      // Later saves anywhere, until the next load or rewind.
      expect(gate.allows(60 * _min + 20 * _s), isTrue);
    });

    test('a resume rewind sends nothing until the pre-rewind spot is passed',
        () {
      // Opened at 4:04, rewound to 3:38 (Prologue's case): the ticks in
      // between are the listener re-hearing, not moving.
      final gate = ReportGate()..load(4 * _min + 4 * _s);
      expect(gate.allows(3 * _min + 48 * _s), isFalse);
      expect(gate.allows(3 * _min + 58 * _s), isFalse);
      expect(gate.allows(4 * _min + 4 * _s), isFalse);
      expect(gate.allows(4 * _min + 8 * _s), isTrue);
    });

    test('an in-session rewind holds an open gate until it is passed again',
        () {
      final gate = ReportGate()
        ..load(0)
        ..allows(30 * _min); // listening
      expect(gate.isOpen, isTrue);
      gate.rewound(30 * _min); // paused at 30:00, back after a while
      expect(gate.allows(29 * _min + 40 * _s), isFalse);
      expect(gate.allows(30 * _min + 1 * _s), isTrue);
    });

    test('a rewind never lowers the hold a load set', () {
      final gate = ReportGate()..load(60 * _min);
      gate.rewound(59 * _min + 50 * _s);
      expect(gate.heldUntilMs, 60 * _min);
      expect(gate.allows(59 * _min + 55 * _s), isFalse);
    });

    test('a move of the listener\'s own opens it at once, anywhere', () {
      final gate = ReportGate()..load(60 * _min);
      gate.moved();
      expect(gate.allows(10 * _min), isTrue);
      expect(gate.heldUntilMs, isNull);
    });

    test('a reload keeps the hold its place was saved under', () {
      // The 2026-11-13 dogfood: opened at 6:56:21, rewound, paused at 6:56:04
      // before getting back past the hold, app restarted. Holding at the
      // saved 6:56:04 opened reports 17 s behind what Plex already had.
      final gate = ReportGate()
        ..load(_t(6, 56, 4), savedHoldMs: _t(6, 56, 21));
      expect(gate.heldUntilMs, _t(6, 56, 21));
      expect(gate.allows(_t(6, 56, 14)), isFalse);
      expect(gate.allows(_t(6, 56, 24)), isTrue);
    });

    test('a saved hold behind the loaded place changes nothing', () {
      final gate = ReportGate()..load(_t(1, 0, 0), savedHoldMs: _t(0, 59, 0));
      expect(gate.heldUntilMs, _t(1, 0, 0));
    });

    test('the next load holds it again', () {
      final gate = ReportGate()..moved();
      gate.load(5 * _min);
      expect(gate.allows(5 * _min), isFalse);
    });
  });

  group('BookPosition.reportHoldMs', () {
    final at = DateTime(2026, 11, 13, 10, 28);
    test('survives a round trip, and is absent when the place was reported',
        () {
      final held = BookPosition(
          trackRatingKey: 't',
          positionMs: 5,
          absolutePositionMs: 5,
          savedAt: at,
          reportHoldMs: 900);
      expect(BookPosition.fromMap(held.toMap()).reportHoldMs, 900);
      final sent = BookPosition(
          trackRatingKey: 't', positionMs: 5, absolutePositionMs: 5, savedAt: at);
      expect(sent.toMap().containsKey('reportHoldMs'), isFalse);
      expect(BookPosition.fromMap(sent.toMap()).reportHoldMs, isNull);
    });

    test('a negative hold from a hand-edited backup is dropped', () {
      final map = {
        'trackRatingKey': 't',
        'positionMs': 5,
        'savedAt': at.toIso8601String(),
        'reportHoldMs': -1.0,
      };
      expect(BookPosition.fromMap(map).reportHoldMs, isNull);
    });
  });

  group('BookStartPoint.isChosen', () {
    test('resume and the beginning are not moves; explicit points are', () {
      expect(const BookStartPoint.resume().isChosen, isFalse);
      expect(const BookStartPoint.beginning().isChosen, isFalse);
      expect(const BookStartPoint.atTrack('t1').isChosen, isTrue);
      expect(const BookStartPoint.atTrackIndex(2).isChosen, isTrue);
    });
  });

  group('the player wires the gate', () {
    final src = File('lib/features/player/player_service.dart')
        .readAsLinesSync()
        .where((l) => !l.trimLeft().startsWith('//'))
        .join('\n');

    String body(String signature) {
      final start = src.indexOf(signature);
      expect(start, isNot(-1), reason: '$signature not found');
      return src.substring(start, src.indexOf('\n  }\n', start));
    }

    test('the local save runs whatever the gate says', () {
      // The gate wraps the reportTimeline call only. A held report costs
      // nothing; a skipped save loses a place. It is asked before the save
      // so the place carries its hold, and only consulted after it.
      final save = body('Future<void> _saveAndReportPosition(');
      final asked = save.indexOf('_reportGate.allows(');
      final stored = save.indexOf('await BookmarkStore.save(');
      final held = save.indexOf('if (!reportAllowed || repeat) return;');
      final report = save.indexOf('_api.reportTimeline(');
      expect(asked, isNot(-1));
      expect(stored, greaterThan(asked));
      expect(held, greaterThan(stored));
      expect(report, greaterThan(held));
      expect(save.substring(stored, held).contains('reportHoldMs:'), isTrue,
          reason: 'a held place is saved with its hold');
      expect(save.substring(stored, held).contains('isRepeatReport('), isTrue,
          reason: 'a report that says nothing new is not sent');
    });

    test('every report to Plex from the player passes the gate', () {
      // The other call is the offline queue's replay (rule 6), which only
      // ever holds reports the gate already let out.
      expect('_api.reportTimeline('.allMatches(src).length, 2);
      expect(body('Future<void> _flushTimelineQueue(')
          .contains('_api.reportTimeline('), isTrue);
    });

    test('each move of the listener\'s own opens the gate', () {
      for (final sig in [
        'Future<void> seek(Duration position)',
        'Future<void> skipToNext()',
        'Future<void> skipToPrevious()',
        'Future<void> skipToQueueItem(int index)',
        'Future<void> undoSeek()',
        'Future<void> seekAbsolute(Duration absolutePosition)',
      ]) {
        expect(body(sig).contains('_listenerMoved()'), isTrue, reason: sig);
      }
    });

    test('the resume rewind in play() holds the gate', () {
      expect(body('Future<void> play()').contains('_reportGate.rewound('),
          isTrue);
    });
  });
}
