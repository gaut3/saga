import 'package:flutter/material.dart';

import '../../core/diagnostics/app_log.dart';
import '../../core/theme/saga_theme.dart';

/// The standard full-area error state: icon, friendly message, Retry.
///
/// The raw [error] is never rendered — exception text can embed the server
/// address (a `DioException` prints the request URI), which must not appear
/// on screen or in the screenshots users attach to bug reports. It goes to
/// the diagnostics log instead, once per mount.
class SagaErrorView extends StatefulWidget {
  final String message;
  final Object? error;
  final VoidCallback? onRetry;

  const SagaErrorView({
    super.key,
    this.message = 'Something went wrong',
    this.error,
    this.onRetry,
  });

  @override
  State<SagaErrorView> createState() => _SagaErrorViewState();
}

class _SagaErrorViewState extends State<SagaErrorView> {
  @override
  void initState() {
    super.initState();
    if (widget.error != null) {
      AppLog.log('ui', 'error view ("${widget.message}"): ${widget.error}');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
            const SizedBox(height: 12),
            Text(widget.message,
                textAlign: TextAlign.center,
                style: TextStyle(color: SagaColors.fgMuted)),
            if (widget.onRetry != null) ...[
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: widget.onRetry,
                style: ElevatedButton.styleFrom(
                  backgroundColor: SagaColors.accent,
                  foregroundColor: SagaColors.accentFg,
                ),
                child: const Text('Retry'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
