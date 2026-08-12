import 'package:flutter/material.dart';

// ── Per-theme data ─────────────────────────────────────────────────────────────

// `onyx` must stay LAST-appended: the variant is persisted by index.
enum SagaThemeVariant { ink, cream, terra, onyx }

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
  // Dimmed accent for large filled areas (anything bigger than a pill/chip) —
  // full-brightness amber over big regions blooms on OLED black. Null means
  // "same as accent" (all non-Onyx themes).
  final Color? accentDim;
  // Accent for BODY-SIZED text (below 18px regular / 14px bold): the only
  // accent that clears WCAG AA 4.5:1 on both grounds. Null means "same as
  // accent" (Ink, Onyx). See brand/05-contrast/README.md for the ratios.
  final Color? accentText;
  final Color markSide;
  final Color markMiddle;
  final Color heatEmpty;
  final Color heat1;
  final Color heat2;
  final Color heat3;
  final Color heat4;
  final Color heatMax;

  // ── Cover reveal (player screen) ────────────────────────────────────────────
  // Tapping the cover defocuses it and surfaces the book's detail through it.
  // How far the theme background scrims the defocused artwork, and how much
  // saturation the artwork keeps. Light themes need a heavier scrim: pale cover
  // art over a pale background leaves text with nothing to sit on.
  final double coverRevealScrim;
  final double coverRevealSaturation;

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
    this.accentDim,
    this.accentText,
    required this.markSide,
    required this.markMiddle,
    required this.heatEmpty,
    required this.heat1,
    required this.heat2,
    required this.heat3,
    required this.heat4,
    required this.heatMax,
    this.coverRevealScrim = 0.55,
    this.coverRevealSaturation = 0.35,
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
    fgSubtle:   Color(0x84F4EAD8),  // 52%: 4.71 on surface (40% was 3.42)
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
    fgMuted:    Color(0xB31E1410),  // 70%: 6.00 on surface (60% was 4.34)
    fgSubtle:   Color(0xA01E1410),  // 63%: 4.75 on surface (40% was 2.47)
    border:     Color(0x1F1E1410),
    accent:     Color(0xFFC25A3A),
    accentFg:   Color(0xFFF4EAD8),
    // Terracotta is 3.65 on cream — fine as icon/fill (3:1), not as body text.
    accentText: Color(0xFF9E4128),  // 5.11 on surface
    markSide:   Color(0xFF1E1410),
    markMiddle: Color(0xFFC25A3A),
    heatEmpty:  Color(0xFFE8D8BD),
    heat1:      Color(0xFFE2C090),
    heat2:      Color(0xFFCF9A68),
    heat3:      Color(0xFFBC7448),
    heat4:      Color(0xFFB05530),
    heatMax:    Color(0xFFC25A3A),
    // Light theme: a pale cover behind pale text needs a much heavier scrim.
    coverRevealScrim: 0.74,
    coverRevealSaturation: 0.30,
  );

  // ── EMBER (deep terracotta bold) ──────────────────────────────────────────────
  // Display name "Ember"; the enum stays `terra` (persisted by index). The old
  // terracotta #C25A3A ground was a mid-tone no text color could clear AA on
  // (cream 3.65, ink 4.14), so the grounds darkened one step per the AA retune
  // (brand/05-contrast). #C25A3A survives as a non-text hero color only.
  static const terra = SagaThemeData(
    variant:    SagaThemeVariant.terra,
    isDark:     true,
    bg:         Color(0xFF8E3A22),  // cream fg: 6.34 (was #C25A3A @ 3.65)
    surface:    Color(0xFF7A301B),
    surfaceAlt: Color(0xFF6E2A17),
    fg:         Color(0xFFF4EAD8),
    fgMuted:    Color(0xD9F4EAD8),  // 85%: 5.07 on bg
    fgSubtle:   Color(0xCBF4EAD8),  // 80%: 4.63 on bg
    border:     Color(0x33F4EAD8),
    // Ink-as-accent retired with the darker grounds (2.39 on bg, under the
    // 3:1 non-text floor); amber takes over, as on Ink/Onyx.
    accent:     Color(0xFFE0A050),  // 3.35 bg / 4.11 surface — non-text + large
    accentFg:   Color(0xFF1E1410),
    accentText: Color(0xFFF0C48C),  // 4.67 on bg
    markSide:   Color(0xFFF4EAD8),
    markMiddle: Color(0xFFE0A050),  // ink spine fails 3:1 on the new ground
    heatEmpty:  Color(0xFF6E2A17),  // tracks surfaceAlt, as before
    heat1:      Color(0xFFA04530),
    heat2:      Color(0xFFB87060),
    heat3:      Color(0xFFCFA890),
    heat4:      Color(0xFFE0D0B8),
    heatMax:    Color(0xFFF4EAD8),
    // Deeper than the old terra but still warmer than Ink: keep the heavier
    // scrim so text over defocused cover art has enough behind it.
    coverRevealScrim: 0.68,
  );

  // ── ONYX (OLED true black, opt-in) ────────────────────────────────────────────
  // Per the design spec (July 2026): page is #000 (pixels off); surfaces step
  // to #0C0908 / #16100D and nothing sits below #0C0908 (panels crush
  // near-blacks). Ink drops from cream #F4EAD8 (17.8:1, blooms at night) to
  // #E4D9C6 (~15:1). No shadows — elevation comes from hairlines/borders (the
  // app's few BoxShadows are dark-on-dark here and vanish on their own);
  // border sits at 14% ink. Amber stays the brand accent for pill-sized
  // fills; [accentDim] for anything bigger. The heatmap floor is lifted above
  // surfaceAlt so empty cells don't vanish into the black page.
  static const onyx = SagaThemeData(
    variant:    SagaThemeVariant.onyx,
    isDark:     true,
    bg:         Color(0xFF000000),
    surface:    Color(0xFF0C0908),
    surfaceAlt: Color(0xFF16100D),
    fg:         Color(0xFFE4D9C6),
    fgMuted:    Color(0xA6E4D9C6),
    fgSubtle:   Color(0x8CE4D9C6),  // 55%: 4.73 on bg; #7D776D on black — no bloom
    border:     Color(0x24E4D9C6),
    accent:     Color(0xFFE0A050),
    accentFg:   Color(0xFF000000),
    accentDim:  Color(0xFFB77E3C),
    markSide:   Color(0xFFE4D9C6),
    markMiddle: Color(0xFFE0A050),
    heatEmpty:  Color(0xFF1E1712),
    heat1:      Color(0xFF4D3520),
    heat2:      Color(0xFF6E4E2A),
    heat3:      Color(0xFF946A38),
    heat4:      Color(0xFFBF8C4A),
    heatMax:    Color(0xFFE0A050),
  );

  static SagaThemeData fromVariant(SagaThemeVariant v) => switch (v) {
        SagaThemeVariant.ink   => ink,
        SagaThemeVariant.cream => cream,
        SagaThemeVariant.terra => terra,
        SagaThemeVariant.onyx  => onyx,
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

  /// Accent for LARGE filled areas (bigger than a pill/chip/mark). Identical
  /// to [accent] except on Onyx, where full amber over big regions blooms on
  /// OLED black. Use for any new full-width or panel-sized accent fill.
  static Color get accentDim  => _current.accentDim ?? _current.accent;

  /// Accent for BODY-SIZED text — the only accent permitted below 18px
  /// regular / 14px bold. [accent] stays for icons, fills and large/bold text
  /// (3:1 floor); this tier clears 4.5:1 on both grounds in every theme.
  static Color get accentText => _current.accentText ?? _current.accent;
  static double get coverRevealScrim      => _current.coverRevealScrim;
  static double get coverRevealSaturation => _current.coverRevealSaturation;
  static Color get markSide   => _current.markSide;
  static Color get markMiddle => _current.markMiddle;
  static Color get heatEmpty  => _current.heatEmpty;
  static Color get heat1      => _current.heat1;
  static Color get heat2      => _current.heat2;
  static Color get heat3      => _current.heat3;
  static Color get heat4      => _current.heat4;
  static Color get heatMax    => _current.heatMax;
}
