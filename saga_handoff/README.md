# Saga — design handoff (canonical)

Single source of truth for the Saga audiobook player's visual system. Everything in
this folder is **current**. Superseded material lives in `../_archive/` (kept for
reference, not for building from).

> **Read this first.** Saga's mark went through a generational change. If you opened an
> older file describing a *three-spine* mark or a Manrope-800 wordmark, that's Gen 1 and
> it's archived. The current mark is the **four-spine** play/pause mark below.

---

## What's inside

```
saga_handoff/
├── README.md          ← you are here
├── 01-brand/          ← foundations: colour tokens, type, theming, accessibility
│                         (tokens.css is the implementation source of truth)
├── 02-mark/           ← THE mark — four spines that double as the play/pause control:
│                         geometry, triangle⇄spines morph, every playback state,
│                         app-icon, monochrome, notification assets, Flutter painter
├── 04-flutter/        ← drop-in Dart/Flutter implementation of the brand
└── assets/            ← regenerated 4-spine export set (SVG + PNG), see below
```

---

## What changed in Gen 2 (vs the archived Gen 1)

| | Gen 1 (archived) | Gen 2 (canonical, here) |
|---|---|---|
| **Mark** | 3 stacked spines | **4 spines**, folding into the play triangle (`02-mark/`) |
| **Wordmark weight** | Manrope 800 | **600 (SemiBold)**; 800 reserved for hero-only |
| **Player control** | mark = "playing" indicator only | mark **is** the transport — paused = triangle, playing = live meter, + buffering / downloading / breathing / finished |
| **Palette** | ink `#1E1410` · cream `#F4EAD8` · terra `#C25A3A` · amber `#E0A050` | refined: ink `#1C140F` · cream `#F2E7D6` · terra `#C2603C` · amber `#E8A24A` |


The regenerated logo exports in `assets/` use the **Gen-2 mark palette** (`#E8A24A`
amber, etc.), because that's the canonical mark spec in `02-mark/`. So a brand asset
and the live app may differ by a few percent in hue until the palette refresh is taken.
Decide the palette before mass-exporting production icons.

### Terra theme — contrast rule
Terracotta (`#C25A3A`) is a mid-tone, so neither cream nor ink clears WCAG AA (4.5:1)
against it for normal text — solid cream is only ~3.7:1 (AA-large only). **Secondary
text on Terra must sit on `--saga-surface` (`#9E4128`), not `--saga-bg`**, where cream
clears ~5.4:1. The `fg-muted` / `fg-subtle` tiers were raised (0.78→0.88, 0.55→0.72) so
they hold up on that surface (~4.6:1 / ~3.6:1); on the bright `bg` directly, only
large/bold text meets AA. Don't use low-opacity cream as the contrast mechanism on Terra.

---

## assets/ — regenerated 4-spine export set

The old 3-spine SVG/PNG exports are archived (`../_archive/gen1-3spine-svgs/`,
`../_archive/gen1-3spine-pngs/`). These are their 4-spine replacements, drawn from the
**static logo pose** in `02-mark` (bars at x = 41 / 73 / 105 / 137 in a 200-box, the
2nd bar accent, radius 5).

```
assets/
└── svg/
    ├── mark/         saga-mark-{ink,cream,terra}.svg (transparent) + -bg.svg (app-icon-ready)
    ├── wordmark/     saga-wordmark-{ink,cream,terra}.svg  (Manrope 600 + accent triangle)
    ├── lockup/       saga-lockup-{ink,cream,terra}.svg    (mark + wordmark)
    └── monochrome/   saga-mono-{white,black}.svg          (flat silhouette, no accent)
```

For the play-triangle / pause-bars / animated states, use `02-mark/` (the canonical
spec + its own `assets/`). The wordmark SVGs use a live `<text>` element — render with
Manrope available, or convert text→outlines before handing to a tool without the font.

---

## Where to start, by task

- **Implementing the app (Flutter):** `04-flutter/` for the brand package, `02-mark/`
  for the mark painter, `01-brand/` for tokens.
- **Making a logo/icon/marketing asset:** `assets/` (exports) or `02-mark/` (source + icon).
- **Changing colours or type:** `01-brand/tokens.css` — and read the deferred-palette note above.
