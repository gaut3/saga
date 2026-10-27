// The relativeDayLabel DST cases exercise the Europe/Oslo boundaries
// (spring-forward 2026-03-29, fall-back 2026-10-25). DateTime uses the
// process-local timezone, so they are only fully meaningful when the suite
// runs under Europe/Oslo — the dev machine is, and CI pins TZ=Europe/Oslo.
import 'package:flutter_test/flutter_test.dart';
import 'package:saga/core/utils/format.dart';

void main() {
  group('fmtBookPositionMs', () {
    test('keeps the hour under an hour, so it never reads as a clock', () {
      // "48:49" beside "16:40–17:14" in a session row read as a time of day.
      expect(fmtBookPositionMs(2929000), '0:48:49');
      expect(fmtBookPositionMs(0), '0:00:00');
    });

    test('hours and beyond', () {
      expect(fmtBookPositionMs(3600000), '1:00:00');
      expect(fmtBookPositionMs(75735000), '21:02:15');
    });

    test('a negative position clamps to zero', () {
      expect(fmtBookPositionMs(-5), '0:00:00');
    });
  });

  group('fmtListenedMs', () {
    test('under a minute reads as "<1m", never blank', () {
      expect(fmtListenedMs(0), '<1m');
      expect(fmtListenedMs(1), '<1m');
      expect(fmtListenedMs(59999), '<1m');
    });

    test('minutes', () {
      expect(fmtListenedMs(60000), '1m');
      expect(fmtListenedMs(2700000), '45m');
      expect(fmtListenedMs(3599999), '59m');
    });

    test('hours always carry the minutes', () {
      expect(fmtListenedMs(3600000), '1h 0m');
      expect(fmtListenedMs(3660000), '1h 1m');
      expect(fmtListenedMs(7500000), '2h 5m');
    });
  });

  group('relativeDayLabel', () {
    final now = DateTime(2026, 6, 12, 14, 30);

    test('today at any hour', () {
      expect(relativeDayLabel(DateTime(2026, 6, 12, 0, 0), now: now), 'Today');
      expect(
          relativeDayLabel(DateTime(2026, 6, 12, 23, 59), now: now), 'Today');
    });

    test('yesterday', () {
      expect(
          relativeDayLabel(DateTime(2026, 6, 11, 22), now: now), 'Yesterday');
    });

    test('anything older is a date', () {
      expect(relativeDayLabel(DateTime(2026, 6, 10), now: now), '10/6/2026');
      expect(relativeDayLabel(DateTime(2025, 12, 3), now: now), '3/12/2025');
    });

    test('a future day is a date, not "Today"', () {
      expect(relativeDayLabel(DateTime(2026, 6, 13), now: now), '13/6/2026');
    });

    test('yesterday survives spring-forward', () {
      // Oslo, 2026-03-29 02:00 CET -> 03:00 CEST. Midnight on the 30th minus
      // 24h is 23:00 on the 29th, which equals no midnight at all — the local
      // copy this replaced compared exactly that and printed a bare date.
      expect(
        relativeDayLabel(DateTime(2026, 3, 29, 12),
            now: DateTime(2026, 3, 30, 10)),
        'Yesterday',
      );
    });

    test('yesterday survives fall-back', () {
      // Oslo, 2026-10-25 03:00 CEST -> 02:00 CET.
      expect(
        relativeDayLabel(DateTime(2026, 10, 25, 12),
            now: DateTime(2026, 10, 26, 10)),
        'Yesterday',
      );
    });
  });
}
