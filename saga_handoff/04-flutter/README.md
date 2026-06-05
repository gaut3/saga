# Saga — Flutter handoff

Drop-in Dart/Flutter implementation of the Saga brand: colors, the stacked-spines mark (static + animated), the wordmark, and the lockup. Pure Flutter — no platform channels, no WebViews, no SVG dependencies.

---

## Folder layout

```
design_handoff_saga_flutter/
├── README.md                          ← you are here
├── lib/saga_brand/
│   ├── saga_brand.dart                ← barrel export — import this
│   ├── saga_colors.dart               ← SagaColors + SagaTheme tokens
│   ├── saga_mark.dart                 ← static mark (CustomPaint)
│   ├── animated_saga_mark.dart        ← playing / breathing / loading / paused
│   ├── saga_wordmark.dart             ← "saga ▶" — needs Manrope 800
│   └── saga_lockup.dart               ← mark + wordmark
└── example/main.dart                  ← demo screen with state switcher
```

---

## Install

### 1. Copy the package into your app

```bash
cp -R design_handoff_saga_flutter/lib/saga_brand <your_flutter_app>/lib/
```

### 2. Add Manrope to your project

The wordmark requires **Manrope 800**. Pick one of:

**Option A — google_fonts package (easiest):**

```yaml
# pubspec.yaml
dependencies:
  google_fonts: ^6.2.1
```

Then in your app entry point, set Manrope as the default text font once:

```dart
import 'package:google_fonts/google_fonts.dart';

MaterialApp(
  theme: ThemeData(
    textTheme: GoogleFonts.manropeTextTheme(Theme.of(context).textTheme),
  ),
  ...
)
```

The `SagaWordmark` widget reads `fontFamily: 'Manrope'` by default, which will resolve to the Google Fonts copy automatically as long as the family is registered in your theme.

**Option B — bundle the TTF (offline-safe, app-store-friendly):**

Download `Manrope-ExtraBold.ttf` (and any other weights you use) from the Manrope GitHub release, drop it into `assets/fonts/`, then:

```yaml
# pubspec.yaml
flutter:
  fonts:
    - family: Manrope
      fonts:
        - asset: assets/fonts/Manrope-ExtraBold.ttf
          weight: 800
```

### 3. Import and use

```dart
import 'package:your_app/saga_brand/saga_brand.dart';
```

---

## Quick start

```dart
import 'package:flutter/material.dart';
import 'package:your_app/saga_brand/saga_brand.dart';

// Static mark
SagaMark(size: 40, theme: SagaTheme.ink);

// Animated mark
AnimatedSagaMark(
  size: 48,
  theme: SagaTheme.ink,
  state: SagaMarkState.playing,
);

// Wordmark (needs Manrope, see above)
SagaWordmark(size: 32, theme: SagaTheme.cream);

// Full lockup — mark + wordmark
SagaLockup(
  size: 40,
  theme: SagaTheme.cream,
  markState: SagaMarkState.playing,   // optional: animate the mark
);
```

The `example/main.dart` file is a ready-to-run showcase. Drop it next to your existing `main.dart` and run.

---

## The four states

| State                     | Loop          | Character                                  | Use it for                                                |
|---------------------------|---------------|--------------------------------------------|-----------------------------------------------------------|
| `SagaMarkState.paused`    | —             | static logo (matches the brand reference)  | default, idle, screenshots                                |
| `SagaMarkState.playing`   | 0.9–1.7s      | each spine pulses on its own rhythm        | now-playing affordance (mini player, lock screen, badge)  |
| `SagaMarkState.breathing` | 2.4s          | gentle 88%-scale + slight opacity fade     | splash, app launch, "alive" hints                         |
| `SagaMarkState.loading`   | 1.6s          | staggered fill from short to tall          | buffering, Plex sync, downloading offline                 |

State swaps are hot — change the `state` prop and `didUpdateWidget` will spin up / spin down controllers smoothly. No need to rebuild the widget tree.

---

## Theme

