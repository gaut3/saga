import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:saga/features/player/player_service.dart';

void main() {
  // audio_service stops its service when the published state moves to idle,
  // and just_audio reports idle at the start of every source swap (#32).
  test('idle during a load is published as loading', () {
    expect(
      AudioPlayerService.publishedProcessingState(ProcessingState.idle,
          loading: true),
      AudioProcessingState.loading,
    );
  });

  test('idle with no load running stays idle', () {
    expect(
      AudioPlayerService.publishedProcessingState(ProcessingState.idle,
          loading: false),
      AudioProcessingState.idle,
    );
  });

  test('every other state passes through, loading or not', () {
    for (final loading in [true, false]) {
      expect(
          AudioPlayerService.publishedProcessingState(ProcessingState.ready,
              loading: loading),
          AudioProcessingState.ready);
      expect(
          AudioPlayerService.publishedProcessingState(
              ProcessingState.completed,
              loading: loading),
          AudioProcessingState.completed);
    }
  });
}
