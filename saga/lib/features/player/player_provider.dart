import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/audio/m4b_chapter_reader.dart';
import '../../core/diagnostics/app_log.dart';
import '../../core/plex/models/plex_track.dart';
import '../../core/providers.dart';
import '../../core/storage/artwork_cache.dart';
import '../../core/storage/book_download_store.dart';
import '../../core/storage/download_store.dart';
import '../../core/storage/settings_store.dart';
import '../../core/storage/track_cache_store.dart';
import 'book_launch.dart';
import 'play_next.dart';
import 'player_service.dart';

// Initialized in main.dart before runApp
AudioPlayerService? _serviceInstance;

final playerServiceProvider = Provider<AudioPlayerService>((ref) {
  final service = _serviceInstance!;
  service.onBookCompleted = () {
    ref.read(completionRevisionProvider.notifier).state++;
    _maybeAutoAdvance(ref, service);
  };
  service.onBookmarkSaved = () {
    ref.read(bookmarkRevisionProvider.notifier).state++;
  };
  service.onHistoryRecorded = () {
    ref.read(historyRevisionProvider.notifier).state++;
  };
  service.onStreamError = (bookRatingKey, position) async {
    try {
      AppLog.log('playback',
          'auto-reload after stream error: book $bookRatingKey');
      final tracks = await ref.read(tracksProvider(bookRatingKey).future);
      if (tracks.isEmpty) return;
      await startBook(
        service: service,
        bookRatingKey: bookRatingKey,
        tracks: tracks,
        // The live position captured when the stream died, which is fresher
        // than the saved one; no rewind, because no time has passed. Falls
        // back to the saved position if the error arrived before one existed.
        from: position != null
            ? BookStartPoint.atTrack(position.trackRatingKey,
                positionMs: position.positionMs)
            : const BookStartPoint.resume(),
        isAutoReload: true,
      );
    } catch (e) {
      // Server still unreachable — player stays paused, user can retry manually
      AppLog.log('playback', 'auto-reload failed: $e');
    }
  };
  return service;
});

void setPlayerServiceInstance(AudioPlayerService s) {
  _serviceInstance = s;
}

/// Seconds the finished panel counts down before the next book starts.
const _kAutoAdvanceSeconds = 5;

/// Starts the next book in the collection when one finishes, if the user has
/// opted in.
///
/// This lives here rather than in the finished panel because the panel only
/// exists while `PlayerScreen` is on screen — and books usually finish with the
/// phone in a pocket. Completion is observed here, so the decision is too.
///
/// The 5-second countdown is the escape hatch for the case where the user *is*
/// looking: the panel renders it with a Cancel. With the screen off it just
/// elapses.
void _maybeAutoAdvance(Ref ref, AudioPlayerService service) {
  if (!SettingsStore.autoPlayNextBook) return;
  final bookKey = service.currentBookRatingKey;
  if (bookKey == null) return;

  Future<void>(() async {
    try {
      final libraryKey = await ref.read(activeLibraryKeyProvider.future);
      if (libraryKey == null) return;
      // Only resolves for books in a user-made collection — there's no
      // Plex-metadata series fallback yet. The setting's subtitle says so.
      final next =
          await ref.read(nextInSeriesProvider('$libraryKey|$bookKey').future);
      if (next == null) return;
      // The user may have acted while the lookup was in flight: dismissed the
      // finished panel, started another book, or hit play to hear this one
      // again. Any of those means don't arm anything.
      if (service.justFinishedBook.value != bookKey) return;
      if (service.currentBookRatingKey != bookKey) return;
      if (service.playbackState.value.playing) return;

      service.scheduleAutoAdvance(_kAutoAdvanceSeconds, () async {
        AppLog.log('playback', 'auto-advancing to ${next.$2.ratingKey}');
        await playNextBook(
          service: service,
          book: next.$2,
          loadTracks: (key) => ref.read(tracksProvider(key).future),
        );
      });
    } catch (e) {
      AppLog.log('playback', 'auto-advance lookup failed: $e');
    }
  });
}

// ── Download notifier ─────────────────────────────────────────────────────────

class DownloadState {
  final Map<String, double> progress; // trackRatingKey -> 0.0..1.0 (queued or downloading)
  final Set<String> completed;        // trackRatingKeys fully downloaded
  final Set<String> downloadedBooks;  // bookRatingKeys with at least one track
  final Set<String> failed;           // trackRatingKeys whose last attempt failed

  const DownloadState({
    this.progress = const {},
    this.completed = const {},
    this.downloadedBooks = const {},
    this.failed = const {},
  });

