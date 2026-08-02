import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// A source of display-ready loudness for [AnimatedSagaMark]'s reactive bars.
///
/// Implemented by [AudioLevel] (the real tap) and by [CannedAudioLevel] (a
/// recorded trace, for previewing the motion with nothing playing).
abstract interface class AudioLevelSource {
  /// Display-ready loudness, 0..1.
  ValueListenable<double> get level;

  /// Whether a fresh sample arrived recently. False makes the mark fall back to
  /// its synthetic envelope.
  bool get isLive;
}

/// Real-time output loudness tapped from the audio pipeline by the vendored
/// just_audio patch (a Media3 `TeeAudioProcessor` — no `RECORD_AUDIO`).
///
/// The native side emits a raw RMS (~30 Hz, only while audio plays). We apply a
/// little gain so [level] is a display-ready 0..1 value. The animated mark uses
/// it to drive the "playing" bars and falls back to its synthetic envelope
/// whenever the tap isn't [isLive] (paused, between tracks, non-PCM output…).
class AudioLevel implements AudioLevelSource {
  AudioLevel._();
  static final AudioLevel instance = AudioLevel._();

  static const _channel = EventChannel('com.ryanheise.just_audio.rms');

  /// Display-ready loudness, 0..1.
  @override
  final ValueNotifier<double> level = ValueNotifier<double>(0);

  StreamSubscription<dynamic>? _sub;
  DateTime _lastAt = DateTime.fromMillisecondsSinceEpoch(0);

  // Delay buffer: holds (timestamp, rms) pairs when _delayMs > 0.
  // Incoming RMS is queued; values older than _delayMs are emitted.
  // This compensates for Bluetooth A2DP latency (typically 100–300 ms).
  int _delayMs = 0;
  final _buffer = <(DateTime, double)>[];

  /// Set how many milliseconds to delay the RMS signal before emitting it.
  /// 0 = no delay (default). Clears the buffer when changed.
  void setDelay(int ms) {
    _delayMs = ms;
    _buffer.clear();
  }

  /// Whether a fresh sample arrived recently (the tap is actively producing).
  @override
  bool get isLive =>
      DateTime.now().difference(_lastAt).inMilliseconds < 350;

  // ── Trace capture (debug builds only) ──────────────────────────────────────
  //
  // Used once, by hand, to bake the settings preview's speech trace. It records
  // what the tap *actually emits* — post-gain, post-clamp, at the native
  // cadence — so the preview can't drift from the real thing the way an
  // offline-computed envelope would.

  List<(DateTime, double)>? _capture;

  /// Whether a capture is currently running.
  bool get isCapturing => _capture != null;

  /// Records [duration] of emitted levels and returns a paste-ready Dart
  /// snippet for `lib/core/audio/speech_trace.dart`.
  ///
  /// Run it from Settings → Player animation (the button only exists in debug
  /// builds) with a book playing and the animation sync delay at 0, so no A2DP
  /// offset is baked in. Pick a passage with real dynamics — sentence, breath,
  /// sentence — and trim the ends into a pause so the loop seam doesn't show.
  Future<String> captureTrace(
      [Duration duration = const Duration(seconds: 6)]) async {
    if (!kDebugMode) return '// capture is debug-only';
    _capture = [];
    await Future<void>.delayed(duration);
    final samples = _capture ?? const <(DateTime, double)>[];
    _capture = null;
    if (samples.length < 2) {
      return '// no samples — is audio actually playing?';
    }
    // Mean gap between emissions: the native cadence, which the replay must
    // match. Documented as ~30 Hz but measure rather than trust the comment.
    final spanMs = samples.last.$1.difference(samples.first.$1).inMilliseconds;
    final intervalMs = (spanMs / (samples.length - 1)).round();
    final values =
        samples.map((s) => s.$2.toStringAsFixed(3)).join(', ');
    return 'const int kSpeechTraceIntervalMs = $intervalMs;\n'
        'const List<double> kSpeechTrace = <double>[$values];';
  }

  /// Begin listening. Idempotent; safe to call once at startup.
  void start() {
    _sub ??= _channel.receiveBroadcastStream().listen(
      (event) {
        // Accept only a sane, finite RMS. Garbage (NaN / ∞ / negative — e.g.
        // malformed PCM, or a Media3 processor reorder after a just_audio bump)
        // is ignored, so [isLive] lapses and the mark degrades to its synthetic
        // envelope instead of rendering silently-wrong levels. This guards the
        // "channel present but emitting nonsense" failure mode, not just the
        // "no fresh sample" one.
        if (event is num && event.isFinite && event >= 0) {
          _lastAt = DateTime.now();
          // Speech RMS sits low (~0.03–0.25); lift it into a lively bar range.
          final rms = (event.toDouble() * 3.2).clamp(0.0, 1.0);
          _capture?.add((_lastAt, rms));
          if (_delayMs == 0) {
            level.value = rms;
          } else {
            _buffer.add((_lastAt, rms));
            final cutoff =
                _lastAt.subtract(Duration(milliseconds: _delayMs));
            while (_buffer.isNotEmpty &&
                _buffer.first.$1.isBefore(cutoff)) {
              level.value = _buffer.removeAt(0).$2;
            }
          }
        }
      },
      // Stream error → stop updating; isLive lapses → synthetic fallback.
      onError: (_) {},
    );
  }
}
