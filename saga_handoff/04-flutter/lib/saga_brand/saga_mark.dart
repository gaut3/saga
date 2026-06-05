// saga_mark.dart
// The Saga logo mark — three stacked book-spine rectangles drawn
// with CustomPaint. Use this when the mark is static. For the
// playing/breathing/loading states, use AnimatedSagaMark instead.

import 'package:flutter/material.dart';
import 'saga_colors.dart';

class SagaMark extends StatelessWidget {
  /// Pixel size of the square mark.
  final double size;

  /// Theme controls which spine colors are used. Pick the theme
  /// that matches the surrounding surface, NOT the user's preference.
  final SagaTheme theme;

  /// When true, draw without the title-line ornaments — use at ≤ 32px.
  final bool flat;

  /// Semantic label for screen readers. Pass null for decorative use.
  final String? semanticLabel;

  const SagaMark({
    super.key,
    this.size = 40,
    this.theme = SagaTheme.cream,
    this.flat = false,
    this.semanticLabel = 'Saga',
  });

  @override
  Widget build(BuildContext context) {
    final paint = CustomPaint(
      size: Size(size, size),
      painter: SagaMarkPainter(
        theme: theme,
        flat: flat,
        leftScale: 1.0,
        midScale: 1.0,
        rightScale: 1.0,
        leftOpacity: 1.0,
        midOpacity: 1.0,
        rightOpacity: 1.0,
      ),
    );
    if (semanticLabel == null) return paint;
    return Semantics(
      image: true,
      label: semanticLabel,
      child: paint,
    );
  }
}

/// Painter shared by [SagaMark] and [AnimatedSagaMark]. Animated calls
/// vary the per-spine scale/opacity each frame; static calls leave them
/// at 1.0 for an exact match with the brand reference.
class SagaMarkPainter extends CustomPainter {
  final SagaTheme theme;
  final bool flat;
  final double leftScale;
  final double midScale;
  final double rightScale;
  final double leftOpacity;
  final double midOpacity;
  final double rightOpacity;

  SagaMarkPainter({
    required this.theme,
    required this.flat,
    required this.leftScale,
    required this.midScale,
    required this.rightScale,
    required this.leftOpacity,
    required this.midOpacity,
    required this.rightOpacity,
  });

  // Geometry is defined on a 200u canvas (matches the SVG source);
  // we scale to whatever Flutter gives us.
  static const _canvasUnits = 200.0;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / _canvasUnits;

    void spine({
      required double x,
      required double y,
      required double w,
      required double h,
      required Color color,
      required double scale,
      required double opacity,
    }) {
      // Anchor bottom: scale from the spine's bottom edge so the bar
      // looks like it's pinned to a baseline.
      final scaledH = h * scale;
      final top = y + (h - scaledH);
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x * s, top * s, w * s, scaledH * s),
        Radius.circular(4 * s),
      );
      canvas.drawRRect(rect, Paint()..color = color.withOpacity(opacity));
    }

    void ornament(double x, double y, double w, Color color, double opacity) {
      canvas.drawRect(
        Rect.fromLTWH(x * s, y * s, w * s, 2 * s),
        Paint()..color = color.withOpacity(opacity),
      );
    }

    // Three spines
    spine(x: 30,  y: 56, w: 32, h: 100, color: theme.markSide,   scale: leftScale,  opacity: leftOpacity);
    spine(x: 74,  y: 36, w: 32, h: 140, color: theme.markMiddle, scale: midScale,   opacity: midOpacity);
    spine(x: 118, y: 68, w: 32, h: 80,  color: theme.markSide,   scale: rightScale, opacity: rightOpacity);

    if (!flat) {
      // Side spine title lines
      ornament(38,  74, 16, theme.markSideDot, 0.7);
      ornament(38,  82, 10, theme.markSideDot, 0.7);
      ornament(126, 84, 16, theme.markSideDot, 0.7);
      ornament(126, 92, 10, theme.markSideDot, 0.7);
      // Middle spine title lines
      ornament(82, 58, 16, theme.markMidDot, 0.5);
      ornament(82, 66, 10, theme.markMidDot, 0.5);
    }
  }

  @override
  bool shouldRepaint(SagaMarkPainter old) {
    return old.theme != theme ||
        old.flat != flat ||
        old.leftScale != leftScale ||
        old.midScale != midScale ||
        old.rightScale != rightScale ||
        old.leftOpacity != leftOpacity ||
        old.midOpacity != midOpacity ||
        old.rightOpacity != rightOpacity;
  }
}
