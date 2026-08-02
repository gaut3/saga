import 'dart:async';

import 'package:flutter/foundation.dart';

import 'audio_level.dart';
import 'speech_trace.dart';

/// Replays a recorded loudness trace so the Reactive mark motion can be
/// previewed with nothing playing.
///
/// Prefers the real tap: whenever [AudioLevel.instance] is live (a book is
/// playing while Settings is open) this passes its values straight through, so
/// the preview shows actual audio rather than a recording of some other book.
///
/// Falls back to [kSpeechTrace] when the tap is idle. If that trace hasn't been
/// captured yet the source reports `isLive: false`, and the mark degrades to
/// its synthetic envelope exactly as it does for silent playback — no invented
/// motion.
class CannedAudioLevel implements AudioLevelSource {
  CannedAudioLevel({List<double>? trace, int? intervalMs})
      : _trace = trace ?? kSpeechTrace,
        _intervalMs = intervalMs ?? kSpeechTraceIntervalMs;

  final List<double> _trace;
  final int _intervalMs;

  final ValueNotifier<double> _level = ValueNotifier<double>(0);
  Timer? _timer;
  int _i = 0;

  @override
  ValueListenable<double> get level =>
      AudioLevel.instance.isLive ? AudioLevel.instance.level : _level;

  @override
  bool get isLive => AudioLevel.instance.isLive || _trace.isNotEmpty;

  /// Starts replaying. Idempotent.
  void start() {
    if (_timer != null || _trace.isEmpty) return;
    _timer = Timer.periodic(Duration(milliseconds: _intervalMs), (_) {
      _level.value = _trace[_i];
      _i = (_i + 1) % _trace.length;
    });
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
    _level.dispose();
  }
}
