import 'package:flutter/material.dart';

import '../../core/theme/saga_theme.dart';

/// The standard confirm dialog: title, message, Cancel, one confirm action.
/// Returns true only when the user confirmed. Seven screens hand-rolled this
/// and had already drifted in content and button styling; one function so they
/// can't.
///
/// [confirmColor] defaults to the accent; pass e.g. [Colors.redAccent] for
/// destructive actions.
Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  Color? confirmColor,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    // Pop with the dialog's own context: callers often sit in a tab navigator
    // while the dialog is on the root navigator, so popping with the outer
    // context targets the wrong stack.
    builder: (dialogCtx) => AlertDialog(
      backgroundColor: SagaColors.surface,
      title: Text(title, style: TextStyle(color: SagaColors.fg)),
      content: Text(message, style: TextStyle(color: SagaColors.fgMuted)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogCtx, false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(dialogCtx, true),
          child: Text(confirmLabel,
              style: TextStyle(color: confirmColor ?? SagaColors.accentText)),
        ),
      ],
    ),
  );
  return confirmed == true;
}
