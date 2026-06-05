import 'package:flutter/material.dart';
import '../../core/theme/saga_theme.dart';

/// Themed modal bottom sheet.
///
/// Presented on the *tab* navigator (not the root) so the nav bar + mini player
/// paint on top of the sheet — the card visually sits "behind" them. Each call
/// site is responsible for padding its own content past the bottom chrome using
/// the calling context's `MediaQuery.padding.bottom`, which (thanks to the
/// shell's `extendBody: true`) already encodes the system inset + nav pill +
/// mini player (the latter only when a book is loaded). That keeps the card
/// behind the bar while its content stays above it.
Future<T?> showSagaSheet<T>(BuildContext context, WidgetBuilder builder,
        {bool scrollable = true}) =>
    showModalBottomSheet<T>(
      context: context,
      isScrollControlled: scrollable,
      backgroundColor: SagaColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: builder,
    );
