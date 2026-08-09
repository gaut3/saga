import '../storage/playback_log_store.dart';

/// One listening session: a `play` event and the `pause` that closed it —
/// or no pause at all, when the log never saw one (app killed mid-listen,
/// or the session is still running).
class ListeningSession {
  final AudioLogEvent play;
  final AudioLogEvent? pause;

  const ListeningSession({required this.play, this.pause});

  /// Wall-clock span of the session, or null when it was never closed.
  Duration? get duration => pause?.timestamp.difference(play.timestamp);
}

/// Pairs the playback log's play/pause events into sessions — the single
/// definition of "a session", shared by the player's Sessions sheet and both
/// of History's per-book panels.
///
/// Those three used to hand-roll the pairing with three different rules, and
/// two had already drifted: the player's copy walked the *raw* event list and
/// required the very next entry to be a pause, but `skipNext`, `skipPrev` and
/// `sleepTimer` are logged into the same list — so a session with a sleep
/// timer set inside it showed no duration in the player while History showed
/// "42m listened" for the same two events.
///
/// Rules, chosen to match what History already displayed:
///  * only `play` and `pause` events participate; everything else is ignored;
///  * events are paired in timestamp order;
///  * a `play` followed by another `play` (double log, crash between them)
///    becomes a session with unknown duration rather than stealing the next
///    pause from the later play;
///  * a `pause` with no open play (its play pruned away) pairs with nothing
///    and credits no time;
///  * a trailing unclosed `play` is still a session — it has a start worth
///    listing — with a null duration.
List<ListeningSession> pairListeningSessions(Iterable<AudioLogEvent> events) {
  final chrono = [
    for (final e in events)
      if (e.type == 'play' || e.type == 'pause') e
  ]..sort((a, b) => a.timestamp.compareTo(b.timestamp));

  final sessions = <ListeningSession>[];
  AudioLogEvent? open;
  for (final e in chrono) {
    if (e.type == 'play') {
      if (open != null) sessions.add(ListeningSession(play: open));
      open = e;
    } else if (open != null) {
      sessions.add(ListeningSession(play: open, pause: e));
      open = null;
    }
  }
  if (open != null) sessions.add(ListeningSession(play: open));
  return sessions;
}

/// Total listened time across [sessions], counting only closed ones.
Duration totalListened(Iterable<ListeningSession> sessions) {
  var total = Duration.zero;
  for (final s in sessions) {
    final d = s.duration;
    if (d != null) total += d;
  }
  return total;
}
