import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../../core/diagnostics/app_log.dart';
import '../../core/plex/models/plex_track.dart';
import '../../core/plex/plex_api.dart';
import '../../core/plex/plex_client.dart';
import '../../core/audio/m4b_chapter_reader.dart';
import '../../core/storage/artwork_cache.dart';
import '../../core/storage/bookmark_store.dart';
import '../../core/storage/chapter_store.dart';
import '../../core/storage/settings_store.dart';
import '../../core/storage/completed_books_store.dart';
import '../../core/storage/download_store.dart';
import '../../core/storage/listen_days_store.dart';
import '../../core/storage/listening_history_store.dart';
import '../../core/storage/playback_log_store.dart';
import '../../core/storage/timeline_queue_store.dart';

class AudioPlayerService extends BaseAudioHandler with SeekHandler {
  final AudioPlayer _player = AudioPlayer();
  final PlexApi _api;
  late ConcatenatingAudioSource _playlist;

  List<PlexTrack> _tracks = [];
  String? _bookRatingKey;
  Timer? _progressTimer;
  Timer? _sleepTimer;
  DateTime? _trackingFrom;
  DateTime? _pausedAt;
  void Function()? onBookCompleted;
  void Function()? onBookmarkSaved;
  void Function()? onHistoryRecorded;
  Future<void> Function(String bookRatingKey, BookPosition? position)? onStreamError;
  bool _reloadInProgress = false;
  // Incremented on every loadBook; lets an in-flight load detect that a newer
  // load has superseded it across an await gap, so a stale failure can't
  // clobber the new book's state (which would silently drop position saves).
  int _loadGeneration = 0;
  int _lastChapterIndex = -1; // for chapter-aware notification title (single M4B)
  bool _completedThisSession = false; // guards the per-listen completion count
  int _previousAbsolutePositionMs = -1; // -1 = no saved position for undo
  final ValueNotifier<bool> canUndoSeekNotifier = ValueNotifier(false);
  String? _lastListenDay; // in-memory guard: mark a listen-day at most once/day
  // Set to a book's key the instant it finishes (natural end / 95%); the player
  // screen shows the finished panel while this matches the current book. Cleared
  // on the next loadBook.
  final ValueNotifier<String?> justFinishedBook = ValueNotifier<String?>(null);

