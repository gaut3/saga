# Saga — brand (canonical)

Single source of truth for the Saga audiobook player's visual system. Everything in
this folder is **current**. Superseded material lives in `../Old design/` (kept locally
for reference, not tracked in git, not for building from).

The mark is **four spines** that fold into a play triangle, and the wordmark is
Manrope 600. Anything describing a three-spine mark or a Manrope-800 wordmark is
superseded and belongs in the archive, not here.

---

## What's inside

```
brand/
├── README.md          ← you are here
├── 01-brand/          ← foundations: colour tokens, type, theming, accessibility
├── 02-mark/           ← THE mark — four spines that double as the play/pause control:
│                         geometry, triangle⇄spines morph, every playback state,
│                         app-icon, monochrome, notification assets, painter spec
└── assets/            ← 4-spine export set (SVG), see below
```

The **app** is the implementation authority: `saga/lib/core/theme/saga_theme.dart` for
colour, `saga/lib/shared/widgets/saga_mark.dart` for the mark. These documents explain
the intent; where a document and the shipped code disagree, the code wins and the
document is what needs fixing.

---

## Palette — a known divergence

The SVG exports in `assets/` were drawn with a refined mark palette (ink `#1C140F` ·
cream `#F2E7D6` · terra `#C2603C` · amber `#E8A24A`). The app still ships the original
values (ink `#1E1410` · cream `#F4EAD8` · terra `#C25A3A` · amber `#E0A050`), and
`01-brand/tokens.css` documents those. So a brand asset and the live app differ by a
few percent in hue.

This is deferred, not forgotten. **Decide the palette before mass-exporting production
icons** — picking one after the fact means regenerating every launcher density, every
notification asset, and every screenshot on the landing page.

Exception: the **ember** exports were redrawn with the app/AA values (spines `#F4EAD8`,
amber `#E0A050`, ground `#8E3A22`) when the theme was renamed — the old export palette
predates the retune, and its ink accent fails the 3:1 floor on the new ground.

### Ember (formerly Terra) — contrast
Superseded 2026-08-10 by the AA retune in `05-contrast/`: the `#C25A3A` ground was
unfixable for text, so grounds darkened to `#8E3A22`/`#7A301B`, ink-as-accent was
retired for amber, and every text tier now clears AA on `bg` (the on-surface rule is
retired). `#C25A3A` lives on as the non-text hero color. Values and ratios:
`05-contrast/README.md`.

---

## assets/ — the 4-spine export set

Drawn from the **static logo pose** in `02-mark` (bars at x = 41 / 73 / 105 / 137 in a
200-box, the 2nd bar accent, radius 5).

```
assets/
└── svg/
    ├── mark/         saga-mark-{ink,cream,ember,onyx}.svg (transparent) + -bg.svg (app-icon-ready)
    ├── wordmark/     saga-wordmark-{ink,cream,ember}.svg  (Manrope 600 + accent triangle)
    ├── lockup/       saga-lockup-{ink,cream,ember}.svg    (mark + wordmark)
    └── monochrome/   saga-mono-{white,black}.svg          (flat silhouette, no accent)
```

Onyx exists as a mark export only — the repo README uses all four `-bg` variants for its
theme table. There is no onyx wordmark or lockup yet; use the ink pair on a black field.

For the play-triangle / pause-bars / animated states, use `02-mark/` (the canonical
spec + its own `assets/`). The wordmark SVGs use a live `<text>` element — render with
Manrope available, or convert text→outlines before handing to a tool without the font.

---

## Where to start, by task

- **Implementing the app (Flutter):** the live implementation is in the app itself —
  `saga/lib/shared/widgets/saga_mark.dart` and `saga/lib/core/theme/saga_theme.dart`.
  Use `02-mark/` for the painter spec and `01-brand/` for tokens.
- **Making a logo/icon/marketing asset:** `assets/` (exports) or `02-mark/` (source + icon).
- **Changing colours or type:** `saga/lib/core/theme/saga_theme.dart` is what users see;
  `01-brand/tokens.css` is the web mirror. Change both, and read the palette note above first.
