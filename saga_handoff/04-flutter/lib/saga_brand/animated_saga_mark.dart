// animated_saga_mark.dart
// The Saga logo mark with four playback states.
//
// Usage:
//   AnimatedSagaMark(
//     size: 48,
//     theme: SagaTheme.ink,
//     state: SagaMarkState.playing,
//   )
//
// State is hot-swappable — change the `state` prop and the widget
// transitions smoothly (no flicker, no rebuild thrash).

import 'package:flutter/material.dart';
import 'saga_colors.dart';
import 'saga_mark.dart';

enum SagaMarkState {
  /// Static logo (default). Matches the brand reference exactly.
  paused,

  /// VU-meter pulse, each spine on its own rhythm.
  /// Use for the now-playing affordance.
  playing,

  /// Gentle "alive" hint — 88% scale + slight opacity fade.
  /// Use for splash, idle, hero surfaces.
  breathing,

  /// Staggered fill — bars rise short → tall in sequence.
  /// Use for buffering / Plex sync.
  loading,
}

class AnimatedSagaMark extends StatefulWidget {
  final double size;
  final SagaTheme theme;
  final SagaMarkState state;
  final String? semanticLabel;

  const AnimatedSagaMark({
    super.key,
    this.size = 40,
    this.theme = SagaTheme.ink,
    this.state = SagaMarkState.paused,
    this.semanticLabel = 'Saga',
  });

  @override
  State<AnimatedSagaMark> createState() => _AnimatedSagaMarkState();
}

