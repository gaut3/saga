/// Which position saves may also go to Plex — rule 5 of the position-sync
/// design (`planning/Position sync design.md`): **only positions the listener
/// reached**.
///
/// Opening a book, a session restore, a cold start and a resume rewind are not
/// the listener moving. Reported, each reaches another device as the newest
/// place: a fresh install has nothing local to weigh it against, and every
/// resume rewind arrives as "newer but behind", which would make the other
/// device ask almost every time you switch phones. Prologue shows the bug:
/// open a book at 4:04, it rewinds to 3:38 and tells the server 3:38.
///
/// Per load the gate starts **held** at the loaded position. It opens when
/// playback passes that position — after a resume rewind, the spot *before*
/// the rewind — or at once on a move of the listener's own: a seek, a skip, a
/// chapter or bookmark jump.
///
/// It gates the report only. The local save never asks it: a held report
/// costs nothing on this device, a skipped save would lose a place.
///
/// Positions are absolute milliseconds into the book. Pure, so the rules are
/// testable without a player.
class ReportGate {
  bool _open = false;
  int? _heldUntilMs;

  /// Whether reports go out now.
  bool get isOpen => _open;

  /// The absolute position playback has to pass to open the gate. Null when
  /// it's open, and before any book has loaded (nothing to report then).
  int? get heldUntilMs => _open ? null : _heldUntilMs;

  /// A book has been loaded at [loadedAtMs], before any resume rewind.
  ///
  /// [savedHoldMs] is the hold that place was saved under, if it was saved
  /// while reports were held (`BookPosition.reportHoldMs`). Then Plex never
  /// heard of it, and still has the hold's place: the new hold is the
  /// further of the two. Without it, a listen that stopped inside a resume
  /// rewind came back after a reload as the "loaded spot", and reports opened
  /// up to a minute behind what Plex already had.
  void load(int loadedAtMs, {int? savedHoldMs}) {
    _open = false;
    _heldUntilMs = savedHoldMs != null && savedHoldMs > loadedAtMs
        ? savedHoldMs
        : loadedAtMs;
  }

  /// A resume rewind from [fromMs]: held until playback is back past it.
  /// Never lowers a hold already in place, so a rewind soon after a load
  /// can't open the gate short of the loaded position.
  void rewound(int fromMs) {
    final held = _heldUntilMs;
    if (!_open && held != null && held >= fromMs) return;
    _open = false;
    _heldUntilMs = fromMs;
  }

  /// The listener moved: a seek, a skip, a chapter or bookmark jump.
  void moved() {
    _open = true;
    _heldUntilMs = null;
  }

  /// Whether a report at [positionMs] may go. Opens the gate once playback is
  /// past the hold; it then stays open until the next [load] or [rewound].
  bool allows(int positionMs) {
    final held = _heldUntilMs;
    if (!_open && held != null && positionMs > held) moved();
    return _open;
  }
}

/// A timeline report as sent to Plex: enough to tell whether the next one
/// says anything new.
typedef SentReport = ({
  String bookKey,
  String trackRatingKey,
  int positionMs,
  String state,
});

/// Whether [next] repeats [last]: the same book, file and state, within a
/// second. Such a report moves nothing but Plex's `lastViewedAt`, which then
/// says an old place is the newest. Dogfood 2026-11-13: after a pause at
/// 7:09:10, every trip to the background re-sent 7:09:10, so a phone opened
/// briefly after listening elsewhere would have stamped its stale place over
/// the other device's newer one. A change of state still goes once (a
/// `stopped` after a `paused` ends the play in Plex's activity view).
bool isRepeatReport(SentReport? last, SentReport next) =>
    last != null &&
    last.bookKey == next.bookKey &&
    last.trackRatingKey == next.trackRatingKey &&
    last.state == next.state &&
    (last.positionMs - next.positionMs).abs() <= 1000;
