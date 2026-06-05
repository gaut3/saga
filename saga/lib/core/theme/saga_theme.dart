import 'package:flutter/material.dart';

// ── Per-theme data ─────────────────────────────────────────────────────────────

enum SagaThemeVariant { ink, cream, terra }

class SagaThemeData {
  final SagaThemeVariant variant;
  final bool isDark;
  final Color bg;
  final Color surface;
  final Color surfaceAlt;
  final Color fg;
  final Color fgMuted;
  final Color fgSubtle;
  final Color border;
  final Color accent;
  final Color accentFg;
  final Color markSide;
  final Color markMiddle;
  final Color heatEmpty;
  final Color heat1;
  final Color heat2;
  final Color heat3;
  final Color heat4;
  final Color heatMax;

  const SagaThemeData({
    required this.variant,
    required this.isDark,
    required this.bg,
    required this.surface,
    required this.surfaceAlt,
    required this.fg,
    required this.fgMuted,
    required this.fgSubtle,
    required this.border,
    required this.accent,
    required this.accentFg,
    required this.markSide,
    required this.markMiddle,
    required this.heatEmpty,
    required this.heat1,
    required this.heat2,
    required this.heat3,
    required this.heat4,
    required this.heatMax,
  });

  // ── INK (dark) ────────────────────────────────────────────────────────────────
  static const ink = SagaThemeData(
    variant:    SagaThemeVariant.ink,
    isDark:     true,
    bg:         Color(0xFF1E1410),
    surface:    Color(0xFF261B16),
    surfaceAlt: Color(0xFF2F221C),
    fg:         Color(0xFFF4EAD8),
    fgMuted:    Color(0xA6F4EAD8),
    fgSubtle:   Color(0x66F4EAD8),
    border:     Color(0x1FF4EAD8),
    accent:     Color(0xFFE0A050),
    accentFg:   Color(0xFF1E1410),
    markSide:   Color(0xFFF4EAD8),
    markMiddle: Color(0xFFE0A050),
    heatEmpty:  Color(0xFF2F221C),
    heat1:      Color(0xFF4D3520),
    heat2:      Color(0xFF6E4E2A),
    heat3:      Color(0xFF946A38),
    heat4:      Color(0xFFBF8C4A),
    heatMax:    Color(0xFFE0A050),
  );

  // ── CREAM (light) ─────────────────────────────────────────────────────────────
  static const cream = SagaThemeData(
    variant:    SagaThemeVariant.cream,
    isDark:     false,
    bg:         Color(0xFFF4EAD8),
    surface:    Color(0xFFEFE3CE),
    surfaceAlt: Color(0xFFE8D8BD),
    fg:         Color(0xFF1E1410),
    fgMuted:    Color(0x991E1410),
    fgSubtle:   Color(0x661E1410),
    border:     Color(0x1F1E1410),
    accent:     Color(0xFFC25A3A),
    accentFg:   Color(0xFFF4EAD8),
    markSide:   Color(0xFF1E1410),
    markMiddle: Color(0xFFC25A3A),
    heatEmpty:  Color(0xFFE8D8BD),
    heat1:      Color(0xFFE2C090),
    heat2:      Color(0xFFCF9A68),
    heat3:      Color(0xFFBC7448),
    heat4:      Color(0xFFB05530),
    heatMax:    Color(0xFFC25A3A),
  );

  // ── TERRA (terracotta bold) ────────────────────────────────────────────────────
  static const terra = SagaThemeData(
    variant:    SagaThemeVariant.terra,
    isDark:     true,
    bg:         Color(0xFFC25A3A),
    surface:    Color(0xFF9E4128),
    surfaceAlt: Color(0xFF8A3520),
    fg:         Color(0xFFF4EAD8),
    fgMuted:    Color(0xC7F4EAD8),
    fgSubtle:   Color(0x8CF4EAD8),
    border:     Color(0x33F4EAD8),
    accent:     Color(0xFF1E1410),
    accentFg:   Color(0xFFF4EAD8),
    markSide:   Color(0xFFF4EAD8),
    markMiddle: Color(0xFF1E1410),
    heatEmpty:  Color(0xFF8A3520),
    heat1:      Color(0xFFA04530),
    heat2:      Color(0xFFB87060),
    heat3:      Color(0xFFCFA890),
    heat4:      Color(0xFFE0D0B8),
    heatMax:    Color(0xFFF4EAD8),
  );

  static SagaThemeData fromVariant(SagaThemeVariant v) => switch (v) {
        SagaThemeVariant.ink   => ink,
        SagaThemeVariant.cream => cream,
        SagaThemeVariant.terra => terra,
      };
}

// ── Backwards-compat static accessor ──────────────────────────────────────────
// All existing SagaColors.xxx calls continue to work.
// App.build() calls SagaColors.apply() when the theme changes.

abstract final class SagaColors {
  static SagaThemeData _current = SagaThemeData.ink;

  static void apply(SagaThemeData data) {
    _current = data;
  }

  // ── Raw palette (always const) ───────────────────────────────────────────────
  static const cream       = Color(0xFFF4EAD8);
  static const paper       = Color(0xFFEFE3CE);
  static const linen       = Color(0xFFE8D8BD);
  static const ink         = Color(0xFF1E1410);
  static const inkSoft     = Color(0xFF3A2A20);
  static const terracotta  = Color(0xFFC25A3A);
  static const terraDeep   = Color(0xFF9E4128);
  static const amber       = Color(0xFFE0A050);
  static const amberSoft   = Color(0xFFEAB877);
  static const rose        = Color(0xFFA85C4A);

  // ── Semantic (theme-aware) getters ───────────────────────────────────────────
  static Color get bg         => _current.bg;
  static Color get surface    => _current.surface;
  static Color get surfaceAlt => _current.surfaceAlt;
  static Color get fg         => _current.fg;
  static Color get fgMuted    => _current.fgMuted;
  static Color get fgSubtle   => _current.fgSubtle;
  static Color get border     => _current.border;
  static Color get accent     => _current.accent;
  static Color get accentFg   => _current.accentFg;
  static Color get markSide   => _current.markSide;
  static Color get markMiddle => _current.markMiddle;
  static Color get heatEmpty  => _current.heatEmpty;
  static Color get heat1      => _current.heat1;
  static Color get heat2      => _current.heat2;
  static Color get heat3      => _current.heat3;
  static Color get heat4      => _current.heat4;
  static Color get heatMax    => _current.heatMax;
}
