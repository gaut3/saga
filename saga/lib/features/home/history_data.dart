import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/stats/listening_sessions.dart';
import '../../core/storage/playback_log_store.dart';
import '../../core/utils/date_math.dart';

/// Everything History derives from the playback log, in one pass.
class PlaybackLogIndex {
  /// Day (local midnight) → book → that day's raw events, for the per-day
  /// book rows and their expanded session panels.
  final Map<DateTime, Map<String, List<AudioLogEvent>>> eventsByDay;

  /// Day → book → wall-clock ms credited that day. Credit comes from the
  /// shared session pairing with sessions *split at midnight*: a session from
  /// 23:30 to 00:20 credits 30 minutes to one day and 20 to the next.
  /// Bucketing raw events alone credited neither — the play landed in day N's
  /// bucket with no pause, the pause in day N+1's with no play — so the day
  /// row said "1h" (from the accounting store) while every book row under it
  /// said nothing.
  final Map<DateTime, Map<String, int>> creditedMsByDay;

  const PlaybackLogIndex({
    required this.eventsByDay,
    required this.creditedMsByDay,
  });
}

/// One scan of every book's log, memoized per history revision.
///
/// The Day and Month tabs used to run this scan inside `build` — which also
/// re-runs on tab switches, theme changes and every now-playing flip, each
/// time walking all events of all books. Watching this provider instead
/// recomputes only when the log can actually have changed (a history tick,
/// ~10 s apart while playing) and rebuilds the tabs off the cached result the
/// rest of the time.
final playbackLogIndexProvider = Provider<PlaybackLogIndex>((ref) {
  ref.watch(historyRevisionProvider);

  final eventsByDay = <DateTime, Map<String, List<AudioLogEvent>>>{};
  final creditedMsByDay = <DateTime, Map<String, int>>{};

  for (final bookKey in PlaybackLogStore.bookRatingKeys()) {
    final log = PlaybackLogStore.getLog(bookKey);
    for (final e in log) {
      final day = dayOnly(e.timestamp);
      (eventsByDay.putIfAbsent(day, () => {})[bookKey] ??= []).add(e);
    }
    for (final s in pairListeningSessions(log)) {
      final end = s.pause?.timestamp;
      if (end == null) continue;
      var cursor = s.play.timestamp;
      while (cursor.isBefore(end)) {
        final day = dayOnly(cursor);
        final nextMidnight = addDays(day, 1);
        final segEnd = end.isBefore(nextMidnight) ? end : nextMidnight;
        final ms = segEnd.difference(cursor).inMilliseconds;
        if (ms > 0) {
          final dayMap = creditedMsByDay.putIfAbsent(day, () => {});
          dayMap[bookKey] = (dayMap[bookKey] ?? 0) + ms;
        }
        cursor = segEnd;
      }
    }
  }

  return PlaybackLogIndex(
    eventsByDay: eventsByDay,
    creditedMsByDay: creditedMsByDay,
  );
});
