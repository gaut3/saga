import '../utils/date_math.dart';

/// Milliseconds listened on a given (local-midnight) day.
typedef MsForDay = int Function(DateTime day);

/// Current and longest listening streaks, shared by the Home listening strip
/// and the History screen so the two can never drift apart.
///
/// [msForDay] is injectable (normally `ListeningHistoryStore.getMs`) and [now]
/// is overridable so the streak rules are unit-testable. [longestWindowDays]
/// bounds the longest-streak scan.
({int current, int longest}) computeStreak({
  required MsForDay msForDay,
  DateTime? now,
  int longestWindowDays = 365,
}) {
  final todayClean = dayOnly(now ?? DateTime.now());

  // If today has no listening yet the streak is still alive — it just hasn't
  // been extended yet. Start counting from yesterday in that case.
  var d = msForDay(todayClean) > 0 ? todayClean : addDays(todayClean, -1);

  int current = 0;
  while (msForDay(d) > 0) {
    current++;
    d = addDays(d, -1);
  }

  int longest = 0;
  int run = 0;
  for (int i = 0; i < longestWindowDays; i++) {
    if (msForDay(addDays(todayClean, -i)) > 0) {
      run++;
      if (run > longest) longest = run;
    } else {
      run = 0;
    }
  }
  if (current > longest) longest = current;
  return (current: current, longest: longest);
}
