# Handoff: AA contrast retune + Ember rename

WCAG 2.1 AA fix for the text-hierarchy tokens across all four themes, plus the
Terra → **Ember** rename. Live spec with mocks and full rationale:
`Saga Theme Contrast Spec.html` (project root). All ratios computed the audit's
way: alpha composited onto the named ground, then ratioed.

## What's in this package

```
05-contrast/
├── README.md        ← you are here: values, ratios, policy, Dart table
└── tokens-aa.css    ← drop-in override layer; import AFTER 01-brand/tokens.css
```

## The strategy in four lines

1. **fgSubtle stays a real-content tier** (it carries the 12px nav labels). Alphas rise per theme to the minimum that clears 4.5:1 on the lighter ground, plus margin. No usage-contract change; the ~90 call sites keep their token.
2. **Terra → Ember.** No text color passes on `#C25A3A` (cream 3.65, ink 4.14 — the mid-tone caps everything below 4.5). Grounds darken one step: bg `#8E3A22`, surface `#7A301B`. `#C25A3A` survives as the theme's non-text hero color. Renamed **Ember** — display-only, persisted index unchanged.
3. **Cream moves both steps** (muted 60→70%, subtle 40→63%): the single A6 nudge clears muted but leaves no passing room for subtle beneath it.
4. **New `accentText` tier** — the only accent allowed at body sizes (13px links, active values); must clear 4.5 on both grounds. `accent` keeps its values for non-text UI and large/bold text (3:1 floor).

## Token values (pin these in tests)

Ratio shown as bg / surface; **pin the worst of the two**.

| theme | token | value | ratio |
|---|---|---|---|
| ink | fgMuted | fg @ `0xA6` (65%) — unchanged | 6.93 / **6.68** |
| ink | fgSubtle | fg @ `0x84` (52%) | 4.86 / **4.71** |
| ink | accentText | `#E0A050` (= accent) | 8.01 / **7.45** |
| cream | fgMuted | fg @ `0xB3` (70%) | 6.18 / **6.00** |
| cream | fgSubtle | fg @ `0xA0` (63%) | 4.84 / **4.75** |
| cream | accentText | `#9E4128` (new; was accent `#C25A3A` @ 3.65) | 5.43 / **5.11** |
| ember | bg | `#8E3A22` (was `#C25A3A`) | — |
| ember | surface | `#7A301B` (was `#9E4128`) | — |
| ember | surfaceAlt | `#6E2A17` (was `#8A3520`) | — |
| ember | fg | `#F4EAD8` — unchanged | **6.34** / 7.77 |
| ember | fgMuted | fg @ `0xD9` (85%) | **5.07** / 6.08 |
| ember | fgSubtle | fg @ `0xCB` (80%) | **4.63** / 5.53 |
| ember | accentText | `#F0C48C` (new; ink-as-text retired) | **4.67** / 5.73 |
| ember | hero | `#C25A3A` — non-text roles only (1.73 vs bg) | n/a |
| onyx | fgMuted | fg @ `0xA6` (65%) — unchanged | 6.39 / **6.31** |
| onyx | fgSubtle | fg @ `0x8C` (55%) | **4.73** / 4.76 |
| onyx | accentText | `#E0A050` (= accent) | 9.31 / **8.80** |

Onyx bloom check: subtle @ 55% composites to `#7D776D` on black — far dimmer than
the already-dimmed fg, nothing new glows at night.

### Dart (saga_theme.dart)

```dart
// ink
fgMuted:  Color(0xA6F4EAD8),  fgSubtle: Color(0x84F4EAD8),  accentText: Color(0xFFE0A050),
// cream
fgMuted:  Color(0xB31E1410),  fgSubtle: Color(0xA01E1410),  accentText: Color(0xFF9E4128),
// ember (theme index of terra — rename is display-only)
bg: Color(0xFF8E3A22), surface: Color(0xFF7A301B), surfaceAlt: Color(0xFF6E2A17),
fgMuted:  Color(0xD9F4EAD8),  fgSubtle: Color(0xCBF4EAD8),  accentText: Color(0xFFF0C48C),
hero: Color(0xFFC25A3A), // non-text only
// onyx
fgMuted:  Color(0xA6E4D9C6),  fgSubtle: Color(0x8CE4D9C6),  accentText: Color(0xFFE0A050),
```

## Mark & extension touchpoints

- **The mark is the transport control** → non-text UI, 3:1 floor. Only Ember changes:
  the ink accent spine falls to 2.39 on the new ground. **`mark-middle: ink → amber`**
  (`#E0A050`, 3.35 on bg / 4.11 on surface). Side spines stay cream (6.34). Ink,
  Cream, Onyx marks are untouched.
- **Generated cover fallback** (Mark Extensions §01): covers carry no text — exempt
  from AA. But two of the six hashed palette pairs use retired terra grounds; swap
  `#9E4128 → #8E3A22` and `#8A3520 → #7A301B` so covers match Ember's real surfaces.
  Theme-locked mode inherits the new grounds automatically.
- **Pattern / texture** (§02): opacity-governed decorative fields, unchanged. Move the
  sticker ground `#9E4128 → #8E3A22` at next export for consistency.

## Code follow-ups when this lands

1. Retire the "secondary text on Terra must sit on surface" guideline — every tier now passes on bg.
2. Repoint Ember's ink-as-text call sites to `accentText`.
3. Rename the settings label Terra → Ember (persisted index untouched).
4. Keep the alpha-token structure everywhere; no opaque migration needed.
5. Add contrast pins from the table above to the theme test.

## Superseded

This package supersedes the "Terra theme — contrast rule" section of the main
handoff README and the terra block + comments in `01-brand/tokens.css`. Until the
retune ships, `tokens.css` still holds current app values; `tokens-aa.css` is the
override layer to flip on with the release.