class _AnimatedSagaMarkState extends State<AnimatedSagaMark>
    with TickerProviderStateMixin {
  // Three independent controllers — used by the "playing" state where
  // each spine pulses on its own rhythm.
  late final AnimationController _ctrlLeft;
  late final AnimationController _ctrlMid;
  late final AnimationController _ctrlRight;

  // One shared controller — used by the "breathing" and "loading" states,
  // which share a common period across all three spines with per-spine
  // phase offsets.
  late final AnimationController _ctrlShared;

  @override
  void initState() {
    super.initState();
    _ctrlLeft   = AnimationController(vsync: this, duration: const Duration(milliseconds: 1300));
    _ctrlMid    = AnimationController(vsync: this, duration: const Duration(milliseconds:  900));
    _ctrlRight  = AnimationController(vsync: this, duration: const Duration(milliseconds: 1700));
    _ctrlShared = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));
    _applyState();
  }

  @override
  void didUpdateWidget(covariant AnimatedSagaMark old) {
    super.didUpdateWidget(old);
    if (old.state != widget.state) _applyState();
  }

  void _applyState() {
    switch (widget.state) {
      case SagaMarkState.playing:
        _ctrlShared.stop();
        // 1.3 / 0.9 / 1.7 s — but use repeat(reverse:true) so the
        // effective full-cycle is 2× duration to match the CSS keyframes.
        _ctrlLeft.duration  = const Duration(milliseconds: 650);
        _ctrlMid.duration   = const Duration(milliseconds: 450);
        _ctrlRight.duration = const Duration(milliseconds: 850);
        _ctrlLeft.repeat(reverse: true);
        _ctrlMid.repeat(reverse: true);
        _ctrlRight.repeat(reverse: true);
        break;
      case SagaMarkState.breathing:
        _ctrlLeft.stop();
        _ctrlMid.stop();
        _ctrlRight.stop();
        _ctrlShared.duration = const Duration(milliseconds: 2400);
        _ctrlShared.repeat(reverse: true);
        break;
      case SagaMarkState.loading:
        _ctrlLeft.stop();
        _ctrlMid.stop();
        _ctrlRight.stop();
        _ctrlShared.duration = const Duration(milliseconds: 1600);
        _ctrlShared.repeat(reverse: true);
        break;
      case SagaMarkState.paused:
        _ctrlLeft.stop();
        _ctrlMid.stop();
        _ctrlRight.stop();
        _ctrlShared.stop();
        break;
    }
  }

  @override
  void dispose() {
    _ctrlLeft.dispose();
    _ctrlMid.dispose();
    _ctrlRight.dispose();
    _ctrlShared.dispose();
    super.dispose();
  }

  // ─── Scale + opacity calculators per state ─────────────────
  // Curve helper: ease-in-out matches the CSS timing function.
  double _eased(double t) => Curves.easeInOut.transform(t);

  ({double scale, double opacity}) _spineLeftValues(double mediaQueryAnim) {
    switch (widget.state) {
      case SagaMarkState.playing:
        // 1 → 0.55 → 1 (each half-period)
        return (scale: _lerp(_eased(_ctrlLeft.value), 1.0, 0.55), opacity: 1.0);
      case SagaMarkState.breathing:
        return _breatheValues(phaseDelay: 0.0);
      case SagaMarkState.loading:
        return _loadValues(phaseDelay: 0.0);
      case SagaMarkState.paused:
        return (scale: 1.0, opacity: 1.0);
    }
  }

  ({double scale, double opacity}) _spineMidValues(double mediaQueryAnim) {
    switch (widget.state) {
      case SagaMarkState.playing:
        return (scale: _lerp(_eased(_ctrlMid.value), 1.0, 0.42), opacity: 1.0);
      case SagaMarkState.breathing:
        return _breatheValues(phaseDelay: 0.083); // 0.2s of 2.4s
      case SagaMarkState.loading:
        return _loadValues(phaseDelay: 0.094);   // 0.15s of 1.6s
      case SagaMarkState.paused:
        return (scale: 1.0, opacity: 1.0);
    }
  }

  ({double scale, double opacity}) _spineRightValues(double mediaQueryAnim) {
    switch (widget.state) {
      case SagaMarkState.playing:
        return (scale: _lerp(_eased(_ctrlRight.value), 1.0, 0.62), opacity: 1.0);
      case SagaMarkState.breathing:
        return _breatheValues(phaseDelay: 0.167); // 0.4s of 2.4s
      case SagaMarkState.loading:
        return _loadValues(phaseDelay: 0.188);    // 0.3s of 1.6s
      case SagaMarkState.paused:
        return (scale: 1.0, opacity: 1.0);
    }
  }

  // Breathing: scale 1 ↔ 0.88, opacity 1 ↔ 0.85
  ({double scale, double opacity}) _breatheValues({required double phaseDelay}) {
    final t = _phaseShift(_ctrlShared.value, phaseDelay);
    final eased = _eased(t);
    return (
      scale:   _lerp(eased, 1.0, 0.88),
      opacity: _lerp(eased, 1.0, 0.85),
    );
  }

  // Loading: scale 0.35 ↔ 1
  ({double scale, double opacity}) _loadValues({required double phaseDelay}) {
    final t = _phaseShift(_ctrlShared.value, phaseDelay);
    return (scale: _lerp(_eased(t), 0.35, 1.0), opacity: 1.0);
  }

  double _phaseShift(double v, double delay) {
    final shifted = (v - delay) % 1.0;
    return shifted < 0 ? shifted + 1.0 : shifted;
  }

  double _lerp(double t, double from, double to) => from + (to - from) * t;

  @override
  Widget build(BuildContext context) {
    // Respect reduced-motion preference (Flutter exposes this via MediaQuery).
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    final inner = AnimatedBuilder(
      animation: Listenable.merge([_ctrlLeft, _ctrlMid, _ctrlRight, _ctrlShared]),
      builder: (context, _) {
        final l = reduceMotion ? (scale: 1.0, opacity: 1.0) : _spineLeftValues(0);
        final m = reduceMotion ? (scale: 1.0, opacity: 1.0) : _spineMidValues(0);
        final r = reduceMotion ? (scale: 1.0, opacity: 1.0) : _spineRightValues(0);

        return CustomPaint(
          size: Size(widget.size, widget.size),
          painter: SagaMarkPainter(
            theme: widget.theme,
            flat: false,
            leftScale: l.scale,
            midScale: m.scale,
            rightScale: r.scale,
            leftOpacity: l.opacity,
            midOpacity: m.opacity,
            rightOpacity: r.opacity,
          ),
        );
      },
    );

    if (widget.semanticLabel == null) return inner;
    return Semantics(
      image: true,
      label: widget.semanticLabel,
      liveRegion: widget.state == SagaMarkState.playing ||
                  widget.state == SagaMarkState.loading,
      child: inner,
    );
  }
}
