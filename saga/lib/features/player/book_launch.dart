import '../../core/diagnostics/app_log.dart';
import '../../core/plex/models/plex_track.dart';
import '../../core/storage/bookmark_store.dart';
import '../../core/storage/settings_store.dart';
import 'player_service.dart';

enum _StartKind { resume, beginning, trackKey, trackIndex }

/// What a launch should do about playback.
enum LaunchPlayback {
  /// Load only — the book sits loaded and paused. Home's hero card does this
  /// when it wants the mark and chapter label live without starting audio.
  none,

  /// Declare the play intent before the load and start audio afterwards. What
  /// every "the listener tapped this" launch wants.
  start,

  /// Declare the play intent, but leave the final `play()` to the caller.
  ///
  /// For the session restore that runs *inside*
  /// [AudioPlayerService.play] — that call goes on to do the rest of a play
  /// itself, and playing again from in here would log a second play event and
  /// save a second bookmark for one press of a headphone button.
  intentOnly,
}

/// Where a launch should begin. See [startBook].
class BookStartPoint {
  final _StartKind _kind;
  final String? _trackRatingKey;
  final int? _trackIndex;
  final int _positionMs;

  /// Pick up from the saved position. The only kind that gets the smart resume
  /// rewind, because it is the only kind where time has passed since the
  /// listener was last here.
  const BookStartPoint.resume()
      : _kind = _StartKind.resume,
        _trackRatingKey = null,
        _trackIndex = null,
        _positionMs = 0;

  /// The start of the book. No rewind — an unstarted book has nothing to
  /// rewind to.
  const BookStartPoint.beginning()
      : _kind = _StartKind.beginning,
        _trackRatingKey = null,
        _trackIndex = null,
        _positionMs = 0;

  /// An exact point, identified by the track holding it: a named bookmark, a
  /// history entry, the live position of a stream being reloaded. Never
  /// rewound — an explicit jump has to land where it was told.
  const BookStartPoint.atTrack(String trackRatingKey, {int positionMs = 0})
      : _kind = _StartKind.trackKey,
        _trackRatingKey = trackRatingKey,
        _trackIndex = null,
        _positionMs = positionMs;

  /// An exact point in the nth track — the book screen's chapter and file
  /// lists, which already hold the index. Never rewound, as [atTrack].
  const BookStartPoint.atTrackIndex(int trackIndex, {int positionMs = 0})
      : _kind = _StartKind.trackIndex,
        _trackRatingKey = null,
        _trackIndex = trackIndex,
        _positionMs = positionMs;
}

/// Resolves [start] against a book's track keys and its saved position.
///
/// Pure, so the rules are testable without Hive or a player. Returns null when
/// the launch can't proceed — no tracks, or an explicit point naming a track
/// this book doesn't have. Refusing is deliberate: the call sites that
/// hand-rolled this fell through to "track 0, position 0" instead, and
/// silently restarting a book is the one outcome a player must never produce
/// by accident.
({int trackIndex, int positionMs, bool applyResumeRewind})? resolveBookStart({
  required BookStartPoint start,
  required List<String> trackRatingKeys,
  required BookPosition? saved,
}) {
  const fromScratch = (trackIndex: 0, positionMs: 0, applyResumeRewind: false);
  if (trackRatingKeys.isEmpty) return null;

  switch (start._kind) {
    case _StartKind.beginning:
      return fromScratch;

    case _StartKind.resume:
      // Nothing saved, or a saved position whose track is gone (the book was
      // re-imported and every key changed): resume is what was asked for, so
      // the start of the book is the honest answer rather than a refusal.
      if (saved == null) return fromScratch;
      final idx = trackRatingKeys.indexOf(saved.trackRatingKey);
      if (idx < 0) return fromScratch;
      return (
        trackIndex: idx,
        positionMs: saved.positionMs,
        applyResumeRewind: true,
      );

    case _StartKind.trackKey:
      final idx = trackRatingKeys.indexOf(start._trackRatingKey!);
      if (idx < 0) return null;
      return (
        trackIndex: idx,
        positionMs: start._positionMs,
        applyResumeRewind: false,
      );

    case _StartKind.trackIndex:
      final idx = start._trackIndex!;
      if (idx < 0 || idx >= trackRatingKeys.length) return null;
      return (
        trackIndex: idx,
        positionMs: start._positionMs,
        applyResumeRewind: false,
      );
  }
}

/// Loads a book into the player and, unless [play] is false, starts it.
///
/// The single path from "the listener picked something" to audio. Every launch
/// site comes through here — Continue Listening, the Resume and From-start
/// buttons, a chapter or file tap, a named bookmark, a history entry, session
/// restore after Android kills the app, the auto-reload after a stream error,
/// and the next book in a series — so what has to happen on every launch can't
/// be forgotten at one of them.
///
/// It owns three such things. The book's saved speed is applied *before* the
/// load, because once the play intent is declared audio can start the instant
/// buffering completes and setting the speed afterwards is audibly late; four
/// of the eight sites used to omit it altogether, so tapping a chapter played
/// the book at whatever speed the previous book had been using. The saved
/// position is resolved to a track index by one rule ([resolveBookStart]). And
/// the resume rewind is applied to genuine resumes only.
///
/// Returns false when the book couldn't be started; the caller decides whether
/// that deserves a message.
Future<bool> startBook({
  required AudioPlayerService service,
  required String bookRatingKey,
  required List<PlexTrack> tracks,
  required BookStartPoint from,
  LaunchPlayback playback = LaunchPlayback.start,
  bool isAutoReload = false,
}) async {
  try {
    final resolved = resolveBookStart(
      start: from,
      trackRatingKeys: [for (final t in tracks) t.ratingKey],
      saved: BookmarkStore.load(bookRatingKey),
    );
    if (resolved == null) {
      AppLog.log('playback', 'no start point resolved for book $bookRatingKey');
      return false;
    }

    await service.setSpeed(SettingsStore.getBookSpeed(bookRatingKey));
    await service.loadBook(
      bookRatingKey: bookRatingKey,
      tracks: tracks,
      startTrackIndex: resolved.trackIndex,
      startPositionMs: resolved.positionMs,
      applyResumeRewind: resolved.applyResumeRewind,
      playWhenReady: playback != LaunchPlayback.none,
      isAutoReload: isAutoReload,
    );
    if (playback == LaunchPlayback.start) await service.play();
    return true;
  } catch (e) {
    AppLog.log('playback', 'start failed for book $bookRatingKey: $e');
    return false;
  }
}
