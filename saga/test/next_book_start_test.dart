import 'package:flutter_test/flutter_test.dart';
import 'package:saga/core/storage/bookmark_store.dart';
import 'package:saga/features/player/play_next.dart';

BookPosition _pos(int absoluteMs, {int? totalMs}) => BookPosition(
      trackRatingKey: 't1',
      positionMs: absoluteMs,
      absolutePositionMs: absoluteMs,
      totalDurationMs: totalMs,
      savedAt: DateTime(2026, 8, 14),
    );

// The rule deciding whether the series advance resumes a next book or starts
// it from the beginning. The dangerous mistake it prevents: "resuming" the
// end-of-book position a finish leaves behind replays the final second,
// completes again, and — with auto-play on — cascades through every finished
// book in the collection.
void main() {
  test('no bookmark: start from the beginning', () {
    expect(isResumablePosition(null), isFalse);
  });

  test('a position at zero is not a place', () {
    expect(isResumablePosition(_pos(0, totalMs: 3600000)), isFalse);
  });

  test('a mid-book position resumes', () {
    expect(isResumablePosition(_pos(1800000, totalMs: 3600000)), isTrue);
  });

  test('the end-of-book artifact of a finish does not resume', () {
    expect(isResumablePosition(_pos(3600000, totalMs: 3600000)), isFalse);
    expect(isResumablePosition(_pos(3595000, totalMs: 3600000)), isFalse);
  });

  test('just outside the end margin still resumes', () {
    expect(isResumablePosition(_pos(3589000, totalMs: 3600000)), isTrue);
  });

  test('unknown book length: resume, never discard a real place', () {
    expect(isResumablePosition(_pos(1800000)), isTrue);
  });
}
