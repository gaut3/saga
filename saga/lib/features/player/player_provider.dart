import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/audio/m4b_chapter_reader.dart';
import '../../core/diagnostics/app_log.dart';
import '../../core/plex/models/plex_track.dart';
import '../../core/providers.dart';
import '../../core/storage/book_download_store.dart';
import '../../core/storage/download_store.dart';
import '../../core/storage/settings_store.dart';
import 'player_service.dart';

// Initialized in main.dart before runApp
AudioPlayerService? _serviceInstance;

final playerServiceProvider = Provider<AudioPlayerService>((ref) {
  final service = _serviceInstance!;
  service.onBookCompleted = () {
    ref.read(completionRevisionProvider.notifier).state++;
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
      final idx = position != null
          ? tracks.indexWhere((t) => t.ratingKey == position.trackRatingKey)
          : -1;
      await service.loadBook(
        bookRatingKey: bookRatingKey,
        tracks: tracks,
        startTrackIndex: idx < 0 ? 0 : idx,
        startPositionMs: position?.positionMs ?? 0,
        isAutoReload: true,
      );
      final savedSpeed = SettingsStore.getBookSpeed(bookRatingKey);
      await service.setSpeed(savedSpeed);
      ref.read(playbackSpeedProvider.notifier).state = savedSpeed;
      await service.play();
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
  }

  void _loadExisting() {
    final all = DownloadStore.allDownloads();
    final books = BookDownloadStore.booksWithDownloads();
    state = state.copyWith(completed: all.keys.toSet(), downloadedBooks: books);
  }

  /// Enqueues [track] for download. Returns immediately; the job runs when a
  /// concurrency slot frees up. Safe to call repeatedly — already-downloaded,
  /// queued, or in-flight tracks are ignored.
  Future<void> downloadTrack(PlexTrack track, String bookRatingKey) async {
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
          _markFailed(key);
          return;
        }
      }

      final client = _ref.read(plexClientProvider);
      final url = client.buildStreamUrl(track.partKey);
      if (url == null) {
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

  Future<void> deleteBook(String bookRatingKey, List<PlexTrack> tracks) async {
    // Collect paths before removing from store.
    final paths = tracks
        .map((t) => DownloadStore.getPath(t.ratingKey))
        .whereType<String>()
        .toList();

    // Update UI state immediately so the button reacts before file I/O finishes.
    final keys = tracks.map((t) => t.ratingKey).toSet();
    state = state.copyWith(
      completed: Set<String>.from(state.completed)..removeAll(keys),
      downloadedBooks: Set<String>.from(state.downloadedBooks)
        ..remove(bookRatingKey),
      failed: {...state.failed}..removeAll(keys),
    );

    // Clean up store metadata.
    for (final track in tracks) {
      await DownloadStore.remove(track.ratingKey);
      BookDownloadStore.removeDownload(bookRatingKey, track.ratingKey);
    }

    // Delete the actual files.
    for (final path in paths) {
      final file = File(path);
      if (await file.exists()) await file.delete();
    }
  }

  Future<void> deleteTrack(PlexTrack track, String bookRatingKey) async {
    final path = DownloadStore.getPath(track.ratingKey);
    if (path != null) {
      final file = File(path);
      if (await file.exists()) await file.delete();
    }
    await DownloadStore.remove(track.ratingKey);
    BookDownloadStore.removeDownload(bookRatingKey, track.ratingKey);

    final newCompleted = Set<String>.from(state.completed)
      ..remove(track.ratingKey);
    final newBooks = BookDownloadStore.hasDownload(bookRatingKey)
        ? state.downloadedBooks
        : (Set<String>.from(state.downloadedBooks)..remove(bookRatingKey));
    state = state.copyWith(
      completed: newCompleted,
      downloadedBooks: newBooks,
      failed: {...state.failed}..remove(track.ratingKey),
    );
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

enum SleepMode { timed, endOfChapter }

class SleepTimerNotifier extends StateNotifier<DateTime?> {
  Timer? _timer;
  StreamSubscription<bool>? _playingSub;
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

  bool get isActive => state != null;

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
      _cancelAll();
      await _service.pause();
    });
  }

  /// Pauses the countdown when playback pauses and resumes it when playback
  /// resumes, so the timer can't fire while paused or drift after an
  /// interruption. The countdown then measures listening time, not wall time.
  void _watchPlayback() {
    _playingSub?.cancel();
    _playingSub =
        _service.playbackState.map((s) => s.playing).distinct().listen((playing) {
      if (state == null) return; // no active timer
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

  void _cancelAll() {
    _timer?.cancel();
    _timer = null;
    _playingSub?.cancel();
    _playingSub = null;
    _pausedRemaining = null;
    state = null;
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

final playbackSpeedProvider =
    StateProvider<double>((_) => SettingsStore.defaultSpeed);