  DownloadState copyWith({
    Map<String, double>? progress,
    Set<String>? completed,
    Set<String>? downloadedBooks,
    Set<String>? failed,
  }) =>
      DownloadState(
        progress: progress ?? this.progress,
        completed: completed ?? this.completed,
        downloadedBooks: downloadedBooks ?? this.downloadedBooks,
        failed: failed ?? this.failed,
      );
}

/// True when every track of the book is downloaded. When the expected total is
/// unknown (book downloaded before the track cache existed and not yet
/// backfilled), falls back to the old optimistic "has any download" behavior.
/// Callers must watch [downloadNotifierProvider] for reactivity.
bool isBookFullyDownloaded(String bookRatingKey) {
  final have = BookDownloadStore.downloadedCount(bookRatingKey);
  if (have == 0) return false;
  final expected = TrackCacheStore.trackCount(bookRatingKey);
  return expected == null ? true : have >= expected;
}

class DownloadNotifier extends StateNotifier<DownloadState> {
  final Ref _ref;

  /// Cap on simultaneous downloads. A whole-book "download" enqueues every
  /// track at once; without a cap that opens dozens of parallel connections,
  /// saturating the link and spiking memory. Excess jobs wait in [_queue].
  static const _maxConcurrent = 3;
  final List<({PlexTrack track, String bookRatingKey})> _queue = [];
  int _active = 0;

  DownloadNotifier(this._ref) : super(const DownloadState()) {
    _loadExisting();
    reconcile(); // fire-and-forget: heal store/disk drift at startup
  }

  void _loadExisting() {
    final all = DownloadStore.allDownloads();
    final books = BookDownloadStore.booksWithDownloads();
    state = state.copyWith(completed: all.keys.toSet(), downloadedBooks: books);
  }

  /// Drops download metadata whose files no longer exist on disk. Historic
  /// cause: the storage manager's delete used to remove folders without
  /// clearing the stores, so Browse showed "downloaded" for books with no
  /// files while the storage list (folder-based at the time) didn't list
  /// them. Runs at startup and before every storage scan; heals that state.
  Future<int> reconcile() async {
    var purged = 0;
    for (final book in BookDownloadStore.booksWithDownloads().toList()) {
      for (final key in BookDownloadStore.trackKeys(book).toList()) {
        final path = DownloadStore.getPath(key);
        if (path == null || !File(path).existsSync()) {
          await DownloadStore.remove(key);
          BookDownloadStore.removeDownload(book, key);
          purged++;
        }
      }
      if (!BookDownloadStore.hasDownload(book)) {
        await TrackCacheStore.delete(book);
      }
    }
    if (purged > 0) {
      AppLog.log('download',
          'reconciled $purged download entries with missing files');
      _loadExisting();
    }
    return purged;
  }

  /// Enqueues every not-yet-downloaded track of a book.
  Future<void> downloadBook(
      String bookRatingKey, List<PlexTrack> tracks) async {
    for (final track in tracks) {
      await downloadTrack(track, bookRatingKey, tracks);
    }
  }

  /// Enqueues [track] for download. Returns immediately; the job runs when a
  /// concurrency slot frees up. Safe to call repeatedly — already-downloaded,
  /// queued, or in-flight tracks are ignored.
  ///
  /// [bookTracks] is the book's *full* track list, required on every path so
  /// the offline track cache can't be skipped: it makes the book openable with
  /// the server unreachable, and it's the only record of how many files the
  /// book has — without it [isBookFullyDownloaded] falls back to "any download
  /// counts" and the completed badge lights up on the first file of a 20-file
  /// book (the per-chapter download button used to do exactly that).
  Future<void> downloadTrack(PlexTrack track, String bookRatingKey,
      List<PlexTrack> bookTracks) async {
    if (TrackCacheStore.trackCount(bookRatingKey) != bookTracks.length) {
      await TrackCacheStore.save(bookRatingKey, bookTracks);
    }
    final key = track.ratingKey;
    if (state.completed.contains(key)) return;
    if (state.progress.containsKey(key)) return; // queued or downloading
    if (_queue.any((j) => j.track.ratingKey == key)) return;

    // 0.0 marks it as queued so the UI shows a pending spinner immediately.
    state = state.copyWith(
      progress: {...state.progress, key: 0.0},
      failed: {...state.failed}..remove(key),
    );
    _queue.add((track: track, bookRatingKey: bookRatingKey));
    _pump();
  }

  void _pump() {
    while (_active < _maxConcurrent && _queue.isNotEmpty) {
      final job = _queue.removeAt(0);
      _active++;
      // Fire-and-forget; _runDownload decrements _active and re-pumps when done.
      _runDownload(job.track, job.bookRatingKey);
    }
  }

