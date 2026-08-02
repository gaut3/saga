import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart' show HapticFeedback;

/// Wraps the mini player so it can be swiped away, matching the notification
/// shade in Android 16 (Material 3 Expressive).
///
/// That gesture is not the frictionless glide it was before 16. Dragged slowly,
/// a notification *sticks* — it resists, barely moving — until it **snaps**
/// free of the stack with a haptic rumble, after which it tracks the finger
/// normally. Release is spring physics throughout: let go short and it springs
/// back with a little bounce; throw it and the fling's momentum carries it off.
///
/// So there are three phases here — stuck, snap, free — plus springs on
/// release. Getting only the last part right feels like pre-16 Android, which
/// is the trap this widget exists to avoid.
///
/// The shade also nudges the *neighbouring* notifications as you drag; the pill
/// has no neighbours, so what it sticks to is its own slot.
///
/// Flutter's [Dismissible] can't express any of this: it tracks the finger 1:1
/// from the first pixel, with no resistance phase and no snap.
class SwipeAwayPill extends StatefulWidget {
  /// Fired once the pill has left the screen.
  final VoidCallback onDismissed;

  /// Long-press handler. The swipe is unlabeled by design, so this is the
  /// discoverable, screen-reader-reachable route to the same thing — see
  /// `main_shell`'s options menu.
  final VoidCallback? onLongPress;

  final Widget child;

  const SwipeAwayPill({
    super.key,
    required this.onDismissed,
    required this.child,
    this.onLongPress,
  });

  @override
  State<SwipeAwayPill> createState() => _SwipeAwayPillState();
}

