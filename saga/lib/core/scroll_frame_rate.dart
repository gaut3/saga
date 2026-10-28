import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Asks Android for the screen's top refresh rate while the user scrolls.
///
/// Phones with adaptive refresh rate pick each app's render rate from what
/// its surfaces ask for, and a surface that asks for nothing gets "normal",
/// which is 60 Hz on a 120 Hz Pixel. Native views ask for more while they
/// scroll; Flutter draws into a single surface that never asks, so every
/// list in Saga scrolled at 60 while the rest of the phone ran at 120.
///
/// The request is held only while something moves (plus [_hold] after the
/// last movement), so a still screen costs nothing extra. A touch boosts
/// too, so the first frames of a drag aren't the slow ones. The user's own
/// cap (Smooth display off, Battery Saver) still wins: Android clamps the
/// request to it.
class ScrollFrameRateBoost extends StatefulWidget {
  final Widget child;

  const ScrollFrameRateBoost({super.key, required this.child});

  @override
  State<ScrollFrameRateBoost> createState() => _ScrollFrameRateBoostState();
}

class _ScrollFrameRateBoostState extends State<ScrollFrameRateBoost> {
  static const _channel = MethodChannel('com.gaut3.saga/frame_rate');
  static const _hold = Duration(milliseconds: 500);

  bool _boosted = false;
  Timer? _relax;

  void _bump() {
    _relax?.cancel();
    _relax = Timer(_hold, () => _set(false));
    if (!_boosted) _set(true);
  }

  void _set(bool boost) {
    _boosted = boost;
    // A missing or failing native side just means the default rate — never
    // worth surfacing.
    _channel.invokeMethod('setBoost', boost).catchError((_) => null);
  }

  @override
  void dispose() {
    _relax?.cancel();
    if (_boosted) _set(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _bump(),
      child: NotificationListener<ScrollNotification>(
        onNotification: (_) {
          _bump();
          return false;
        },
        child: widget.child,
      ),
    );
  }
}
