import 'track_position_math.dart';

/// One file's progress as the server has it, in file order. Plain values,
/// not Plex types, so Audiobookshelf (1.6.0) can feed the same resolver.
typedef ServerFileProgress = ({
  int durationMs,
  int? viewOffsetMs,
  DateTime? lastViewedAt,
});

/// Where the server says the listener is in a book.
typedef ServerPosition = ({
  /// Index into the files passed in (file order, not Plex's `index` field).
  int fileIndex,

  /// Position within that file, and in the whole book.
  int positionMs,
  int absoluteMs,

  /// When the server last heard about the book: that file's `lastViewedAt`,
  /// on the server's clock (rule 3's `Ts`).
  DateTime at,

  /// The newest file had no offset: a report under a minute erased it, so
  /// the place is "somewhere in that file's first minute", taken as its start.
  bool offsetErased,
});

/// Rule 2 of the position-sync design: which file the server says you're
/// in, and where.
///
/// Plex keeps one offset per file and none for the book, and files left
/// behind keep their stale offsets (the probe, 2026-11-12). So:
/// - The file with the **newest `lastViewedAt`** is the one you're in; a
///   tie (the field is whole seconds) goes to the later file.
/// - That file's `viewOffset` is the place. Missing means a report under a
///   minute erased it: the start of that file.
/// - No file with a `lastViewedAt` means the server knows nothing: null.
///
/// Also null when the newest file's offset is past its end. That's not a
/// place any player reached (a re-encoded file, a wrong duration), and a
/// fallback here would be silent and wrong: better no information than a
/// confident wrong place.
///
/// Rejected: the highest-numbered file with an offset (wrong after a rewind
/// into an earlier file), and adding the offsets up (Prologue's 1%).
ServerPosition? resolveServerPosition(List<ServerFileProgress> files) {
  int? newest;
  for (var i = 0; i < files.length; i++) {
    final at = files[i].lastViewedAt;
    if (at == null) continue;
    final best = newest == null ? null : files[newest].lastViewedAt!;
    if (best == null || !at.isBefore(best)) newest = i;
  }
  if (newest == null) return null;

  final file = files[newest];
  final offset = file.viewOffsetMs;
  if (offset != null && file.durationMs > 0 && offset > file.durationMs) {
    return null;
  }
  final positionMs = offset ?? 0;
  return (
    fileIndex: newest,
    positionMs: positionMs,
    absoluteMs: absoluteFromTrack(
        [for (final f in files) f.durationMs], newest, positionMs),
    at: file.lastViewedAt!,
    offsetErased: offset == null,
  );
}