  Future<void> _runDownload(PlexTrack track, String bookRatingKey) async {
    final key = track.ratingKey;
    String? filePath;
    try {
      // Respect the "download on Wi-Fi only" setting: skip (and surface as a
      // retryable failure) when on a metered connection.
      if (SettingsStore.downloadWifiOnly) {
        final conn = await Connectivity().checkConnectivity();
        final unmetered = conn.contains(ConnectivityResult.wifi) ||
            conn.contains(ConnectivityResult.ethernet);
        if (!unmetered) {
          // The UI shows the same "Retry N failed" for every failure kind —
          // without this line a metered-connection skip reads as a broken app.
          AppLog.log('download',
              'track $key skipped: Wi-Fi only is on and connection is metered');
          _markFailed(key);
          return;
        }
      }

      final client = _ref.read(plexClientProvider);
      final url = client.buildDownloadUrl(track.partKey);
      if (url == null) {
        AppLog.log('download', 'track $key failed: no server URI configured');
        _markFailed(key);
        return;
      }

      const audioExtensions = {
        'mp3', 'm4b', 'm4a', 'ogg', 'flac', 'opus', 'aac', 'wav'
      };
      final rawExt = (track.partFile?.split('.').last ?? '').toLowerCase();
      final ext = audioExtensions.contains(rawExt) ? rawExt : 'mp3';
      final dir = await _downloadDir(track);
      filePath = '${dir.path}/$key.$ext';

      // connectTimeout fails fast on an unreachable server; receiveTimeout is an
      // inactivity timeout (no bytes for the duration) so a stalled connection
      // aborts instead of hanging forever, without killing slow-but-progressing
      // large downloads.
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 60),
      ));
      await dio.download(
        url,
        filePath,
        options: Options(headers: client.authHeaders),
        onReceiveProgress: (received, total) {
          if (total > 0) {
            state = state.copyWith(
              progress: {...state.progress, key: received / total},
            );
          }
        },
      );

      await DownloadStore.save(key, filePath);
      BookDownloadStore.recordDownload(bookRatingKey, key);

      // Take the cover while the server is still in reach. Nothing else caches
      // it until the player loads the book, so a book downloaded for a trip and
      // not played before leaving showed a grey tile on the offline shelf — the
      // one screen where re-fetching it isn't an option. Not awaited, and a
      // failure is ignored: a missing cover must never fail a download.
      final thumb = track.thumbPath;
      final serverUri = client.serverUri;
      if (thumb != null && serverUri != null) {
        unawaited(ArtworkCache.prefetch(thumb, serverUri, client.authHeaders));
      }

      state = state.copyWith(
        progress: Map<String, double>.from(state.progress)..remove(key),
        completed: {...state.completed, key},
        downloadedBooks: {...state.downloadedBooks, bookRatingKey},
      );
    } catch (e) {
      // The UI only shows "Retry N failed" — the reason lives here.
      AppLog.log('download', 'track $key failed: $e');
      // Remove the partially-written file: it's never played (playback is
      // gated on DownloadStore metadata) but would sit invisibly on disk —
      // the storage manager only lists completed downloads.
      if (filePath != null) {
        try {
          await File(filePath).delete();
        } catch (_) {}
      }
      _markFailed(key);
    } finally {
      _active--;
      _pump();
    }
  }

  void _markFailed(String trackRatingKey) {
    state = state.copyWith(
      progress: Map<String, double>.from(state.progress)..remove(trackRatingKey),
      failed: {...state.failed, trackRatingKey},
    );
  }

  Future<Directory> _downloadDir(PlexTrack track) async {
    final base = await getApplicationDocumentsDirectory();
    final raw = track.bookTitle ?? track.ratingKey;
    final sanitized = raw
        .replaceAll('..', '_')
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_')
        .trim();
    final dirName = sanitized.isEmpty ? track.ratingKey : sanitized;
    final dir = Directory('${base.path}/downloads/$dirName');
    await dir.create(recursive: true);
    return dir;
  }

  Future<void> deleteBook(String bookRatingKey, List<PlexTrack> tracks) =>
      deleteBookByKeys(bookRatingKey, tracks.map((t) => t.ratingKey));

  /// Key-based variant for callers that don't have `PlexTrack` objects (the
  /// storage manager works from the stores). ALL download deletion must go
  /// through here so files, store metadata, track cache, and UI state can
  /// never diverge — a raw `Directory.delete` once left Browse showing
  /// "downloaded" for books whose files were gone.
  Future<void> deleteBookByKeys(
      String bookRatingKey, Iterable<String> trackRatingKeys) async {
    final keys = trackRatingKeys.toSet();
    // Collect paths before removing from store.
    final paths =
        keys.map(DownloadStore.getPath).whereType<String>().toList();

    // Store metadata BEFORE the state update: the settings storage list
    // refreshes when this notifier's state changes and rebuilds from the
    // stores — with state first, it re-scanned while the stores still listed
    // the book and stayed stale until the next state change (Kiffir's
    // follow-up on issue #2). Hive ops are milliseconds, so the UI still
    // reacts effectively immediately; only slow file I/O stays after.
    for (final key in keys) {
      await DownloadStore.remove(key);
      BookDownloadStore.removeDownload(bookRatingKey, key);
    }
    await TrackCacheStore.delete(bookRatingKey);

    state = state.copyWith(
      completed: Set<String>.from(state.completed)..removeAll(keys),
      downloadedBooks: Set<String>.from(state.downloadedBooks)
        ..remove(bookRatingKey),
      failed: {...state.failed}..removeAll(keys),
    );

    // Delete the actual files, then any book folders left empty.
    for (final path in paths) {
      final file = File(path);
      if (await file.exists()) await file.delete();
    }
    for (final dirPath in paths.map((p) => File(p).parent.path).toSet()) {
      try {
        final dir = Directory(dirPath);
        if (dir.existsSync() && dir.listSync().isEmpty) {
          await dir.delete();
        }
      } catch (_) {} // best-effort cleanup only
    }
  }

}

