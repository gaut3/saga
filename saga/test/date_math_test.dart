// These tests exercise the Europe/Oslo DST boundaries (spring-forward
// 2026-03-29, fall-back 2026-10-25). DateTime uses the process-local
// timezone, so the DST assertions are only fully meaningful when the suite
// runs under Europe/Oslo — the dev machine is, and CI pins TZ=Europe/Oslo.
import 'package:flutter_test/flutter_test.dart';
import 'package:saga/core/utils/date_math.dart';

void main() {
  group('dayOnly', () {
    test('strips time-of-day', () {
      expect(dayOnly(DateTime(2026, 6, 12, 23, 59, 59)), DateTime(2026, 6, 12));
      expect(dayOnly(DateTime(2026, 6, 12)), DateTime(2026, 6, 12));
    });
  });

  group('addDays', () {
    test('basic forward and backward', () {
      expect(addDays(DateTime(2026, 6, 12), 1), DateTime(2026, 6, 13));
      expect(addDays(DateTime(2026, 6, 12), -1), DateTime(2026, 6, 11));
      expect(addDays(DateTime(2026, 6, 12), 0), DateTime(2026, 6, 12));
    });

    test('month and year rollover', () {
      expect(addDays(DateTime(2026, 1, 31), 1), DateTime(2026, 2, 1));
      expect(addDays(DateTime(2026, 12, 31), 1), DateTime(2027, 1, 1));
      expect(addDays(DateTime(2026, 3, 1), -1), DateTime(2026, 2, 28));
      expect(addDays(DateTime(2024, 3, 1), -1), DateTime(2024, 2, 29)); // leap
    });

    test('crossing spring-forward stays at local midnight', () {
      // Europe/Oslo: 2026-03-29 02:00 CET -> 03:00 CEST. The Duration form
      // lands at 23:00 on the 28th; the constructor form must not.
      final d = addDays(DateTime(2026, 3, 28), 1);
      expect(d, DateTime(2026, 3, 29));
      expect(d.hour, 0);
      expect(d.day, 29);
    });

    test('crossing fall-back stays at local midnight', () {
      // Europe/Oslo: 2026-10-25 03:00 CEST -> 02:00 CET.
      final d = addDays(DateTime(2026, 10, 24), 1);
      expect(d, DateTime(2026, 10, 25));
      expect(d.hour, 0);
    });

    test('long spans across both DST boundaries are consecutive midnights',
        () {
      var d = DateTime(2026, 3, 1);
      for (int i = 0; i < 250; i++) {
        final next = addDays(d, 1);
        expect(next.hour, 0, reason: 'non-midnight at $next');
        expect(next.difference(d).inHours, anyOf(23, 24, 25),
            reason: 'skipped/repeated a day at $next');
        expect(dayOnly(next), next);
        d = next;
      }
      expect(d, DateTime(2026, 11, 6));
    });
  });

  group('mondayOf / mondayWeek', () {
    test('returns the Monday of the week', () {
      expect(mondayOf(DateTime(2026, 6, 12)), DateTime(2026, 6, 8)); // Fri
      expect(mondayOf(DateTime(2026, 6, 8)), DateTime(2026, 6, 8)); // Mon
      expect(mondayOf(DateTime(2026, 6, 14)), DateTime(2026, 6, 8)); // Sun
    });

    test('mondayWeek yields 7 consecutive midnights, Mon-first', () {
      final week = mondayWeek(DateTime(2026, 6, 12));
      expect(week.length, 7);
      expect(week.first, DateTime(2026, 6, 8));
      expect(week.last, DateTime(2026, 6, 14));
      for (int i = 0; i < 7; i++) {
        expect(week[i].weekday, i + 1);
        expect(week[i].hour, 0);
      }
    });

    test('week containing the spring-forward Sunday', () {
      // 2026-03-29 is a Sunday; the week is Mon 03-23 through Sun 03-29.
      final week = mondayWeek(DateTime(2026, 3, 29));
      expect(week.first, DateTime(2026, 3, 23));
      expect(week.last, DateTime(2026, 3, 29));
      expect(week.last.hour, 0); // Duration form would land at 23:00 Sat
    });
  });

  group('heatmapStart', () {
    test('13 weeks back from the current week, on a Monday, at midnight', () {
      final start = heatmapStart(DateTime(2026, 6, 12));
      expect(start.weekday, DateTime.monday);
      expect(start, DateTime(2026, 3, 16));
      expect(start.hour, 0);
    });

    test('window crossing the spring-forward boundary is normalized', () {
      // From a date shortly after the DST change, the window starts before it.
      final start = heatmapStart(DateTime(2026, 4, 10));
      expect(start, DateTime(2026, 1, 12)); // Mon Apr 6 minus 84 days
      expect(start.weekday, DateTime.monday);
      expect(start.hour, 0);
    });
  });

  group('monthGridMetrics', () {
    test('month starting on each weekday gets the right leading blanks', () {
      // 2026: Jun 1 = Monday, Sep 1 = Tuesday, Apr 1 = Wednesday,
      // Jan 1 = Thursday, May 1 = Friday, Aug 1 = Saturday, Mar 1 = Sunday.
      expect(monthGridMetrics(2026, 6).leadingBlanks, 0);
      expect(monthGridMetrics(2026, 9).leadingBlanks, 1);
      expect(monthGridMetrics(2026, 4).leadingBlanks, 2);
      expect(monthGridMetrics(2026, 1).leadingBlanks, 3);
      expect(monthGridMetrics(2026, 5).leadingBlanks, 4);
      expect(monthGridMetrics(2026, 8).leadingBlanks, 5);
      expect(monthGridMetrics(2026, 3).leadingBlanks, 6);
    });

    test('daysInMonth handles short, long, and leap months', () {
      expect(monthGridMetrics(2026, 2).daysInMonth, 28);
      expect(monthGridMetrics(2024, 2).daysInMonth, 29);
      expect(monthGridMetrics(2026, 4).daysInMonth, 30);
      expect(monthGridMetrics(2026, 12).daysInMonth, 31);
    });

    test('gridCount is padded to a multiple of 7 and fits the month', () {
      for (int m = 1; m <= 12; m++) {
        final g = monthGridMetrics(2026, m);
        expect(g.gridCount % 7, 0, reason: 'month $m');
        expect(
            g.gridCount, greaterThanOrEqualTo(g.leadingBlanks + g.daysInMonth));
        expect(g.gridCount - (g.leadingBlanks + g.daysInMonth), lessThan(7));
      }
      // Exact fit, no padding: Feb 2027 starts on a Monday and has 28 days.
      expect(monthGridMetrics(2027, 2).gridCount, 28);
    });
  });
}
