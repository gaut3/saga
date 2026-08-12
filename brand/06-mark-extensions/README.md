# Handoff: Mark extensions — cover fallback & spine pattern

Two derived uses of the four-spine mark, from `Saga Mark Extensions.html` (project
root, live + interactive — the generator there is the reference implementation).
Both are **decorative artwork**, so WCAG AA text rules don't apply; the one contrast
rule that does is the 3:1 non-text floor where the accent spine sits on Ember
grounds — use amber there, never ink (see `05-contrast/`). All values below are
already Ember-aligned.

## What's in this package

```
06-mark-extensions/
└── README.md    ← algorithm + tile spec; reference impl in the HTML at root
```

---

## 01 — Generated cover fallback

Every book Plex has no artwork for gets a deterministic cover: four spine heights,
one accent position, one palette — all derived from a hash, so the same book looks
identical on every device and launch. **No text on the cover**: every surface in
Saga already prints the title beside it, which also kills font-fallback, clamping
and RTL problems.

### Algorithm

```
input     series key + volume number if Plex supplies a grouped series,
          else the full title
hash      FNV-1a 32-bit over the string, lowercased, punctuation stripped
          (keep letters, numbers, spaces — unicode-aware)
heights   4 × 5 bits  → h[i] = 44 + round(bits/31 × 56)   (44–100% of box)
accent    2 bits (h >>> 21) → which spine takes the accent colour
palette   8 bits (h >>> 24) → index into the six brand pairs below
```

Series mode (when a series key + volume exists): hash the **series key**, then vary
by volume v (1-based): `accent = (accent + v−1) mod 4`, and height slot
`(v−1) mod 4` is re-rolled `44 + ((h−44 + 17·v) mod 57)` — so a shelf of one series
reads as a family, volumes distinguished by accent position and one bar.

### Palette pairs (hashed mode)

| # | bg | spines | accent |
|---|----|--------|--------|
| 0 | `#1E1410` ink | `#F4EAD8` | `#E0A050` |
| 1 | `#8E3A22` ember | `#F4EAD8` | `#E0A050` |
| 2 | `#F4EAD8` cream | `#1E1410` | `#9E4128` |
| 3 | `#0C0908` pitch | `#E4D9C6` | `#E0A050` |
| 4 | `#7A301B` ember-deep | `#F4EAD8` | `#E0A050` |
| 5 | `#E8D8BD` linen | `#1E1410` | `#9E4128` |

Theme-locked mode ignores the palette bits and uses the active theme's
bg / fg / accent (for Ember that means the new `#8E3A22` ground and amber accent).

### Geometry & sizes

- Spines: 4 bars, width 22, pitch 32, radius 5, in a 118 × 100 box, centred on the
  vertical mid-line (never shelved to a baseline).
- Cover box: square, radius 10 (7 at ≤48px, 14 at ≥300px).
- Padding: 15% of the box; 17% at list-row size (≤48px).
- Proven sizes: 48 (list row) · 86 (finished shelf) · 132 (grid) · 300 (player).

### Open decisions (carried from the exploration)

1. **Series key for loose files** — parsing ", Vol. N" out of titles misfires on
   some libraries. Proposal: run series mode only when Plex supplies the grouping;
   fall back to full-title hash silently.
2. **Hashed vs theme-locked** — recommendation on record: theme-locked inside the
   library (a shelf of ten hashed covers reads as a colour test), hashed only where
   covers travel alone (share cards, site).

---

## 02 — Spine pattern / texture

The mark's bars tiled into a field — a meter that never resolves. One tile, scaled
and faded; opacity is the whole control.

### The tile

```
canvas     320 × 200 units, repeats on both axes
spines     8 · width 22 · pitch 40 · radius 5
heights    96 · 132 · 76 · 112 · 68 · 124 · 84 · 108
alignment  centred on the tile mid-line, never shelved
accent     spine 2 only — one per tile, as in the mark
           (at 2× the field's base opacity)
scale      0.55 mobile · 0.8 card · 1.0 band · 1.5 ghost
```

### Opacity ladder

| use | opacity |
|---|---|
| behind body copy | 5% |
| site section bands | 7–8% |
| cards, headings only on top | 10% |
| print / stickers, nothing read through it | 16% |

Rule of thumb: if text sits on it, the field must be invisible when you stop
looking for it. If nothing sits on it, push it.

### Rules

- Field colour = the surface's fg (cream on dark, ink on light); accent = the
  theme's accent. On Ember grounds the accent is **amber**, never ink (3:1 floor).
- One-colour print drops the accent spine and still works.
- Proven surfaces: GitHub repo header (1280×640, safe-area centred), OG card
  (1200×630), site bands, onyx splash (8%), ember sticker (16%, `#8E3A22` ground).
- Not explored yet (deliberately): the field as a mask over cover art; an animated
  site-hero version. Both easy to overdo — treat as future explorations, not spec.
