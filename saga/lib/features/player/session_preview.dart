import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../../core/diagnostics/app_log.dart';
import '../../core/plex/models/plex_track.dart';
import 'player_service.dart';
import 'session_place.dart';
import 'track_audio_source.dart';

/// Plays a short clip around a session's position so the listener can find
/// their place *before* committing to it (GitHub #16 — "I fell asleep, where
/// was I?").
///
/// The one rule: **a preview never touches the main player's records.** It
/// runs on its own throwaway [AudioPlayer], so nothing it does can reach the
/// saved position, the playback log, listening history or the media session —
/// those are all wired to the main player only. `session_preview_test.dart`
/// pins that against this file's source. The single interaction is pausing
/// the main player first (an ordinary [AudioPlayerService.pause], which
/// saves), so two books never play at once; and a main-player play stops the
/// preview, for the same reason.
///
/// The preview player takes no audio focus and handles no interruptions:
/// the main player already holds focus, and a second request from the same
/// app must not register as an interruption of the first.
class SessionPreview {
  SessionPreview._();
  static final instance = SessionPreview._();

  /// Id of the row currently previewing, or null. Rows watch this to animate
  /// their mark, and so that starting one preview visibly stops another.
  final ValueNotifier<String?> active = ValueNotifier(null);

  AudioPlayer? _player;
  final _subs = <StreamSubscription<Object?>>[];
  // Bumped by every start and stop: a slow load that finishes after the user
  // tapped elsewhere must not start playing.
  int _generation = 0;

  /// Starts a preview of [positionMs] in [track] for row [id], or stops it if
  /// [id] is already previewing. False when the clip couldn't load.
  Future<bool> toggle({
    required String id,
    required PlexTrack track,
    required int positionMs,
    required AudioPlayerService main,
  }) async {
    if (active.value == id) {
      await stop();
      return true;
    }
    await stop();
    final generation = ++_generation;
    active.value = id;
    try {
      if (main.playbackState.value.playing) await main.pause();
      final window = previewWindow(positionMs, track.durationMs);
      final player = _player = AudioPlayer(
        useProxyForRequestHeaders: false,
        handleInterruptions: false,
        handleAudioSessionActivation: false,
      );
      await player.setAudioSource(ClippingAudioSource(
        child: audioSourceForTrack(track),
        start: window.start,
        end: window.end,
      ));
      if (generation != _generation) return true;
      _subs
        ..add(player.processingStateStream.listen((s) {
          if (s == ProcessingState.completed) stop();
        }))
        // skip(1): playbackState replays its current value on listen.
        ..add(main.playbackState.skip(1).listen((s) {
          if (s.playing) stop();
        }));
      // play() completes when playback ends, not when it starts.
      unawaited(player.play());
      return true;
    } catch (e) {
      AppLog.log('playback', 'session preview failed: $e');
      if (generation == _generation) await stop();
      return false;
    }
  }

  /// Stops any preview and releases its player. Safe to call when idle.
  Future<void> stop() async {
    _generation++;
    active.value = null;
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    final player = _player;
    _player = null;
    await player?.dispose();
  }
}
