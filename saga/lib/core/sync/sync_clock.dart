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
///
/// [queuedAt] is the phone's clock and [serverNewest] the server's. [skew] is
/// how far the server's clock is ahead of the phone's ([measureSkew], from
/// the same answer [serverNewest] came in), and moves [queuedAt] onto the
/// server's clock first. Without it a phone five minutes fast (or a server
/// five minutes slow) made a queued report look five minutes newer than it
/// was, and the margin alone covers one. Null when the answer carried no
/// usable `Date`: the raw clocks are compared, as before.
bool shouldReplayQueued({
  required DateTime queuedAt,
  required DateTime? serverNewest,
  Duration? skew,
}) =>
    serverNewest == null ||
    queuedAt
        .add(skew ?? Duration.zero)
        .isAfter(serverNewest.add(syncClockMargin));
