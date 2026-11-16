/// How much newer one clock's time must be than another's to count as newer
/// (sync design rule 4). Saga's times are the phone's clock, Plex's the
/// server's; the margin absorbs the skew between them, and Saga's own reports
/// arriving a few seconds after they were saved. Chronicle 0.62.9 and Cue use
/// the same 60 s.
const syncClockMargin = Duration(seconds: 60);

/// The newest of a book's per-file `lastViewedAt`s: when Plex last heard
/// anything about the book. Null when it has heard nothing.
DateTime? newestViewedAt(Iterable<DateTime?> perFile) {
  DateTime? newest;
  for (final t in perFile) {
    if (t != null && (newest == null || t.isAfter(newest))) newest = t;
  }
  return newest;
}

/// Rule 6: whether a report queued offline at [queuedAt] may be replayed,
/// given the newest time Plex has for the book. Only when it beats that by
/// [syncClockMargin]. Anything else may be older than what Plex has from
/// another device since, and a replay would overwrite it (arrival order
/// wins on Plex). A dropped entry costs nothing: the place is still saved on
/// this phone, and the book's next open settles it (rule 3).
bool shouldReplayQueued(
        {required DateTime queuedAt, required DateTime? serverNewest}) =>
    serverNewest == null || queuedAt.isAfter(serverNewest.add(syncClockMargin));
