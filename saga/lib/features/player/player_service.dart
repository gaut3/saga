import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:rxdart/rxdart.dart';

import '../../core/cast/cast_service.dart';
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
import '../../core/storage/listen_days_store.dart';
import '../../core/storage/listening_history_store.dart';
import '../../core/storage/playback_log_store.dart';
import '../../core/storage/timeline_queue_store.dart';
import '../../core/storage/track_cache_store.dart';
import 'book_launch.dart';
import 'cast_queue.dart';
import 'media_browse.dart';
import 'resume_rewind.dart';
import 'session_restore.dart';
import 'track_audio_source.dart';
import 'track_position_math.dart';
import '../../core/book_status.dart';

class AudioPlayerService extends BaseAudioHandler with SeekHandler {
  /// `useProxyForRequestHeaders: false` — headers go straight to ExoPlayer.
  ///
  /// just_audio's default is to start a **cleartext HTTP server on localhost**
  /// and route every stream through it, purely so the auth header can be
  /// attached. Android has never needed that: the platform side applies the
  /// headers itself (`setDefaultRequestProperties` in `AudioPlayer.java`), so
  /// the proxy bought nothing and cost three things — a loopback port serving
  /// this listener's audiobooks to any app on the device that finds it, a bare
  /// `_handlerMap[path]!` that throws on an unmatched request, and an upstream
  /// fetch that catches only `HttpException`, so a DNS failure on the server's
  /// `plex.direct` name escaped as an uncaught async error.
  ///
  /// Turning it off deletes all three. It also means nothing in the app speaks
  /// cleartext to localhost any more, which is what allows the network security
  /// config to be tightened.
  final AndroidLoudnessEnhancer _loudnessEnhancer = AndroidLoudnessEnhancer();
  late final AudioPlayer _player = AudioPlayer(
    useProxyForRequestHeaders: false,
    audioPipeline: AudioPipeline(androidAudioEffects: [_loudnessEnhancer]),
  );
  final PlexApi _api;
  late ConcatenatingAudioSource _playlist;

  List<PlexTrack> _tracks = [];
  String? _bookRatingKey;
  Timer? _progressTimer;
  DateTime? _trackingFrom;
  DateTime? _pausedAt;
  void Function()? onBookCompleted;
  void Function()? onBookmarkSaved;
  void Function()? onHistoryRecorded;
  Future<void> Function(String bookRatingKey, BookPosition? position)? onStreamError;
  bool _reloadInProgress = false;
  bool _restoringSession = false; // re-entry guard for _restoreLastSession
  bool _clearing = false; // re-entry guard for stopAndClear
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
  // True from loadBook's identity swap until its finally: the fields name the
  // incoming book while the platform player still holds the outgoing one, so
  // any position save in that window would file A's position under B's key.
  bool _loadInProgress = false;
  // The phone player's volume is the product of three things, and only
  // [_applyVolume] writes it: loadBook's mute (hides the old audio during a
  // playWhenReady load), the interruption duck, and the sleep timer's fade.
  // Three writers of one volume each restored to 1.0 and wiped out the
  // others: a duck ending mid-fade jumped back to full volume.
  bool _mutedForLoad = false;
  double _duckLevel = 1.0;
  double _fadeLevel = 1.0;
  int _lastChapterIndex = -1; // for chapter-aware notification title (single M4B)
  bool _completedThisSession = false; // guards the per-listen completion count
  int _previousAbsolutePositionMs = -1; // -1 = no saved position for undo
  final ValueNotifier<bool> canUndoSeekNotifier = ValueNotifier(false);
  String? _lastListenDay; // in-memory guard: mark a listen-day at most once/day
  // Set to a book's key the instant it finishes (plays to its end); the player
  // screen shows the finished panel while this matches the current book. Cleared
  // on the next loadBook.
  final ValueNotifier<String?> justFinishedBook = ValueNotifier<String?>(null);

  /// Seconds left before the next book starts automatically, or null when no
  /// advance is pending. Driven by the completion handler in player_provider;
  /// the finished panel renders the countdown and its Cancel from this.
  final ValueNotifier<int?> autoAdvanceCountdown = ValueNotifier<int?>(null);
  Timer? _autoAdvanceTimer;

  /// The next book's key when an auto-advance fired and the book didn't
  /// start, so the finished panel can say so where the countdown was — it
  /// used to just vanish, indistinguishable from a cancel. Cleared by the
  /// next countdown and by any load.
  final ValueNotifier<String?> autoAdvanceFailed = ValueNotifier<String?>(null);

  /// Fires once a jump the listener made has *landed* — seek, skip, undo,
  /// queue jump, or the book reloaded at a new point (a chapter in a
  /// multi-file book, a bookmark, a session's Resume). Not the automatic move
  /// to the next file, and not a stream-error reload. just_audio's own seek
  /// discontinuity fires before the platform seek, still on the old track,
  /// and a reload emits none, so the end-of-chapter timer listens here.
  Stream<void> get jumps => _jumps.stream;
  final _jumps = StreamController<void>.broadcast();
  void _jumped() => _jumps.add(null);

  /// Fires after a position save and after a finish is recorded: what the
  /// home-screen widget redraws on. A stream rather than another callback
  /// slot, because those slots are filled by a Riverpod provider, and the
  /// headless engine a widget tap starts (app closed) never builds it.
  Stream<void> get progressChanged => _progressChanged.stream;
  final _progressChanged = StreamController<void>.broadcast();

  /// Stops a pending auto-advance. Called by any user action that implies they
  /// want to stay put — play, pause, seek, dismissing the panel, loading
  /// another book, or clearing the session.
  void cancelAutoAdvance() {
    if (_autoAdvanceTimer == null && autoAdvanceCountdown.value == null) return;
    _autoAdvanceTimer?.cancel();
    _autoAdvanceTimer = null;
    autoAdvanceCountdown.value = null;
  }

  /// Counts [seconds] down and then runs [start], unless cancelled first.
  ///
  /// The delay is the escape hatch: the book has just finished, and if the user
  /// is looking at the screen they get a beat to say no. With the screen off it
  /// simply elapses.
  void scheduleAutoAdvance(int seconds, Future<void> Function() start) {
    cancelAutoAdvance();
    autoAdvanceFailed.value = null;
    autoAdvanceCountdown.value = seconds;
    _autoAdvanceTimer = Timer.periodic(const Duration(seconds: 1), (t) async {
      final left = (autoAdvanceCountdown.value ?? 0) - 1;
      if (left > 0) {
        autoAdvanceCountdown.value = left;
        return;
      }
      cancelAutoAdvance();
      await start();
    });
  }

