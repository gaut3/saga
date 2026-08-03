import 'package:flutter_test/flutter_test.dart';
import 'package:saga/core/book_progress.dart';
import 'package:saga/core/plex/models/plex_book.dart';
import 'package:saga/core/storage/bookmark_store.dart';

void main() {
  PlexBook book({int? durationMs}) =>
      PlexBook(ratingKey: 'b1', title: 'A Book', totalDurationMs: durationMs);

  BookPosition position({
    int positionMs = 0,
    int absolutePositionMs = 0,
    int? totalDurationMs,
  }) =>
      BookPosition(
        trackRatingKey: 't1',
        positionMs: positionMs,
        absolutePositionMs: absolutePositionMs,
        totalDurationMs: totalDurationMs,
        savedAt: DateTime(2026, 8, 1),
      );

  group('bookTotalDurationMs', () {
    test('prefers what Plex reports', () {
      expect(
        bookTotalDurationMs(
            book(durationMs: 7200000), position(totalDurationMs: 9999)),
        7200000,
      );
    });

    test('falls back to the saved position when Plex has none', () {
      // The album API omits duration for some libraries; the saved position
      // carries the sum of the track durations from the first play.
      expect(
        bookTotalDurationMs(book(), position(totalDurationMs: 7200000)),
        7200000,
      );
    });

    test('a Plex zero does not win', () {
      // Some call sites used a bare `??`, so a zero from Plex beat a real
      // length in the bookmark and the progress bar vanished.
      expect(
        bookTotalDurationMs(
            book(durationMs: 0), position(totalDurationMs: 7200000)),
        7200000,
      );
    });

    test('null when nothing knows', () {
      expect(bookTotalDurationMs(book(), null), isNull);
      expect(bookTotalDurationMs(book(), position()), isNull);
      expect(bookTotalDurationMs(book(durationMs: 0), position()), isNull);
    });
  });

  group('bookProgressFraction', () {
    test('measures from the book-absolute position', () {
      // Multi-file book: 6 min into file two of a two-hour book. The
      // track-relative figure would read as 5%.
      final f = bookProgressFraction(
        book(durationMs: 7200000),
        position(positionMs: 360000, absolutePositionMs: 3600000),
      );
      expect(f, 0.5);
    });

    test('clamps past the end', () {
      expect(
        bookProgressFraction(book(durationMs: 1000),
            position(absolutePositionMs: 5000)),
        1.0,
      );
    });

    test('null when the book was never started', () {
      expect(bookProgressFraction(book(durationMs: 7200000), null), isNull);
    });

    test('null when no source knows the length', () {
      expect(
        bookProgressFraction(book(), position(absolutePositionMs: 3600000)),
        isNull,
      );
    });

    test('uses the saved length when Plex has none', () {
      expect(
        bookProgressFraction(
          book(),
          position(absolutePositionMs: 1800000, totalDurationMs: 7200000),
        ),
        0.25,
      );
    });
  });

  group('pickTotalDurationMs', () {
    test('same rule without a book', () {
      expect(pickTotalDurationMs(500, 900), 500);
      expect(pickTotalDurationMs(0, 900), 900);
      expect(pickTotalDurationMs(null, 900), 900);
      expect(pickTotalDurationMs(null, 0), isNull);
      expect(pickTotalDurationMs(null, null), isNull);
    });
  });
}
