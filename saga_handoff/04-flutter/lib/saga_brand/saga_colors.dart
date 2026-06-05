// saga_colors.dart
// Saga brand color tokens for Flutter.
//
// Three themes are supported. Pick the one that matches the
// surrounding surface (not the user's overall theme preference).

import 'package:flutter/material.dart';

class SagaColors {
  // ── Raw palette ────────────────────────────────────────────
  static const cream      = Color(0xFFF4EAD8);
  static const paper      = Color(0xFFEFE3CE);
  static const linen      = Color(0xFFE8D8BD);
  static const ink        = Color(0xFF1E1410);
  static const inkSoft    = Color(0xFF3A2A20);
  static const terracotta = Color(0xFFC25A3A);
  static const terraDeep  = Color(0xFF9E4128);
  static const amber      = Color(0xFFE0A050);
  static const amberSoft  = Color(0xFFEAB877);
  static const rose       = Color(0xFFA85C4A);
}

/// A semantic palette set — picks the right pair of mark spine colors
/// (and a few foreground hints) for each background context.
class SagaTheme {
  final Color background;
  final Color foreground;
  final Color foregroundMuted;
  final Color accent;
  final Color markSide;
  final Color markMiddle;
  final Color markSideDot;
  final Color markMidDot;

  const SagaTheme({
    required this.background,
    required this.foreground,
    required this.foregroundMuted,
    required this.accent,
    required this.markSide,
    required this.markMiddle,
    required this.markSideDot,
    required this.markMidDot,
  });

  /// Use on cream / paper / light surfaces.
  static const cream = SagaTheme(
    background: SagaColors.cream,
    foreground: SagaColors.ink,
    foregroundMuted: Color(0x991E1410), // ink @ 60%
    accent: SagaColors.terracotta,
    markSide: SagaColors.ink,
    markMiddle: SagaColors.terracotta,
    markSideDot: SagaColors.terracotta,
    markMidDot: SagaColors.cream,
  );

  /// Use on ink / dark surfaces. Dark-mode default.
  static const ink = SagaTheme(
    background: SagaColors.ink,
    foreground: SagaColors.cream,
    foregroundMuted: Color(0xA6F4EAD8), // cream @ 65%
    accent: SagaColors.amber,
    markSide: SagaColors.cream,
    markMiddle: SagaColors.amber,
    markSideDot: SagaColors.amber,
    markMidDot: SagaColors.ink,
  );

  /// Use on terracotta surfaces.
  static const terra = SagaTheme(
    background: SagaColors.terracotta,
    foreground: SagaColors.cream,
    foregroundMuted: Color(0xC7F4EAD8), // cream @ 78%
    accent: SagaColors.ink,
    markSide: SagaColors.cream,
    markMiddle: SagaColors.ink,
    markSideDot: SagaColors.ink,
    markMidDot: SagaColors.cream,
  );
}
