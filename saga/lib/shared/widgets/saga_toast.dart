import 'package:flutter/material.dart';
import '../../core/theme/saga_theme.dart';

void showSagaToast(
  BuildContext context,
  String message, {
  Duration duration = const Duration(milliseconds: 2500),
}) {
  final overlay = Overlay.of(context);
  final top = MediaQuery.of(context).padding.top;
  late OverlayEntry entry;

  entry = OverlayEntry(
    builder: (_) => _SagaToast(
      message: message,
      top: top,
      duration: duration,
      onDone: () => entry.remove(),
    ),
  );

  overlay.insert(entry);
}

class _SagaToast extends StatefulWidget {
  final String message;
  final double top;
  final Duration duration;
  final VoidCallback onDone;

  const _SagaToast({
    required this.message,
    required this.top,
    required this.duration,
    required this.onDone,
  });

  @override
  State<_SagaToast> createState() => _SagaToastState();
}

class _SagaToastState extends State<_SagaToast>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _opacity;

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
                  color: SagaColors.surface,
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
                    color: SagaColors.fg,
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
