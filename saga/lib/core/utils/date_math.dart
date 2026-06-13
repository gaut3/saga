/// Calendar-day arithmetic helpers — the single home for date math.
///
/// Standing principle: never do calendar-day math with [Duration].
/// `Duration(days: N)` is exactly N×24h, which is *not* N calendar days across
/// a DST change (Europe/Oslo springs forward in late March). The [DateTime]
/// constructor normalizes out-of-range components and is DST-safe, so every
/// helper here uses the constructor form and always returns local midnight.
library;

/// Local midnight of [d]'s calendar day.
DateTime dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// Local midnight of the day [n] calendar days from [day]. [n] may be
/// negative. DST-safe (constructor form, never `Duration`).
DateTime addDays(DateTime day, int n) =>
    DateTime(day.year, day.month, day.day + n);

/// Local midnight of the Monday of [day]'s week.
DateTime mondayOf(DateTime day) => addDays(day, -(day.weekday - 1));

/// The 7 days of [day]'s Mon-first week, each at local midnight.
List<DateTime> mondayWeek(DateTime day) {
  final monday = mondayOf(day);
  return List.generate(7, (i) => addDays(monday, i));
}

/// First day (a Monday, local midnight) of the [weeks]-week heatmap window
/// whose last column is [today]'s week.
DateTime heatmapStart(DateTime today, {int weeks = 13}) =>
    addDays(mondayOf(today), -7 * (weeks - 1));

/// Mon-first calendar-grid metrics for a month: number of days, leading blank
/// cells before day 1 (Mon=0 … Sun=6), and total cell count padded to a
/// multiple of 7.
({int daysInMonth, int leadingBlanks, int gridCount}) monthGridMetrics(
    int year, int month) {
  final daysInMonth = DateTime(year, month + 1, 0).day;
  final leadingBlanks = (DateTime(year, month, 1).weekday - 1) % 7;
  final totalCells = leadingBlanks + daysInMonth;
  final gridCount = totalCells + (7 - totalCells % 7) % 7;
  return (
    daysInMonth: daysInMonth,
    leadingBlanks: leadingBlanks,
    gridCount: gridCount,
  );
}
