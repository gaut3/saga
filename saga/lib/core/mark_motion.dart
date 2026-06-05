import 'package:flutter/foundation.dart';

import 'storage/settings_store.dart';

/// What the now-playing mark does in the `playing` state. The triangle⇄glyph
/// morph (the play/pause affordance) is identical for all three; only the
/// playing end-state differs.
enum MarkMotion {
  /// Four spines tracking the real audio loudness (the visualizer). Default.
  reactive,

  /// Four spines with gentle synthetic motion — no audio tap.
  gentle,

  /// The four spines fold into a static two-bar pause glyph.
  pause,
}

/// Backed by [SettingsStore]; the notifier lets already-built marks switch the
/// instant the setting changes (no need to thread it through every call site).
final ValueNotifier<MarkMotion> markMotionListenable =
    ValueNotifier<MarkMotion>(MarkMotion.reactive);

/// Load the persisted choice into the notifier. Call once after SettingsStore.init.
void initMarkMotion() {
  final i = SettingsStore.markMotionIndex;
  if (i >= 0 && i < MarkMotion.values.length) {
    markMotionListenable.value = MarkMotion.values[i];
  }
}

Future<void> setMarkMotion(MarkMotion m) async {
  markMotionListenable.value = m;
  await SettingsStore.setMarkMotionIndex(m.index);
}