  AudioPlayerService(this._api) {
    _player.playbackEventStream.listen(
      _broadcastState,
      onError: (Object e, StackTrace st) {
        // Network drop or stream error: save position immediately, then attempt
        // a transparent reload so the user doesn't need to restart the app.
        // Guard behind ready: if the error fires during loading, _player.position
        // is Duration.zero and writing that would overwrite the real resume point.
        AppLog.log('playback', 'stream error: $e');
        _progressTimer?.cancel();
        if (_player.processingState == ProcessingState.ready) {
          _saveAndReportPosition(state: 'paused');
        }
        final key = _bookRatingKey;
        if (key != null && !_reloadInProgress) {
          _reloadInProgress = true;
          onStreamError?.call(key, BookmarkStore.load(key));
        }
      },
    );
    // All listeners carry a no-op onError: an unhandled stream error would
    // cancel the subscription silently, killing e.g. completion detection or
    // chapter titles for the rest of the session.
    _player.currentIndexStream.listen((index) {
      if (index != null && index < _tracks.length) {
        final track = _tracks[index];
        mediaItem.add(_trackToMediaItem(track));
        _prefetchArtwork(track);
      }
    }, onError: (Object e, StackTrace st) {});
    _player.positionStream
        .listen(_updateChapterMediaItem, onError: (Object e, StackTrace st) {});
    _player.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) {
        _markBookCompleted();
        stop();
      }
    }, onError: (Object e, StackTrace st) {});

    // Pause when headphones are unplugged (ACTION_AUDIO_BECOMING_NOISY).
    // audio_service does not handle this automatically.
    AudioSession.instance.then((session) {
      session.becomingNoisyEventStream.listen((_) {
        if (_player.playing) pause();
      }, onError: (Object e, StackTrace st) {});

      // Duck volume on transient interruptions (nav prompts, notifications);
      // pause on longer interruptions. Don't auto-resume after pause — user
      // must press play, which is the standard audiobook expectation.
      session.interruptionEventStream.listen((event) {
        if (event.begin) {
          switch (event.type) {
            case AudioInterruptionType.duck:
              _player.setVolume(0.5);
            case AudioInterruptionType.pause:
            case AudioInterruptionType.unknown:
              if (_player.playing) pause();
          }
        } else {
          switch (event.type) {
            case AudioInterruptionType.duck:
              _player.setVolume(1.0);
            case AudioInterruptionType.pause:
            case AudioInterruptionType.unknown:
              break;
          }
        }
      }, onError: (Object e, StackTrace st) {});
    });
  }

  Future<void> loadBook({
    required String bookRatingKey,
    required List<PlexTrack> tracks,
    int startTrackIndex = 0,
    int startPositionMs = 0,
    bool isAutoReload = false,
    bool applyResumeRewind = false,
  }) async {
    if (tracks.isEmpty) throw ArgumentError('Cannot load a book with no tracks');

    final gen = ++_loadGeneration;
    _bookRatingKey = bookRatingKey;
    _tracks = tracks;
    _pausedAt = null; // new book — don't rewind on first play
    _lastChapterIndex = -1; // recompute chapter title for the new book
    _completedThisSession = false; // a fresh listen can be counted again
    justFinishedBook.value = null; // any (re)load dismisses the finished panel
    _previousAbsolutePositionMs = -1;
    canUndoSeekNotifier.value = false;
    // Only reset the reload guard on user-initiated loads. Auto-reloads keep it
    // true so that if the freshly-loaded stream also errors, we don't loop.
    if (!isAutoReload) _reloadInProgress = false;

    // Smart rewind on resume: shift the resume point back proportionally to how
    // long the user was away (from the bookmark's savedAt). Only on genuine
    // resume paths (Continue Listening, Resume button) — never on explicit jumps
    // (chapter/bookmark/history taps), which must land exactly where chosen.
    var resumePositionMs = startPositionMs;
    if (applyResumeRewind && resumePositionMs > 0) {
      final bookmark = BookmarkStore.load(bookRatingKey);
      if (bookmark != null) {
        final awaySeconds =
            DateTime.now().difference(bookmark.savedAt).inSeconds;
        final rewindMs = _resumeRewindMs(awaySeconds);
        resumePositionMs =
            (resumePositionMs - rewindMs).clamp(0, resumePositionMs);
      }
    }

    final sources = tracks.map((t) {
      final localPath = DownloadStore.getPath(t.ratingKey);
      if (localPath != null && File(localPath).existsSync()) {
        return AudioSource.file(localPath, tag: t.ratingKey);
      }
      final streamUrl = PlexClient.instance.buildStreamUrl(t.partKey);
      if (streamUrl == null) throw StateError('No Plex server configured');
      return AudioSource.uri(
        Uri.parse(streamUrl),
        headers: PlexClient.instance.authHeaders,
        tag: t.ratingKey,
      );
    }).toList();

    try {
      _playlist = ConcatenatingAudioSource(children: sources);
      await _player.setAudioSource(_playlist, initialIndex: startTrackIndex);
    } catch (e) {
      AppLog.log('playback', 'setAudioSource failed for book $bookRatingKey: $e');
      // Only clear state if no newer load has taken over: a failed stale load
      // (e.g. interrupted because the user tapped another book) must not wipe
      // the new book's key/tracks — that would silently drop its saves.
      if (gen == _loadGeneration) {
        _bookRatingKey = null;
        _tracks = [];
      }
      rethrow;
    }
    if (gen != _loadGeneration) return; // superseded by a newer load

    // Seek atomically after the source is confirmed ready so that callers
    // reading _player.position after loadBook() see the correct resume point.
    if (resumePositionMs > 0) {
      await _player.seek(
        Duration(milliseconds: resumePositionMs),
        index: startTrackIndex,
      );
      if (gen != _loadGeneration) return;
    }

    final queue = tracks.map(_trackToMediaItem).toList();
    this.queue.add(queue);
    mediaItem.add(_trackToMediaItem(tracks[startTrackIndex]));
    _prefetchArtwork(tracks[startTrackIndex]);
  }

  void _prefetchArtwork(PlexTrack track) {
    final thumbPath = track.thumbPath;
    if (thumbPath == null) return;
    final client = PlexClient.instance;
    final serverUri = client.serverUri;
    if (serverUri == null) return;
    if (ArtworkCache.getLocalUri(thumbPath) != null) return;

    ArtworkCache.prefetch(thumbPath, serverUri, client.authHeaders)
        .then((fileUri) {
      if (fileUri == null) return;
      final current = mediaItem.value;
      if (current?.id == track.ratingKey) {
        mediaItem.add(current!.copyWith(artUri: fileUri));
      }
    });
  }

  /// Seconds-away → rewind milliseconds for the smart resume-rewind. Shared by
  /// the live resume-after-pause path ([play]) and the resume-after-load path
  /// ([loadBook]) so the two curves can never drift apart. ~50 ms per second
  /// away (5 s per 100 s), no rewind under 5 s, capped at 60 s.
  static int _resumeRewindMs(int awaySeconds) {
    if (!SettingsStore.autoRewindEnabled) return 0;
    return awaySeconds <= 5 ? 0 : (awaySeconds * 50).clamp(0, 60000);
  }

  @override
  Future<void> play() async {
    // Smart rewind: if resuming after a pause, seek back proportionally to how
    // long the user was away. Only fires when paused within the same session
    // (_pausedAt is set). Uses the same curve as the resume-after-load path.
    if (_pausedAt != null && _player.processingState == ProcessingState.ready) {
      final awaySeconds = DateTime.now().difference(_pausedAt!).inSeconds;
      _pausedAt = null;
      final rewindMs = _resumeRewindMs(awaySeconds);
      if (rewindMs > 0) {
        final currentMs = _player.position.inMilliseconds;
        final targetMs = (currentMs - rewindMs).clamp(0, currentMs);
        if (targetMs < currentMs) await _player.seek(Duration(milliseconds: targetMs));
      }
    } else {
      _pausedAt = null;
    }

    // Save bookmark immediately so Continue Listening appears without waiting
    // for the 10-second progress timer to fire. Skip when the source is still
    // loading — position is not meaningful and would overwrite the resume point.
    if (_player.processingState == ProcessingState.ready) {
      await _saveAndReportPosition(state: 'playing');
    }
    _trackingFrom = DateTime.now();
    _startProgressTimer();
    _logEvent('play');
    await _player.play();
  }

  @override
  Future<void> pause() async {
    _progressTimer?.cancel();
    _pausedAt = DateTime.now();
    _logEvent('pause');
    await _player.pause();
    await _saveAndReportPosition(state: 'paused');
  }

  @override
  Future<void> stop() async {
    _progressTimer?.cancel();
    _sleepTimer?.cancel();
    _pausedAt = DateTime.now();
    await _saveAndReportPosition(state: 'stopped');
    await _player.stop();
    await super.stop();
  }

  @override
  Future<void> seek(Duration position) async {
    _previousAbsolutePositionMs = absolutePositionMs;
    canUndoSeekNotifier.value = true;
    await _player.seek(position);
  }

  /// Seek to [position] and record it in the playback log (used by the slider
  /// on drag-end only, so drags don't spam the history).
  Future<void> seekAndLog(Duration position) async {
    _previousAbsolutePositionMs = absolutePositionMs;
    canUndoSeekNotifier.value = true;
    _logEvent('seek', overridePositionMs: position.inMilliseconds);
    await _player.seek(position);
  }

  @override
  Future<void> skipToNext() async {
    _logEvent('skipNext');
    final chapters = _chaptersIfSingleTrack();
    if (chapters != null) {
      final posMs = _player.position.inMilliseconds;
      final next = chapters.firstWhere(
        (c) => c.start.inMilliseconds > posMs,
        orElse: () => chapters.last,
      );
      await _player.seek(next.start);
    } else {
      await _player.seekToNext();
    }
  }

  @override
  Future<void> skipToPrevious() async {
    _logEvent('skipPrev');
    final chapters = _chaptersIfSingleTrack();
    if (chapters != null) {
      final posMs = _player.position.inMilliseconds;
      final idx = chapters.lastIndexWhere(
        (c) => c.start.inMilliseconds <= posMs,
      );
      const thresholdMs = 5000;
      if (idx <= 0) {
        await _player.seek(Duration.zero);
      } else if (posMs - chapters[idx].start.inMilliseconds < thresholdMs) {
        await _player.seek(chapters[idx - 1].start);
      } else {
        await _player.seek(chapters[idx].start);
      }
    } else {
      await _player.seekToPrevious();
    }
  }

  /// Returns cached chapters for single-track (M4B) books, null otherwise.
  List<M4bChapter>? _chaptersIfSingleTrack() {
    if (_tracks.length != 1) return null;
    final chapters = ChapterStore.load(_tracks.first.ratingKey);
    return (chapters != null && chapters.isNotEmpty) ? chapters : null;
  }

  /// For single-file M4B books, surfaces the current chapter name on the
  /// lock-screen / notification as playback crosses chapter boundaries. No-op
  /// for multi-track books (each track already carries its own title) and when
  /// no chapters are cached. Only touches `mediaItem` when the chapter changes.
  void _updateChapterMediaItem(Duration position) {
    final chapters = _chaptersIfSingleTrack();
    if (chapters == null) {
      _lastChapterIndex = -1;
      return;
    }
    final posMs = position.inMilliseconds;
    var idx = 0;
    for (var i = chapters.length - 1; i >= 0; i--) {
      if (posMs >= chapters[i].start.inMilliseconds) {
        idx = i;
        break;
      }
    }
    if (idx == _lastChapterIndex) return;
    _lastChapterIndex = idx;
    final current = mediaItem.value;
    if (current == null) return;
    mediaItem.add(current.copyWith(title: chapters[idx].title));
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    await _player.seek(Duration.zero, index: index);
  }

  @override
  Future<void> setSpeed(double speed) async {
    await _player.setSpeed(speed);
    playbackState.add(playbackState.value.copyWith(speed: speed));
  }

  void setSleepTimer(Duration duration) {
    _sleepTimer?.cancel();
    _sleepTimer = Timer(duration, () async {
      await pause();
    });
  }

  void cancelSleepTimer() {
    _sleepTimer?.cancel();
    _sleepTimer = null;
  }

  /// Saves the current position immediately. Called by the periodic 10-s timer;
  /// skips when the player is not fully ready to avoid writing a stale position.
  Future<void> savePosition() async {
    if (_player.processingState == ProcessingState.ready) {
      await _saveAndReportPosition(state: _player.playing ? 'playing' : 'paused');
    }
  }

  /// Saves the current position unconditionally. Called on app lifecycle events
  /// (background, detach) so the position is never lost when Android kills the app
  /// while the player is buffering on a slow connection.
  /// _player.position remains valid during ProcessingState.buffering.
  Future<void> savePositionForLifecycle() async {
    final ps = _player.processingState;
    if (ps == ProcessingState.idle || ps == ProcessingState.completed) return;
    await _saveAndReportPosition(state: _player.playing ? 'playing' : 'paused');
  }

  @override
  Future<void> fastForward() async {
    final skipMs = SettingsStore.skipForwardSeconds * 1000;
    await seekAbsolute(Duration(milliseconds: absolutePositionMs + skipMs));
  }

  @override
  Future<void> rewind() async {
    final skipMs = SettingsStore.skipBackwardSeconds * 1000;
    await seekAbsolute(Duration(milliseconds: absolutePositionMs - skipMs));
  }

  AudioPlayer get player => _player;
  String? get currentBookRatingKey => _bookRatingKey;
  PlexTrack? get currentTrackInfo => _currentTrack;
  List<PlexTrack> get currentTracks => List.unmodifiable(_tracks);

  Stream<Duration> get positionStream => _player.positionStream;
  Stream<Duration?> get durationStream => _player.durationStream;
  Stream<int?> get currentIndexStream => _player.currentIndexStream;

  /// Total duration of all tracks in the currently loaded book.
  int get totalBookDurationMs =>
      _tracks.fold<int>(0, (s, t) => s + t.durationMs);

  /// Current position expressed as an absolute offset into the whole book.
  int get absolutePositionMs =>
      _absolutePositionMs(_player.position.inMilliseconds);

  /// Whether there is a previous position that [undoSeek] can restore.
  bool get canUndoSeek => _previousAbsolutePositionMs >= 0;

  /// Restore the position that existed before the most recent [seekAbsolute]
  /// call. Single undo level — a second call is a no-op. Seeks directly
  /// without re-saving, so undo cannot itself be undone.
  Future<void> undoSeek() async {
    if (_previousAbsolutePositionMs < 0) return;
    final target = _previousAbsolutePositionMs;
    _previousAbsolutePositionMs = -1;
    canUndoSeekNotifier.value = false;
    var ms = target.clamp(0, totalBookDurationMs);
    for (var i = 0; i < _tracks.length; i++) {
      final dur = _tracks[i].durationMs;
      if (ms <= dur || i == _tracks.length - 1) {
        await _player.seek(Duration(milliseconds: ms), index: i);
        return;
      }
      ms -= dur;
    }
  }

  /// Seek to [absolutePosition] within the book, resolving the correct
  /// track index and intra-track offset automatically.
  Future<void> seekAbsolute(Duration absolutePosition) async {
    _previousAbsolutePositionMs = absolutePositionMs;
    canUndoSeekNotifier.value = true;
    var ms = absolutePosition.inMilliseconds.clamp(0, totalBookDurationMs);
    for (var i = 0; i < _tracks.length; i++) {
      final dur = _tracks[i].durationMs;
      if (ms <= dur || i == _tracks.length - 1) {
        await _player.seek(Duration(milliseconds: ms), index: i);
        return;
      }
      ms -= dur;
    }
  }

  void logSleepTimer() => _logEvent('sleepTimer');

  void _logEvent(String type, {int? overridePositionMs}) {
    final track = _currentTrack;
    final bookKey = _bookRatingKey;
    if (track == null || bookKey == null) return;
    PlaybackLogStore.log(
      bookRatingKey: bookKey,
      event: AudioLogEvent(
        type: type,
        trackRatingKey: track.ratingKey,
        positionMs: overridePositionMs ?? _player.position.inMilliseconds,
        timestamp: DateTime.now(),
      ),
    );
  }

  Future<void> _markBookCompleted() async {
    final bookKey = _bookRatingKey;
    if (bookKey == null) return;
    // Guard against double-counting within one listen (the 95% auto-complete and
    // the completed-stream both fire). A fresh load resets the flag, so a later
    // re-listen counts as a new completion — that drives the listen count.
    if (_completedThisSession) return;
    _completedThisSession = true;
    await CompletedBooksStore.markCompleted(bookKey);
    final track = _tracks.firstOrNull;
    ListeningHistoryStore.recordCompleted(
      ratingKey: bookKey,
      title: track?.bookTitle,
      thumbPath: track?.thumbPath,
    );
    justFinishedBook.value = bookKey; // trigger the finished panel
    onBookCompleted?.call();
  }

  void _startProgressTimer() {
    _progressTimer?.cancel();
    _progressTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      // Skip saves while buffering/loading — position is not yet settled and
      // saving it would create a false drift on the next resume.
      if (!_player.playing || _player.processingState != ProcessingState.ready) {
        return;
      }
      _saveAndReportPosition(state: 'playing');
    });
  }

  Future<void> _saveAndReportPosition({required String state}) async {
    final track = _currentTrack;
    if (track == null || _bookRatingKey == null) return;

    final now = DateTime.now();
    if (_trackingFrom != null) {
      final elapsed = now.difference(_trackingFrom!);
      // Credit at most 15 s per save. The progress timer fires every 10 s, so a
      // legit segment is ≤~10 s; a longer gap means the timer was throttled
      // (e.g. background Doze) — clamp rather than drop it so we don't undercount.
      final creditedMs = elapsed.inMilliseconds.clamp(0, 15000);
      if (creditedMs > 0) {
        ListeningHistoryStore.recordListening(creditedMs);
        onHistoryRecorded?.call();
      }
    }
    _trackingFrom = (state == 'playing') ? now : null;

    // Durable per-read-through listen-day record (drives the finished panel's
    // "days listened" / span). At most once per calendar day while playing.
    if (state == 'playing') {
      final dayKey = '${now.year}-${now.month}-${now.day}';
      if (_lastListenDay != dayKey) {
        _lastListenDay = dayKey;
        ListenDaysStore.markListenedToday(
          _bookRatingKey!,
          lastCompletedAt:
              CompletedBooksStore.completionDates(_bookRatingKey!).lastOrNull,
        );
      }
    }

    final positionMs = _player.position.inMilliseconds;
    final absolutePositionMs = _absolutePositionMs(positionMs);

    // Awaited so the write is durable before this future completes — the
    // lifecycle save path (app backgrounded/killed) depends on it.
    await BookmarkStore.save(
      _bookRatingKey!,
      BookPosition(
        trackRatingKey: track.ratingKey,
        positionMs: positionMs,
        absolutePositionMs: absolutePositionMs,
        totalDurationMs: _tracks.fold<int>(0, (sum, t) => sum + t.durationMs),
        savedAt: DateTime.now(),
      ),
    );
    onBookmarkSaved?.call();

    _api.reportTimeline(
      ratingKey: track.ratingKey,
      key: track.key,
      positionMs: positionMs,
      durationMs: track.durationMs,
      state: state,
    ).then((_) {
      // Success — opportunistically flush anything queued while offline.
      _flushTimelineQueue();
    }, onError: (_) async {
      // Server unreachable — persist the latest position for this book so it
      // survives a kill and syncs to Plex's "Continue" on the next success or
      // app foreground. Last-write-wins: one pending entry per book.
      final bookKey = _bookRatingKey;
      if (bookKey != null) {
        await TimelineQueueStore.enqueue(
          bookKey,
          PendingTimeline(
            ratingKey: track.ratingKey,
            key: track.key,
            positionMs: positionMs,
            durationMs: track.durationMs,
            state: state,
            savedAt: DateTime.now(),
          ),
        );
      }
    });
  }

  bool _flushingQueue = false;

  /// Replays position updates that previously failed to reach Plex (e.g. saved
  /// while offline). Stops at the first failure (still offline). Safe to call
  /// repeatedly; called on successful reports and on app foreground.
  Future<void> flushTimelineQueue() => _flushTimelineQueue();

  Future<void> _flushTimelineQueue() async {
    if (_flushingQueue || TimelineQueueStore.isEmpty) return;
    _flushingQueue = true;
    try {
      for (final entry in TimelineQueueStore.all().entries) {
        final t = entry.value;
        try {
          await _api.reportTimeline(
            ratingKey: t.ratingKey,
            key: t.key,
            positionMs: t.positionMs,
            durationMs: t.durationMs,
            state: t.state,
          );
          await TimelineQueueStore.remove(entry.key);
        } catch (_) {
          break; // still offline — try again next time
        }
      }
    } finally {
      _flushingQueue = false;
    }
  }

  PlexTrack? get _currentTrack {
    final index = _player.currentIndex;
    if (index == null || index >= _tracks.length) return null;
    return _tracks[index];
  }

  int _absolutePositionMs(int currentTrackPositionMs) {
    final index = _player.currentIndex ?? 0;
    var offset = 0;
    for (var i = 0; i < index && i < _tracks.length; i++) {
      offset += _tracks[i].durationMs;
    }
    return offset + currentTrackPositionMs;
  }

  void _broadcastState(PlaybackEvent event) {
    final playing = _player.playing;
    playbackState.add(playbackState.value.copyWith(
      controls: [
        MediaControl.rewind,
        if (playing) MediaControl.pause else MediaControl.play,
        MediaControl.fastForward,
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
        MediaAction.rewind,
        MediaAction.fastForward,
        MediaAction.skipToNext,
        MediaAction.skipToPrevious,
      },
      androidCompactActionIndices: const [0, 1, 2],
      processingState: {
        ProcessingState.idle: AudioProcessingState.idle,
        ProcessingState.loading: AudioProcessingState.loading,
        ProcessingState.buffering: AudioProcessingState.buffering,
        ProcessingState.ready: AudioProcessingState.ready,
        ProcessingState.completed: AudioProcessingState.completed,
      }[_player.processingState]!,
      playing: playing,
      updatePosition: _player.position,
      bufferedPosition: _player.bufferedPosition,
      speed: _player.speed,
      queueIndex: event.currentIndex,
    ));
  }

  MediaItem _trackToMediaItem(PlexTrack track) {
    final thumbPath = track.thumbPath;
    // Prefer a local cached file (no token in URI) over the authenticated network URL.
    final artUri = ArtworkCache.getLocalUri(thumbPath)
        ?? PlexClient.instance.buildArtUri(thumbPath);

    return MediaItem(
      id: track.ratingKey,
      title: track.title,
      album: track.bookTitle,
      artist: track.authorName,
      duration: Duration(milliseconds: track.durationMs),
      artUri: artUri,
    );
  }

  @override
  Future<void> onTaskRemoved() async {
    await stop();
  }
}
