import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../core/audio/audio_level.dart';
import '../../core/mark_motion.dart';
import '../../core/theme/saga_theme.dart';

// ── Animated mark (4-spine, v3) ───────────────────────────────────────────────
//
// One mark, every playback moment. Paused folds into a solid play triangle;
// every other state is the four spines, alive. They are the *same four shapes*
// (the triangle is the spines folded into four contiguous wedges) so any state
// morphs cleanly into any other and collapses back to the triangle when stopped.
//
// Geometry lives in a 200×200 design box; we scale to render size. The spine
// "text" lines from the large brand lockup are intentionally dropped here — at
// UI sizes and in motion they smear into noise (handoff §05).

enum SagaMarkState {
  paused,      // solid play triangle (tap to resume)
  playing,     // loudness-reactive VU wave (now-playing affordance)
  buffering,   // staggered sweep (stream loading)
  downloading, // determinate fill from the floor — bars = % complete
  breathing,   // gentle synchronized swell (idle / splash)
  finished,    // celebratory overshoot bloom (book complete / streak)
}

class AnimatedSagaMark extends StatefulWidget {
  final double size;
  final SagaMarkState state;

  /// 0..1, only used by [SagaMarkState.downloading] (each bar is a quarter).
  final double progress;

  /// When set, the whole mark is drawn in this single colour instead of the
  /// theme's two-tone spines — e.g. monochrome on an accent button.
  final Color? monoColor;

  /// Renders the mark as a play/pause control: the play triangle (when [state]
  /// is paused) morphs to/from the two-bar pause glyph (any other state),
  /// ignoring the global motion mode and audio levels. The open glyph is always
  /// the two bars, so resuming/pausing is a clean reverse of the same morph.
  final bool playPauseControl;

  /// Only meaningful with [playPauseControl]: while true the two pause bars
  /// shimmer to signal buffering, then settle to solid bars when cleared.
  final bool loading;

  const AnimatedSagaMark({
    super.key,
    this.size = 40,
    this.state = SagaMarkState.paused,
    this.progress = 0,
    this.monoColor,
    this.playPauseControl = false,
    this.loading = false,
  });

  @override
  State<AnimatedSagaMark> createState() => _AnimatedSagaMarkState();
}

