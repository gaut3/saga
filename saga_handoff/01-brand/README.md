# Handoff: Saga brand identity

Audiobook player for Plex — visual identity package for implementation in the app.

---

## What's in this package

```
design_handoff_saga_brand/
├── README.md                    ← you are here
├── brand-reference.html         ← open in a browser; visual source of truth
├── tokens.css                   ← drop-in CSS custom properties
├── saga-mark-animations.css     ← optional: animated playing/breathing/loading states
├── components/
│   └── SagaMark.tsx             ← React (TS) components: <SagaMark>, <SagaWordmark>, <SagaLockup>
└── assets/
    ├── mark/
    │   ├── saga-mark-{cream,ink,terracotta}.svg        ← transparent
    │   └── saga-mark-{cream,ink,terracotta}-bg.svg     ← on-background, app-icon-ready
    ├── wordmark/
    │   ├── saga-wordmark-{cream,ink,terracotta}.svg    ← transparent
    │   └── saga-wordmark-{cream,ink,terracotta}-bg.svg
    └── lockup/
        ├── saga-lockup-{cream,ink,terracotta}.svg      ← mark + wordmark
        └── saga-lockup-{cream,ink,terracotta}-bg.svg
```

---

## About these files

**These files are design references**, not production code to ship as-is. The HTML is a static mock of the intended look — your job is to recreate the same visual system in **the target codebase's existing environment** (React Native, SwiftUI, web React, Vue, etc.) using its established conventions and component library. If the project doesn't have an environment yet, pick the most appropriate framework for the platform and implement from there.

The implementation primitives you'll actually want to import:

- **`tokens.css`** — the implementation source of truth. All colors, type, spacing, radii, and theme switches. Use the variables; don't hardcode hex values in components.
- **`components/SagaMark.tsx`** — the mark and wordmark as React components. If you're not using React, port the same SVG structure to your framework.
- **`assets/**/*.svg`** — static SVGs for places where you can't render a component (favicons, OG images, README badges, marketing pages, app icons).

## Fidelity

**High-fidelity.** Colors, type, geometry, and proportions are final. Recreate the mark, wordmark, and color theming pixel-perfectly. Layout/copy in the "in context" surfaces is illustrative — the brand bits inside them (mark colors, wordmark treatment, label-mono styling) are what's specified.

---

## The system at a glance

**Two brand elements:**
1. **The mark** — three stacked book-spine rectangles. The middle spine is taller and uses the accent color; reads as both a row of books and an audio level meter.
2. **The wordmark** — the word "saga" in Manrope 800, all lowercase, with tight negative tracking (`-0.055em`), followed by a small play-triangle in the accent color.

**Three palettes** — all three are supported and should be selectable:
- **Cream** — default / light. Page = `#F4EAD8`, ink = `#1E1410`, accent = `#C25A3A` terracotta.
- **Ink** — dark mode. Page = `#1E1410`, ink = `#F4EAD8` cream, accent = `#E0A050` amber.
- **Terracotta** — reverse / loud. Page = `#C25A3A`, ink = `#F4EAD8` cream, accent = `#1E1410`.

Theme switching should be driven by the `data-theme` attribute on the `<html>` element (web) or the equivalent root-level toggle on native. Default to `cream` for first-run; respect the OS dark-mode preference if no explicit user choice exists (the `@media (prefers-color-scheme: dark)` rule in `tokens.css` handles that automatically for the web).

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

Semantic tokens (these flip per theme — always prefer these in components):
`--saga-bg`, `--saga-surface`, `--saga-surface-alt`, `--saga-fg`, `--saga-fg-muted`, `--saga-fg-subtle`, `--saga-border`, `--saga-accent`, `--saga-accent-fg`, `--saga-mark-side`, `--saga-mark-middle`.

### Typography

- **Display & UI:** Manrope, weights 400 / 500 / 600 / 700 / **800** (800 is required for the wordmark).
- **Mono labels:** JetBrains Mono, weights 400 / 500.
- Both available on Google Fonts. Web import:

  ```html
  <link href="https://fonts.googleapis.com/css2?family=Manrope:wght@400;500;600;700;800&family=JetBrains+Mono:wght@400;500&display=swap" rel="stylesheet">
  ```

  Native: bundle the Manrope and JetBrains Mono TTFs from Google Fonts.

