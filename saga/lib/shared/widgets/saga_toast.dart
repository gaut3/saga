import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers.dart';
import '../../core/theme/saga_theme.dart';

/// Show a floating toast anchored below the status bar.
///
/// [isError] tints the pill red-amber so errors are visually distinct from
/// informational confirmations. Pass the calling widget's [BuildContext] —
/// the toast is inserted into the root overlay so it appears above everything
/// including the full-screen player.
void showSagaToast(
  BuildContext context,
  String message, {
  bool isError = false,
  Duration duration = const Duration(milliseconds: 2500),
}) {
  // Use the root navigator's overlay so the toast is visible even when
  // PlayerScreen (rootNavigator: true) is covering the tab overlay.
  final overlay = Navigator.of(context, rootNavigator: true).overlay;
  if (overlay == null) return;

  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (ctx) {
      // Read padding inside the builder — padding captured at call time goes
      // stale after a device rotation.
      final top = MediaQuery.of(ctx).padding.top;
      return _SagaToast(
        message: message,
        top: top,
        isError: isError,
        duration: duration,
        onDone: () {
          // Guard against the overlay entry already being removed (e.g. a
          // route change that tore down the overlay between the timer firing
          // and this callback running).
          if (entry.mounted) entry.remove();
        },
      );
    },
  );

  overlay.insert(entry);
}

class _SagaToast extends ConsumerStatefulWidget {
  final String message;
  final double top;
  final bool isError;
  final Duration duration;
  final VoidCallback onDone;

  const _SagaToast({
    required this.message,
    required this.top,
    required this.isError,
    required this.duration,
    required this.onDone,
  });

  @override
  ConsumerState<_SagaToast> createState() => _SagaToastState();
}

class _SagaToastState extends ConsumerState<_SagaToast>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _opacity;
  bool _dismissed = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _opacity = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _ctrl.forward();
    Future.delayed(widget.duration, _dismiss);
  }

  void _dismiss() {
    // Guard: timer and tap can both fire; only the first should act.
    if (_dismissed) return;
    _dismissed = true;
    if (mounted) {
      _ctrl.reverse().then((_) => widget.onDone());
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(sagaThemeVariantProvider);
    // Error toasts use fixed amber+ink — these are static const values unchanged
    // by theme variants, so the toast always pops regardless of which theme is
    // active (terra surface == terraDeep, so a terra-toned error pill is invisible
    // on the Terra theme).
    final Color bg = widget.isError ? SagaColors.amber : SagaColors.surface;
    final Color fg = widget.isError ? SagaColors.ink   : SagaColors.fg;

    return Positioned(
      top: widget.top + 12,
      left: 0,
      right: 0,
      child: FadeTransition(
        opacity: _opacity,
        child: Center(
          child: GestureDetector(
            onTap: _dismiss,
            child: Material(
              color: Colors.transparent,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(99),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.25),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Text(
                  widget.message,
                  style: TextStyle(
                    color: fg,
                    fontFamily: 'Manrope',
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
