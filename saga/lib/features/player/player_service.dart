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
import '../../core/storage/track_cache_store.dart';
import 'resume_rewind.dart';
import 'session_restore.dart';
import 'track_position_math.dart';

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
  bool _restoringSession = false; // re-entry guard for _restoreLastSession
  // True while paused *by* an audio interruption (call, alarm) rather than by
  // the user — the only case where interruption-end may auto-resume. Cleared
  // by any user-initiated play (see [play]).
  bool _pausedByInterruption = false;
  DateTime? _interruptionBeganAt;
  // True when the device's audio mode indicated telephony (ring / call / VoIP)
  // at interruption begin — the one case where a long interruption may still
  // auto-resume. Sampled asynchronously; see [_onInterruptionBegin].
  bool _interruptionCallLike = false;
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
    }, onError: (Object e, StackTrace st) {
      // Should never fire — which is exactly why it's worth recording.
      AppLog.log('playback', 'listener error: $e');
    });
    _player.positionStream
        .listen(_updateChapterMediaItem, onError: (Object e, StackTrace st) {
      // Should never fire — which is exactly why it's worth recording.
      AppLog.log('playback', 'listener error: $e');
    });
    _player.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) {
        _markBookCompleted();
        stop();
      }
    }, onError: (Object e, StackTrace st) {
      // Should never fire — which is exactly why it's worth recording.
      AppLog.log('playback', 'listener error: $e');
    });

    // Pause when headphones are unplugged (ACTION_AUDIO_BECOMING_NOISY).
    // audio_service does not handle this automatically.
    AudioSession.instance.then((session) async {
      // Declare spoken-word content (contentType speech, focus gain,
      // pause-when-ducked enforced at the source). Without this,
      // audio_session falls back to a music profile on the first focus
      // request — wrong attributes for an audiobook app.
      try {
        await session.configure(const AudioSessionConfiguration.speech());
      } catch (e) {
        AppLog.log('playback', 'audio session configure failed: $e');
      }
      session.becomingNoisyEventStream.listen((_) {
        if (_player.playing) pause();
      }, onError: (Object e, StackTrace st) {
      // Should never fire — which is exactly why it's worth recording.
      AppLog.log('playback', 'listener error: $e');
    });

      // Interruption policy for spoken word: ducking (lowering volume under a
      // nav prompt or notification) means missed words — unlike music, speech
      // can't be half-heard. So when auto-resume is enabled, duck requests
      // pause-and-resume like any other transient interruption (the Audible /
      // Pocket Casts convention). With auto-resume off, ducks fall back to
      // lowering volume — pausing without resuming would be strictly worse.
      // Resume decisions live in [_maybeResumeAfterInterruption]; the system's
      // "resuming is appropriate" signal alone is NOT sufficient — see there.
      session.interruptionEventStream.listen((event) {
        if (event.begin) {
          switch (event.type) {
            case AudioInterruptionType.duck:
              if (SettingsStore.resumeAfterInterruption) {
                if (_player.playing) _onInterruptionBegin('duck');
              } else {
                _player.setVolume(0.5);
              }
            case AudioInterruptionType.pause:
            case AudioInterruptionType.unknown:
              if (_player.playing) _onInterruptionBegin(event.type.name);
          }
        } else {
          switch (event.type) {
            case AudioInterruptionType.duck:
              _player.setVolume(1.0); // no-op if we paused instead of ducking
              _maybeResumeAfterInterruption('duck');
            case AudioInterruptionType.pause:
              _maybeResumeAfterInterruption('pause');
            case AudioInterruptionType.unknown:
              // Resume not recommended — permanent focus loss.
              _pausedByInterruption = false;
          }
        }
      }, onError: (Object e, StackTrace st) {
      // Should never fire — which is exactly why it's worth recording.
      AppLog.log('playback', 'listener error: $e');
    });
    });
  }

  /// Telephony check: ringtone / in-call / in-communication audio mode means
  /// the current focus loss came from a phone or VoIP call rather than another
  /// media app. Reads the platform AudioManager mode — no permission needed.
  static Future<bool> _inCallAudioMode() async {
    try {
      final mode = await AndroidAudioManager().getMode();
      return mode == AndroidAudioHardwareMode.ringtone ||
          mode == AndroidAudioHardwareMode.inCall ||
          mode == AndroidAudioHardwareMode.inCommunication;
    } catch (_) {
      return false; // unknown → treat as not a call
    }
  }

  void _onInterruptionBegin(String type) {
    _pausedByInterruption = true;
    _interruptionBeganAt = DateTime.now();
    _interruptionCallLike = false;
    // Sampled async so the pause itself is never delayed by a platform call.
    unawaited(_inCallAudioMode().then((inCall) {
      if (inCall) _interruptionCallLike = true;
    }));
    AppLog.log('playback', 'interruption begin ($type)');
    pause();
  }

  /// The focus-regained event says resuming is *allowed* — not that it's
  /// wanted. Another media app (video, music) that took transient focus and
  /// later released it (paused its stream, rebuffered, ad break) produces the
  /// exact same event as a phone call ending — and resuming the audiobook
  /// over someone's video is the worst failure mode of naive auto-resume.
  /// So resume only when the interruption was plausibly call-like: telephony
  /// audio mode at begin or end, or a short blip (≤ 30 s — TTS announcements,
  /// quickly dismissed alarms). A long non-call interruption stays paused.
  Future<void> _maybeResumeAfterInterruption(String type) async {
    if (!_pausedByInterruption) return;
    _pausedByInterruption = false;
    if (!SettingsStore.resumeAfterInterruption) return;
    final began = _interruptionBeganAt;
    final elapsed = began == null ? null : DateTime.now().difference(began);
    final callLike = _interruptionCallLike || await _inCallAudioMode();
    final shortBlip =
        elapsed != null && elapsed <= const Duration(seconds: 30);
    if (callLike || shortBlip) {
      AppLog.log('playback',
          'interruption end ($type): resuming — ${callLike ? 'call-like' : 'short'} (${elapsed?.inSeconds ?? '?'}s)');
      await play();
    } else {
      AppLog.log('playback',
          'interruption end ($type): NOT resuming — media-like (${elapsed?.inSeconds ?? '?'}s)');
    }
  }

  Future<void> loadBook({
    required String bookRatingKey,
    required List<PlexTrack> tracks,
    int startTrackIndex = 0,
    int startPositionMs = 0,
    bool isAutoReload = false,
    bool applyResumeRewind = false,
    bool playWhenReady = false,
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

    // Publish queue/notification metadata before the (potentially slow) network
    // load, so the media notification has real content the moment the service
    // goes foreground below — not a blank "Saga" card until buffering finishes.
    queue.add(tracks.map(_trackToMediaItem).toList());
    mediaItem.add(_trackToMediaItem(tracks[startTrackIndex]));
    _prefetchArtwork(tracks[startTrackIndex]);

    try {
      _playlist = ConcatenatingAudioSource(children: sources);
      if (playWhenReady) {
        // Declare the play intent BEFORE the network await. Broadcasting
        // playing=true is what makes audio_service promote to a foreground
        // service and take its wake lock — started here, while the app is
        // still guaranteed foreground, the initial buffer survives the user
        // backgrounding the app mid-load. Started only after the load (the
        // old ordering), the process is an ordinary cached app for the whole
        // round-trip to Plex and Android may freeze it, stalling the stream.
        // play()'s future is intentionally unawaited: it only completes once
        // playback actually starts, i.e. after setAudioSource below.
        if (_player.audioSource != null) {
          // A previous source is still loaded — mute so the early play intent
          // doesn't audibly resume the old audio during the load. Restored in
          // the finally below.
          await _player.setVolume(0);
        }
        unawaited(_player.play());
      }
      // initialPosition (rather than a seek after load) so playback starts at
      // the resume point directly — with playWhenReady, a post-load seek would
      // audibly play a moment from 0:00 first. Callers reading _player.position
      // after loadBook() still see the correct resume point.
      await _player.setAudioSource(
        _playlist,
        initialIndex: startTrackIndex,
        initialPosition: Duration(milliseconds: resumePositionMs),
      );
    } catch (e) {
      AppLog.log('playback', 'setAudioSource failed for book $bookRatingKey: $e');
      // Withdraw the play intent: a failed load must not leave a playing=true
      // foreground service with no audio source.
      if (playWhenReady) unawaited(_player.pause());
      // Only clear state if no newer load has taken over: a failed stale load
      // (e.g. interrupted because the user tapped another book) must not wipe
      // the new book's key/tracks — that would silently drop its saves.
      if (gen == _loadGeneration) {
        _bookRatingKey = null;
        _tracks = [];
      }
      rethrow;
    } finally {
      // Unmute on every exit path (success, failure, superseded) — a stray
      // zero volume would make all playback silent with no visible cause.
      if (_player.volume == 0) await _player.setVolume(1);
    }
    if (gen != _loadGeneration) return; // superseded by a newer load
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
  static int _resumeRewindMs(int awaySeconds) =>
      resumeRewindMs(awaySeconds, enabled: SettingsStore.autoRewindEnabled);

  /// After process death (OEM battery kill, memory pressure) Android 11+ keeps
  /// the media card in the shade, and tapping its play button cold-starts this
  /// service with no book loaded. Restore the most recently listened book —
  /// the same one Continue Listening would offer — so the controls work
  /// instead of silently doing nothing. Returns true when a book was loaded
  /// (with playback already starting via playWhenReady).
  Future<bool> _restoreLastSession() async {
    if (_restoringSession) return false; // absorb double-taps mid-restore
    _restoringSession = true;
    try {
      final bookKey = mostRecentBookRatingKey(BookmarkStore.allPositions());
      if (bookKey == null) return false;
      final position = BookmarkStore.load(bookKey);
      // Cache first: instant, and works offline for downloaded books. The
      // network fetch covers streamed books (needs the server reachable).
      final tracks =
          TrackCacheStore.load(bookKey) ?? await _api.fetchTracks(bookKey);
      if (tracks.isEmpty) return false;
      final idx = position != null
          ? tracks.indexWhere((t) => t.ratingKey == position.trackRatingKey)
          : -1;
      await setSpeed(SettingsStore.getBookSpeed(bookKey));
      await loadBook(
        bookRatingKey: bookKey,
        tracks: tracks,
        startTrackIndex: idx < 0 ? 0 : idx,
        startPositionMs: position?.positionMs ?? 0,
        applyResumeRewind: true,
        playWhenReady: true,
      );
      AppLog.log('playback', 'restored last session: book $bookKey');
      return true;
    } catch (e) {
      AppLog.log('playback', 'session restore failed: $e');
      return false;
    } finally {
      _restoringSession = false;
    }
  }

  @override
  Future<void> play() async {
    // No book loaded means this play command reached a freshly cold-started
    // service (media controls after process death) — restore the session.
    // Without a successful restore we must return before _player.play():
    // with no source it broadcasts playing=true and never completes, leaving
    // the notification stuck on a lying pause icon.
    if (_bookRatingKey == null || _tracks.isEmpty) {
      if (!await _restoreLastSession()) return;
    }

    // Any play (user or auto-resume itself) settles a pending interruption —
    // a later interruption-end must not trigger a second resume.
    _pausedByInterruption = false;

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
    final targetMs = _previousAbsolutePositionMs;
    _previousAbsolutePositionMs = -1;
    canUndoSeekNotifier.value = false;
    final target = trackFromAbsolute(_trackDurationsMs, targetMs);
    if (target == null) return;
    await _player.seek(Duration(milliseconds: target.positionMs),
        index: target.index);
  }

  /// Seek to [absolutePosition] within the book, resolving the correct
  /// track index and intra-track offset automatically.
  /// Absolute (book-level) bounds of the chapter containing the current
  /// position, for chapter-range scrubbing. Single-file books use embedded
  /// chapters; multi-file books use the current track (one file ≈ one
  /// chapter). Falls back to the whole book when neither applies.
  ({int startMs, int endMs}) currentChapterRangeMs() {
    final totalMs = totalBookDurationMs;
    final chapters = _chaptersIfSingleTrack();
    if (chapters != null) {
      return chapterRangeAt(
        [for (final c in chapters) c.start.inMilliseconds],
        _player.position.inMilliseconds,
        totalMs,
      );
    }
    if (_tracks.length > 1) {
      final durations = _trackDurationsMs;
      final idx = (_player.currentIndex ?? 0).clamp(0, durations.length - 1);
      final startMs = absoluteFromTrack(durations, idx, 0);
      return (startMs: startMs, endMs: startMs + durations[idx]);
    }
    return (startMs: 0, endMs: totalMs);
  }

  Future<void> seekAbsolute(Duration absolutePosition) async {
    _previousAbsolutePositionMs = absolutePositionMs;
    canUndoSeekNotifier.value = true;
    final target =
        trackFromAbsolute(_trackDurationsMs, absolutePosition.inMilliseconds);
    if (target == null) return;
    await _player.seek(Duration(milliseconds: target.positionMs),
        index: target.index);
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

  List<int> get _trackDurationsMs => [for (final t in _tracks) t.durationMs];

  int _absolutePositionMs(int currentTrackPositionMs) => absoluteFromTrack(
      _trackDurationsMs, _player.currentIndex ?? 0, currentTrackPositionMs);

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

  /// The user swiped the app out of recents: stop playback and the service.
  /// Deliberate decision (July 2026, reversed once): a keep-playing variant
  /// shipped briefly because it's what music apps do, but in actual use the
  /// owner expects swipe-away to mean "quit" — audiobooks aren't background
  /// wallpaper like playlists. Position is saved by [stop]; session restore
  /// brings the book back on the next play. Do not re-litigate without a
  /// user request in the other direction.
  @override
  Future<void> onTaskRemoved() async {
    await stop();
  }
}
