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
}