class _AnimatedSagaMarkState extends State<AnimatedSagaMark>
    with TickerProviderStateMixin {
  // Morph: t = 0 → triangle (paused), t = 1 → bars (everything else).
  late final AnimationController _morph;
  // Continuous clock for the level-driven states. Not run for paused (static
  // triangle) or downloading (determinate — repaints on progress change).
  late final Ticker _clock;
  final ValueNotifier<int> _repaint = ValueNotifier(0);

  double _phase = 0;
  double _master = 0.6;
  double _mTarget = 0.6;
  final math.Random _rng = math.Random();
  List<double> _levels = const [1, 1, 1, 1];
  List<double> _opacities = const [1, 1, 1, 1];

  // Per-bar phase + rate offsets give the loudness wave its organic ripple.
  static const _rate = [1.0, 1.6, 1.3, 2.0];
  static const _off = [0.0, 1.1, 2.3, 3.4];

  // The brand logo's resting spine heights — the pose the finished bloom
  // settles back onto, and the static pose used when motion is disabled.
  static const _logoPose = [0.78, 1.0, 0.66, 0.86];

  @override
  void initState() {
    super.initState();
    _morph = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 470),
      value: widget.state == SagaMarkState.paused ? 0.0 : 1.0,
    );
    _clock = createTicker(_onTick);
    markMotionListenable.addListener(_onMotionChanged);
    _applyState();
  }

  void _onMotionChanged() {
    // Mode switched in Settings: re-evaluate the clock (pause mode is static).
    if (mounted) _applyState();
  }

  @override
  void didUpdateWidget(covariant AnimatedSagaMark old) {
    super.didUpdateWidget(old);
    if (old.state != widget.state ||
        old.loading != widget.loading ||
        old.playPauseControl != widget.playPauseControl) {
      _applyState();
    }
  }

  void _applyState() {
    // easeInOutCubic morph (cubic-bezier(.66,0,.34,1)) — triangle only on pause.
    if (widget.state == SagaMarkState.paused) {
      _morph.reverse();
    } else {
      _morph.forward();
    }
    final needsClock = widget.playPauseControl
        ? widget.loading // only the buffering shimmer needs the clock
        : switch (widget.state) {
            // Pause-bars mode is static (no audio, no motion) — no clock needed.
            SagaMarkState.playing =>
              markMotionListenable.value != MarkMotion.pause,
            SagaMarkState.buffering ||
            SagaMarkState.breathing ||
            SagaMarkState.finished =>
              true,
            SagaMarkState.paused || SagaMarkState.downloading => false,
          };
    if (needsClock) {
      if (!_clock.isActive) _clock.start();
    } else if (_clock.isActive) {
      _clock.stop();
    }
  }

  void _onTick(Duration elapsed) {
    // Play/pause control: the only motion is the buffering shimmer — the two
    // pause bars alternate opacity so it reads as "working", then settles to
    // solid bars when loading clears.
    if (widget.playPauseControl) {
      final secs = elapsed.inMicroseconds / 1e6;
      final a = 0.4 + 0.6 * (0.5 + 0.5 * math.sin(secs * 4.2));
      final b = 0.4 + 0.6 * (0.5 + 0.5 * math.sin(secs * 4.2 + math.pi));
      _opacities = [a, a, b, b];
      _repaint.value++;
      return;
    }
    _phase += 0.09; // ~matches the reference rAF cadence at 60fps
    switch (widget.state) {
      case SagaMarkState.playing:
        final live = AudioLevel.instance;
        final reactive =
            markMotionListenable.value == MarkMotion.reactive && live.isLive;
        if (reactive) {
          // Follow the real output loudness. Higher factor = tighter tracking
          // (less lag) at the cost of a touch more jitter; tune 0.3–0.8.
          // 0.72 keeps ~29 ms lag at 60fps, vs ~46 ms at 0.55 — important for
          // sync-delay users where the smoothing adds on top of the A2DP offset.
          _master += (live.level.value - _master) * 0.72;
        } else {
          // Gentle mode (or reactive with no live sample): a slow, calm drift.
          if (_rng.nextDouble() < 0.02) _mTarget = 0.5 + _rng.nextDouble() * 0.4;
          _master += (_mTarget - _master) * 0.08;
        }
        // Gentle ripples noticeably slower and subtler than the reactive meter.
        final rippleSpeed = reactive ? 1.0 : 0.4;
        final amp = reactive ? 0.18 : 0.12;
        _levels = List.generate(
            4,
            (i) => (_master +
                    amp * math.sin(_phase * _rate[i] * rippleSpeed + _off[i]))
                .clamp(0.16, 1.0));
        _opacities = const [1, 1, 1, 1];
      case SagaMarkState.buffering:
        _levels = List.generate(
            4, (i) => 0.3 + 0.7 * ((math.sin(_phase - i * 0.5) + 1) / 2));
        _opacities = const [1, 1, 1, 1];
      case SagaMarkState.breathing:
        _levels = List.generate(4, (i) {
          final s = (math.sin(_phase * 0.6 - i * 0.6) + 1) / 2;
          return 0.82 + 0.18 * s;
        });
        _opacities = List.generate(4, (i) {
          final s = (math.sin(_phase * 0.6 - i * 0.6) + 1) / 2;
          return 0.85 + 0.15 * s;
        });
      case SagaMarkState.finished:
        // One slow cycle: bloom out of the logo, settle back to the logo pose,
        // hold a beat, then bloom again. Driven by real elapsed time so the
        // cadence is framerate-independent (and unhurried).
        const period = 4.5; // seconds per bloom → logo → hold cycle
        const bloomPortion = 0.5; // first half blooms, second half rests on logo
        final secs = elapsed.inMicroseconds / 1e6;
        final c = (secs / period) % 1.0;
        if (c < bloomPortion) {
          final cb = c / bloomPortion;
          // Shared bell weight: 0 at both cycle edges, 1 mid-bloom. Identical for
          // every spine so they all land back exactly on the logo at cb = 1 (no
          // snap). The per-bar ripple lives in the bloom shape's phase instead.
          final w = math.sin(math.pi * cb);
          _levels = List.generate(4, (i) {
            final u = (cb * 1.12 - i * 0.04).clamp(0.0, 1.0);
            final bloom = _celebrate(u);
            return (_logoPose[i] + (bloom - _logoPose[i]) * w).clamp(0.12, 1.4);
          });
        } else {
          _levels = _logoPose;
        }
        _opacities = const [1, 1, 1, 1];
      case SagaMarkState.downloading:
      case SagaMarkState.paused:
        break;
    }
    _repaint.value++;
  }

  // Celebrate keyframes: 1 → 0.42 → 1.18 → 0.94 → 1, eased between control points.
  static double _celebrate(double u) {
    const pts = [
      (0.0, 1.0),
      (0.26, 0.42),
      (0.54, 1.18),
      (0.76, 0.94),
      (1.0, 1.0),
    ];
    for (var i = 0; i < pts.length - 1; i++) {
      final (t0, v0) = pts[i];
      final (t1, v1) = pts[i + 1];
      if (u <= t1) {
        final f = ((u - t0) / (t1 - t0)).clamp(0.0, 1.0);
        return v0 + (v1 - v0) * Curves.easeInOut.transform(f);
      }
    }
    return 1.0;
  }

  List<double> _levelsFor(bool reduceMotion) {
    switch (widget.state) {
      case SagaMarkState.paused:
        return const [1, 1, 1, 1]; // unused at t=0
      case SagaMarkState.downloading:
        return List.generate(
            4, (i) => (widget.progress * 4 - i).clamp(0.14, 1.0));
      default:
        // Static representative pose when motion is disabled.
        return reduceMotion ? _logoPose : _levels;
    }
  }

  @override
  void dispose() {
    markMotionListenable.removeListener(_onMotionChanged);
    _clock.dispose();
    _morph.dispose();
    _repaint.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: Listenable.merge([_morph, _repaint, markMotionListenable]),
          builder: (context, _) {
            // easeInOutCubic shaping on the morph value.
            final t = Curves.easeInOutCubic.transform(_morph.value);
            // Pause-bars: the playing end-state is a static two-bar glyph. In
            // play/pause-control mode the open glyph is ALWAYS the two bars, so
            // resuming/pausing is a clean reverse of the same triangle⇄bars
            // morph (never flashing the 4 spines in between).
            final pauseGlyph = widget.playPauseControl ||
                (widget.state == SagaMarkState.playing &&
                    markMotionListenable.value == MarkMotion.pause);
            final opacities = widget.playPauseControl
                ? (widget.loading ? _opacities : const [1.0, 1.0, 1.0, 1.0])
                : (reduceMotion ? const [1.0, 1.0, 1.0, 1.0] : _opacities);
            return CustomPaint(
              painter: _SpineMorphPainter(
                t: t,
                levels: (pauseGlyph || widget.playPauseControl)
                    ? const [1, 1, 1, 1]
                    : _levelsFor(reduceMotion),
                opacities: opacities,
                bottomAnchor: widget.state == SagaMarkState.downloading,
                pauseGlyph: pauseGlyph,
                neutral: widget.monoColor ?? SagaColors.markSide,
                accent: widget.monoColor ?? SagaColors.markMiddle,
              ),
            );
          },
        ),
      ),
    );
  }
}

