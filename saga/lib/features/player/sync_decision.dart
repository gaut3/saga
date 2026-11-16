import '../../core/sync/sync_clock.dart';
import 'server_position.dart';

/// What to do with the server's place for a book (sync design rule 3).
enum SyncAction {
  /// Plex knows nothing, or the two places are within [syncSameWindow]:
  /// nothing to do.
  same,

  /// This phone's place stands: it is newer, or not older by more than the
  /// clock margin.
  keep,

  /// Plex's place is newer and further on: take it, with a toast and Undo
  /// (rule 9).
  apply,

  /// Plex's place is newer but further back, or the book is finished here:
  /// ask (rule 9; rule 8 for a finished book).
  ask,
}

/// Places this close are the same place (rule 3's first row): a few seconds
/// of drift between a save and a report, never worth a toast.
const syncSameWindow = Duration(seconds: 10);

/// This phone's place for a book, captured **before** the server is asked
/// (rule 4): the 10 s save timer can fire while the request is in flight,
/// and a `savedAt` read afterwards would be newer than the place it is
/// compared as (absorb cbf57416).
typedef LocalPlace = ({int absoluteMs, DateTime savedAt});

/// A decision, with what it was made from: the shadow log prints it.
typedef SyncDecision = ({SyncAction action, String reason});

/// Rules 3–4: compare the server's place S (heard at `Ts`, server clock)
/// with this phone's L (saved at `Tl`, phone clock).
///
/// | Case                                   | Action |
/// |----------------------------------------|--------|
/// | Plex knows nothing                     | same   |
/// | \|S − L\| ≤ 10 s                        | same   |
/// | Ts > Tl + 60 s, S ahead                | apply  |
/// | Ts > Tl + 60 s, S behind               | ask    |
/// | otherwise                              | keep   |
///
/// The 60 s ([syncClockMargin]) covers skew between the two clocks and
/// Saga's own reports arriving a few seconds after the save they carry: the
/// common case, your own phone, lands in `keep` or `same`, never a prompt.
///
/// No local place (a fresh install, or a book never played here) takes a
/// server place past [syncSameWindow]: there is nothing to lose, and Undo
/// goes back to the start.
///
/// A book finished here ([localFinished]) never gets `apply`: a sync never
/// clears a finish on its own (rule 8). A newer server place there is
/// offered, as `ask`.
///
/// Rejected: silent last-write-wins (most "lost my place" reports), furthest
/// wins (a stale report wins), asking on every difference (your own phone
/// causes most of them).
SyncDecision decideSync({
  required LocalPlace? local,
  required ServerPosition? server,
  bool localFinished = false,
}) {
  if (server == null) {
    return (action: SyncAction.same, reason: 'Plex knows nothing of this book');
  }
  final s = server.absoluteMs;
  final l = local?.absoluteMs ?? 0;
  final gapMs = s - l;
  final where = '${_span(gapMs.abs())} ${gapMs >= 0 ? 'ahead' : 'behind'}';
  if (gapMs.abs() <= syncSameWindow.inMilliseconds) {
    return (action: SyncAction.same, reason: 'same place ($where)');
  }

  final newer = local == null ||
      server.at.isAfter(local.savedAt.add(syncClockMargin));
  final age = local == null
      ? 'nothing saved here'
      : _age(server.at.difference(local.savedAt));
  if (!newer) {
    return (action: SyncAction.keep, reason: 'Plex $where, $age');
  }
  if (localFinished) {
    return (action: SyncAction.ask, reason: 'finished here; Plex $where, $age');
  }
  return (
    action: gapMs > 0 ? SyncAction.apply : SyncAction.ask,
    reason: 'Plex $where, $age',
  );
}

String _span(int ms) {
  final s = ms ~/ 1000;
  if (s < 60) return '$s s';
  if (s < 3600) return '${s ~/ 60} min ${s % 60} s';
  return '${s ~/ 3600} h ${(s % 3600) ~/ 60} min';
}

/// "newer by 4 min 10 s" / "older by 12 s", from Ts − Tl.
String _age(Duration d) =>
    '${d.isNegative ? 'older' : 'newer'} by ${_span(d.inMilliseconds.abs())}';
