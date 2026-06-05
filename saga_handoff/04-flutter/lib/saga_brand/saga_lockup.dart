// saga_lockup.dart
// Mark + wordmark, horizontal, baseline-aligned.

import 'package:flutter/material.dart';
import 'animated_saga_mark.dart';
import 'saga_colors.dart';
import 'saga_mark.dart';
import 'saga_wordmark.dart';

class SagaLockup extends StatelessWidget {
  /// Wordmark font-size in logical px. The mark sizes itself relative
  /// to this (1.15×) to match the brand spec.
  final double size;

  final SagaTheme theme;

  /// Optional: animate the mark.
  final SagaMarkState? markState;

  const SagaLockup({
    super.key,
    this.size = 40,
    this.theme = SagaTheme.cream,
    this.markState,
  });

  @override
  Widget build(BuildContext context) {
    final markSize = size * 1.15;
    final gap = size * 0.3;

    final mark = markState == null
        ? SagaMark(size: markSize, theme: theme, semanticLabel: null)
        : AnimatedSagaMark(size: markSize, theme: theme, state: markState!, semanticLabel: null);

    return Semantics(
      label: 'Saga',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          mark,
          SizedBox(width: gap),
          SagaWordmark(size: size, theme: theme),
        ],
      ),
    );
  }
}
