# Handoff: Saga Animated Mark (4-spine play/pause)

## Overview
Saga's brand mark — four book "spines" — doubles as the player's **play/pause control** and as a single animated indicator for every playback moment (playing, paused, buffering, downloading, idle, finished). This package specifies the mark's geometry, colours, the play-triangle ⇄ spines morph, each animated state, and how to build it in Flutter.

The headline idea: **paused = a solid play triangle; playing = the four spines, alive.** They are the *same four shapes* — the triangle is just the spines folded into four contiguous wedges — so any state morphs cleanly into any other, and everything collapses back to the triangle when stopped.

## About the Design Files
The files in this bundle are **design references created in HTML/CSS/JS** — prototypes showing the intended look and motion, **not production code to copy**. The target app is **Flutter**; recreate the mark there as a `CustomPainter` widget (sketch included below), wired into the existing player/theme system. Use the HTML only to confirm shapes, colours, timings, and feel.

## Fidelity
**High-fidelity.** Colours, geometry, and motion timings are final. Reproduce the silhouette and the morph precisely; match the per-state timings within reason.

---

## The mark — geometry
All coordinates live in a **200 × 200 design box**. Scale uniformly to render size (`s = renderWidth / 200`). Corner radius is **5** design units (`5 * s`).

### Four upright spines (the base / "playing" shape)
Width **22**, top **y = 36**, bottom **y = 164** (height 128), gap **10**:
| bar | x | corners (TL, TR, BR, BL) |
|----|----|---|
| 0 | 41  | (41,36) (63,36) (63,164) (41,164) |
| 1 *(accent)* | 73  | (73,36) (95,36) (95,164) (73,164) |
| 2 | 105 | (105,36) (127,36) (127,164) (105,164) |
| 3 | 137 | (137,36) (159,36) (159,164) (137,164) |

### Play triangle (the "paused" shape)
The triangle is the four bars folded into four contiguous wedges (apex right at (159,100), left edge x=41 from y=36→164). Morphing bar→wedge by lerping corresponding corners gives the fold:
| slice | corners (TL, TR, BR, BL) |
|----|---|
| 0 | (41,36) (70.5,52) (70.5,148) (41,164) |
| 1 | (70.5,52) (100,68) (100,132) (70.5,148) |
| 2 | (100,68) (129.5,84) (129.5,116) (100,132) |
| 3 | (129.5,84) (159,100) (159,100) (129.5,116) |

> The triangle reads as **one solid shape** because the slices touch; only when they separate into bars do the gaps appear. For a standalone static play icon you can just draw the single triangle `M41 36 L159 100 L41 164 Z` with round line-joins.

### Static "logo" pose (for app icon / lockups, not animated)
Varied heights, width 22, radius 5: bar0 `x41 y60 h104`, **bar1 (accent) `x73 y40 h124`**, bar2 `x105 y76 h88`, bar3 `x137 y56 h108`.

### ⚠️ Spine "text" lines — DROP for the animated mark
The little title-lines drawn on each spine are a **large static-logo detail only**. At UI sizes and in any animation they smear into noise and muddy the silhouette. **The animated mark, the player button, and every in-app instance use the clean spines.** Reserve the text-lined version (`saga-mark-ink-textlines.png`) for big marketing/splash lockups only.

---

## Design tokens

### Core palette
| token | hex | use |
|---|---|---|
| ink | `#1C140F` | dark bg / neutral on light |
| cream | `#F2E7D6` | light bg / neutral on dark |
| terra | `#C2603C` | reverse theme bg / accent on light |
| amber | `#E8A24A` | primary accent, play triangle on dark |
| amber ramp | `#A4672B` `#C9863A` `#E8A24A` `#F4C277` | optional "spectrum" colouring (bar 0→3) |
| sub | `#CDBBA6` | secondary text / inactive icon |
| muted | `#8C7C6C` | tertiary text |