class _SwipeAwayPillState extends State<SwipeAwayPill>
    with TickerProviderStateMixin {
  // ── Feel ───────────────────────────────────────────────────────────────────
  // Tuned by eye against the shade rather than ported from AOSP constants.

  /// Drag distance that breaks the pill free of its slot, measured from where
  /// the horizontal drag is recognised — real finger travel is this plus
  /// `kTouchSlop` (~18), and the resistance is felt across all of it.
  static const _kUnstick = 34.0;

  /// How far the pill actually moves while stuck. It strains toward this and
  /// never reaches it, which is what makes the snap feel earned.
  static const _kMaxStuck = 18.0;

  // Note: there is no overshoot constant. The lunge at the moment of detach
  // isn't decoration added on top — it falls out of the pill closing the gap it
  // built up while stuck (see [_catchUp]), which is what the shade actually
  // does. Measured off a screen recording of Android 16: the card holds
  // completely still for the first ~20 px of finger travel, then covers ~160 px
  // while the finger covers ~85 — roughly double speed — until it has caught up.

  /// Fraction of the pill's width that commits to a dismiss on release.
  static const _kDismissFraction = 1 / 3;

  /// Fling speed (px/s) that dismisses regardless of distance — but only once
  /// free, and only thrown the way the pill is already going. Velocity relaxes
  /// the distance requirement; it never substitutes for the snap.
  static const _kEscapeVelocity = 600.0;

  /// Travel (as a fraction of width) at which the fade bottoms out.
  static const _kFadeEnd = 0.9;
  static const _kMinOpacity = 0.15;

  /// Release spring: slightly under-damped, so a snap-back lands with the same
  /// small bounce a released notification has.
  static final _releaseSpring = SpringDescription.withDampingRatio(
    mass: 1,
    stiffness: 500,
    ratio: 0.82,
  );

  /// Detach spring: stiffer and bouncier — this one is the *snap* itself.
  static final _snapSpring = SpringDescription.withDampingRatio(
    mass: 1,
    stiffness: 900,
    ratio: 0.55,
  );

  /// Unbounded: `value` is the rendered horizontal offset in logical pixels, so
  /// a simulation can drive it straight out past the screen edge.
  late final AnimationController _offset =
      AnimationController.unbounded(vsync: this);

  /// How far *behind* the finger the pill still is, springing to zero once it
  /// detaches. While stuck the pill falls behind; the snap is that debt being
  /// paid back, which is why the pill briefly outruns the finger.
  late final AnimationController _catchUp =
      AnimationController.unbounded(vsync: this);

  double _raw = 0;
  double _dir = 1; // travel sign latched at the snap
  bool _unstuck = false;
  bool _dragging = false;
  bool _dismissing = false;
  double _width = 0;

  @override
  void initState() {
    super.initState();
    // Only recompose from _catchUp while the finger is down; after release the
    // simulation on _offset owns the value outright.
    _catchUp.addListener(() {
      if (_dragging) _apply();
    });
  }

  @override
  void dispose() {
    _offset.dispose();
    _catchUp.dispose();
    super.dispose();
  }

  double get _commitDistance => _width * _kDismissFraction;

  /// Where the pill would sit with no debt outstanding: damped while stuck,
  /// exactly under the finger once free.
  ///
  /// Note the free case is plain `_raw`, not `_raw` minus the distance given up
  /// while stuck. Holding that gap open forever would leave the pill trailing
  /// the finger for the rest of the drag; the shade instead closes it, and
  /// closing it *is* the snap.
  double get _base {
    if (!_unstuck) {
      final s = _raw.isNegative ? -1.0 : 1.0;
      final t = _raw.abs() / _kUnstick;
      // tanh: strains toward the asymptote instead of stopping dead.
      final damped = (math.exp(2 * t) - 1) / (math.exp(2 * t) + 1);
      return s * _kMaxStuck * damped;
    }
    return _raw;
  }

  void _apply() => _offset.value = _base + _catchUp.value;

  void _onDragStart(DragStartDetails _) {
    _offset.stop();
    _catchUp.stop();
    _catchUp.value = 0;
    _dragging = true;

    // The small tick as the drag takes hold, before anything detaches.
    HapticFeedback.selectionClick();

    // Grabbing the pill mid-animation: if it's already clear of the stuck zone
    // it stays free, and _raw is back-solved from where it actually is so it
    // doesn't jump under the finger.
    final at = _offset.value;
    if (at.abs() > _kMaxStuck) {
      _unstuck = true;
      _dir = at.isNegative ? -1.0 : 1.0;
      _raw = at; // already free: the pill is under the finger
    } else {
      _unstuck = false;
      _raw = at;
    }
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (_dismissing) return;
    _raw += details.delta.dx;

    if (!_unstuck && _raw.abs() >= _kUnstick) {
      final stuckAt = _base; // damped position, before the rule changes
      _unstuck = true;
      _dir = _raw.isNegative ? -1.0 : 1.0;
      // The rumble as it comes off the stack — the one moment in this gesture
      // that deserves a real impact rather than a tick.
      HapticFeedback.mediumImpact();
      // The debt: how far behind the finger the stuck phase left it. Spring it
      // to zero and the pill lunges forward to meet the finger, briefly moving
      // faster than the drag, then settles under it — with the overshoot coming
      // free from an under-damped spring rather than being bolted on.
      final debt = stuckAt - _raw;
      _catchUp.value = debt;
      _catchUp.animateWith(SpringSimulation(_snapSpring, debt, 0, 0));
    }

    _apply();
  }

  void _onDragEnd(DragEndDetails details) {
    _dragging = false;
    if (_dismissing) return;
    final velocity = details.velocity.pixelsPerSecond.dx;
    final at = _offset.value;

    // A fling only counts once free, and only thrown the way the pill is
    // already going — a flick back toward the slot is a "put it back", and
    // honouring its sign would sling the pill off the opposite edge.
    final flung = _unstuck &&
        velocity.abs() >= _kEscapeVelocity &&
        (velocity.isNegative ? -1.0 : 1.0) == _dir;

    if (_unstuck && (at.abs() >= _commitDistance || flung)) {
      _dismissing = true;
      _catchUp.stop();
      // Carry the throw out past the edge rather than tweening at a fixed rate.
      _offset
          .animateWith(SpringSimulation(
              _releaseSpring, at, _dir * (_width + 96), velocity))
          .whenComplete(() {
        if (mounted) widget.onDismissed();
      });
    } else {
      _catchUp.stop();
      _catchUp.value = 0;
      _offset
          .animateWith(SpringSimulation(_releaseSpring, at, 0, velocity))
          .whenComplete(() {
        // Re-sticks only after release: once free it stays free for the rest
        // of that drag, even if the finger comes back inside the threshold.
        if (!mounted) return;
        _raw = 0;
        _unstuck = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _width = constraints.maxWidth;
        return GestureDetector(
          onHorizontalDragStart: _onDragStart,
          onHorizontalDragUpdate: _onDragUpdate,
          onHorizontalDragEnd: _onDragEnd,
          onLongPress: widget.onLongPress,
          // Clip.none so the pill leaves the screen rather than vanishing at
          // the bottom bar's box edge.
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              AnimatedBuilder(
                animation: _offset,
                builder: (context, child) {
                  final dx = _offset.value;
                  final fadeSpan = _width * _kFadeEnd;
                  final opacity = fadeSpan > 0
                      ? (1.0 - (dx.abs() / fadeSpan)).clamp(_kMinOpacity, 1.0)
                      : 1.0;
                  return Transform.translate(
                    offset: Offset(dx, 0),
                    child: Opacity(opacity: opacity, child: child),
                  );
                },
                child: widget.child,
              ),
            ],
          ),
        );
      },
    );
  }
}
