import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:saga/core/book_status.dart';
import 'package:saga/core/storage/bookmark_store.dart';
import 'package:saga/core/storage/completed_books_store.dart';
import 'package:saga/core/storage/listening_history_store.dart';
import 'package:saga/core/storage/playback_log_store.dart';

import 'helpers/hive_test_env.dart';

const _hour = 3600000;

BookPosition _at(int absoluteMs, DateTime savedAt, {int? totalMs = 10 * _hour}) =>
    BookPosition(
      trackRatingKey: 't1',
      positionMs: absoluteMs,
      absolutePositionMs: absoluteMs,
      totalDurationMs: totalMs,
      savedAt: savedAt,
    );

/// "Finished" used to mean "ever finished", which hid every re-read from
/// Continue Listening, the resume card, Android Auto and session restore —
/// and the only way out, marking the book not finished, deleted its history.
void main() {
  final finished = DateTime(2026, 10, 1, 20, 0);

  group('isFinishedNow', () {
    bool finishedWith({
      DateTime? completed,
      DateTime? reopened,
      BookPosition? saved,
      DateTime? played,
    }) =>
        isFinishedNow(
          lastCompletion: completed,
          reopenedAt: reopened,
          saved: saved,
          lastPlayAt: played,
        );

    test('never completed is not finished', () {
      expect(finishedWith(), isFalse);
    });

    test('played again after finishing, mid-book, is not finished', () {
      expect(
          finishedWith(
            completed: finished,
            saved: _at(2 * _hour, DateTime(2026, 10, 20)),
            played: DateTime(2026, 10, 20),
          ),
          isFalse);
    });

    test('a save after finishing without a play stays finished', () {
      // The first version keyed on the save time; the player also saves when
      // the app goes to the background, paused or not, so a book marked
      // finished while loaded in the player came straight back.
      expect(
          finishedWith(
            completed: finished,
            saved: _at(4 * _hour, finished.add(const Duration(hours: 3))),
            played: finished.subtract(const Duration(days: 1)),
          ),
          isTrue);
    });

    test("a finish's own end-of-book position stays finished, even played", () {
      // Pressing play on a finished book at its end completes it again.
      expect(
          finishedWith(
            completed: finished,
            saved: _at(10 * _hour, finished.add(const Duration(minutes: 5))),
            played: finished.add(const Duration(minutes: 5)),
          ),
          isTrue);
    });

    test('an undated (pre-tracking) finish ignores plays', () {
      // Epoch 0 = finished before per-finish dates were kept: every play in
      // the log is "after" it, including the original listen.
      expect(
          finishedWith(
            completed: DateTime.fromMillisecondsSinceEpoch(0),
            saved: _at(3 * _hour, DateTime(2026, 9, 1)),
            played: DateTime(2026, 9, 1),
          ),
          isTrue);
    });

    test('an undated finish can still be marked not finished', () {
      expect(
          finishedWith(
            completed: DateTime.fromMillisecondsSinceEpoch(0),
            reopened: DateTime(2026, 10, 25),
          ),
          isFalse);
    });

    test('marked not finished after the last completion is not finished', () {
      expect(
          finishedWith(
              completed: finished,
              reopened: finished.add(const Duration(days: 1))),
          isFalse);
    });

    test('finished again after being reopened is finished', () {
      expect(
          finishedWith(
              completed: finished,
              reopened: finished.subtract(const Duration(days: 1))),
          isTrue);
    });
  });

  group('stores', () {
    late Directory dir;

    setUp(() async {
      dir = await startHiveTestEnv();
      await CompletedBooksStore.init(testEncKey);
      await BookmarkStore.init(testEncKey);
      await ListeningHistoryStore.init(testEncKey);
      await PlaybackLogStore.init(testEncKey);
    });

    tearDown(() => stopHiveTestEnv(dir));

    test('marking not finished takes back only the latest finish', () async {
      await CompletedBooksStore.markCompleted('42');
      await CompletedBooksStore.markCompleted('42');
      await CompletedBooksStore.markIncomplete('42');

      expect(isBookFinished('42'), isFalse);
      expect(CompletedBooksStore.completionCount('42'), 1);
      expect(CompletedBooksStore.allCompleted(), {'42'});
    });

    test('a mistaken mark can be fully undone', () async {
      await CompletedBooksStore.markCompleted('42');
      await CompletedBooksStore.markIncomplete('42');

      expect(isBookFinished('42'), isFalse);
      expect(CompletedBooksStore.isCompleted('42'), isFalse);
      expect(CompletedBooksStore.allCompleted(), isEmpty);
    });

    test('toggling finished, not, finished counts one listen', () async {
      await CompletedBooksStore.markCompleted('42');
      await CompletedBooksStore.markIncomplete('42');
      await CompletedBooksStore.markCompleted('42');

      expect(CompletedBooksStore.completionCount('42'), 1);
      expect(isBookFinished('42'), isTrue);
    });

    test('the reopen marker is never mistaken for a book', () async {
      await CompletedBooksStore.markCompleted('42');
      await CompletedBooksStore.markCompleted('42');
      await CompletedBooksStore.markIncomplete('42');
      await coldRestartHive();
      await CompletedBooksStore.init(testEncKey);

      expect(CompletedBooksStore.allCompleted(), {'42'});
      expect(CompletedBooksStore.exportAll().keys, ['42']);
      expect(CompletedBooksStore.reopenedAt('42'), isNotNull);
    });

    test('finishing again clears the reopen', () async {
      await CompletedBooksStore.markCompleted('42');
      await CompletedBooksStore.markCompleted('42');
      await CompletedBooksStore.markIncomplete('42');
      await CompletedBooksStore.markCompleted('42');

      expect(isBookFinished('42'), isTrue);
      expect(CompletedBooksStore.reopenedAt('42'), isNull);
    });

    test('finishedBookKeys leaves out a re-read in progress', () async {
      await CompletedBooksStore.markCompleted('done');
      await CompletedBooksStore.markCompleted('again');
      final later = DateTime.now().add(const Duration(minutes: 5));
      await BookmarkStore.save('again', _at(_hour, later));
      PlaybackLogStore.log(
        bookRatingKey: 'again',
        event: AudioLogEvent(
            type: 'play', trackRatingKey: 't1', positionMs: 0, timestamp: later),
      );

      expect(finishedBookKeys(), {'done'});
    });

    test('a hand-marked finish reaches the day record', () async {
      await recordBookFinished(ratingKey: '42', title: 'Dune Messiah');

      final today = ListeningHistoryStore.getCompleted(DateTime.now());
      expect(today.map((b) => b.ratingKey), ['42']);
      expect(CompletedBooksStore.isCompleted('42'), isTrue);
    });
  });
}