| Use                       | Family            | Weight | Tracking     |
|---------------------------|-------------------|--------|--------------|
| Wordmark                  | Manrope           | 800    | -0.055em     |
| Display / large headings  | Manrope           | 800    | -0.035em     |
| H1 / H2                   | Manrope           | 700    | -0.025em     |
| Body                      | Manrope           | 400/500| -0.01em      |
| Mono caption / metadata   | JetBrains Mono    | 400    | 0.12em UPPER |

### Radii & spacing

- Radii: `6`, `10`, `16`, `24` px. App-icon mask: `22.5%`.
- Spacing scale (4 px base): `4 · 8 · 12 · 16 · 24 · 32 · 48 · 64`.
- Shadows are **warm-tinted**, built from `rgba(30, 20, 16, …)` — never pure black.

---

## The mark — exact geometry

200 × 200 canvas, all coordinates in canvas units:

| Element              | x, y     | w × h      | Radius | Fill          |
|----------------------|----------|------------|--------|---------------|
| Left spine           | 30, 56   | 32 × 100   | 4      | `--mark-side` |
| Middle spine (taller)| 74, 36   | 32 × 140   | 4      | `--mark-mid`  |
| Right spine          | 118, 68  | 32 × 80    | 4      | `--mark-side` |
| Title line (side ×4) | various  | 16/10 × 2  | 0      | accent @0.7   |
| Title line (mid ×2)  | 82, 58/66| 16/10 × 2  | 0      | bg @0.5       |

Side rectangles are 12 units apart. Clearspace: leave at least 22 units (≈ one spine-width) of empty space on every side. Minimum legible size: **24 px square**. Below that, prefer the wordmark only.

The recommended primary mark is in cream theme. See `assets/mark/saga-mark-cream-bg.svg` for the canonical SVG.

---

## The wordmark — exact construction

```
font-family : Manrope, system-ui, sans-serif
font-weight : 800
font-size   : varies (recommend 16 px minimum for UI, 32 px+ for marquee)
letter-spacing : -0.055em
case        : all lowercase ("saga", never "Saga" or "SAGA")
color       : --saga-fg (theme-flipped)
```

Followed by a small play-triangle in `--saga-accent`:
- Triangle width = `0.42em` of the wordmark's font-size
- Gap between word and triangle = `0.14em`
- Vertical centering: align triangle to the optical center of the "a" x-height
- Triangle path: `M 8 4 L 34 20 L 8 36 Z` in a `0 0 40 40` viewBox

The triangle is **always** present in the wordmark — it's not optional ornament. Drop it only when space requires text-only (e.g., 12 px footer credits).

---

## Lockup rules

**Horizontal lockup** (mark on left, wordmark on right):
- Mark size = `1.15 ×` wordmark font-size (so the mark visually equals the cap height of the "g" descender)
- Gap = `0.3 ×` wordmark font-size
- Vertical center alignment

**Stacked lockup** (mark above wordmark):
- Use only on splash screens, welcome surfaces, and tall narrow placements
- Mark size 1.3-1.6× the wordmark size
- 12-16 px vertical gap

**Don't:**
- Don't rotate the mark.
- Don't recolor individual spines outside the three sanctioned palettes.
- Don't change the triangle to any other shape (circle, square, custom).
- Don't capitalize "saga".
- Don't apply drop shadows to the wordmark or mark.
- Don't place the cream wordmark on an amber background (insufficient contrast).

---

## App icon

The on-background SVG variants (`saga-mark-{theme}-bg.svg`) are sized for app-icon use:
- 200 × 200 canvas
- Background fill with `border-radius: 44` (matches iOS app-icon `22.5%` superellipse approximation)
- Mark sits centered with `~22 unit` clearspace on every side

For production iOS / Android icons, export the desired theme at the platform's required sizes (1024² master + scaled outputs). The sunset gradient variant shown in `brand-reference.html` is an **alternate marketing icon**, not the default — ship `cream` as the default light icon and `ink` as the default dark icon.

