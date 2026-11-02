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
/// The app's root navigator, so code with no screen of its own (a provider
/// reacting to playback) can still say something. Wired into `MaterialApp`.
final rootNavigatorKey = GlobalKey<NavigatorState>();

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

/// A toast that stays until it's closed: tapping the body runs [onTap], the
/// close button runs [onClose], and either one removes it.
///
/// For news that a 2.5 s toast at launch is too easy to miss (the update
/// check: it fires while the app is still opening, and people missed it).
void showSagaBanner(
  BuildContext context,
  String message, {
  required VoidCallback onTap,
  required VoidCallback onClose,
}) {
  final overlay = Navigator.of(context, rootNavigator: true).overlay;
  if (overlay == null) return;

  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (ctx) => _SagaToast(
      message: message,
      top: MediaQuery.of(ctx).padding.top,
      isError: false,
      onTap: onTap,
      onClose: onClose,
      onDone: () {
        if (entry.mounted) entry.remove();
      },
    ),
  );

  overlay.insert(entry);
}

class _SagaToast extends ConsumerStatefulWidget {
  final String message;
  final double top;
  final bool isError;

  /// Null keeps it up until [onTap] or [onClose] (a banner).
  final Duration? duration;
  final VoidCallback? onTap;

  /// Non-null shows a close button.
  final VoidCallback? onClose;
  final VoidCallback onDone;

  const _SagaToast({
    required this.message,
    required this.top,
    required this.isError,
    this.duration,
    this.onTap,
    this.onClose,
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
    final duration = widget.duration;
    if (duration != null) Future.delayed(duration, _dismiss);
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
    // active (an ember/terra-toned error pill would sink into the Ember
    // theme's own grounds).
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
            onTap: () {
              // The guard in _dismiss also keeps a double tap from running
              // the action twice.
              if (_dismissed) return;
              _dismiss();
              widget.onTap?.call();
            },
            child: Material(
              color: Colors.transparent,
              child: Container(
                padding: widget.onClose == null
                    ? const EdgeInsets.symmetric(horizontal: 20, vertical: 10)
                    : const EdgeInsets.only(left: 20, right: 4),
                margin: const EdgeInsets.symmetric(horizontal: 16),
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
                // liveRegion is how SnackBar gets TalkBack to read it out;
                // without it every toast confirmation is visual-only.
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Semantics(
                        liveRegion: true,
                        button: widget.onTap != null,
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
                    if (widget.onClose != null)
                      IconButton(
                        icon: Icon(Icons.close, size: 18, color: fg),
                        tooltip: 'Dismiss',
                        onPressed: () {
                          if (_dismissed) return;
                          _dismiss();
                          widget.onClose!();
                        },
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