// ── Morph painter (triangle ⇄ four spines) ────────────────────────────────────

class _SpineMorphPainter extends CustomPainter {
  final double t; // 0 triangle, 1 open glyph
  final List<double> levels;
  final List<double> opacities;
  final bool bottomAnchor;
  final bool pauseGlyph; // open glyph is the two-bar pause instead of 4 spines
  final Color neutral;
  final Color accent;

  const _SpineMorphPainter({
    required this.t,
    required this.levels,
    required this.opacities,
    required this.bottomAnchor,
    required this.pauseGlyph,
    required this.neutral,
    required this.accent,
  });

  // Corner order per shape: TL, TR, BR, BL.
  static const _tri = <List<Offset>>[
    [Offset(41, 36), Offset(70.5, 52), Offset(70.5, 148), Offset(41, 164)],
    [Offset(70.5, 52), Offset(100, 68), Offset(100, 132), Offset(70.5, 148)],
    [Offset(100, 68), Offset(129.5, 84), Offset(129.5, 116), Offset(100, 132)],
    [Offset(129.5, 84), Offset(159, 100), Offset(159, 100), Offset(129.5, 116)],
  ];
  static const _bar = <List<Offset>>[
    [Offset(41, 36), Offset(63, 36), Offset(63, 164), Offset(41, 164)],
    [Offset(73, 36), Offset(95, 36), Offset(95, 164), Offset(73, 164)],
    [Offset(105, 36), Offset(127, 36), Offset(127, 164), Offset(105, 164)],
    [Offset(137, 36), Offset(159, 36), Offset(159, 164), Offset(137, 164)],
  ];
  // Pause glyph: spines 0&1 fold into the left bar, 2&3 into the right bar.
  // The accent spine (#1) merges into the left bar → amber-left / cream-right.
  static const _pauseBar = <List<Offset>>[
    [Offset(50, 36), Offset(94, 36), Offset(94, 164), Offset(50, 164)],
    [Offset(50, 36), Offset(94, 36), Offset(94, 164), Offset(50, 164)],
    [Offset(106, 36), Offset(150, 36), Offset(150, 164), Offset(106, 164)],
    [Offset(106, 36), Offset(150, 36), Offset(150, 164), Offset(106, 164)],
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 200.0;
    final open = pauseGlyph ? _pauseBar : _bar;
    for (var i = 0; i < 4; i++) {
      final p = List.generate(
          4, (k) => Offset.lerp(_tri[i][k], open[i][k], t)!);
      // Height scaling only applies in bar mode (folded triangle is solid).
      final pivotY = bottomAnchor
          ? math.max(p[2].dy, p[3].dy)
          : (p[0].dy + p[2].dy) / 2;
      final lvl = levels[i] < 0.16 ? 0.16 : levels[i];
      final h = lerpDouble(1.0, lvl, t)!;
      final q = p
          .map((o) => Offset(o.dx, pivotY + (o.dy - pivotY) * h) * s)
          .toList();
      final paint = Paint()
        ..isAntiAlias = true
        ..color = (i == 1 ? accent : neutral)
            .withValues(alpha: opacities[i].clamp(0.0, 1.0));
      canvas.drawPath(Path()..addPolygon(q, true), paint);
    }
  }

