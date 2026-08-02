import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saga/core/utils/text_measure.dart';

/// The book detail summary used to offer "Show more" even when the whole
/// summary already fitted, because nothing measured it. Both callers (that
/// toggle and the flipped cover's fade mask) now go through this.
void main() {
  const style = TextStyle(fontSize: 14, height: 1.5);

  group('textOverflows', () {
    test('short text within maxLines does not overflow', () {
      expect(
        textOverflows(
          text: 'A short blurb.',
          style: style,
          maxWidth: 320,
          maxLines: 3,
        ),
        isFalse,
      );
    });

    test('long text beyond maxLines overflows', () {
      expect(
        textOverflows(
          text: 'A very long blurb. ' * 60,
          style: style,
          maxWidth: 320,
          maxLines: 3,
        ),
        isTrue,
      );
    });

    test('the same text can fit wide and overflow narrow', () {
      const text =
          'Rand al\'Thor rides out of the Two Rivers with the Dragon Reborn '
          'at his back and the Dark One stirring in Shayol Ghul.';
      expect(
        textOverflows(
            text: text, style: style, maxWidth: 1200, maxLines: 2),
        isFalse,
      );
      expect(
        textOverflows(text: text, style: style, maxWidth: 120, maxLines: 2),
        isTrue,
      );
    });

    test('text scaling can push fitting text into overflow', () {
      // Sized for the test font, whose glyphs are a fixed em square: 20 chars
      // at 14 px is one line in 300, but ~3 at 2.5× scale.
      const text = 'A short description.';
      final unscaled = textOverflows(
        text: text,
        style: style,
        maxWidth: 300,
        maxLines: 2,
      );
      final scaled = textOverflows(
        text: text,
        style: style,
        maxWidth: 300,
        maxLines: 2,
        textScaler: const TextScaler.linear(2.5),
      );
      expect(unscaled, isFalse);
      expect(scaled, isTrue);
    });

    test('empty text never overflows', () {
      expect(
        textOverflows(text: '', style: style, maxWidth: 320, maxLines: 1),
        isFalse,
      );
    });

    test('an unusable width reports no overflow rather than throwing', () {
      // LayoutBuilder can hand out an infinite or zero width mid-layout; the
      // caller must not blow up or flash a toggle it can't justify.
      expect(
        textOverflows(
            text: 'anything', style: style, maxWidth: double.infinity,
            maxLines: 2),
        isFalse,
      );
      expect(
        textOverflows(text: 'anything', style: style, maxWidth: 0, maxLines: 2),
        isFalse,
      );
    });
  });
}