final downloadNotifierProvider =
    StateNotifierProvider<DownloadNotifier, DownloadState>((ref) {
  return DownloadNotifier(ref);
});

/// Emits the ratingKey of the book actively playing, or null when paused/stopped.
final nowPlayingKeyProvider = StreamProvider<String?>((ref) async* {
  final service = ref.watch(playerServiceProvider);
  await for (final state in service.playbackState.stream) {
    yield state.playing ? service.currentBookRatingKey : null;
  }
});

// ── Sleep timer ───────────────────────────────────────────────────────────────

typedef _PlaybackPhase = ({bool playing, AudioProcessingState processing});

class SleepTimerNotifier extends StateNotifier<DateTime?> {
  // Fade the last moments of the countdown instead of cutting mid-sentence.
  // Floor of 0.05 rather than 0: the pause lands before silence, and a true
  // zero would trip loadBook's stray-mute restore if a book loaded mid-fade.
  static const _fadeWindow = Duration(seconds: 15);

  Timer? _timer;
  Timer? _fadeTicker;
  bool _faded = false;
  StreamSubscription<_PlaybackPhase>? _playbackSub;
  final AudioPlayerService _service;

  // Set while playback is paused mid-countdown: the frozen time remaining, so
  // the timer measures *listening* time, not wall-clock. Restored on resume.
  Duration? _pausedRemaining;

  SleepTimerNotifier(this._service) : super(null);

  void set(Duration duration) {
    _cancelAll();
    _service.logSleepTimer();
    _arm(duration);
    _watchPlayback();
  }

  /// Pauses at the end of the current chapter/track.
  /// For M4B single-file books pass [m4bChapters] so the timer fires at the
  /// next chapter boundary; for multi-track books leave it null and the timer
  /// fires when the current track finishes. The remaining audio is divided by
  /// the current playback speed so the timer fires at the boundary even at >1×.
  void setEndOfChapter({List<M4bChapter>? m4bChapters}) {
    _cancelAll();

    final durationMs = _service.player.duration?.inMilliseconds;
    final positionMs = _service.player.position.inMilliseconds;

    int targetMs;
    if (m4bChapters != null && m4bChapters.isNotEmpty) {
      // Find the first chapter that starts after the current position. When the
      // user is already in the last chapter no such chapter exists — fall through
      // to the file-duration target so the timer stops at the end of the audio
      // rather than firing immediately (the previous orElse: () => last bug).
      final upcoming = m4bChapters
          .where((c) => c.start.inMilliseconds > positionMs);
      targetMs = upcoming.isNotEmpty
          ? upcoming.first.start.inMilliseconds
          : (durationMs ?? positionMs + 60000);
    } else {
      targetMs = durationMs ?? positionMs + 60000;
    }

    final audioRemainingMs = (targetMs - positionMs).clamp(0, 1 << 31);
    final speed = _service.player.speed;
    final remainingMs =
        (speed > 0 ? audioRemainingMs / speed : audioRemainingMs).round();
    if (remainingMs <= 0) {
      _service.pause();
      return;
    }

    _service.logSleepTimer();
    _arm(Duration(milliseconds: remainingMs));
    _watchPlayback();
  }

