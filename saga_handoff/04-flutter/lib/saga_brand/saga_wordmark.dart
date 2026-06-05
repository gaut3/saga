// saga_wordmark.dart
// The Saga wordmark: "saga" in Manrope 800, lowercase, tight tracking,
// followed by a play-triangle in the accent color.
//
// Requires Manrope 800 to be available. Either:
//   1. Use the google_fonts package: GoogleFonts.manrope(weight: FontWeight.w800)
//   2. Bundle Manrope-ExtraBold.ttf in pubspec.yaml under `fonts:`
//
// The default constructor assumes Manrope is registered as a font family
// in your pubspec. Use SagaWordmark.googleFonts() if you'd rather pull
// it from the google_fonts package.

import 'package:flutter/material.dart';
import 'saga_colors.dart';

class SagaWordmark extends StatelessWidget {
  /// Font-size for the wordmark, in logical px.
  final double size;
  final SagaTheme theme;
  final TextStyle? textStyle;

  const SagaWordmark({
    super.key,
    this.size = 40,
    this.theme = SagaTheme.cream,
    this.textStyle,
  });

  @override
  Widget build(BuildContext context) {
    final triSize = size * 0.42;
    final gap = size * 0.14;

    final style = (textStyle ?? const TextStyle(fontFamily: 'Manrope')).copyWith(
      fontWeight: FontWeight.w800,
      fontSize: size,
      letterSpacing: size * -0.055,
      color: theme.foreground,
      height: 1.0,
    );

    return Semantics(
      label: 'Saga',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text('saga', style: style),
          SizedBox(width: gap),
          SizedBox(
            width: triSize,
            height: triSize,
            child: CustomPaint(painter: _PlayTrianglePainter(color: theme.accent)),
          ),
        ],
      ),
    );
  }
}

class _PlayTrianglePainter extends CustomPainter {
  final Color color;
  _PlayTrianglePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    // Triangle in a 40u box: M8 4 L34 20 L8 36 Z
    final s = size.width / 40.0;
    final path = Path()
      ..moveTo(8 * s, 4 * s)
      ..lineTo(34 * s, 20 * s)
      ..lineTo(8 * s, 36 * s)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_PlayTrianglePainter old) => old.color != color;
}
