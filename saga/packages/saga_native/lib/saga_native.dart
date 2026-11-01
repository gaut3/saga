import 'package:flutter/services.dart';

/// The home-screen widget's native side.
///
/// A local plugin rather than a channel on `MainActivity`, because the widget
/// is updated from engines that have no activity: the one audio_service starts
/// when the widget's play cold-starts the app.
class SagaWidgetBridge {
  SagaWidgetBridge._();

  static const _channel = MethodChannel('com.gaut3.saga/widget');

  /// Replaces what the widget shows and redraws it.
  ///
  /// [snapshot] is display-only: strings and paths, already formatted, so the
  /// native side draws without knowing any rules. [playing] is held in memory
  /// only, never stored, so a dead process always draws paused.
  static Future<void> update(Map<String, Object?> snapshot,
          {required bool playing}) =>
      _channel.invokeMethod('update', {'snapshot': snapshot, 'playing': playing});
}