### Theme → mark colours
| theme | bg | neutral spines | accent bar (#1) + triangle |
|---|---|---|---|
| Ink (dark, default) | `#1C140F` | `#F2E7D6` | `#E8A24A` |
| Cream (light) | `#F2E7D6` | `#1C140F` | `#C2603C` |
| Terra (reverse) | `#C2603C` | `#F2E7D6` | `#1C140F` |

**Recommended colouring:** three neutral spines + the **second bar** as the accent (an off-centre focal point — with 4 bars there is no true middle). The whole play triangle is the accent colour. The amber ramp is an optional livelier alternative for the playing state.

---

## Wordmark
- **Typeface:** Manrope.
- **Weight:** **600 (SemiBold)** — *not* ExtraBold/800. The current in-app wordmark reads ~500–600; 600 is confident and legible at small sizes without shouting. Reserve 800 for very large hero-only moments.
- **Case / tracking:** lowercase `saga`, letter-spacing ≈ `-0.025em`.
- **Play triangle:** the existing `saga ▸` (word + small accent-coloured triangle) stays valid as the text logo; the 4-spine mark is the standalone icon/app-icon. They can also be locked together (mark + word). Triangle = the same accent colour as the mark's accent bar.

---

## States (one mark, many drivers)
`t` = morph value (0 = triangle, 1 = bars). `morph.forward()` on play, `morph.reverse()` on pause. Morph duration **≈460–480 ms**, easing **easeInOutCubic** (`cubic-bezier(.66,0,.34,1)`). Each state below sets `t` and a `levels[4]` (0..1) source; a per-bar `scaleY(level)` is applied about the noted origin. Always floor levels (~0.16) so bars never fully vanish.

| state | t | level source | origin | timing |
|---|---|---|---|---|
| **paused** | 0 | — (play triangle, **accent stripe**) | — | static |
| **playing** | 1 | loudness envelope (see below) | centre | live |
| **buffering** | 1 | staggered sine `0.3 + 0.7·((sin(phase − i·0.5)+1)/2)` | centre | ~1.4 s loop |
| **downloading** | 1 | determinate `clamp(progress·4 − i, 0.14, 1)` | **bottom** | tracks % |
| **breathing** (idle/splash) | 1 | `0.82 + 0.18·sin(phase·0.6)` all bars; +opacity 1→0.85 | centre | 2.4 s loop, staggered 0/.15/.3/.45 s |
| **finished** | 1 | one-shot overshoot: 1 → 0.42 → 1.18 → 0.94 → 1 | centre | ~1.4 s, staggered 0/.08/.16/.24 s |

### ⚠️ Alignment — centre all states EXCEPT downloading
Every state scales **about the vertical centre** (`transform-origin: center`) — **except `downloading`, which is bottom-anchored** (`transform-origin: bottom`) so it reads literally as "filling up from the floor." The mark's identity is the centred form that folds into the play triangle, so centring the other states keeps the optical centre fixed → any of them crossfades into another with no vertical jump, and the mark shares one baseline with the wordmark. Downloading is the single, deliberate exception (its fill metaphor is worth the anchor change; the transition into/out of it is brief and reads fine).

### Playing = loudness, NOT FFT
This is **speech** (audiobooks), so an FFT spectrum looks like meaningless static. Drive the bars from an **RMS loudness envelope**: one master level, rippled across the four bars with small per-bar phase offsets and smoothing.
```
master += (rmsTarget − master) * 0.12;            // smooth
levels[i] = clamp(master + 0.18*sin(phase*rate[i] + off[i]), 0.16, 1);
// rate = [1, 1.6, 1.3, 2.0]   off = [0, 1.1, 2.3, 3.4]
```

### Accent stripe carries through EVERY state
The accent (spine #2, amber) is the mark's signature and must read the same in every state — it's a **stripe in the meter**, a **vertical stripe through the play triangle** (triangle is cream with the #2 slice amber — *not* solid amber), and the **left bar** in pause mode. Same spine, same horizontal position, every state.

### Setting — Now-playing animation: Reactive vs Pause bars
A user setting (e.g. **Settings › Player › Now-playing animation**) picks what the *playing* state becomes:
- **Reactive** (default) — the 4 spines spread into the loudness meter above.
- **Pause bars** — the 4 spines fold into a standard two-bar pause: spines 1+2 x-merge into the left bar, 3+4 into the right. Static (ignores audio). The accent spine (#2) lands in the **left** bar → **amber-left / cream-right**. Default reduced-motion users to this.

The paused→playing morph is identical for both; only the playing end-state differs. In Flutter it's one flag on the painter — `targetFor(playing, reactive, levels)` returns `levels` (reactive) or `[1,1,1,1]` with x-merged bar centres `[72,72,128,128]` (pause). See `Saga Pause-bar Option.html`.

## Flutter implementation

```dart
class SpinePainter extends CustomPainter {
  SpinePainter({required this.t, required this.levels, required this.neutral, required this.accent});
  final double t;             // 0 = triangle, 1 = bars
  final List<double> levels;  // 4 heights, 0..1
  final Color neutral, accent;

  static const tri = [
    [Offset(41,36),   Offset(70.5,52),  Offset(70.5,148), Offset(41,164)],
    [Offset(70.5,52), Offset(100,68),   Offset(100,132),  Offset(70.5,148)],
    [Offset(100,68),  Offset(129.5,84), Offset(129.5,116),Offset(100,132)],
    [Offset(129.5,84),Offset(159,100),  Offset(159,100),  Offset(129.5,116)],
  ];
  static const bar = [
    [Offset(41,36), Offset(63,36),  Offset(63,164),  Offset(41,164)],
    [Offset(73,36), Offset(95,36),  Offset(95,164),  Offset(73,164)],
    [Offset(105,36),Offset(127,36), Offset(127,164), Offset(105,164)],
    [Offset(137,36),Offset(159,36), Offset(159,164), Offset(137,164)],
  ];

  @override
  void paint(Canvas c, Size size) {
    final s = size.width / 200.0;
    for (var i = 0; i < 4; i++) {
      final p  = List.generate(4, (k) => Offset.lerp(tri[i][k], bar[i][k], t)!);
      final cy = (p[0].dy + p[2].dy) / 2;                       // bar centre
      final h  = lerpDouble(1, levels[i].clamp(.16, 1), t)!;    // only scale in bar mode
      final q  = p.map((o) => Offset(o.dx, cy + (o.dy - cy) * h) * s).toList();
      c.drawPath(Path()..addPolygon(q, true),
                 Paint()..isAntiAlias = true..color = i == 1 ? accent : neutral);
      // (optional) round corners: build the path with arcs instead of addPolygon.
    }
  }

  @override
  bool shouldRepaint(SpinePainter o) => o.t != t || o.levels != levels;
}
```
Host it in a `StatefulWidget` with one `AnimationController` for `t` (the morph) and a `Ticker`/stream that updates `levels` for the active state. For the **playing** RMS source: Android `Visualizer` API or iOS `AVAudioEngine` tap → vDSP RMS; or, for zero platform code, a synthetic envelope (phase-shifted sines gated on `isPlaying`) — for narration it reads just as well.

---

## Assets (in `assets/`)
PNGs at 1024², transparent unless noted. Regenerate at other sizes from the geometry above.
- `saga-mark-ink.png` — clean 4-spine, cream spines + amber accent (for dark UI)
- `saga-mark-cream.png` — ink spines + terra accent (for light UI)
- `saga-mark-terra.png` — cream spines + ink accent (reverse theme)
- `saga-play-triangle-amber.png` — the play triangle, **cream with the amber accent stripe** (slice #2)
- `saga-pause-bars.png` — two-tone pause: amber-left / cream-right (the Pause-bars setting)
- `saga-appicon-1024.png` — ink rounded-square icon with the mark
- `saga-mark-ink-textlines.png` — **large-lockup-only** variant with spine text lines (do NOT use in UI/animation)

### Monochrome (notification shade / status bar / tinted surfaces)
Flat single-colour silhouette of the resting 4-spine pose — **no accent bar, no text lines**.
- `saga-mono-white.png` — 1024², white on transparent (dark / tinted surfaces, iOS template image)
- `saga-mono-black.png` — 1024², black on transparent (light surfaces, docs)
- `notification/saga-notification-{mdpi-24,hdpi-36,xhdpi-48,xxhdpi-72,xxxhdpi-96}.png` — white density set for the Android small icon (drawn at ~66% safe-zone)

**Android rule:** the notification small icon MUST be white-on-transparent — the OS tints the silhouette and discards any colour. Ship the density set as the `ic_stat_saga` drawable. **iOS:** use `saga-mono-white.png` as a template image for Control Center / lock-screen player glyphs.

## Files (HTML design references)
- `Saga Animated Mark v3.html` — **canonical**: morph + all six states + per-state Flutter notes + the stripes rule
- `Saga Monochrome Mark.html` — flat white/black silhouette, Android status bar + notification shade mock, density set
- `Saga Pause-bar Option.html` — the Reactive-vs-Pause-bars setting; working toggle, two-tone pause, accent-striped triangle
- `Saga 4-Spine Audio-reactive.html` — the loudness-reactive playing state, colour treatments, Flutter painter
- `Saga Player Mark in Context.html` — the mark as the real Now-Playing / mini-player transport (in app colours)
- `Saga Wordmark and Alignment.html` — Manrope weight ladder (→ 600) + centred-vs-shelf rationale + lockups
