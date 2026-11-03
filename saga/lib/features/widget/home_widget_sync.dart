import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:saga_native/saga_native.dart';

import '../../core/diagnostics/app_log.dart';
import '../../core/local_library.dart';
import '../../core/plex/plex_client.dart';
import '../../core/storage/artwork_cache.dart';
import '../../core/storage/bookmark_store.dart';
import '../../core/storage/settings_store.dart';
import '../../core/storage/track_cache_store.dart';
import '../../core/theme/saga_theme.dart';
import '../../core/utils/format.dart';
import '../../shared/widgets/resume_card.dart';
import '../player/player_service.dart';

/// What the home-screen widget shows, as display-only values for the native
/// side to draw verbatim.
///
/// The book is Home's resume card's book (newest saved position, not
/// finished: [localInProgressKeys]), except that a loaded book wins while it
/// is in progress, because that's the book the widget's pause acts on. Local
/// stores only, so it answers on a cold start with the server unreachable.
///
/// Never read back: the widget's buttons name a book, and the app resumes it
/// from Hive. absorb kept a copy of the position for its widget and then had to
/// stop the stale copy being written back over the real one.
Map<String, Object?> widgetSnapshot({
  required bool signedIn,
  String? loadedBookKey,
}) {
  final colors = widgetColors();
  if (!signedIn) return {'state': 'signedOut', ...colors};
  final keys = localInProgressKeys();
  final key = keys.contains(loadedBookKey) ? loadedBookKey : keys.firstOrNull;
  final book = key == null ? null : localBook(key);
  if (key == null || book == null) return {'state': 'empty', ...colors};
  final pos = BookmarkStore.load(key);
  final tracks = TrackCacheStore.load(key);
  // With "Scrub within chapter" on, the bar, time left and % follow the
  // chapter, as the player's seek bar does (GitHub #17). From the time
  // listened in whole minutes: a chapter's bar moves every few seconds, and
  // the widget redraws whenever its snapshot changes, so it would redraw on
  // every 10 s save rather than once a minute. Rounding what's listened, not
  // what's left, keeps the bar from running ahead: rounding what's left drew
  // a fresh 7.6-minute chapter at 8%.
  final chapter =
      SettingsStore.chapterScrub ? resumeChapterProgress(tracks, pos) : null;
  final int? remainingMs;
  final double fraction;
  if (chapter != null) {
    final listenedMs =
        (chapter.spanMs - chapter.remainingMs) ~/ 60000 * 60000;
    remainingMs = chapter.spanMs - listenedMs;
    fraction = listenedMs / chapter.spanMs;
  } else {
    (:remainingMs, :fraction) = resumeProgress(book, pos);
  }
  return {
    ...colors,
    'state': 'book',
    'bookKey': key,
    'title': book.title,
    'chapter': resumeChapterLabel(tracks, pos),
    'timeLeft': remainingMs == null
        ? null
        : chapter != null
            ? '${fmtListenedMs(remainingMs)} left in chapter'
            : '${fmtListenedMs(remainingMs)} left',
    'percent': '${(fraction * 100).round()}%',
    'progress': (fraction * 1000).round().clamp(0, 1000),
    // A path to the app-private cover file, never a URL: the widget draws
    // from disk, and a URL is the shape a credential leaks in.
    'cover': ArtworkCache.getLocalUri(book.thumbPath)?.toFilePath(),
    'skipBack': SettingsStore.skipBackwardSeconds,
    'skipForward': SettingsStore.skipForwardSeconds,
  };
}

/// The widget wears the app's theme. Read from the stored setting, not from
/// [SagaColors]: that is applied by the app's `build()`, which never runs in
/// the headless engine a widget tap starts.
Map<String, int> widgetColors() {
  final t = SagaThemeData.fromVariant(SagaThemeVariant.values[SettingsStore
      .themeIndex
      .clamp(0, SagaThemeVariant.values.length - 1)]);
  return {
    'colorSurface': t.surface.toARGB32(),
    // The card's bar track, as on Home's card.
    'colorTrack': t.surfaceAlt.toARGB32(),
    'colorFg': t.fg.toARGB32(),
    'colorFgMuted': t.fgMuted.toARGB32(),
    'colorFgSubtle': t.fgSubtle.toARGB32(),
    'colorBar': t.accent.toARGB32(),
    // accentDim, as the card's footer: the widest amber area (Onyx).
    'colorFooter': (t.accentDim ?? t.accent).toARGB32(),
    'colorAccentFg': t.accentFg.toARGB32(),
    'colorMarkSide': t.markSide.toARGB32(),
    'colorMarkMiddle': t.markMiddle.toARGB32(),
  };
}

/// Keeps the home-screen widget in step with the app.
///
/// Redraws when the loaded book changes, when play/pause flips, after the
/// service saves a position or records a finish, and when the app goes to
/// the background (anything changed inside it: a finish marked by hand, a
/// sign-out, a server switch). Every call is cheap: the native side is only
/// called when what it would draw has changed, so the 10 s position saves
/// redraw it once a minute, as the time left changes.
class HomeWidgetSync {
  HomeWidgetSync._();

  static AudioPlayerService? _service;
  static Map<String, Object?>? _lastSnapshot;
  static bool? _lastPlaying;
  static final _coversRequested = <String>{};

  static void attach(AudioPlayerService service) {
    _service = service;
    service.mediaItem.listen((_) => refresh());
    service.playbackState
        .map((s) => s.playing)
        .distinct()
        .listen((_) => refresh());
    service.progressChanged.listen((_) => refresh());
    refresh();
  }

  static Future<void> refresh() async {
    try {
      final service = _service;
      final client = PlexClient.instance;
      final snapshot = widgetSnapshot(
        signedIn: client.isAuthenticated,
        loadedBookKey: service?.currentBookRatingKey,
      );
      // "Playing" goes to the native side in memory only: a dead process
      // must draw paused, and a stored flag outlives it (absorb, AntennaPod).
      final playing = service?.playbackState.value.playing ?? false;
      if (mapEquals(snapshot, _lastSnapshot) && playing == _lastPlaying) {
        return;
      }
      _lastSnapshot = snapshot;
      _lastPlaying = playing;
      await SagaWidgetBridge.update(snapshot, playing: playing);
      _fetchMissingCover(snapshot, client);
    } catch (e) {
      AppLog.log('widget', 'refresh failed: $e');
    }
  }

  /// A book that hasn't been loaded since its cover left the cache (or ever,
  /// on this phone) has no cover file. Fetch it once, the same way the player
  /// does, and redraw.
  static void _fetchMissingCover(
      Map<String, Object?> snapshot, PlexClient client) {
    if (snapshot['state'] != 'book' || snapshot['cover'] != null) return;
    final key = snapshot['bookKey'] as String;
    final thumb = localBook(key)?.thumbPath;
    final serverUri = client.serverUri;
    if (thumb == null || serverUri == null) return;
    if (!_coversRequested.add(thumb)) return;
    unawaited(ArtworkCache.prefetch(thumb, serverUri, client.authHeaders)
        .then((uri) {
      if (uri != null) refresh();
    }));
  }
}
