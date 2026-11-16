// Sync design build step 5: the dark flag, and the shadow check that reads
// and logs on in-app opens and plays only.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:saga/core/sync/sync_mode.dart';

String _code(String path) => File(path)
    .readAsLinesSync()
    .where((l) => !l.trimLeft().startsWith('//') && !l.trimLeft().startsWith('///'))
    .join('\n');

String _body(String src, String signature) {
  final start = src.indexOf(signature);
  expect(start, isNot(-1), reason: '$signature not found');
  return src.substring(start, src.indexOf('\n  }\n', start));
}

void main() {
  group('effectiveSyncMode', () {
    test('a release build never syncs, whatever is stored', () {
      // § Shipping dark: the beta notes may say how to turn shadow on, and a
      // public changelog makes "hidden" mean "documented".
      for (var i = -1; i <= SyncMode.values.length; i++) {
        expect(effectiveSyncMode(prerelease: false, storedIndex: i),
            SyncMode.off,
            reason: 'stored $i');
      }
    });

    test('a beta or dev build uses the stored mode', () {
      for (final m in SyncMode.values) {
        expect(effectiveSyncMode(prerelease: true, storedIndex: m.index), m);
      }
    });

    test('a stored value out of range is off', () {
      expect(effectiveSyncMode(prerelease: true, storedIndex: 7), SyncMode.off);
      expect(effectiveSyncMode(prerelease: true, storedIndex: -1), SyncMode.off);
    });
  });

  group('measureSkew', () {
    final sent = DateTime.utc(2026, 11, 13, 12);
    test('against the middle of the request', () {
      expect(
          measureSkew(
              sentAt: sent,
              receivedAt: sent.add(const Duration(seconds: 2)),
              serverDate: sent.add(const Duration(seconds: 31))),
          const Duration(seconds: 30));
    });

    test('a server clock behind the phone is negative', () {
      expect(
          measureSkew(
              sentAt: sent,
              receivedAt: sent,
              serverDate: sent.subtract(const Duration(seconds: 45))),
          const Duration(seconds: -45));
    });
  });

  group('the shadow check', () {
    test('can read and log, and reach nothing that moves a place', () {
      final src = _code('lib/features/player/sync_check.dart');
      for (final banned in [
        'BookmarkStore',
        'seek',
        'loadBook',
        'startBook',
        'reportTimeline',
        'player_service.dart',
      ]) {
        expect(src.contains(banned), isFalse, reason: 'sync_check uses $banned');
      }
    });

    test('runs only on in-app resumes and plays (rule 1)', () {
      final service = _code('lib/features/player/player_service.dart');
      // A headset, notification or widget play is play(): it never checks.
      expect(_body(service, 'Future<void> play() async').contains('_syncPlaceFor('),
          isFalse);
      expect(_body(service, 'Future<void> playFromApp()').contains('_syncPlaceFor('),
          isTrue);
      // The widget resumes without inApp.
      final widget = _body(service, 'Future<dynamic> customAction(');
      expect(widget.contains('resumeBook(book)'), isTrue);
      expect(widget.contains('inApp'), isFalse);

      final launch = _code('lib/features/player/book_launch.dart');
      expect(launch.contains('inApp && (from.isResume || startsOver)'), isTrue);
      expect(_code('lib/features/player/open_player.dart').contains('inApp: true'),
          isTrue);
      for (final f in [
        'lib/features/player/player_screen.dart',
        'lib/shared/widgets/mini_player_pill.dart',
      ]) {
        expect(_code(f).contains('playFromApp'), isTrue, reason: f);
      }
    });
  });

  group('live', () {
    final service = _code('lib/features/player/player_service.dart');

    test('takes a place only into a paused player, never mid-load (rule 7)',
        () {
      final play = _body(service, 'Future<void> playFromApp()');
      final take = play.indexOf('_takeServerPlace(');
      final guard = play.lastIndexOf('!_isPlaying &&', take);
      expect(take, isNot(-1));
      expect(guard, isNot(-1), reason: 'checked again after the wait');
      expect(play.substring(guard, take).contains('!_loadInProgress'), isTrue);
    });

    test("Plex's place holds reports and gets no resume rewind", () {
      final take = _body(service, 'Future<void> _takeServerPlace(');
      expect(take.contains('_reportGate.load('), isTrue);
      expect(take.contains('_pausedAt = null'), isTrue);
      expect(take.indexOf('_saveAndReportPosition('),
          greaterThan(take.indexOf('_reportGate.load(')),
          reason: 'saved with its hold, so a kill keeps it');
    });

    test("a launch at Plex's place saves it straight after the load", () {
      // Home's card read the old place: a load saves nothing.
      final launch = _code('lib/features/player/book_launch.dart');
      final load = launch.indexOf('await service.loadBook(');
      final save = launch.indexOf('await service.saveSyncedPlace();');
      expect(save, greaterThan(load));
    });

    test('Undo is a move of the listener\'s own, so it is reported (rule 9)',
        () {
      expect(_body(service, 'void announceSyncApplied(').contains('undo: undoSeek'),
          isTrue);
      expect(_body(service, 'Future<void> undoSeek()').contains('_listenerMoved()'),
          isTrue);
    });

    test('a finished book: Listen again checks too, and "finished" is now',
        () {
      // Rule 8: finished here, listened to elsewhere since.
      final launch = _code('lib/features/player/book_launch.dart');
      expect(
          launch.contains(
              'final startsOver = from.isBeginning && isBookFinished(bookRatingKey);'),
          isTrue);
      expect(launch.contains('inApp && (from.isResume || startsOver)'), isTrue);
      // Finished until picked up again: "ever finished" would ask forever.
      final sync = _body(service, 'Future<({ServerPosition server');
      expect(sync.contains('isBookFinished(bookKey)'), isTrue);
      expect(sync.contains('CompletedBooksStore.isCompleted'), isFalse);
    });

    test('a stopped or finished player loads at Plex\'s place, not seeks', () {
      // play() reloads such a player (from the start, for a finished book),
      // which would lose a seek.
      final play = _body(service, 'Future<void> playFromApp()');
      final branch = play.indexOf('if (replay || stopped)');
      expect(branch, isNot(-1));
      expect(play.indexOf('BookStartPoint.synced(', branch), greaterThan(branch));
      expect(play.indexOf('saveSyncedPlace()', branch), greaterThan(branch));
    });

    test('an answer after audio started is offered, and moves only on a yes',
        () {
      final sync = _body(service, 'Future<({ServerPosition server');
      expect('_offerAfterStart('.allMatches(sync).length, 2,
          reason: 'both the no-wait and the late answer are offered');
      final offer = _body(service, 'Future<void> _offerAfterStart(');
      final asked = offer.indexOf('await offer(');
      final yes = offer.indexOf('if (jump != true');
      final move = offer.indexOf('_takeServerPlace(');
      expect(asked, isNot(-1));
      expect(yes, greaterThan(asked));
      expect(move, greaterThan(yes));
      expect(offer.contains('_offerWindow'), isTrue,
          reason: 'a stale answer is not offered');
    });

    test('a downloaded book about to play never waits (rule 1)', () {
      final sync = _body(service, 'Future<({ServerPosition server');
      expect(sync.contains('final wait = live && !(downloaded && startsAudio);'),
          isTrue);
      expect(sync.contains('check.timeout(syncWaitLimit'), isTrue);
    });
  });
}