---

## Theming pattern (recommended)

### Web (CSS)

```html
<html data-theme="cream"> <!-- "cream" | "ink" | "terra" -->
  <head>
    <link rel="stylesheet" href="tokens.css">
  </head>
  <body>
    <div style="background: var(--saga-bg); color: var(--saga-fg);">
      <SagaLockup size={40} />
    </div>
  </body>
</html>
```

```js
// switch themes at runtime:
document.documentElement.dataset.theme = "ink";
```

### React Native / SwiftUI / etc.

Mirror the same three semantic palettes as a `ThemeProvider` context with the same token names. The mark component should accept a `theme` prop ("cream" | "ink" | "terra") for places where it needs to differ from the surrounding surface (e.g., a lockup rendered over a hero image).

---

## How to use the components

```tsx
import { SagaMark, SagaWordmark, SagaLockup } from "./components/SagaMark";

// inherits the surrounding theme via CSS vars
<SagaLockup size={48} />

// pin to a specific palette regardless of surrounding theme
<SagaMark size={24} theme="terra" />
<SagaWordmark size={32} theme="ink" />
```

`SagaMark` falls back to `--saga-mark-side` / `--saga-mark-middle` when no `theme` prop is given. `SagaWordmark` falls back to `--saga-fg` / `--saga-accent`.

---

## Animated states

The mark has three motion variants for in-app moments. Load `saga-mark-animations.css` alongside `tokens.css`, then pass a `state` prop (or set `data-state` on the SVG):

| State        | Use for                       | Loop      | Character                                 |
|--------------|-------------------------------|-----------|-------------------------------------------|
| `paused`     | default — static logo          | —         | matches the brand reference exactly        |
| `playing`    | now-playing affordance         | 0.9–1.7s  | VU-meter pulse, each spine its own rhythm  |
| `breathing`  | splash / idle / "alive" hint   | 2.4s      | gentle 88%-scale + slight opacity fade     |
| `loading`    | buffering / Plex sync          | 1.6s      | staggered fill from short to tall          |

```tsx
<SagaMark size={32} state="playing" />
<SagaMark size={80} state="breathing" theme="terra" />
```

Animations are pure CSS, no JS. The CSS file includes a `prefers-reduced-motion` guard that disables all animations when the user has motion sensitivity preferences enabled.

See `Saga Animated Mark.html` (project root) for a live preview with all three variants.

---

## Accessibility

- All three palette pairings meet WCAG AA for normal text (≥ 4.5:1) when using `--saga-fg` on `--saga-bg`. Verified:
  - Cream `#F4EAD8` ↔ Ink `#1E1410` — **17.5 : 1**
  - Ink `#1E1410` ↔ Cream `#F4EAD8` — **17.5 : 1**
  - Terracotta `#C25A3A` ↔ Cream `#F4EAD8` — **4.7 : 1** (AA normal, not AAA)
- The accent colors should **not** be used as primary text on their default backgrounds (e.g., amber on ink is for icons/highlights, not body copy).
- The mark has an `aria-label="Saga"` when rendered as a meaningful element, and `role="presentation"` when decorative. Pass `title=""` to suppress.

---

## Surfaces shown in `brand-reference.html`

| Section | What to copy |
|---------|--------------|
| 01 Primary lockup | The mark + wordmark spacing and color pairing in each theme |
| 02 App icons | Background fill + mark inset for app-tile rendering |
| 03 Palette | Exact hex values and role assignments |
| 04 In context | How the brand reads inside a library tile, mini player, and welcome splash — copy the structure and label-mono usage, not the literal layout |
| 05 Construction | The 200u canvas geometry for the mark |
| 06 Wordmark | Type detail at marquee size |

---

## Open the reference

```bash
open brand-reference.html
```

Or serve the folder with any static server. The file is self-contained except for the Google Fonts CDN.

---

## Files (project-relative)

- `Saga Logo.html` — the original full exploration canvas, with all 8 mark candidates and rejected directions for reference
- `design_handoff_saga_brand/` — this package
