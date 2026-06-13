import 'package:flutter_test/flutter_test.dart';
import 'package:saga/features/player/track_position_math.dart';

void main() {
  // A typical multi-file book: 10 min, 20 min, 15 min tracks.
  const durations = [600000, 1200000, 900000];
  const total = 2700000;

  group('absoluteFromTrack', () {
    test('first track is a passthrough', () {
      expect(absoluteFromTrack(durations, 0, 0), 0);
      expect(absoluteFromTrack(durations, 0, 5000), 5000);
    });

    test('later tracks add preceding durations', () {
      expect(absoluteFromTrack(durations, 1, 0), 600000);
      expect(absoluteFromTrack(durations, 2, 1000), 1801000);
    });

    test('out-of-range index sums all durations', () {
      expect(absoluteFromTrack(durations, 99, 0), total);
    });

    test('empty track list returns the raw position', () {
      expect(absoluteFromTrack(const [], 0, 1234), 1234);
    });
  });

  group('trackFromAbsolute', () {
    test('resolves within each track', () {
      expect(trackFromAbsolute(durations, 0), (index: 0, positionMs: 0));
      expect(trackFromAbsolute(durations, 5000), (index: 0, positionMs: 5000));
      expect(trackFromAbsolute(durations, 700000),
          (index: 1, positionMs: 100000));
      expect(trackFromAbsolute(durations, 1900000),
          (index: 2, positionMs: 100000));
    });

    test('exact track boundary stays on the earlier track', () {
      // ms == duration keeps the position at the end of track 0, not the
      // start of track 1 — pins the existing `ms <= dur` semantics.
      expect(trackFromAbsolute(durations, 600000),
          (index: 0, positionMs: 600000));
    });

    test('clamps beyond-total to the end of the last track', () {
      expect(trackFromAbsolute(durations, total + 999999),
          (index: 2, positionMs: 900000));
    });

    test('clamps negative to the start', () {
      expect(trackFromAbsolute(durations, -100), (index: 0, positionMs: 0));
    });

    test('last track catches the remainder', () {
      expect(trackFromAbsolute(durations, total),
          (index: 2, positionMs: 900000));
    });

    test('zero-duration tracks fall through', () {
      const withZero = [600000, 0, 900000];
      // Position right at the zero track's boundary stays on track 0.
      expect(trackFromAbsolute(withZero, 600000),
          (index: 0, positionMs: 600000));
      // One ms past it lands inside track 2 (1 ms in).
      expect(
          trackFromAbsolute(withZero, 600001), (index: 2, positionMs: 1));
    });

    test('single zero-duration track resolves to it', () {
      expect(trackFromAbsolute(const [0], 5000), (index: 0, positionMs: 0));
    });

    test('empty track list returns null (no seek)', () {
      expect(trackFromAbsolute(const [], 5000), isNull);
    });

    test('round-trips with absoluteFromTrack', () {
      for (final abs in [0, 1, 599999, 600000, 600001, 1800000, total]) {
        final t = trackFromAbsolute(durations, abs)!;
        expect(absoluteFromTrack(durations, t.index, t.positionMs), abs,
            reason: 'absolute $abs');
      }
    });
  });
}
