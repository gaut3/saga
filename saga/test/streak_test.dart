import 'package:flutter_test/flutter_test.dart';
import 'package:saga/core/stats/streak.dart';
import 'package:saga/core/utils/date_math.dart';

void main() {
  // Builds an msForDay lookup from a set of active days (offsets back from
  // [now]: 0 = today, 1 = yesterday, ...).
  MsForDay daysActive(DateTime now, Set<int> offsets) {
    final active = {for (final o in offsets) addDays(dayOnly(now), -o)};
    return (day) => active.contains(day) ? 60000 : 0;
  }

  final now = DateTime(2026, 6, 12, 14, 30); // mid-afternoon Friday

  test('no listening at all gives 0/0', () {
    final s = computeStreak(msForDay: (_) => 0, now: now);
    expect(s.current, 0);
    expect(s.longest, 0);
  });

  test('listened today and the two days before gives 3', () {
    final s = computeStreak(msForDay: daysActive(now, {0, 1, 2}), now: now);
    expect(s.current, 3);
    expect(s.longest, 3);
  });

  test('today empty but yesterday active: streak still alive', () {
    final s = computeStreak(msForDay: daysActive(now, {1, 2, 3}), now: now);
    expect(s.current, 3);
  });

  test('gap two days ago breaks the current streak', () {
    final s =
        computeStreak(msForDay: daysActive(now, {0, 1, 3, 4, 5}), now: now);
    expect(s.current, 2);
    expect(s.longest, 3); // the older 3-day run
  });

  test('longest run in window beats current', () {
    final s = computeStreak(
        msForDay: daysActive(now, {0, 10, 11, 12, 13, 14}), now: now);
    expect(s.current, 1);
    expect(s.longest, 5);
  });

  test('runs outside longestWindowDays are not counted', () {
    final s = computeStreak(
      msForDay: daysActive(now, {0, 400, 401, 402}),
      now: now,
      longestWindowDays: 365,
    );
    expect(s.longest, 1);
  });

  test('current streak longer than window still wins longest', () {
    final s = computeStreak(
      msForDay: daysActive(now, {for (int i = 0; i < 20; i++) i}),
      now: now,
      longestWindowDays: 10,
    );
    expect(s.current, 20);
    expect(s.longest, 20);
  });

  test('streak spanning the spring-forward DST weekend is unbroken', () {
    // Europe/Oslo springs forward 2026-03-29. Active 03-26 through 03-31,
    // "now" is the 31st: a 6-day streak across the boundary.
    final dstNow = DateTime(2026, 3, 31, 9);
    final active = {
      DateTime(2026, 3, 26),
      DateTime(2026, 3, 27),
      DateTime(2026, 3, 28),
      DateTime(2026, 3, 29),
      DateTime(2026, 3, 30),
      DateTime(2026, 3, 31),
    };
    final s = computeStreak(
        msForDay: (day) => active.contains(day) ? 60000 : 0, now: dstNow);
    expect(s.current, 6);
    expect(s.longest, 6);
  });
}
