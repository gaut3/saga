# Handoff: Saga brand identity

Audiobook player for Plex — visual identity foundations for implementation in the app.

---

## What's in this package

```
01-brand/
├── README.md                    ← you are here
├── brand-reference.html         ← open in a browser; visual source of truth
├── tokens.css                   ← drop-in CSS custom properties
└── saga-mark-animations.css     ← animated playing/breathing/loading states (CSS only)
```

For the **animated 4-spine mark** geometry, states, and Flutter painter — see `../02-mark/`.

---

## About these files

**These files are design references**, not production code to ship as-is. The HTML is a static mock of the intended look — your job is to recreate the same visual system in the target codebase's existing environment using its established conventions.

The implementation primitives you'll actually want:

- **`tokens.css`** — the implementation source of truth. All colors, type, spacing, radii, and theme switches. Use the variables; don't hardcode hex values in components.
- **`assets/**/*.svg`** — static SVGs for places where you can't render a component (favicons, OG images, README badges, marketing pages, app icons). Located in `../assets/`.

---

## The system at a glance

**Two brand elements:**
1. **The mark** — four book-spine rectangles that double as the play/pause control. See `../02-mark/` for the full animated spec.
2. **The wordmark** — the word "saga" in Manrope 600, all lowercase, with tight negative tracking (`-0.025em`), followed by a small play-triangle in the accent color.

**Three palettes** — all three are supported and should be selectable:
- **Ink** — dark mode (default). Page = `#1E1410`, ink = `#F4EAD8` cream, accent = `#E0A050` amber.
- **Cream** — light. Page = `#F4EAD8`, ink = `#1E1410`, accent = `#C25A3A` terracotta.
- **Terra** — reverse / loud. Page = `#C25A3A`, ink = `#F4EAD8` cream, accent = `#1E1410`.

Theme switching should be driven by the `data-theme` attribute on the `<html>` element (web) or the equivalent root-level toggle on native.

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

- **Display & UI:** Manrope, weights 400 / 500 / 600 / 700.
- **Mono labels:** JetBrains Mono, weights 400 / 500.

```html
<link href="https://fonts.googleapis.com/css2?family=Manrope:wght@400;500;600;700&family=JetBrains+Mono:wght@400;500&display=swap" rel="stylesheet">
```

| Use                       | Family            | Weight | Tracking     |
|---------------------------|-------------------|--------|--------------|
| Wordmark                  | Manrope           | 600    | -0.025em     |
| Display / large headings  | Manrope           | 700    | -0.025em     |
| H1 / H2                   | Manrope           | 700    | -0.015em     |
| Body                      | Manrope           | 400/500| -0.01em      |
| Mono caption / metadata   | JetBrains Mono    | 400    | 0.12em UPPER |

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
- Don't recolor individual spines outside the three sanctioned palettes.
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

## Theming pattern (recommended)

### Web (CSS)

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

### React Native / SwiftUI / etc.

Mirror the same three semantic palettes as a `ThemeProvider` context with the same token names. The mark component should accept a `theme` prop ("ink" | "cream" | "terra") for places where it needs to differ from the surrounding surface.

---

## Accessibility

- All three palette pairings meet WCAG AA for normal text (≥ 4.5:1) when using `--saga-fg` on `--saga-bg`:
  - Cream `#F4EAD8` ↔ Ink `#1E1410` — **17.5 : 1**
  - Terracotta `#C25A3A` ↔ Cream `#F4EAD8` — **4.7 : 1** (AA normal)
- Accent colors should **not** be used as primary text on their default backgrounds.
- Terra theme: secondary text must sit on `--saga-surface` (`#9E4128`), not `--saga-bg`, to clear AA.
- The mark has an `aria-label="Saga"` when rendered as a meaningful element, and `role="presentation"` when decorative.
