import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saga/core/theme/saga_theme.dart';

/// Pins the WCAG 2.1 AA retune (brand/05-contrast) against the live theme
/// data, so a token can't quietly drift back under the floor it was raised to.
///
/// The rule set, from the retune package:
/// - fg, fgMuted, fgSubtle and accentText carry body-sized text and must
///   clear 4.5:1 on BOTH grounds (bg and surface) in every theme.
/// - accent is icons, fills and large/bold text only: 3:1 on both grounds.
/// - The mark is the transport control (non-text): both spine colors clear
///   3:1 against bg.
///
/// Ratios are computed the same way the audit computed them: the token's
/// alpha composited onto the ground first, then contrasted.
void main() {
  double chan(int c) {
    final s = c / 255.0;
    return s <= 0.03928 ? s / 12.92 : pow((s + 0.055) / 1.055, 2.4).toDouble();
  }

  double lum(Color c) {
    final v = c.toARGB32();
    return 0.2126 * chan((v >> 16) & 0xFF) +
        0.7152 * chan((v >> 8) & 0xFF) +
        0.0722 * chan(v & 0xFF);
  }

  Color composite(Color fg, Color bg) => Color.alphaBlend(fg, bg);

  double ratio(Color fg, Color bg) {
    final l1 = lum(composite(fg, bg));
    final l2 = lum(bg);
    return (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05);
  }

  final themes = {
    'ink': SagaThemeData.ink,
    'cream': SagaThemeData.cream,
    'ember': SagaThemeData.terra,
    'onyx': SagaThemeData.onyx,
  };

  for (final entry in themes.entries) {
    final name = entry.key;
    final t = entry.value;
    final grounds = {'bg': t.bg, 'surface': t.surface};

    group(name, () {
      for (final g in grounds.entries) {
        test('body text tiers clear AA (4.5:1) on ${g.key}', () {
          expect(ratio(t.fg, g.value), greaterThanOrEqualTo(4.5),
              reason: 'fg on ${g.key}');
          expect(ratio(t.fgMuted, g.value), greaterThanOrEqualTo(4.5),
              reason: 'fgMuted on ${g.key}');
          expect(ratio(t.fgSubtle, g.value), greaterThanOrEqualTo(4.5),
              reason: 'fgSubtle on ${g.key}');
          expect(ratio(t.accentText ?? t.accent, g.value),
              greaterThanOrEqualTo(4.5),
              reason: 'accentText on ${g.key}');
        });

        test('accent clears the non-text floor (3:1) on ${g.key}', () {
          expect(ratio(t.accent, g.value), greaterThanOrEqualTo(3.0),
              reason: 'accent on ${g.key}');
        });
      }

      test('mark spines clear 3:1 against bg', () {
        expect(ratio(t.markSide, t.bg), greaterThanOrEqualTo(3.0),
            reason: 'markSide on bg');
        expect(ratio(t.markMiddle, t.bg), greaterThanOrEqualTo(3.0),
            reason: 'markMiddle on bg');
      });
    });
  }

  test('the retired ember ink-spine really does fail — the guard is real', () {
    // The reason markMiddle moved to amber: ink on the ember ground is 2.39.
    // If this ever passes, the grounds changed and the spine choice should be
    // revisited rather than inherited.
    expect(ratio(const Color(0xFF1E1410), SagaThemeData.terra.bg), lessThan(3.0));
  });
}
