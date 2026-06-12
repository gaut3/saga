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
///
/// A drag handle is added automatically. Pass `showHandle: false` only for
/// sheets that manage their own scroll geometry (`DraggableScrollableSheet`)
/// and render the handle inside their scrollable column instead.
Future<T?> showSagaSheet<T>(BuildContext context, WidgetBuilder builder,
        {bool scrollable = true, bool showHandle = true}) =>
    showModalBottomSheet<T>(
      context: context,
      isScrollControlled: scrollable,
      backgroundColor: SagaColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: !showHandle
          ? builder
          : (ctx) => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SagaSheetHandle(),
                  Flexible(child: builder(ctx)),
                ],
              ),
    );

/// The standard 40×4 drag pill shown at the top of every sheet.
class SagaSheetHandle extends StatelessWidget {
  const SagaSheetHandle({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      child: Center(
        child: Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: SagaColors.fgSubtle,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );
  }
}

/// The standard sheet header: 18 pt bold foreground text. One widget so the
/// title can't drift between sheets (it was split 16/18 across the app).
class SagaSheetTitle extends StatelessWidget {
  final String text;
  final EdgeInsetsGeometry padding;

  const SagaSheetTitle(
    this.text, {
    super.key,
    this.padding = const EdgeInsets.fromLTRB(16, 4, 16, 12),
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(text,
            style: TextStyle(
                color: SagaColors.fg,
                fontSize: 18,
                fontWeight: FontWeight.bold)),
      ),
    );
  }
}
