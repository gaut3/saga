@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saga/core/mark_motion.dart';
import 'package:saga/shared/widgets/saga_mark.dart';

/// Pixel regression net for the mark painter.
///
/// The mark *is* the play/pause control and the now-playing indicator, so a
/// silent geometry regression is expensive. These goldens pin the painter's
/// output for every shape it can draw; they're the safety net for edits to
/// `saga_mark.dart` (the reactive/gentle envelopes feed the *same* painter, so
/// covering the deterministic states covers the geometry completely).
///
/// Only deterministic states are pinned. The gentle envelope is driven by an
/// unseeded `math.Random`, so it is deliberately absent — pinning it would
/// flake.
///
/// Regenerate after an *intended* visual change:
///   flutter test --update-goldens test/saga_mark_golden_test.dart
void main() {
  // A frame at a time, so the phase-accumulating states land on an exact,
  // repeatable phase rather than wherever wall-clock left them.
  Future<void> pumpFrames(WidgetTester tester, int frames) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  Future<void> pumpMark(
    WidgetTester tester,
    Widget mark, {
    bool disableAnimations = false,
  }) async {
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(disableAnimations: disableAnimations),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: RepaintBoundary(child: mark),
          ),
        ),
      ),
    );
  }

  Future<void> expectMark(WidgetTester tester, String name) async {
    await expectLater(
      find.byType(AnimatedSagaMark),
      matchesGoldenFile('goldens/$name.png'),
    );
  }

  // The morph settles over 470 ms; 40 frames clears it with room to spare.
  const settled = 40;

  tearDown(() => markMotionListenable.value = MarkMotion.reactive);

  testWidgets('paused — solid play triangle', (tester) async {
    await pumpMark(
        tester, const AnimatedSagaMark(size: 200, state: SagaMarkState.paused));
    await pumpFrames(tester, settled);
    await expectMark(tester, 'mark_paused');
  });

  testWidgets('buffering — staggered sweep', (tester) async {
    await pumpMark(tester,
        const AnimatedSagaMark(size: 200, state: SagaMarkState.buffering));
    await pumpFrames(tester, settled);
    await expectMark(tester, 'mark_buffering');
  });

  testWidgets('breathing — idle swell', (tester) async {
    await pumpMark(tester,
        const AnimatedSagaMark(size: 200, state: SagaMarkState.breathing));
    await pumpFrames(tester, settled);
    await expectMark(tester, 'mark_breathing');
  });

  testWidgets('finished — bloom', (tester) async {
    await pumpMark(tester,
        const AnimatedSagaMark(size: 200, state: SagaMarkState.finished));
    await pumpFrames(tester, settled);
    await expectMark(tester, 'mark_finished');
  });

  testWidgets('downloading — bottom-anchored fill at 50%', (tester) async {
    await pumpMark(
      tester,
      const AnimatedSagaMark(
          size: 200, state: SagaMarkState.downloading, progress: 0.5),
    );
    await pumpFrames(tester, settled);
    await expectMark(tester, 'mark_downloading_50');
  });

  testWidgets('playing + pause-bars motion — static two-bar glyph',
      (tester) async {
    markMotionListenable.value = MarkMotion.pause;
    await pumpMark(tester,
        const AnimatedSagaMark(size: 200, state: SagaMarkState.playing));
    await pumpFrames(tester, settled);
    await expectMark(tester, 'mark_playing_pausebars');
  });

  testWidgets('playPauseControl — open glyph is always the two bars',
      (tester) async {
    // Pause-bars glyph must not depend on the motion mode here.
    markMotionListenable.value = MarkMotion.gentle;
    await pumpMark(
      tester,
      const AnimatedSagaMark(
          size: 200, state: SagaMarkState.playing, playPauseControl: true),
    );
    await pumpFrames(tester, settled);
    await expectMark(tester, 'mark_playpause_control');
  });

  testWidgets('playPauseControl + paused — triangle', (tester) async {
    await pumpMark(
      tester,
      const AnimatedSagaMark(
          size: 200, state: SagaMarkState.paused, playPauseControl: true),
    );
    await pumpFrames(tester, settled);
    await expectMark(tester, 'mark_playpause_control_paused');
  });

  testWidgets('reduced motion — static logo pose, full opacity', (tester) async {
    await pumpMark(
      tester,
      const AnimatedSagaMark(size: 200, state: SagaMarkState.playing),
      disableAnimations: true,
    );
    await pumpFrames(tester, settled);
    await expectMark(tester, 'mark_reduced_motion');
  });

  testWidgets('monoColor — single-colour mark', (tester) async {
    await pumpMark(
      tester,
      const AnimatedSagaMark(
        size: 200,
        state: SagaMarkState.breathing,
        monoColor: Color(0xFFFFFFFF),
      ),
      disableAnimations: true,
    );
    await pumpFrames(tester, settled);
    await expectMark(tester, 'mark_mono');
  });
}
