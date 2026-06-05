import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Real-time output loudness tapped from the audio pipeline by the vendored
/// just_audio patch (a Media3 `TeeAudioProcessor` — no `RECORD_AUDIO`).
///
/// The native side emits a raw RMS (~30 Hz, only while audio plays). We apply a
/// little gain so [level] is a display-ready 0..1 value. The animated mark uses
/// it to drive the "playing" bars and falls back to its synthetic envelope
/// whenever the tap isn't [isLive] (paused, between tracks, non-PCM output…).
class AudioLevel {
  AudioLevel._();
  static final AudioLevel instance = AudioLevel._();

  static const _channel = EventChannel('com.ryanheise.just_audio.rms');

  /// Display-ready loudness, 0..1.
  final ValueNotifier<double> level = ValueNotifier<double>(0);

  StreamSubscription<dynamic>? _sub;
  DateTime _lastAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// Whether a fresh sample arrived recently (the tap is actively producing).
  bool get isLive =>
      DateTime.now().difference(_lastAt).inMilliseconds < 350;

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
          level.value = (event.toDouble() * 3.2).clamp(0.0, 1.0);
        }
      },
      // Stream error → stop updating; isLive lapses → synthetic fallback.
      onError: (_) {},
    );
  }
}
