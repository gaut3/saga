/// Pure conversion between book-absolute positions and (track index,
/// intra-track position) pairs. Shared by [seekAbsolute], [undoSeek], and the
/// absolute-position getter in `AudioPlayerService` so the conversions can
/// never drift apart.
library;

/// Book-absolute position for [trackPositionMs] within track [trackIndex].
int absoluteFromTrack(
    List<int> trackDurationsMs, int trackIndex, int trackPositionMs) {
  var offset = 0;
  for (var i = 0; i < trackIndex && i < trackDurationsMs.length; i++) {
    offset += trackDurationsMs[i];
  }
  return offset + trackPositionMs;
}

/// Resolves a book-absolute position to a track index and intra-track
/// position. Clamps to the total book duration. A position exactly on a
/// track boundary (`ms == duration`) stays on the earlier track; the last
/// track catches any remainder, so zero-duration tracks fall through
/// cleanly. Returns null for an empty track list (no seek possible).
({int index, int positionMs})? trackFromAbsolute(
    List<int> trackDurationsMs, int absoluteMs) {
  if (trackDurationsMs.isEmpty) return null;
  final total = trackDurationsMs.fold<int>(0, (a, b) => a + b);
  var ms = absoluteMs.clamp(0, total);
  for (var i = 0; i < trackDurationsMs.length; i++) {
    final dur = trackDurationsMs[i];
    if (ms <= dur || i == trackDurationsMs.length - 1) {
      return (index: i, positionMs: ms);
    }
    ms -= dur;
  }
  // Unreachable: the last-track branch above always returns.
  return (index: trackDurationsMs.length - 1, positionMs: ms);
}

/// Book-absolute start/end of the chapter containing [posMs], given ascending
/// chapter start offsets. Chapter i spans `[start_i, start_{i+1})`; the last
/// chapter runs to [totalMs]. A position before the first start (unusual, but
/// some books' first chapter mark isn't at 0:00) spans `[0, firstStart)`.
/// With no chapters, the whole book is one range.
({int startMs, int endMs}) chapterRangeAt(
    List<int> chapterStartsMs, int posMs, int totalMs) {
  var startMs = 0;
  var endMs = totalMs;
  for (final cs in chapterStartsMs) {
    if (cs <= posMs) {
      startMs = cs;
    } else {
      endMs = cs;
      break;
    }
  }
  return (startMs: startMs, endMs: endMs);
}
