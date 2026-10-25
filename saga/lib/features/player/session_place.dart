import '../../core/audio/m4b_chapter_reader.dart';
import '../../core/plex/models/plex_track.dart';
import '../../core/storage/bookmark_store.dart';
import '../../core/storage/chapter_store.dart';
import '../../core/storage/playback_log_store.dart';
import '../../core/storage/track_cache_store.dart';
import 'track_position_math.dart';

/// Where a logged event sits in its book: a book-absolute offset, plus the
/// chapter holding it when one is known.
typedef SessionPlace = ({int absoluteMs, String? chapter});

/// Places [e] in the book. Pure, so the rules are testable without Hive —
/// [placeOfEvent] is the stored-data wrapper every screen calls.
///
/// An [AudioLogEvent] records a position inside one file, plus which file.
/// Placing it in the whole book needs that file's own offset: from the track
/// list when there is one, else from the saved position — which knows exactly
/// one file's offset (its own: absolute minus track-relative), so it only
/// helps when the event is on the same file. Null when neither can say.
///
/// Chapter: a multi-file book's files *are* its chapters, so the file's
/// title; a single-file book's from its embedded chapter table
/// ([chaptersFor]), the last chapter starting at or before the position.
SessionPlace? resolveEventPlace(
  AudioLogEvent e, {
  required List<PlexTrack>? tracks,
  required BookPosition? saved,
  required List<M4bChapter>? Function(String trackRatingKey) chaptersFor,
}) {
  int? absoluteMs;
  String? chapter;
  final idx = tracks?.indexWhere((t) => t.ratingKey == e.trackRatingKey) ?? -1;
  if (idx >= 0) {
    absoluteMs = absoluteFromTrack(
        [for (final t in tracks!) t.durationMs], idx, e.positionMs);
    if (tracks.length > 1) chapter = tracks[idx].title;
  } else if (saved != null && saved.trackRatingKey == e.trackRatingKey) {
    absoluteMs = saved.absolutePositionMs - saved.positionMs + e.positionMs;
  }
  if (absoluteMs == null) return null;

  if (tracks == null || tracks.length <= 1) {
    final chapters = chaptersFor(e.trackRatingKey);
    if (chapters != null) {
      for (final c in chapters) {
        if (c.start.inMilliseconds > e.positionMs) break;
        chapter = c.title;
      }
    }
  }
  return (absoluteMs: absoluteMs, chapter: chapter);
}

/// [resolveEventPlace] against the stored track list, saved position and
/// chapter cache for [bookKey].
SessionPlace? placeOfEvent(String bookKey, AudioLogEvent e) =>
    resolveEventPlace(
      e,
      tracks: TrackCacheStore.load(bookKey),
      saved: BookmarkStore.load(bookKey),
      chaptersFor: ChapterStore.load,
    );

/// How much a session preview plays.
const kPreviewLength = Duration(seconds: 30);

/// The span a preview of [positionMs] plays inside a file of
/// [trackDurationMs]: [kPreviewLength] centred on the position, slid (not
/// shortened) to stay inside the file, and only cut short when the file
/// itself is shorter. An unknown duration (≤ 0) leaves the end open.
({Duration start, Duration end}) previewWindow(
    int positionMs, int trackDurationMs) {
  final len = kPreviewLength.inMilliseconds;
  var start = positionMs - len ~/ 2;
  if (trackDurationMs > 0 && start + len > trackDurationMs) {
    start = trackDurationMs - len;
  }
  if (start < 0) start = 0;
  var end = start + len;
  if (trackDurationMs > 0 && end > trackDurationMs) end = trackDurationMs;
  return (
    start: Duration(milliseconds: start),
    end: Duration(milliseconds: end),
  );
}