Three palettes, picked by the surface the mark is sitting on (NOT the user's dark-mode preference):

```dart
SagaTheme.cream   // for cream / paper / light backgrounds
SagaTheme.ink     // for ink / dark backgrounds
SagaTheme.terra   // for terracotta backgrounds
```

Each theme bundles the spine colors (`markSide`, `markMiddle`, `markSideDot`, `markMidDot`), plus the foreground / muted / accent colors you'd typically pull in surrounding text styles. The raw palette is in `SagaColors`:

```dart
SagaColors.cream      // #F4EAD8
SagaColors.ink        // #1E1410
SagaColors.terracotta // #C25A3A
SagaColors.amber      // #E0A050
// ...
```

---

## Recommended places to use each state in the app

| Screen / surface          | State            | Notes                                               |
|---------------------------|------------------|-----------------------------------------------------|
| App splash on launch      | `breathing`      | crossfade to `paused` once first paint completes    |
| Mini player (bottom bar)  | `playing` / `paused` | drives off your audio service's `isPlaying`     |
| Now-playing full screen   | `playing` / `paused` | larger size — 96-128px                          |
| Lock-screen / Now Playing widget | `playing` (small) | use 24-32px next to track time                |
| Library sync banner       | `loading`        | show while Plex sync is running                      |
| Per-book "downloading" tile | `loading` (24px) | swap to ✓ icon when complete                       |
| Settings → About row icon | `paused`         | static — that's the brand mark, not a status        |

---

## Accessibility

- Every widget includes a `Semantics(label: 'Saga')` wrapper by default; pass `semanticLabel: null` for decorative usage (e.g., inside a button that already has its own label).
- The animated mark sets `liveRegion: true` for `playing` and `loading` states so screen readers can announce playback start.
- `MediaQuery.disableAnimations` is respected automatically — if the user has reduced-motion preferences on, the mark falls back to the static pose silently.

---

## Performance

- The animated mark uses `CustomPaint` with three `AnimationController`s (`playing`) or one shared controller (`breathing` / `loading`). All work is per-frame paint, not layout.
- `AnimatedBuilder` listens to a `Listenable.merge` of the active controllers, so the painter only repaints when something actually changed.
- Idle (`paused`) state stops every controller — zero CPU until the state changes.

If you're rendering the mark in many list cells simultaneously (e.g., one per book during a library sync), keep them at `SagaMarkState.paused` outside the visible viewport — `AnimatedSagaMark` doesn't auto-pause off-screen.

---

## Optional: drive the bars from real audio

The spines are individually addressable inside `SagaMarkPainter` (`leftScale`, `midScale`, `rightScale`). To replace the canned animation with real audio levels, write a wrapper widget that drives those props from your audio service's level stream:

```dart
class AudioLevelMark extends StatelessWidget {
  final Stream<({double low, double mid, double high})> levels;
  final SagaTheme theme;
  final double size;

  const AudioLevelMark({super.key, required this.levels, this.theme = SagaTheme.ink, this.size = 40});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: levels,
      builder: (ctx, snap) {
        final v = snap.data ?? (low: 1.0, mid: 1.0, high: 1.0);
        return CustomPaint(
          size: Size(size, size),
          painter: SagaMarkPainter(
            theme: theme,
            flat: false,
            leftScale: v.low, midScale: v.mid, rightScale: v.high,
            leftOpacity: 1, midOpacity: 1, rightOpacity: 1,
          ),
        );
      },
    );
  }
}
```

This gives you the same visual language as the canned `playing` state, but reactive to the actual audio. Drop it into the now-playing screen for that little extra delight.

---

## Don'ts

- Don't animate the title-line ornaments — they're intentionally static. The contrast between moving spines and held ornaments is what makes the motion read as books, not just bars.
- Don't speed the playing animation below 0.9s for any spine. Faster reads as ECG / alarm, not music.
- Don't apply `loading` state to a now-playing indicator while audio is actually playing — it implies the app is stuck.
- Don't put `AnimatedSagaMark` inside an `AnimatedBuilder` that already rebuilds every frame; that fights the internal optimizations.

---

## Where the design comes from

These widgets are a direct port of the CSS animations and SVG geometry in `design_handoff_saga_brand/` and `design_handoff_saga_animations/`. If you change the brand spec (colors, geometry, timing), update those folders first, then port the change here — they're the source of truth.

Live preview of the same animations on web: `Saga Animated Mark.html` in the project root.
