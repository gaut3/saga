import 'package:flutter/widgets.dart';

/// Whether [text] would need more than [maxLines] at [maxWidth].
///
/// One shared helper because two places need the same answer — the book
/// detail summary (whether to offer "Show more") and the player's flipped
/// cover (whether to fade the blurb out). They must agree.
///
/// [maxWidth] must be the *real* width, so call this from a `LayoutBuilder`.
/// Measuring against an assumed width is how the always-on "Show more" bug
/// happened in the first place.
bool textOverflows({
  required String text,
  required TextStyle style,
  required double maxWidth,
  required int maxLines,
  TextScaler textScaler = TextScaler.noScaling,
  TextDirection textDirection = TextDirection.ltr,
}) {
  if (!maxWidth.isFinite || maxWidth <= 0) return false;
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    maxLines: maxLines,
    textScaler: textScaler,
    textDirection: textDirection,
  )..layout(maxWidth: maxWidth);
  final result = painter.didExceedMaxLines;
  painter.dispose();
  return result;
}