  @override
  bool shouldRepaint(_SpineMorphPainter old) =>
      old.t != t ||
      old.bottomAnchor != bottomAnchor ||
      old.pauseGlyph != pauseGlyph ||
      old.neutral != neutral ||
      old.accent != accent ||
      !listEquals(old.levels, levels) ||
      !listEquals(old.opacities, opacities);
}

// ── Saga Mark (static brand logo — four spines, varied heights) ───────────────

class SagaMark extends StatelessWidget {
  final double size;

  const SagaMark({super.key, this.size = 40});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _LogoPainter(
          neutral: SagaColors.markSide,
          accent: SagaColors.markMiddle,
        ),
      ),
    );
  }
}

class _LogoPainter extends CustomPainter {
  final Color neutral;
  final Color accent;

  const _LogoPainter({required this.neutral, required this.accent});

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 200.0;
    void bar(double x, double y, double w, double h, Color color) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x * s, y * s, w * s, h * s),
          Radius.circular(5 * s),
        ),
        Paint()
          ..isAntiAlias = true
          ..color = color,
      );
    }

    // Logo pose — width 22, radius 5, accent on the second bar. Bars are
    // CENTRED on the vertical midline (y=100), never bottom-aligned. Brand rule:
    // centre every state except the download animation (handoff §91).
    bar(41, 48, 22, 104, neutral); // h104 centred (100 − 52)
    bar(73, 38, 22, 124, accent); // h124 centred (100 − 62)
    bar(105, 56, 22, 88, neutral); // h88  centred (100 − 44)
    bar(137, 46, 22, 108, neutral); // h108 centred (100 − 54)
  }

  @override
  bool shouldRepaint(_LogoPainter old) =>
      old.neutral != neutral || old.accent != accent;
}

// ── Saga Wordmark ("saga" + play triangle) ────────────────────────────────────

class SagaWordmark extends StatelessWidget {
  final double fontSize;

  const SagaWordmark({super.key, this.fontSize = 32});

  @override
  Widget build(BuildContext context) {
    final triSize = fontSize * 0.42;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          'saga',
          style: TextStyle(
            fontFamily: 'Manrope',
            // Handoff: SemiBold (600), not ExtraBold — confident, not shouting.
            fontWeight: FontWeight.w600,
            fontSize: fontSize,
            letterSpacing: fontSize * -0.025,
            color: SagaColors.fg,
            height: 1,
          ),
        ),
        SizedBox(width: fontSize * 0.14),
        SizedBox(
          width: triSize,
          height: triSize,
          child: CustomPaint(painter: _TrianglePainter(color: SagaColors.accent)),
        ),
      ],
    );
  }
}

class _TrianglePainter extends CustomPainter {
  final Color color;
  const _TrianglePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(size.width * 0.2, size.height * 0.1)
      ..lineTo(size.width * 0.85, size.height * 0.5)
      ..lineTo(size.width * 0.2, size.height * 0.9)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_TrianglePainter old) => old.color != color;
}

// ── Saga Lockup (stacked: mark above wordmark) ───────────────────────────────

class SagaLockup extends StatelessWidget {
  final double wordmarkSize;

  const SagaLockup({super.key, this.wordmarkSize = 40});

  @override
  Widget build(BuildContext context) {
    final markSize = wordmarkSize * 1.5;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SagaMark(size: markSize),
        const SizedBox(height: 14),
        SagaWordmark(fontSize: wordmarkSize),
      ],
    );
  }
}
