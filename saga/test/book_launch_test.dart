import 'package:flutter_test/flutter_test.dart';
import 'package:saga/core/storage/bookmark_store.dart';
import 'package:saga/features/player/book_launch.dart';

void main() {
  // A four-file book.
  const keys = ['t1', 't2', 't3', 't4'];

  BookPosition saved(String trackKey, int positionMs) => BookPosition(
        trackRatingKey: trackKey,
        positionMs: positionMs,
        absolutePositionMs: positionMs,
        savedAt: DateTime(2026, 8, 1),
      );

  group('resume', () {
    test('lands on the saved track and position, with the rewind', () {
      expect(
        resolveBookStart(
          start: const BookStartPoint.resume(),
          trackRatingKeys: keys,
          saved: saved('t3', 12345),
        ),
        (trackIndex: 2, positionMs: 12345, applyResumeRewind: true),
      );
    });

    test('an unstarted book begins at the start, without a rewind', () {
      expect(
        resolveBookStart(
          start: const BookStartPoint.resume(),
          trackRatingKeys: keys,
          saved: null,
        ),
        (trackIndex: 0, positionMs: 0, applyResumeRewind: false),
      );
    });

    test('a saved position whose track is gone falls back to the start', () {
      // Re-imported book: every rating key changed. Resume is what was asked
      // for, so the start of the book beats refusing to play.
      expect(
        resolveBookStart(
          start: const BookStartPoint.resume(),
          trackRatingKeys: keys,
          saved: saved('gone', 9999),
        ),
        (trackIndex: 0, positionMs: 0, applyResumeRewind: false),
      );
    });
  });

  group('beginning', () {
    test('start of the book, no rewind, saved position ignored', () {
      expect(
        resolveBookStart(
          start: const BookStartPoint.beginning(),
          trackRatingKeys: keys,
          saved: saved('t3', 12345),
        ),
        (trackIndex: 0, positionMs: 0, applyResumeRewind: false),
      );
    });
  });

  group('atTrack', () {
    test('resolves the key to its index and never rewinds', () {
      // An explicit jump — a bookmark, a history entry — has to land exactly
      // where it was told, so the resume rewind must not apply.
      expect(
        resolveBookStart(
          start: const BookStartPoint.atTrack('t2', positionMs: 60000),
          trackRatingKeys: keys,
          saved: saved('t4', 1),
        ),
        (trackIndex: 1, positionMs: 60000, applyResumeRewind: false),
      );
    });

    test('refuses a track this book does not have', () {
      // Null, not "track 0, position 0": the hand-rolled call sites fell
      // through to the start of the book, silently losing the listener's place.
      expect(
        resolveBookStart(
          start: const BookStartPoint.atTrack('nope'),
          trackRatingKeys: keys,
          saved: saved('t2', 5000),
        ),
        isNull,
      );
    });
  });

  group('atTrackIndex', () {
    test('passes the index through and never rewinds', () {
      expect(
        resolveBookStart(
          start: const BookStartPoint.atTrackIndex(3, positionMs: 250),
          trackRatingKeys: keys,
          saved: null,
        ),
        (trackIndex: 3, positionMs: 250, applyResumeRewind: false),
      );
    });

    test('refuses an out-of-range index', () {
      expect(
        resolveBookStart(
          start: const BookStartPoint.atTrackIndex(4),
          trackRatingKeys: keys,
          saved: null,
        ),
        isNull,
      );
      expect(
        resolveBookStart(
          start: const BookStartPoint.atTrackIndex(-1),
          trackRatingKeys: keys,
          saved: null,
        ),
        isNull,
      );
    });
  });

  group('a saved place whose track is not in the list', () {
    final saved = BookPosition(
      trackRatingKey: 'gone',
      positionMs: 30000,
      absolutePositionMs: 630000,
      savedAt: DateTime(2026, 1, 1),
    );

    test('resumes at the same time into the book', () {
      expect(
        resolveBookStart(
          start: const BookStartPoint.resume(),
          trackRatingKeys: const ['a', 'b', 'c'],
          saved: saved,
          trackDurationsMs: const [600000, 1200000, 900000],
        ),
        (trackIndex: 1, positionMs: 30000, applyResumeRewind: true),
      );
    });

    test('starts over only when the lengths cannot place it', () {
      const fromScratch =
          (trackIndex: 0, positionMs: 0, applyResumeRewind: false);
      // A file of unknown length, no lengths at all, a place past the end.
      for (final durations in const [
        [600000, 0, 900000],
        <int>[],
        [100000, 100000, 100000],
      ]) {
        expect(
          resolveBookStart(
            start: const BookStartPoint.resume(),
            trackRatingKeys: const ['a', 'b', 'c'],
            saved: saved,
            trackDurationsMs: durations,
          ),
          fromScratch,
          reason: '$durations',
        );
      }
    });
  });

  test('a book with no tracks can never be started', () {
    for (final start in const [
      BookStartPoint.resume(),
      BookStartPoint.beginning(),
      BookStartPoint.atTrack('t1'),
      BookStartPoint.atTrackIndex(0),
    ]) {
      expect(
        resolveBookStart(
            start: start, trackRatingKeys: const [], saved: null),
        isNull,
      );
    }
  });

  test('a single-file book resolves every kind to track 0', () {
    expect(
      resolveBookStart(
        start: const BookStartPoint.resume(),
        trackRatingKeys: const ['only'],
        saved: saved('only', 3600000),
      ),
      (trackIndex: 0, positionMs: 3600000, applyResumeRewind: true),
    );
    expect(
      resolveBookStart(
        start: const BookStartPoint.atTrackIndex(0, positionMs: 90),
        trackRatingKeys: const ['only'],
        saved: null,
      ),
      (trackIndex: 0, positionMs: 90, applyResumeRewind: false),
    );
  });

  group('BookStartPoint.synced', () {
    test("lands on Plex's file and place, with no rewind", () {
      final r = resolveBookStart(
        start: const BookStartPoint.synced('t2', positionMs: 5000),
        trackRatingKeys: const ['t1', 't2', 't3'],
        saved: saved('t3', 12345),
      )!;
      expect(r.trackIndex, 1);
      expect(r.positionMs, 5000);
      expect(r.applyResumeRewind, isFalse);
    });

    test('is neither a resume nor a chosen point: reports hold', () {
      const p = BookStartPoint.synced('t2', positionMs: 5000);
      expect(p.isResume, isFalse);
      expect(p.isChosen, isFalse);
      expect(p.isBeginning, isFalse);
      expect(const BookStartPoint.beginning().isBeginning, isTrue);
    });

    test('a file this book does not have refuses, never restarts', () {
      expect(
          resolveBookStart(
            start: const BookStartPoint.synced('gone', positionMs: 5000),
            trackRatingKeys: const ['t1'],
            saved: null,
          ),
          isNull);
    });
  });
}