  void cancel() => _cancelAll();

  Duration? get remaining {
    if (_pausedRemaining != null) return _pausedRemaining;
    final end = state;
    if (end == null) return null;
    final r = end.difference(DateTime.now());
    return r.isNegative ? null : r;
  }

  /// (Re)starts the countdown for [remaining], scheduling the pause.
  void _arm(Duration remaining) {
    _timer?.cancel();
    _pausedRemaining = null;
    state = DateTime.now().add(remaining);
    _timer = Timer(remaining, () async {
      // Volume is restored only after the pause, so the fade's tail never
      // jumps back to full volume while still audible.
      _cancelAll(restoreVolume: false);
      await _service.pause();
      _restoreVolume();
    });
    _fadeTicker ??=
        Timer.periodic(const Duration(milliseconds: 500), (_) => _fadeTick());
  }

  /// Eases volume down over the countdown's final [_fadeWindow]. Runs for the
  /// timer's whole life but is a no-op until the window; while paused
  /// mid-countdown `remaining` is frozen, so it just re-sets the same volume.
  void _fadeTick() {
    final r = remaining;
    if (r == null || r > _fadeWindow) return;
    _faded = true;
    _service.player
        .setVolume((r.inMilliseconds / _fadeWindow.inMilliseconds).clamp(0.05, 1.0));
  }

  void _restoreVolume() {
    if (!_faded) return;
    _faded = false;
    _service.player.setVolume(1.0);
  }

  /// Pauses the countdown when playback pauses and resumes it when playback
  /// resumes, so the timer can't fire while paused or drift after an
  /// interruption. The countdown then measures listening time, not wall time.
  /// Ends the timer outright when playback ends, which pausing can't be told
  /// apart from otherwise.
  void _watchPlayback() {
    _playbackSub?.cancel();
    _playbackSub = _service.playbackState
        .map((s) => (playing: s.playing, processing: s.processingState))
        .distinct()
        .listen((phase) {
      if (state == null) return; // no active timer
      // Playback is over (book finished, or the service stopped): there is no
      // listening time left for the countdown to measure. Without this the
      // timer froze as if merely paused, so the player kept showing an armed
      // sleep timer after the book ended — and re-armed it against whatever
      // was played next.
      if (phase.processing == AudioProcessingState.completed ||
          phase.processing == AudioProcessingState.idle) {
        _cancelAll();
        return;
      }
      final playing = phase.playing;
      if (!playing && _pausedRemaining == null) {
        _pausedRemaining = remaining; // freeze
        _timer?.cancel();
        _timer = null;
      } else if (playing && _pausedRemaining != null) {
        final r = _pausedRemaining!;
        if (r > Duration.zero) {
          _arm(r); // resume (clears _pausedRemaining)
        } else {
          _pausedRemaining = null;
        }
      }
    }, onError: (Object e, StackTrace st) {
      AppLog.log('sleep-timer', 'playback watch error: $e');
    });
  }

  void _cancelAll({bool restoreVolume = true}) {
    _timer?.cancel();
    _timer = null;
    _fadeTicker?.cancel();
    _fadeTicker = null;
    _playbackSub?.cancel();
    _playbackSub = null;
    _pausedRemaining = null;
    state = null;
    if (restoreVolume) _restoreVolume();
  }

  @override
  void dispose() {
    _cancelAll();
    super.dispose();
  }
}

final sleepTimerProvider =
    StateNotifierProvider<SleepTimerNotifier, DateTime?>((ref) {
  return SleepTimerNotifier(ref.watch(playerServiceProvider));
});

// ── Playback speed ────────────────────────────────────────────────────────────

/// The speed the player is *actually* running at, read from the audio
/// service's own broadcast state — deliberately not a second copy of it.
///
/// Every path that changes speed (book load from Home / Browse / book detail,
/// the player's speed sheet, the Settings default, the auto-reload after a
/// stream error, and session restore after process death) goes through
/// [AudioPlayerService.setSpeed], which republishes `playbackState`. Deriving
/// the UI from that is what stops the two from drifting: the hand-maintained
/// mirror this replaced had six call sites that each had to remember to
/// update it, and session restore didn't — so a book restored from the media
/// notification played at its saved speed while the player screen showed the
/// default.
final playbackSpeedProvider = StreamProvider<double>((ref) {
  final service = ref.watch(playerServiceProvider);
  return service.playbackState.map((s) => s.speed).distinct();
});
