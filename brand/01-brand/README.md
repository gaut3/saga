# Saga brand foundations

Colour, type, spacing and theming for the Saga audiobook player. The system is
**shipped** — `saga/lib/core/theme/saga_theme.dart` (`SagaColors`, `SagaThemeData`)
is where these values live in the app, and it is the authority when the two
disagree. This document explains the intent behind them.

```
01-brand/
├── README.md      ← you are here
└── tokens.css     ← the same palettes as CSS custom properties, for web surfaces
```

For the **animated 4-spine mark** geometry, states, and painter spec — see `../02-mark/`.
For static SVG exports (favicons, OG images, README badges, app icons) — see `../assets/`.

---

## The system at a glance

**Two brand elements:**
1. **The mark** — four book-spine rectangles that double as the play/pause control. See `../02-mark/` for the full animated spec.
2. **The wordmark** — the word "saga" in Manrope 600, all lowercase, with tight negative tracking (`-0.025em`), followed by a small play-triangle in the accent color.

**Four palettes**, all selectable in Settings:
- **Ink** — dark mode (default). Page = `#1E1410`, ink = `#F4EAD8` cream, accent = `#E0A050` amber.
- **Cream** — light. Page = `#F4EAD8`, ink = `#1E1410`, accent = `#C25A3A` terracotta.
- **Terra** — reverse / loud. Page = `#C25A3A`, ink = `#F4EAD8` cream, accent = `#1E1410`.
- **Onyx** — true-black OLED. Page = `#000000` (those pixels are physically off), surfaces warm near-black `#0C0908` / `#16100D`, ink = `#E4D9C6` softened so nothing blooms in the dark, accent = `#E0A050` amber.

In the app the variant is a `SagaThemeVariant` enum persisted **by index**, so `onyx`
must stay last-appended — adding a theme in the middle silently repaints everyone's
app. On web, theme switching is driven by the `data-theme` attribute on `<html>`.

---

## Design tokens

### Colors

| Token                 | Hex       | Role                                  |
|-----------------------|-----------|---------------------------------------|
| `--saga-cream`        | `#F4EAD8` | Page surface (light)                  |
| `--saga-paper`        | `#EFE3CE` | Alt surface, warmer                   |
| `--saga-linen`        | `#E8D8BD` | Alt surface, deeper                   |
| `--saga-ink`          | `#1E1410` | Primary text (light), surface (dark)  |
| `--saga-ink-soft`     | `#3A2A20` | Secondary text on cream               |
| `--saga-terracotta`   | `#C25A3A` | Brand primary, accent on cream        |
| `--saga-terra-deep`   | `#9E4128` | Brand pressed-state, alt surface      |
| `--saga-amber`        | `#E0A050` | Accent on ink (dark mode)             |
| `--saga-amber-soft`   | `#EAB877` | Hover / highlight on ink              |
| `--saga-rose`         | `#A85C4A` | Tertiary / utility                    |

Semantic tokens (flip per theme — always prefer these in components):
`--saga-bg`, `--saga-surface`, `--saga-surface-alt`, `--saga-fg`, `--saga-fg-muted`, `--saga-fg-subtle`, `--saga-border`, `--saga-accent`, `--saga-accent-fg`, `--saga-mark-side`, `--saga-mark-middle`.

### Typography

**Manrope, weights 400 / 500 / 600 / 700** — one family, everywhere.

| Use                       | Family  | Weight  | Tracking |
|---------------------------|---------|---------|----------|
| Wordmark                  | Manrope | 600     | -0.025em |
| Display / large headings  | Manrope | 700     | -0.025em |
| H1 / H2                   | Manrope | 700     | -0.015em |
| Body                      | Manrope | 400/500 | -0.01em  |

**The app bundles the font; it does not fetch it.** `saga/assets/fonts/Manrope-VariableFont_wght.ttf`
is declared in `pubspec.yaml` and loaded locally — Saga makes no request to Google Fonts
or any other third party, and the privacy claims in the README depend on that staying true.
Web surfaces may link the Google Fonts CDN (the landing page does); the app may not.

An earlier draft of this system specified JetBrains Mono for caption and metadata labels.
Nothing uses it — not the app, not the landing page — so it isn't part of the system.

### Radii & spacing

- Radii: `6`, `10`, `16`, `24` px. App-icon mask: `22.5%`.
- Spacing scale (4 px base): `4 · 8 · 12 · 16 · 24 · 32 · 48 · 64`.
- Shadows are **warm-tinted**, built from `rgba(30, 20, 16, …)` — never pure black.

---

## The wordmark — exact construction

```
font-family    : Manrope, system-ui, sans-serif
font-weight    : 600
letter-spacing : -0.025em
case           : all lowercase ("saga", never "Saga" or "SAGA")
color          : --saga-fg (theme-flipped)
```

Followed by a small play-triangle in `--saga-accent`:
- Triangle width = `0.42em` of the wordmark's font-size
- Gap between word and triangle = `0.14em`
- Vertical centering: align triangle to optical center of x-height
- Triangle path: `M 8 4 L 34 20 L 8 36 Z` in a `0 0 40 40` viewBox

The triangle is **always** present in the wordmark. Drop it only when space requires text-only (e.g., 12 px footer credits).

---

## Lockup rules

**Horizontal lockup** (mark on left, wordmark on right):
- Mark size = `1.15 ×` wordmark font-size
- Gap = `0.3 ×` wordmark font-size
- Vertical center alignment

**Don't:**
- Don't rotate the mark.
- Don't recolor individual spines outside the sanctioned palettes.
- Don't change the triangle to any other shape.
- Don't capitalize "saga".
- Don't apply drop shadows to the wordmark or mark.
- Don't place the cream wordmark on an amber background (insufficient contrast).

---

## App icon

The on-background SVG variants (`../assets/svg/mark/saga-mark-{theme}-bg.svg`) are sized for app-icon use:
- 200 × 200 canvas
- Background fill with `border-radius: 44` (matches iOS app-icon `22.5%` superellipse approximation)
- Mark sits centered with `~22 unit` clearspace on every side

---

## Theming pattern

### In the app (Flutter)

`SagaColors` exposes the active `SagaThemeData`; widgets read `SagaColors.bg`, `.fg`,
`.accent` and so on. Anything that must repaint on a theme change has to
`ref.watch(sagaThemeVariantProvider)` **inside its own `build`** — a `const` widget
won't get there on a parent rebuild.

### On web (CSS)

```html
<html data-theme="ink"> <!-- "ink" | "cream" | "terra" -->
  <head>
    <link rel="stylesheet" href="tokens.css">
  </head>
</html>
```

```js
document.documentElement.dataset.theme = "cream";
```

`tokens.css` carries the three original palettes. Onyx is app-only — no web surface
has needed a true-black variant yet.

---

## Accessibility

- Contrast for `--saga-fg` on `--saga-bg`:
  - Cream `#F4EAD8` ↔ Ink `#1E1410` — **17.5 : 1**
  - Terracotta `#C25A3A` ↔ Cream `#F4EAD8` — **4.7 : 1** (AA normal)
  - Onyx `#000000` ↔ `#E4D9C6` — comfortably AA; the foreground is deliberately
    *below* pure cream so it doesn't bloom against true black during night listening.
- Accent colors should **not** be used as primary text on their default backgrounds.
- Terra theme: secondary text must sit on `--saga-surface` (`#9E4128`), not `--saga-bg`, to clear AA.
- The mark has an `aria-label="Saga"` when rendered as a meaningful element, and `role="presentation"` when decorative.