  AudioPlayerService(this._api) {
    // Persisted audio settings; both survive setAudioSource, so once per
    // player is enough. Fire-and-forget: the platform player may not be
    // attached yet, and just_audio replays them on activation.
    unawaited(_player.setSkipSilenceEnabled(SettingsStore.skipSilence));
    unawaited(setVolumeBoost(SettingsStore.volumeBoostDb));
    _player.playbackEventStream.listen(
      _broadcastState,
      onError: (Object e, StackTrace st) {
        // Network drop or stream error: save position immediately, then attempt
        // a transparent reload so the user doesn't need to restart the app.
        // Guard behind ready: if the error fires during loading, _player.position
        // is Duration.zero and writing that would overwrite the real resume point.
        AppLog.log('playback', 'stream error: $e');
        // The phone's player sits paused while a TV plays; an error on it
        // must not reload the book onto the TV.
        if (_castActive) return;
        _progressTimer?.cancel();
        // Capture where playback *actually* is before anything else touches it.
        // This used to reload from `BookmarkStore.load(key)`, which is up to a
        // full progress-timer interval (10 s) behind — and the save above can't
        // be awaited inside a stream callback, so the read landed before the
        // write completed and got the older value regardless. On a flaky
        // connection that reloaded the book seconds away from where the user
        // was, which is audible as a jump.
        final resumeFrom = _liveOrStoredPosition();
        if (_player.processingState == ProcessingState.ready) {
          _saveAndReportPosition(state: 'paused');
        }
        final key = _bookRatingKey;
        if (key != null && !_reloadInProgress) {
          _reloadInProgress = true;
          onStreamError?.call(key, resumeFrom);
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
    _player.positionStream.listen((p) {
      // While casting the phone's position is the stale one the cast began
      // at; the TV's statuses update the chapter instead.
      if (!_castActive) _updateChapterMediaItem(p);
    }, onError: (Object e, StackTrace st) {
      // Should never fire — which is exactly why it's worth recording.
      AppLog.log('playback', 'listener error: $e');
    });
    _player.processingStateStream.listen((state) {
      if (state == ProcessingState.completed && !_castActive) {
        _markBookCompleted();
        stop();
      }
    }, onError: (Object e, StackTrace st) {
      // Should never fire — which is exactly why it's worth recording.
      AppLog.log('playback', 'listener error: $e');
    });

    // Pause when headphones are unplugged (ACTION_AUDIO_BECOMING_NOISY).
    // audio_service does not handle this automatically.
    unawaited(_setUpAudioSession());

    cast.stateStream.listen(_onCastState, onError: (Object e, StackTrace st) {
      AppLog.log('cast', 'listener error: $e');
    });
    cast.statusStream.listen(_onCastStatus, onError: (Object e, StackTrace st) {
      AppLog.log('cast', 'listener error: $e');
    });
    unawaited(_resumeCastIfLive());
  }

  // Held so a retry of [_setUpAudioSession] can't register a listener twice.
  StreamSubscription<void>? _noisySub;
  StreamSubscription<AudioInterruptionEvent>? _interruptionSub;
  StreamSubscription<AudioDevicesChangedEvent>? _devicesSub;

  /// Headphone-unplug pause, interruption handling, and route logging.
  ///
  /// This was one unguarded `.then`: if `AudioSession.instance` rejected, or a
  /// throw landed between the registrations, the unplug pause and the
  /// interruption handling silently never existed for the life of the process
  /// — unplugging blared the book from the speaker, and calls played over it.
  /// Now it's guarded, logged and retried once; the two listeners that protect
  /// the listener register first, so a later throw can only cost the logging.
  Future<void> _setUpAudioSession({bool isRetry = false}) async {
    try {
      final session = await AudioSession.instance;
      // Declare spoken-word content (contentType speech, focus gain,
      // pause-when-ducked enforced at the source). Without this,
      // audio_session falls back to a music profile on the first focus
      // request — wrong attributes for an audiobook app.
      try {
        await session.configure(const AudioSessionConfiguration.speech());
      } catch (e) {
        AppLog.log('playback', 'audio session configure failed: $e');
      }
      _noisySub ??= session.becomingNoisyEventStream.listen((_) {
        // Recorded because this path used to stop a book silently: no entry in
        // the log, nothing in the UI, just a book that isn't playing any more.
        // It fires on headphone unplug, but also on some Bluetooth transitions
        // that have nothing to do with where the audio is going.
        AppLog.log('playback',
            'becoming noisy${_player.playing ? ' → pausing' : ' (not playing)'}');
        if (_player.playing) _pauseFor('becoming noisy');
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
      _interruptionSub ??= session.interruptionEventStream.listen((event) {
        if (event.begin) {
          switch (event.type) {
            case AudioInterruptionType.duck:
              if (SettingsStore.resumeAfterInterruption) {
                if (_player.playing) _onInterruptionBegin('duck');
              } else {
                _duckLevel = 0.5;
                unawaited(_applyVolume());
              }
            case AudioInterruptionType.pause:
            case AudioInterruptionType.unknown:
              if (_player.playing) _onInterruptionBegin(event.type.name);
          }
        } else {
          switch (event.type) {
            case AudioInterruptionType.duck:
              // A no-op if we paused instead of ducking.
              _duckLevel = 1.0;
              unawaited(_applyVolume());
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
      // Output route changes, by device *type* only. A device name is someone's
      // car or their own name, and this log is meant to be pasteable into a
      // public issue. Worth recording at all because a pause that follows a
      // route change and one that doesn't look identical from the outside, and
      // which it is decides where to look.
      _devicesSub ??= session.devicesChangedEventStream.listen((event) {
        String types(Set<AudioDevice> devices) => devices
            .where((d) => d.isOutput)
            .map((d) => d.type.name)
            .toSet()
            .join(',');
        final added = types(event.devicesAdded);
        final removed = types(event.devicesRemoved);
        if (added.isEmpty && removed.isEmpty) return;
        AppLog.log(
            'playback',
            'audio route: ${added.isEmpty ? '' : '+$added '}'
                '${removed.isEmpty ? '' : '-$removed '}'
                '(playing: ${_player.playing})');
      }, onError: (Object e, StackTrace st) {
        AppLog.log('playback', 'listener error: $e');
      });
    } catch (e) {
      AppLog.log('playback',
          'audio session setup failed${isRetry ? ' again — giving up' : ''}: $e');
      if (!isRetry) {
        await Future<void>.delayed(const Duration(seconds: 2));
        await _setUpAudioSession(isRetry: true);
      }
    }
  }

  /// A pause the platform asked for (unplug, interruption). Fire-and-forget at
  /// the call sites, so a failure is logged here rather than surfacing as an
  /// unhandled async error with nothing to say which pause it was.
  void _pauseFor(String why) {
    unawaited(pause().catchError((Object e) {
      AppLog.log('playback', '$why: pause failed: $e');
    }));
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
    _pauseFor('interruption ($type)');
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

    // With a TV connected the book goes there: the phone's player loads it
    // paused, as the place to come back to, and the TV gets the queue. Every
    // launch path (chapter, bookmark, History, the next book) lands here, so
    // none of them can start the phone over a cast. Not a stream-error
    // reload (the phone's own player), and not the relaunch that is taking
    // back a cast the TV is already playing.
    final toTv =
        cast.state == CastState.connected && !_castAdopting && !isAutoReload;

    // A jump while playing (chapter, bookmark, History, a session's Resume)
    // reloads through here and plays again: close the running session at
    // the place being left, while the identity fields still describe it.
    // Not on a stream-error reload: that continues the same listen, and the
    // errored player's position (possibly 0) would be logged as its end.
    if (!isAutoReload) _closeSession();

    // Save the outgoing book's place before the identity fields flip to the
    // new one — the periodic timer's last save can be up to 10 s stale, and
    // once the swap happens no save for the old book is possible.
    if (_bookRatingKey != null && _bookRatingKey != bookRatingKey) {
      await _saveAndReportPosition(state: 'paused');
    }

    final gen = ++_loadGeneration;
    _loadInProgress = true;
    _bookRatingKey = bookRatingKey;
    _tracks = tracks;
    _pausedAt = null; // new book — don't rewind on first play
    _lastChapterIndex = -1; // recompute chapter title for the new book
    _completedThisSession = false; // a fresh listen can be counted again
    justFinishedBook.value = null; // any (re)load dismisses the finished panel
    autoAdvanceFailed.value = null;
    cancelAutoAdvance(); // including the advance that may have caused this load
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
        if (playWhenReady) {
          final awaySeconds =
              DateTime.now().difference(bookmark.savedAt).inSeconds;
          final rewindMs = _resumeRewindMs(awaySeconds);
          resumePositionMs =
              (resumePositionMs - rewindMs).clamp(0, resumePositionMs);
        } else {
          // Load-only launch (Home's hero card opening the player to look at
          // it): never move the position — merely viewing used to rewind here
          // and the next lifecycle save persisted it, walking the bookmark up
          // to 60 s back per look. Seed _pausedAt with the bookmark's age
          // instead, so a play that follows applies the same curve (the
          // in-session branch in [play]) at the moment listening resumes.
          _pausedAt = bookmark.savedAt;
        }
      }
    }

    // Restored positions come from stores and backups, not only the player:
    // clamp into the start track's playable range. A negative value makes
    // ExoPlayer's initial seek fail (the book silently refuses to play); a
    // value at/past the track end trips completion detection on load.
    final startTrackDurMs = tracks[startTrackIndex].durationMs;
    if (startTrackDurMs > 0) {
      resumePositionMs = resumePositionMs
          .clamp(0, (startTrackDurMs - _endGuardMs).clamp(0, startTrackDurMs))
          .toInt();
    } else if (resumePositionMs < 0) {
      resumePositionMs = 0;
    }

    final sources = tracks.map(audioSourceForTrack).toList();

    // Publish queue/notification metadata before the (potentially slow) network
    // load, so the media notification has real content the moment the service
    // goes foreground below — not a blank "Saga" card until buffering finishes.
    queue.add(tracks.map(_trackToMediaItem).toList());
    mediaItem.add(_trackToMediaItem(tracks[startTrackIndex]));
    _prefetchArtwork(tracks[startTrackIndex]);

    try {
      _playlist = ConcatenatingAudioSource(children: sources);
      if (playWhenReady && !toTv) {
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
          _mutedForLoad = true;
          await _applyVolume();
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
      // foreground service with no audio source. Generation-checked like the
      // state clear below — a *stale* load's failure arriving while a newer
      // book loads must not pause the book the user just started.
      if (playWhenReady && !toTv && gen == _loadGeneration) {
        unawaited(_player.pause());
      }
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
      // mute would make all playback silent with no visible cause.
      if (_mutedForLoad) {
        _mutedForLoad = false;
        await _applyVolume();
      }
      // Gen-guarded: a superseded load's finally must not reopen the save
      // window while the newer load is still mid-swap.
      if (gen == _loadGeneration) _loadInProgress = false;
    }
    if (gen != _loadGeneration) return; // superseded by a newer load
    if (toTv) {
      await _castLoad(startTrackIndex, resumePositionMs,
          autoplay: playWhenReady);
    }
    if (!isAutoReload) _jumped();
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
      final bookKey = mostRecentBookRatingKey(BookmarkStore.allPositions(),
          completed: finishedBookKeys());
      if (bookKey == null) return false;
      final tracks = await _tracksFor(bookKey);
      if (tracks.isEmpty) return false;
      final started = await startBook(
        service: this,
        bookRatingKey: bookKey,
        tracks: tracks,
        from: const BookStartPoint.resume(),
        // The [play] that called this finishes the job.
        playback: LaunchPlayback.intentOnly,
      );
      if (started) AppLog.log('playback', 'restored last session: book $bookKey');
      return started;
    } catch (e) {
      AppLog.log('playback', 'session restore failed: $e');
      return false;
    } finally {
      _restoringSession = false;
    }
  }

  /// [_restoreLastSession]'s warm-process sibling: the session was stopped
  /// (media-button stop, natural end — [stop] keeps the book loaded) but the
  /// Dart side survived. Reloads the *current* book through [startBook] so
  /// the smart rewind and the book's saved speed come from the one shared
  /// path, exactly as the dead-process restore does.
  Future<bool> _reloadStoppedSession() async {
    if (_restoringSession) return false; // absorb double-taps mid-restore
    _restoringSession = true;
    try {
      final bookKey = _bookRatingKey;
      if (bookKey == null || _tracks.isEmpty) return false;
      // Play on a book that finished this session means "replay this" — the
      // promise [play]'s comment has always made. Resuming would land on the
      // end-of-book bookmark (clamped one second short), play that second,
      // and count a second completion — every press adding one. Checked via
      // _completedThisSession too, so a panel dismissed with X replays the
      // same way instead of falling back to the last-second loop.
      final replay =
          justFinishedBook.value == bookKey || _completedThisSession;
      final started = await startBook(
        service: this,
        bookRatingKey: bookKey,
        tracks: List.of(_tracks),
        from: replay
            ? const BookStartPoint.beginning()
            : const BookStartPoint.resume(),
        // The [play] that called this finishes the job.
        playback: LaunchPlayback.intentOnly,
      );
      if (started) {
        AppLog.log('playback', 'reloaded stopped session: book $bookKey');
      }
      return started;
    } catch (e) {
      AppLog.log('playback', 'stopped-session reload failed: $e');
      return false;
    } finally {
      _restoringSession = false;
    }
  }

  /// Re-sends the current [mediaItem] *and* playback state to the platform
  /// media session.
  ///
  /// audio_service pushes to Android's MediaSession only when the Dart-side
  /// subjects *emit*. But the Java service — and the MediaSessionCompat it
  /// owns — can be destroyed and recreated inside a Dart process that survives
  /// it: the Flutter engine is cached, so this handler and its BehaviorSubjects
  /// live on with the book still in them. The rebuilt session starts with null
  /// metadata and a default "paused" state, and nothing re-sends either:
  /// - null metadata → the lock screen shows Android's "Saga is running"
  ///   placeholder over a book that is audibly playing (the 1.1.0 bug).
  /// - stale "paused" state → worse: Android resolves media buttons *against
  ///   the session's state*, so every bluetooth press and lock-screen button
  ///   becomes a play command that no-ops on the already-playing player, and
  ///   nothing on the phone can pause the book except the app itself
  ///   (2026-08-14 incident). The 1.1.0 fix assumed playbackEventStream
  ///   re-emits often enough to cover state — true while streaming, where
  ///   buffer updates keep firing, but a downloaded book mid-track can go
  ///   quiet for a whole chapter.
  ///
  /// Idempotent and cheap — artwork is LRU-cached in the Java layer — so call
  /// it from any path that can follow a service restart: play, pause, app
  /// resume, and the 10 s progress timer (which is what heals a rebuilt
  /// session with no user action at all).
  void republishNowPlaying() {
    final current = mediaItem.value;
    if (current != null) mediaItem.add(current);
    _broadcastState(_player.playbackEvent);
  }

  @override
  Future<void> play() async {
    // Pressing play on the finished panel means "replay this", not "carry on".
    // (No-op during an auto-advance: the countdown clears itself before
    // starting the next book.)
    cancelAutoAdvance();
    // No book loaded means this play command reached a freshly cold-started
    // service (media controls after process death) — restore the session.
    // Without a successful restore we must return before _player.play():
    // with no source it broadcasts playing=true and never completes, leaving
    // the notification stuck on a lying pause icon.
    if (_bookRatingKey == null || _tracks.isEmpty) {
      if (!await _restoreLastSession()) return;
    } else if (_castActive
        // The TV finished the book, or dropped it (an error, another
        // sender): the same reload as a stopped phone player.
        ? (_castFinished ||
            (cast.status?.state == CastPlayerState.idle && !_castLoading))
        : (_player.processingState == ProcessingState.idle &&
            !_loadInProgress)) {
      // Warm-process resume: the session was stopped but the process — and
      // the book in this handler — survived, so the restore above is skipped
      // while the platform player sits torn down (idle). Falling through to
      // _player.play() resumed hours later with no smart rewind (the branch
      // below is gated on `ready`) and without re-applying the book's speed,
      // while the dead-process path got both. Same fix as every launch-path
      // bug before it: funnel through the one shared path.
      if (!await _reloadStoppedSession()) return;
    }
    // The media session may have been rebuilt since the last mediaItem
    // emission. A play arriving from the notification, a media button or the
    // lock screen is exactly the moment that card needs its title back.
    republishNowPlaying();

    // Any play (user or auto-resume itself) settles a pending interruption —
    // a later interruption-end must not trigger a second resume.
    _pausedByInterruption = false;

    // Smart rewind: if resuming after a pause, seek back proportionally to how
    // long the user was away. Only fires when paused within the same session
    // (_pausedAt is set). Uses the same curve as the resume-after-load path.
    if (_pausedAt != null && _isReady) {
      final awaySeconds = DateTime.now().difference(_pausedAt!).inSeconds;
      _pausedAt = null;
      final rewindMs = _resumeRewindMs(awaySeconds);
      if (rewindMs > 0) {
        final currentMs = _trackPosMs;
        final targetMs = (currentMs - rewindMs).clamp(0, currentMs);
        if (targetMs < currentMs) await _seekTo(targetMs);
      }
    } else {
      _pausedAt = null;
    }

    // Logged before the save below: the save bumps the revision every
    // "continue" list recomputes on, and a finished book only counts as
    // picked up again once this play is in the log — logged after, the lists
    // still read the book as finished until the next 10 s save.
    _openSession();
    // Save bookmark immediately so Continue Listening appears without waiting
    // for the 10-second progress timer to fire. Skip when the source is still
    // loading — position is not meaningful and would overwrite the resume point.
    if (_isReady) {
      await _saveAndReportPosition(state: 'playing');
    }
    _trackingFrom = DateTime.now();
    _startProgressTimer();
    if (_castActive) {
      // The play guard: with a cast live, nothing plays on the phone.
      _castWantsPlay = true;
      _castCommandAt = DateTime.now();
      _broadcastState();
      // Only a paused receiver needs telling: a load in flight (or one just
      // landed, still buffering) plays when it's ready, and an idle one was
      // reloaded above.
      if (!_castLoading && cast.status?.state == CastPlayerState.paused) {
        await cast.play();
      }
      return;
    }
    await _player.play();
  }

  @override
  Future<void> pause() async {
    cancelAutoAdvance(); // a deliberate pause means "stay here"
    _progressTimer?.cancel();
    _pausedAt = DateTime.now();
    _closeSession();
    if (_castActive) {
      _castWantsPlay = false;
      _castCommandAt = DateTime.now();
      await cast.pause();
    } else {
      await _player.pause();
    }
    // A rebuilt session whose stale state reads "playing" resolves every press
    // to pause — a platform-side no-op that emits nothing. Re-send the truth
    // so the session's buttons flip back to a working direction.
    republishNowPlaying();
    await _saveAndReportPosition(state: 'paused');
  }

  @override
  Future<void> stop() async {
    // The sleep timer lives in SleepTimerNotifier, which cancels itself off
    // this stop (idle processing state) — there is deliberately no timer here.
    // A dead second implementation used to be cancelled on this line, which
    // read as "stopping clears the sleep timer" while clearing nothing.
    _progressTimer?.cancel();
    _pausedAt = DateTime.now();
    // Natural finish, media-button stop and swipe-away all end here, not in
    // pause() — without this the final stretch had no end: no duration in
    // Sessions, no History credit, and no position to return to.
    _closeSession();
    await _saveAndReportPosition(state: 'stopped');
    if (_castActive) {
      // Stopping Saga stops the TV too: swipe-away means quit (see
      // [onTaskRemoved]), and a cast left running would have nothing on the
      // phone controlling it any more. Its place is the one just saved.
      await _leaveCast(saved: true);
      unawaited(cast.stopCasting());
    }
    await _player.stop();
    await super.stop();
  }

  /// Stops playback and tears the media session down completely: the mini
  /// player pill and the system notification both disappear.
  ///
  /// Plain [stop] deliberately doesn't do this — it leaves `mediaItem` set so
  /// the controls stay usable. Dismissing the pill is the one case where the
  /// user has asked for the session to be *gone*.
  ///
  /// The position is saved first (inside [stop], from the live player position
  /// while the source is still loaded), so dismissing never costs the user
  /// their place — the book resumes from Continue Listening as usual.
  Future<void> stopAndClear() async {
    // A swipe and a media-button stop can both land; the second must no-op.
    if (_clearing) return;
    _clearing = true;
    try {
      // The user asked for the session to be gone, so a throw in stop() must
      // not skip the teardown below — the pill and notification would survive
      // the swipe. stop() saves the position before anything that can throw
      // on the player side, so continuing doesn't cost the user their place.
      try {
        await stop();
      } catch (e) {
        AppLog.log('playback', 'stop failed while clearing session: $e');
      }
      cancelAutoAdvance();
      // Any load still in flight is now stale — without this it could
      // repopulate the state we're about to clear.
      _loadGeneration++;
      _progressTimer?.cancel();
      _trackingFrom = null;
      justFinishedBook.value = null;
      _bookRatingKey = null;
      _tracks = [];
      _lastChapterIndex = -1;
      _completedThisSession = false;
      _previousAbsolutePositionMs = -1;
      canUndoSeekNotifier.value = false;
      // Last, so listeners never see a half-cleared session. main_shell hides
      // the pill on a null mediaItem, and audio_service drops the notification.
      queue.add([]);
      mediaItem.add(null);
      AppLog.log('playback', 'session cleared by user');
    } finally {
      _clearing = false;
    }
  }

  /// Explicit seeks never land on the very end of a file: exactly `duration`
  /// is end-of-media, which trips completion detection — e.g. a stale cached
  /// chapter table pointing past a re-encoded, now-shorter file would mark
  /// the book finished from a chapter tap. Clamped [_endGuardMs] short; the
  /// last second is played, never skipped.
  static const _endGuardMs = 1000;

  Duration _clampToTrack(Duration position) {
    if (position.isNegative) return Duration.zero;
    final durMs = currentTrackDurationMs ?? 0;
    if (durMs <= 0) return position;
    final maxMs = (durMs - _endGuardMs).clamp(0, durMs).toInt();
    return position.inMilliseconds > maxMs
        ? Duration(milliseconds: maxMs)
        : position;
  }

  @override
  Future<void> seek(Duration position) async {
    cancelAutoAdvance(); // scrubbing back means "I'm not done with this book"
    _previousAbsolutePositionMs = absolutePositionMs;
    canUndoSeekNotifier.value = true;
    await _seekTo(_clampToTrack(position).inMilliseconds);
    _jumped();
  }

  @override
  Future<void> skipToNext() async {
    _logEvent('skipNext');
    final chapters = _chaptersIfSingleTrack();
    if (chapters != null) {
      final idx = chapterIndexAt(
          [for (final c in chapters) c.start.inMilliseconds], _trackPosMs);
      // Already in the last chapter: nothing to skip to, so do nothing.
      // Falling back to the last chapter (the old `orElse: () => last`)
      // seeked to *its* start — backwards, by up to a whole chapter. Seeking
      // to the end of the audio instead would be worse: it trips completion
      // detection and marks the book finished. Same bug the sleep timer's
      // end-of-chapter target had.
      if (idx + 1 >= chapters.length) return;
      await _seekTo(_clampToTrack(chapters[idx + 1].start).inMilliseconds);
    } else if (_castActive) {
      final next = (_index ?? 0) + 1;
      if (next >= _tracks.length) return;
      await _seekTo(0, index: next);
    } else {
      await _player.seekToNext();
    }
    _jumped();
  }

  @override
  Future<void> skipToPrevious() async {
    _logEvent('skipPrev');
    final chapters = _chaptersIfSingleTrack();
    if (chapters != null) {
      final posMs = _trackPosMs;
      final idx = chapterIndexAt(
          [for (final c in chapters) c.start.inMilliseconds], posMs);
      const thresholdMs = 5000;
      if (idx <= 0) {
        await _seekTo(0);
      } else if (posMs - chapters[idx].start.inMilliseconds < thresholdMs) {
        await _seekTo(chapters[idx - 1].start.inMilliseconds);
      } else {
        await _seekTo(chapters[idx].start.inMilliseconds);
      }
    } else if (_castActive) {
      // just_audio's seekToPrevious: the previous file's start, or this
      // file's start in the first.
      final prev = (_index ?? 0) - 1;
      await _seekTo(0, index: prev < 0 ? null : prev);
    } else {
      await _player.seekToPrevious();
    }
    _jumped();
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
    final idx = chapterIndexAt(
        [for (final c in chapters) c.start.inMilliseconds],
        position.inMilliseconds);
    if (idx == _lastChapterIndex) return;
    _lastChapterIndex = idx;
    final current = mediaItem.value;
    if (current == null) return;
    mediaItem.add(current.copyWith(title: chapters[idx].title));
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    await _seekTo(0, index: index);
    _jumped();
  }

  // ── Where the book plays: the phone, or a TV ────────────────────────────
  //
  // While a cast is live this handler drives the TV instead of the phone's
  // player. Every control (the app, the notification, the lock screen,
  // Bluetooth, the car, the widget) arrives here, so routing here is what
  // keeps them all on the TV: absorb cast beside its handler, and its lock
  // screen went on controlling the stopped phone player. The phone's player
  // holds the book paused where the cast began, and takes it back, paused,
  // at the TV's place when the cast ends. Saves, the session log and History
  // run unchanged against the TV's position, through the getters below.

  /// The Cast bridge. Owned here, not by a provider: a headless engine (the
  /// widget, a headset, the car) never builds providers, and the TV has to
  /// answer to those too.
  final CastService cast = CastService();

  /// True while the TV holds this handler's book.
  final ValueNotifier<bool> casting = ValueNotifier(false);
  final _castingSubject = BehaviorSubject<bool>.seeded(false);
  bool get _castActive => casting.value;

  CastPositionTracker? _castTracker;
  // Where the TV is: its last trustworthy report, or where a load or a seek
  // asked it to be until it reports.
  ({int item, int positionMs}) _castPlace = (item: 0, positionMs: 0);
  DateTime _castPlaceAt = DateTime.now();
  final _castItem = BehaviorSubject<int?>.seeded(null);
  // What the listener asked for. The receiver's own state lags a command by
  // a round trip; the notification and the saves follow this, and the TV's
  // own remote moves it too.
  bool _castWantsPlay = false;
  DateTime? _castCommandAt;
  bool _castLoading = false;
  bool _castFinished = false;
  String? _castLoadId;
  int _castLoadCount = 0;
  DateTime? _castRateAskedAt;
  // The device sheet picked a device: cast the loaded book once connected,
  // playing if the phone (or the TV before it) was.
  bool _castOnConnect = false;
  bool _castAutoplayOnConnect = false;
  // A relaunch found a stored handoff: the session the SDK resumes for it.
  CastHandoff? _castPendingAdopt;
  Timer? _castAdoptTimeout;
  bool _castAdopting = false;
  DateTime? _handoffWrittenAt;
  int? _remoteVolume;

  /// The Default Media Receiver plays 0.5× to 2×.
  static double _castRate(double speed) => speed.clamp(0.5, 2.0).toDouble();

  static const _remoteVolumeSteps = 20;

  /// The current file's index.
  int? get _index => _castActive ? _castPlace.item : _player.currentIndex;

  /// Position within the current file.
  int get _trackPosMs =>
      _castActive ? _castPositionNowMs : _player.position.inMilliseconds;

  bool get _isPlaying => _castActive ? _castWantsPlay : _player.playing;

  /// Whether the position means anything: not mid-load, and on a TV, not
  /// before it has reported a place it can be trusted with.
  bool get _isReady => _castActive
      ? !_castLoading && !_castFinished && _castTracker?.last != null
      : _player.processingState == ProcessingState.ready;

  int get _castPositionNowMs {
    var ms = _castPlace.positionMs;
    final s = cast.status;
    if (_castWantsPlay &&
        !_castLoading &&
        s != null &&
        s.state == CastPlayerState.playing) {
      final elapsed = DateTime.now().difference(_castPlaceAt).inMilliseconds;
      ms += (elapsed * (s.rate > 0 ? s.rate : 1.0)).round();
    }
    final i = _castPlace.item;
    if (i < _tracks.length && _tracks[i].durationMs > 0) {
      ms = ms.clamp(0, _tracks[i].durationMs).toInt();
    }
    return ms;
  }

  AudioProcessingState get _castProcessing {
    if (_castFinished) return AudioProcessingState.completed;
    if (_castLoading) return AudioProcessingState.loading;
    return switch (cast.status?.state) {
      CastPlayerState.loading => AudioProcessingState.loading,
      CastPlayerState.buffering => AudioProcessingState.buffering,
      _ => AudioProcessingState.ready,
    };
  }

  /// Moves playback to [positionMs] in file [index] (the current file when
  /// null), on whichever player holds the book.
  Future<void> _seekTo(int positionMs, {int? index}) async {
    if (!_castActive) {
      await _player.seek(Duration(milliseconds: positionMs), index: index);
      return;
    }
    final item = index ?? _castPlace.item;
    _setCastPlace((item: item, positionMs: positionMs));
    final s = cast.status;
    if (s != null &&
        s.loadId == (_castLoadId ?? s.loadId) &&
        s.item == item &&
        s.state != CastPlayerState.idle) {
      await cast.seek(positionMs);
    } else if (!await cast.jump(item, positionMs)) {
      // The receiver's queue doesn't know the item (or there's no queue):
      // load the book again, at the target.
      await _castLoad(item, positionMs, autoplay: _castWantsPlay);
    }
  }

  /// The one writer of the phone player's volume; see [_mutedForLoad].
  Future<void> _applyVolume() =>
      _player.setVolume(_mutedForLoad ? 0 : _duckLevel * _fadeLevel);

  /// The sleep timer's fade, 0–1 (1 = none). On a TV it fades the stream's
  /// own volume, so the TV's volume stays where the listener set it, and a
  /// fade that never got restored ends with the stream, not the TV.
  Future<void> setFadeLevel(double level) async {
    _fadeLevel = level;
    if (_castActive) {
      await cast.setStreamVolume(level);
    } else {
      await _applyVolume();
    }
  }

  /// Connects to [device], and casts the loaded book once the session is up.
  /// Moving from one TV to another passes through the phone (the SDK ends
  /// the old session first), so whether to play is decided now.
  Future<void> castTo(CastDevice device) async {
    final autoplay = _isPlaying;
    // The current TV hands the place back first, so the next one starts
    // from it.
    if (cast.state == CastState.connected) await stopCasting();
    _castOnConnect = true;
    _castAutoplayOnConnect = autoplay;
    _castPendingAdopt = null;
    await cast.selectDevice(device);
  }

  /// Ends the cast. The TV's place comes back to the phone; [resumeHere]
  /// carries on playing there if the TV was ("This phone" in the device
  /// sheet). Otherwise the phone lands paused.
  Future<void> stopCasting({bool resumeHere = false}) async {
    if (_castActive) {
      // One fresh reading, so the place handed back is the exact one.
      final s = await cast.fetchStatus();
      if (s != null) _onCastStatus(s);
      await _leaveCast(resumeHere: resumeHere);
    }
    await cast.stopCasting();
  }

  /// The TV's own volume, 0–1 (the device sheet's slider).
  Future<void> setCastVolume(double volume) => cast.setDeviceVolume(volume);

  void _onCastState(CastState s) {
    if (s == CastState.connected) {
      _castAdoptTimeout?.cancel();
      if (_castOnConnect) {
        _castOnConnect = false;
        unawaited(_startCasting(
            autoplay: _castAutoplayOnConnect || _player.playing));
      } else if (_castPendingAdopt != null) {
        final h = _castPendingAdopt!;
        _castPendingAdopt = null;
        unawaited(_adoptCast(h));
      }
    } else if (s == CastState.idle) {
      _castOnConnect = false;
      if (_castActive) {
        unawaited(_leaveCast());
      } else if (cast.handoff != null) {
        unawaited(_writeBackHandoff(ended: true));
      }
    }
  }

  /// Hands the loaded book to the TV that just connected, from where the
  /// phone is. With no book loaded the session simply stays up, and the
  /// next book started goes to the TV ([loadBook]).
  Future<void> _startCasting({required bool autoplay}) async {
    if (_bookRatingKey == null || _tracks.isEmpty || _loadInProgress) return;
    if (_castActive) return;
    final index = _player.currentIndex ?? 0;
    final positionMs = _player.position.inMilliseconds;
    // On disk before anything moves: the place the TV starts from.
    await savePositionForLifecycle();
    // A raw pause: the listen carries on, on the TV, so the session log and
    // History keep running.
    await _player.pause();
    final ok = await _castLoad(index, positionMs, autoplay: autoplay);
    // No server to hand the TV: carry on here.
    if (!ok && !_castActive && autoplay) unawaited(_player.play());
  }

  /// Loads the book onto the TV as one queue of its files, at file [index],
  /// [positionMs] in. Returns whether the receiver took it.
  Future<bool> _castLoad(int index, int positionMs,
      {required bool autoplay}) async {
    final key = _bookRatingKey;
    final tracks = List.of(_tracks);
    if (key == null || index < 0 || index >= tracks.length) return false;
    final first = tracks.first;
    final media = await castQueueFor(tracks);
    if (media == null) {
      cast.reportError('Casting needs your Plex server to be reachable.');
      return false;
    }
    if (key != _bookRatingKey) return false; // another book started meanwhile
    final durations = [for (final t in tracks) t.durationMs];
    final total = durations.fold<int>(0, (a, b) => a + b);
    final loadId =
        '${DateTime.now().millisecondsSinceEpoch}-${++_castLoadCount}';
    final handoff = CastHandoff(
      bookRatingKey: key,
      tracks: [
        for (var i = 0; i < tracks.length; i++)
          (
            trackRatingKey: tracks[i].ratingKey,
            startMs: absoluteFromTrack(durations, i, 0),
          ),
      ],
      totalDurationMs: total > 0 ? total : null,
      loadId: loadId,
    );
    // Stored before the load: a relaunch mid-cast has to know what the TV
    // holds, and the session can outlive this process.
    await SettingsStore.setActiveCastHandoff(handoff.serialize());
    _castLoadId = loadId;
    _enterCast(handoff, place: (item: index, positionMs: positionMs));
    _castWantsPlay = autoplay;
    _castLoading = true;
    _broadcastState();
    final ok = await cast.loadQueue(
      items: media.items,
      title: first.bookTitle ?? first.title,
      artist: first.authorName ?? '',
      artwork: media.artwork,
      startIndex: index,
      positionMs: positionMs,
      autoplay: autoplay,
      rate: _castRate(_player.speed),
      loadId: loadId,
    );
    if (loadId != _castLoadId) return ok; // a newer load took over
    _castLoading = false;
    if (!ok) {
      // The session's still up: the TV stays the target, and play tries
      // the load again.
      cast.reportError("The TV couldn't play this book.");
      _castWantsPlay = false;
    }
    _broadcastState();
    return ok;
  }

  void _enterCast(CastHandoff h,
      {required ({int item, int positionMs}) place}) {
    cast.beginSession(h);
    _castTracker = CastPositionTracker(h);
    _castFinished = false;
    if (!_castActive) {
      casting.value = true;
      _castingSubject.add(true);
      if (_fadeLevel < 1) unawaited(cast.setStreamVolume(_fadeLevel));
    }
    _setCastPlace(place);
    _publishRemoteVolume();
  }

  void _setCastPlace(({int item, int positionMs}) place, [DateTime? at]) {
    _castPlace = place;
    _castPlaceAt = at ?? DateTime.now();
    if (_castItem.value != place.item && place.item < _tracks.length) {
      _castItem.add(place.item);
      // The TV moved to another file: the notification follows it.
      _lastChapterIndex = -1;
      mediaItem.add(_trackToMediaItem(_tracks[place.item]));
      _prefetchArtwork(_tracks[place.item]);
    }
    _updateChapterMediaItem(Duration(milliseconds: place.positionMs));
  }

  void _onCastStatus(CastStatus s) {
    final tracker = _castTracker;
    if (tracker == null) return;
    final place = tracker.accept(s);
    if (!_castActive) {
      if (place != null) unawaited(_writeBackHandoff());
      return;
    }
    if (place != null) {
      _setCastPlace(place, s.receivedAt);
      _followCastRemote(s);
      if (s.state == CastPlayerState.playing) _reapplyCastRate(s);
    }
    if (s.finished && !_castLoading && !_castFinished && _castAtBookEnd) {
      unawaited(_onCastFinished());
    }
    _broadcastState();
    _publishRemoteVolume(s);
  }

  /// The TV paused or played on its own (its remote, another sender): the
  /// session log and the saves follow it as they follow the phone. Not in
  /// the moment after a command of ours, when the receiver can still report
  /// the state it's leaving.
  void _followCastRemote(CastStatus s) {
    final command = _castCommandAt;
    if (command != null &&
        DateTime.now().difference(command) < const Duration(seconds: 3)) {
      return;
    }
    if (s.state == CastPlayerState.paused && _castWantsPlay) {
      _castWantsPlay = false;
      _progressTimer?.cancel();
      _pausedAt = DateTime.now();
      _closeSession();
      unawaited(_saveAndReportPosition(state: 'paused'));
    } else if (s.state == CastPlayerState.playing && !_castWantsPlay) {
      _castWantsPlay = true;
      _pausedAt = null;
      _openSession();
      _trackingFrom = DateTime.now();
      _startProgressTimer();
    }
  }

  /// The receiver has a speed of its own, and drops to 1× on a reload or a
  /// reconnect (Audiobookshelf #1254, absorb #15). Put the book's back, at
  /// most every few seconds.
  void _reapplyCastRate(CastStatus s) {
    final want = _castRate(_player.speed);
    if ((s.rate - want).abs() < 0.01) return;
    final now = DateTime.now();
    final asked = _castRateAskedAt;
    if (asked != null && now.difference(asked) < const Duration(seconds: 5)) {
      return;
    }
    _castRateAskedAt = now;
    AppLog.log('cast', 'receiver at ${s.rate}×, re-applying $want×');
    unawaited(cast.setRate(want));
  }

  /// The last file, within its final half minute: the only place a
  /// receiver's "finished" means the book did.
  bool get _castAtBookEnd {
    final last = _tracks.length - 1;
    if (last < 0 || _castPlace.item != last) return false;
    final dur = _tracks[last].durationMs;
    return dur <= 0 || _castPlace.positionMs >= dur - 30000;
  }

  /// The TV played the book's last file to the end (it goes idle, not
  /// "ended": AntennaPod PR #8594). The same finish the phone's player
  /// records, without its stop: the session stays on the TV, and the next
  /// book (auto-advance, or the listener) goes there too.
  Future<void> _onCastFinished() async {
    _castFinished = true;
    _castWantsPlay = false;
    _progressTimer?.cancel();
    final last = _tracks.length - 1;
    _setCastPlace((item: last, positionMs: _tracks[last].durationMs));
    _closeSession();
    await _markBookCompleted();
    await _saveAndReportPosition(state: 'stopped');
    _broadcastState();
  }

  /// The TV is done with the book: its place comes back to the phone's
  /// player, paused there unless [resumeHere]. One path for Stop casting, a
  /// TV switched off, a dropped network and someone else casting over us. A
  /// lost connection never carries on playing on the phone (AntennaPod
  /// #6539): the listener may be across the house from it. [saved]: the
  /// caller has just saved the place.
  Future<void> _leaveCast({bool resumeHere = false, bool saved = false}) async {
    if (!_castActive) return;
    final wasPlaying = _castWantsPlay;
    final finished = _castFinished;
    _progressTimer?.cancel();
    // Still reading the TV: the session closes, and the place saves, at its
    // last good position.
    _closeSession();
    if (!saved && !finished) await _saveAndReportPosition(state: 'paused');
    final place = _castPlace;
    casting.value = false;
    _castingSubject.add(false);
    _castTracker = null;
    _castWantsPlay = false;
    _castLoading = false;
    _castFinished = false;
    _castLoadId = null;
    _remoteVolume = null;
    cast.clearHandoff();
    androidPlaybackInfo.add(LocalAndroidPlaybackInfo());
    await SettingsStore.setActiveCastHandoff(null);
    try {
      if (finished) {
        // Idle, so the next play replays the book ([_reloadStoppedSession])
        // rather than carrying on from where the cast began.
        await _player.stop();
      } else if (_player.audioSource != null && place.item < _tracks.length) {
        await _player.seek(Duration(milliseconds: place.positionMs),
            index: place.item);
      }
    } catch (e) {
      AppLog.log('cast', 'handing the place back to the phone failed: $e');
    }
    _pausedAt = DateTime.now();
    if (_fadeLevel < 1) await _applyVolume();
    _broadcastState();
    AppLog.log('cast', 'cast ended — place handed back to the phone');
    if (resumeHere && wasPlaying) await play();
  }

  /// A relaunch mid-cast: the Cast SDK resumes the session on its own, and
  /// the stored handoff says what the TV holds. The SDK can take a moment,
  /// so a session not up yet gets a minute to connect.
  Future<void> _resumeCastIfLive() async {
    final stored = SettingsStore.activeCastHandoff;
    if (stored == null) return;
    final h = CastHandoff.tryParse(stored);
    if (h == null) {
      await SettingsStore.setActiveCastHandoff(null);
      return;
    }
    if (await cast.syncSessionState()) {
      await _adoptCast(h);
      return;
    }
    _castPendingAdopt = h;
    _castAdoptTimeout = Timer(const Duration(minutes: 1), () {
      if (_castPendingAdopt != h) return;
      _castPendingAdopt = null;
      unawaited(SettingsStore.setActiveCastHandoff(null));
    });
  }

  /// Takes back a cast found live after a relaunch: loads [h]'s book here,
  /// paused at the TV's place, and makes the TV the target again. Anything
  /// that doesn't line up (another book loaded, the files changed, no track
  /// list offline) leaves the TV alone and only keeps its place saved,
  /// through the handoff ([_writeBackHandoff]).
  Future<void> _adoptCast(CastHandoff h) async {
    cast.beginSession(h);
    _castTracker = CastPositionTracker(h);
    final s = cast.status ?? await cast.fetchStatus();
    final at = s == null ? null : _castTracker!.accept(s);
    _castAdopting = true;
    try {
      if (_bookRatingKey != null && _bookRatingKey != h.bookRatingKey) return;
      final tracks = await _tracksFor(h.bookRatingKey);
      final keys = [for (final t in tracks) t.ratingKey];
      if (!listEquals(keys, [for (final t in h.tracks) t.trackRatingKey])) {
        AppLog.log('cast', 'live cast left alone: its files changed');
        return;
      }
      if (_bookRatingKey == null) {
        final started = await startBook(
          service: this,
          bookRatingKey: h.bookRatingKey,
          tracks: tracks,
          from: at != null
              ? BookStartPoint.atTrackIndex(at.item, positionMs: at.positionMs)
              : const BookStartPoint.resume(),
          playback: LaunchPlayback.none,
        );
        if (!started) return;
      }
      _castLoadId = h.loadId;
      _enterCast(h,
          place: at ??
              (
                item: _player.currentIndex ?? 0,
                positionMs: _player.position.inMilliseconds,
              ));
      if (at != null) _castTracker!.accept(s!);
      if (s != null && s.playing) {
        _castWantsPlay = true;
        _openSession();
        _trackingFrom = DateTime.now();
        _startProgressTimer();
      }
      _broadcastState();
      AppLog.log('cast', 'took back a live cast after a relaunch');
    } catch (e) {
      AppLog.log('cast', 'taking back a live cast failed: $e');
    } finally {
      _castAdopting = false;
    }
  }

  /// For a cast this handler didn't take over ([_adoptCast]): keeps the TV's
  /// place saved through the handoff, at most every 10 s, and once more
  /// when the session [ended].
  Future<void> _writeBackHandoff({bool ended = false}) async {
    final tracker = _castTracker;
    final h = cast.handoff;
    if (tracker == null || h == null) return;
    final now = DateTime.now();
    final written = _handoffWrittenAt;
    if (!ended &&
        written != null &&
        now.difference(written) < const Duration(seconds: 10)) {
      return;
    }
    _handoffWrittenAt = now;
    try {
      final last = tracker.last;
      final at = last == null ? null : h.positionAt(last.item, last.positionMs);
      if (at != null) {
        await BookmarkStore.save(
          h.bookRatingKey,
          BookPosition(
            trackRatingKey: at.trackRatingKey,
            positionMs: at.positionMs,
            absolutePositionMs: at.absoluteMs,
            totalDurationMs: h.totalDurationMs,
            savedAt: now,
          ),
        );
        onBookmarkSaved?.call();
        _progressChanged.add(null);
      }
    } catch (e) {
      AppLog.log('cast', 'position writeback failed: $e');
    } finally {
      if (ended) {
        _castTracker = null;
        cast.clearHandoff();
        await SettingsStore.setActiveCastHandoff(null);
        AppLog.log('cast', 'session ended — position handed back');
      }
    }
  }

  /// While casting, the phone's volume keys move the TV.
  void _publishRemoteVolume([CastStatus? s]) {
    if (!_castActive) return;
    final v = (s ?? cast.status)?.deviceVolume ?? 0.5;
    final steps = (v * _remoteVolumeSteps).round();
    if (steps == _remoteVolume) return;
    _remoteVolume = steps;
    androidPlaybackInfo.add(RemoteAndroidPlaybackInfo(
      volumeControlType: AndroidVolumeControlType.absolute,
      maxVolume: _remoteVolumeSteps,
      volume: steps,
    ));
  }

  @override
  Future<void> androidSetRemoteVolume(int volumeIndex) async {
    if (!_castActive) return;
    await cast.setDeviceVolume(volumeIndex / _remoteVolumeSteps);
  }

  @override
  Future<void> androidAdjustRemoteVolume(
      AndroidVolumeDirection direction) async {
    if (!_castActive) return;
    final v = cast.status?.deviceVolume ?? 0.5;
    await cast.setDeviceVolume(
        (v + direction.index / _remoteVolumeSteps).clamp(0.0, 1.0));
  }

  // ── Browsing: Android Auto, the assistant, the resumption card ──────────
  //
  // Saga advertises a MediaBrowserService, so Android walks this tree. Auto
  // builds its library from it, "play <book> in Saga" arrives at
  // [playFromSearch] ([search] only serves Auto's typed search list), and the
  // lock screen's media-resumption card is the `recent` node. Everything is
  // answered from local stores — see [browseChildren] for why.

  @override
  Future<List<MediaItem>> getChildren(String parentMediaId,
          [Map<String, dynamic>? options]) async =>
      browseChildren(parentMediaId);

  @override
  Future<MediaItem?> getMediaItem(String mediaId) async {
    final bookKey = BrowseId.bookKeyOf(mediaId);
    return bookKey == null ? null : bookItem(bookKey);
  }

  @override
  Future<List<MediaItem>> search(String query,
          [Map<String, dynamic>? extras]) async =>
      searchBooks(query);

  /// Voice — `play <book> in Saga`, from the assistant or a car.
  ///
  /// This is the override that makes voice *play* anything: the base class's
  /// [playFromSearch] is an empty no-op, and [search] above only produces the
  /// tappable result list. Voice is the one safe way to pick a book while
  /// driving, so a silent no-op here is a dead feature that looks shipped.
  ///
  /// The query is the listener's spoken words — it names a book, so it is not
  /// logged (record by kind, never by name).
  @override
  Future<void> playFromSearch(String query,
      [Map<String, dynamic>? extras]) async {
    if (query.trim().isEmpty) {
      // "Play something in Saga" — resume the latest book, exactly what the
      // resumption card's play button does.
      await play();
      return;
    }
    final match = searchBooks(query).firstOrNull;
    if (match == null) {
      AppLog.log('playback', 'playFromSearch: no local match for the query');
      return;
    }
    await playFromMediaId(match.id);
  }

  @override
  Future<void> playMediaItem(MediaItem mediaItem) =>
      playFromMediaId(mediaItem.id);

  /// A book's tracks for a launch that didn't come with them. Cache first:
  /// instant, and works offline for downloaded books, which in a car or from
  /// the home-screen widget is the difference between a book starting and
  /// nothing happening. The fetch covers a book never played on this device.
  Future<List<PlexTrack>> _tracksFor(String bookRatingKey) async =>
      TrackCacheStore.load(bookRatingKey) ??
      await _api.fetchTracks(bookRatingKey);

  /// Plays [bookRatingKey] from where the listener left it: a plain [play]
  /// when it's the loaded book (no reload: Prologue 4.2.0 restarted a playing
  /// book from its widget), otherwise a resume launch through [startBook].
  /// Home's resume card and the home-screen widget both come through here.
  /// Throws what [loadTracks] or the launch throws.
  Future<void> resumeBook(String bookRatingKey,
      {Future<List<PlexTrack>> Function()? loadTracks}) async {
    if (_bookRatingKey == bookRatingKey) {
      await play();
      return;
    }
    final tracks = await (loadTracks ?? () => _tracksFor(bookRatingKey))();
    if (tracks.isEmpty) throw StateError('no tracks for book $bookRatingKey');
    await startBook(
      service: this,
      bookRatingKey: bookRatingKey,
      tracks: tracks,
      from: const BookStartPoint.resume(),
    );
  }

  /// The widget's skip buttons. When [bookRatingKey] isn't the loaded book
  /// (the app was closed), it's loaded paused at its saved position first, so
  /// the skip moves from there and never from 0:00, then the result is saved:
  /// a paused book has no timer to save it.
  Future<void> skipBook(String bookRatingKey, {required bool forward}) async {
    if (_bookRatingKey != bookRatingKey) {
      final pos = BookmarkStore.load(bookRatingKey);
      if (pos == null) return;
      final tracks = await _tracksFor(bookRatingKey);
      if (tracks.isEmpty) return;
      final started = await startBook(
        service: this,
        bookRatingKey: bookRatingKey,
        tracks: tracks,
        // The exact saved point: no resume rewind, the listener asked for a
        // skip, not to pick up where they were.
        from: BookStartPoint.atTrack(pos.trackRatingKey,
            positionMs: pos.positionMs),
        playback: LaunchPlayback.none,
      );
      if (!started) return;
    }
    forward ? await fastForward() : await rewind();
    await savePositionForLifecycle();
  }

  /// The home-screen widget's buttons, sent by audio_service's custom-action
  /// start (see the SAGA PATCH in AudioService.onStartCommand). Each names
  /// the book the widget shows, so a press does what the widget says even
  /// when another book is loaded.
  @override
  Future<dynamic> customAction(String name,
      [Map<String, dynamic>? extras]) async {
    final book = extras?['book'] as String?;
    try {
      switch (name) {
        case 'widgetPlay':
          if (book != null) await resumeBook(book);
        case 'widgetPause':
          await pause();
        case 'widgetSkip':
          if (book != null) {
            await skipBook(book, forward: extras?['forward'] == true);
          }
        default:
          return await super.customAction(name, extras);
      }
    } catch (e) {
      // No screen to explain a failure on: leave a trace.
      AppLog.log('playback', 'widget $name failed for book $book: $e');
    }
  }

  /// Starts a book chosen from the browse tree.
  ///
  /// Resumes rather than restarts: picking a book you're halfway through out
  /// of a car list means the same thing it means on the home screen.
  @override
  Future<void> playFromMediaId(String mediaId,
      [Map<String, dynamic>? extras]) async {
    final bookKey = BrowseId.bookKeyOf(mediaId);
    if (bookKey == null) {
      AppLog.log('playback', 'playFromMediaId: not a book id ($mediaId)');
      return;
    }
    try {
      final tracks = await _tracksFor(bookKey);
      if (tracks.isEmpty) {
        AppLog.log('playback', 'playFromMediaId: no tracks for book $bookKey');
        return;
      }
      await startBook(
        service: this,
        bookRatingKey: bookKey,
        tracks: tracks,
        from: const BookStartPoint.resume(),
      );
    } catch (e) {
      // Browsing works with the server unreachable; playing a book whose
      // tracks were never cached does not. Leave a trace rather than a tap
      // that silently did nothing.
      AppLog.log('playback', 'playFromMediaId failed for book $bookKey: $e');
    }
  }

  @override
  Future<void> setSpeed(double speed) async {
    // The phone's player keeps the speed while casting too: it's what the
    // book plays at when it comes back, and what [_castLoad] sends.
    await _player.setSpeed(speed);
    if (_castActive) await cast.setRate(_castRate(speed));
    playbackState.add(playbackState.value.copyWith(speed: speed));
  }

  Future<void> setSkipSilence(bool enabled) =>
      _player.setSkipSilenceEnabled(enabled);

  /// [db] in whole decibels, 0 = off. The fork's Java converts
  /// `targetGain * 1000` → millibels, so the Dart-side unit is tens of dB.
  Future<void> setVolumeBoost(int db) async {
    await _loudnessEnhancer.setTargetGain(db / 10);
    await _loudnessEnhancer.setEnabled(db > 0);
  }

  /// Where playback is right now, for the stream-error reload.
  ///
  /// Prefers the live player position over the stored bookmark — the bookmark
  /// is only as fresh as the last 10-second save. Falls back to the store when
  /// the player isn't ready (mid-load its position is `Duration.zero`, and
  /// resuming there would restart the book).
  BookPosition? _liveOrStoredPosition() {
    final key = _bookRatingKey;
    if (key == null) return null;
    final track = _currentTrack;
    if (track == null || _player.processingState != ProcessingState.ready) {
      return BookmarkStore.load(key);
    }
    final positionMs = _player.position.inMilliseconds;
    return BookPosition(
      trackRatingKey: track.ratingKey,
      positionMs: positionMs,
      absolutePositionMs: _absolutePositionMs(positionMs),
      totalDurationMs: _tracks.fold<int>(0, (sum, t) => sum + t.durationMs),
      savedAt: DateTime.now(),
    );
  }

  /// Saves the current position immediately. Called by the periodic 10-s timer;
  /// skips when the player is not fully ready to avoid writing a stale position.
  Future<void> savePosition() async {
    if (_isReady) {
      await _saveAndReportPosition(state: _isPlaying ? 'playing' : 'paused');
    }
  }

  /// Saves the current position unconditionally. Called on app lifecycle events
  /// (background, detach) so the position is never lost when Android kills the app
  /// while the player is buffering on a slow connection.
  /// _player.position remains valid during ProcessingState.buffering.
  Future<void> savePositionForLifecycle() async {
    if (_castActive) {
      if (!_isReady) return;
    } else {
      final ps = _player.processingState;
      if (ps == ProcessingState.idle || ps == ProcessingState.completed) return;
    }
    await _saveAndReportPosition(state: _isPlaying ? 'playing' : 'paused');
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

  /// Position within the current file, on whichever player holds the book;
  /// moves on between the TV's status pushes.
  Stream<Duration> get positionStream => _castingSubject.switchMap((c) => c
      ? Stream<Duration>.periodic(const Duration(milliseconds: 200),
              (_) => Duration(milliseconds: _castPositionNowMs))
          .startWith(Duration(milliseconds: _castPositionNowMs))
      : _player.positionStream);
  Stream<int?> get currentIndexStream => _castingSubject
      .switchMap((c) => c ? _castItem.stream : _player.currentIndexStream);

  /// Position within the current file, right now.
  int get trackPositionMs => _trackPosMs;

  /// The current file's index.
  int? get currentIndex => _index;

  /// The current file's length: the player's, else Plex's metadata (a
  /// stream still buffering has none, and the TV never says).
  int? get currentTrackDurationMs {
    final playerMs = _castActive ? null : _player.duration?.inMilliseconds;
    if (playerMs != null && playerMs > 0) return playerMs;
    final i = _index;
    final metaMs = i != null && i < _tracks.length ? _tracks[i].durationMs : 0;
    return metaMs > 0 ? metaMs : null;
  }

  /// Total duration of all tracks in the currently loaded book.
  int get totalBookDurationMs =>
      _tracks.fold<int>(0, (s, t) => s + t.durationMs);

  /// Current position expressed as an absolute offset into the whole book.
  int get absolutePositionMs => _absolutePositionMs(_trackPosMs);

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
    await _seekTo(target.positionMs, index: target.index);
    _jumped();
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
        _trackPosMs,
        totalMs,
      );
    }
    if (_tracks.length > 1) {
      final durations = _trackDurationsMs;
      final idx = (_index ?? 0).clamp(0, durations.length - 1);
      final startMs = absoluteFromTrack(durations, idx, 0);
      return (startMs: startMs, endMs: startMs + durations[idx]);
    }
    return (startMs: 0, endMs: totalMs);
  }

  Future<void> seekAbsolute(Duration absolutePosition) async {
    // Clamp 1 s short of the end: landing exactly on the total is
    // end-of-media to ExoPlayer, so a +30 s press with 20 s left would trip
    // completion detection (finished panel, session torn down) mid-sentence.
    // Finishing a book happens by playing its last second, never by seeking.
    final totalMs = totalBookDurationMs;
    var targetMs = absolutePosition.inMilliseconds;
    if (totalMs > 0) {
      targetMs =
          targetMs.clamp(0, (totalMs - _endGuardMs).clamp(0, totalMs)).toInt();
    }
    final target = trackFromAbsolute(_trackDurationsMs, targetMs);
    if (target == null) return;
    // Arm undo only for a seek that actually happens — arming before the
    // null return lit the Undo button against a position never left.
    _previousAbsolutePositionMs = absolutePositionMs;
    canUndoSeekNotifier.value = true;
    await _seekTo(target.positionMs, index: target.index);
    _jumped();
  }

  void logSleepTimer() => _logEvent('sleepTimer');

  // Whether the playback log has a `play` with no `pause` after it yet. The
  // log's sessions are play → pause pairs, and three paths used to break the
  // pairing: a jump while playing logged the new play without closing the old
  // session, a play command while already playing logged a second play, and
  // a pause or stop while already paused logged a pause with nothing to
  // close. Each left a session with no end (or a stray pause) — a list of
  // "from 1:40:21" rows after a few chapter taps. Only these two touch it.
  bool _sessionOpen = false;

  void _openSession() {
    if (_sessionOpen) return;
    _sessionOpen = _logEvent('play');
  }

  void _closeSession() {
    if (!_sessionOpen) return;
    _logEvent('pause');
    _sessionOpen = false;
  }

  /// Whether anything was logged — nothing is, with no book loaded.
  bool _logEvent(String type, {int? overridePositionMs}) {
    final track = _currentTrack;
    final bookKey = _bookRatingKey;
    if (track == null || bookKey == null) return false;
    PlaybackLogStore.log(
      bookRatingKey: bookKey,
      event: AudioLogEvent(
        type: type,
        trackRatingKey: track.ratingKey,
        positionMs: overridePositionMs ?? _trackPosMs,
        timestamp: DateTime.now(),
      ),
    );
    return true;
  }

  Future<void> _markBookCompleted() async {
    final bookKey = _bookRatingKey;
    if (bookKey == null) return;
    // Guard against double-counting within one listen (more than one
    // completion signal can arrive for the same finish). A fresh load resets
    // the flag, so a later re-listen counts as a new completion — that drives
    // the listen count.
    if (_completedThisSession) return;
    _completedThisSession = true;
    final track = _tracks.firstOrNull;
    await recordBookFinished(
      ratingKey: bookKey,
      title: track?.bookTitle,
      thumbPath: track?.thumbPath,
    );
    justFinishedBook.value = bookKey; // trigger the finished panel
    onBookCompleted?.call();
    _progressChanged.add(null);
  }

  void _startProgressTimer() {
    _progressTimer?.cancel();
    _progressTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      // Skip saves while buffering/loading — position is not yet settled and
      // saving it would create a false drift on the next resume.
      if (!_isPlaying || !_isReady) return;
      // Heals a platform session rebuilt mid-listen (see republishNowPlaying)
      // within one tick, before the user ever hits a dead button.
      republishNowPlaying();
      _saveAndReportPosition(state: 'playing');
    });
  }

  Future<void> _saveAndReportPosition({required String state}) async {
    // Mid-load the identity fields already name the incoming book while the
    // player still reports the outgoing one — a save here would file A's
    // position under B's key and destroy B's place. Skip; the next periodic
    // tick lands after the load, and loadBook itself saves the outgoing book.
    if (_loadInProgress) return;
    final track = _currentTrack;
    final bookKey = _bookRatingKey;
    if (track == null || bookKey == null) return;

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
          bookKey,
          lastCompletedAt:
              CompletedBooksStore.completionDates(bookKey).lastOrNull,
        );
      }
    }

    final positionMs = _trackPosMs;
    final absolutePositionMs = _absolutePositionMs(positionMs);

    // Awaited so the write is durable before this future completes — the
    // lifecycle save path (app backgrounded/killed) depends on it.
    await BookmarkStore.save(
      bookKey,
      BookPosition(
        trackRatingKey: track.ratingKey,
        positionMs: positionMs,
        absolutePositionMs: absolutePositionMs,
        totalDurationMs: _tracks.fold<int>(0, (sum, t) => sum + t.durationMs),
        savedAt: DateTime.now(),
      ),
    );
    onBookmarkSaved?.call();
    _progressChanged.add(null);

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
      // app foreground. Last-write-wins: one pending entry per book. Uses the
      // book key captured when the position was, NOT re-read here: the error
      // lands seconds later, and a book switch in between filed A's pending
      // update under B's key.
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
        } on DioException catch (e) {
          // A 4xx means the server saw the report and refused it — retrying
          // can't fix that, and one such entry would stop the loop at itself
          // forever, blocking every entry queued behind it. Auth refusals are
          // the exception: signing back in fixes those, so they wait.
          final status = e.response?.statusCode;
          final permanent = status != null &&
              status >= 400 && status < 500 &&
              status != 401 && status != 403;
          if (permanent) {
            AppLog.log('plex',
                'queued timeline for ${t.ratingKey} rejected ($status) — '
                'dropped');
            await TimelineQueueStore.remove(entry.key);
            continue;
          }
          break; // offline or transient — try again next time
        } catch (_) {
          break; // still offline — try again next time
        }
      }
    } finally {
      _flushingQueue = false;
    }
  }

  PlexTrack? get _currentTrack {
    final index = _index;
    if (index == null || index >= _tracks.length) return null;
    return _tracks[index];
  }

  List<int> get _trackDurationsMs => [for (final t in _tracks) t.durationMs];

  int _absolutePositionMs(int currentTrackPositionMs) => absoluteFromTrack(
      _trackDurationsMs, _index ?? 0, currentTrackPositionMs);

  void _broadcastState([PlaybackEvent? event]) {
    final playing = _isPlaying;
    final position = Duration(milliseconds: _trackPosMs);
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
      processingState: _castActive
          ? _castProcessing
          : {
              ProcessingState.idle: AudioProcessingState.idle,
              ProcessingState.loading: AudioProcessingState.loading,
              ProcessingState.buffering: AudioProcessingState.buffering,
              ProcessingState.ready: AudioProcessingState.ready,
              ProcessingState.completed: AudioProcessingState.completed,
            }[_player.processingState]!,
      playing: playing,
      updatePosition: position,
      bufferedPosition: _castActive ? position : _player.bufferedPosition,
      speed: _player.speed,
      queueIndex: _index,
    ));
  }

  MediaItem _trackToMediaItem(PlexTrack track) {
    final thumbPath = track.thumbPath;
    // Cached file or nothing — never a URL carrying a credential. This item
    // becomes the platform MediaSession's metadata, which any app holding
    // notification access can read, and the Plex token is account-wide.
    // Leaving it null costs nothing: [_prefetchArtwork] downloads the cover
    // with header auth and re-emits this item with the local `file://` URI a
    // moment later.
    final artUri = ArtworkCache.getLocalUri(thumbPath);

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
