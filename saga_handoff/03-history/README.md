# Handoff: Listening History redesign (+ Home tile changes)

## Overview

This package redesigns Saga's **Listening History** screen — currently the weakest screen in the app (it shows only "Today · 2h 14m" floating in empty space) — into a rich, rewarding activity view. As part of the change, the standalone **In Progress** screen is **retired**: its two unique pieces (the *session log* and the *completed-books shelf*) move into Listening History, and the home screen's stat tiles are reworked because the old "1 book in progress" tile pointed at the now-deleted screen.

Three directions were explored. **Direction B ("Streak") is the chosen design** and is the spec below. (Directions A and C remain in the reference prototype for context only.)

The redesign covers:
1. **Listening History** screen — a 3-segment view: **Day / Month / Total**.
2. **Home screen** — replace the 3 disconnected stat tiles with a single consistent, clearly-tappable "Listening" entry point.

---

## About the design files

The files in `reference_prototype/` are **design references built in HTML/React (JSX)** — a high-fidelity prototype showing the intended look and behavior. **They are not production code to copy.** Your job is to **recreate these designs in the Saga Flutter app** using its existing widgets, the `saga_brand` package, and established patterns.

The app already has the brand primitives you need:
- `lib/saga_brand/saga_colors.dart` → `SagaColors` (raw palette) and `SagaTheme` (semantic per-surface palette: `SagaTheme.ink`, `.cream`, `.terra`).
- `lib/saga_brand/animated_saga_mark.dart` → `AnimatedSagaMark` (the VU-meter "playing" indicator).
- Typography is **Manrope** (already configured app-wide per the brand handoff), with **JetBrains Mono** for uppercase metadata labels.

**To view the prototype:** open `reference_prototype/Saga Listening History.html` in a browser. It's a pan/zoom canvas. The first section is the 3 Listening-History directions (use **Direction B**); the second section is the 4 home-screen options. Each phone scrolls internally; in Direction B, tap the **Day / Month / Total** segmented control and tap any day row to expand its session log; in Month, use the ‹ › arrows to change month.

---

## Fidelity

**High-fidelity.** Colors, typography, spacing, radii, and interactions are final and specified to the pixel below. Recreate them exactly using `SagaColors` / `SagaTheme`. The Overlord book covers in the prototype are **sample data** — pull real cover art from Plex. Listening numbers are sample data — wire to the app's real playback history.

Design target is the **Ink (dark)** theme. The screen must also support **Cream** and **Terra** by reading from `SagaTheme` (see Design Tokens).

---

## Design tokens

### Already in `saga_brand`
Use these directly — do not hardcode hex:

| Design value | Flutter token | Ink | Cream | Terra |
|---|---|---|---|---|
| Page background | `SagaTheme.x.background` | `#1E1410` | `#F4EAD8` | `#C25A3A` |
| Primary text | `SagaTheme.x.foreground` | `#F4EAD8` | `#1E1410` | `#F4EAD8` |
| Muted text | `SagaTheme.x.foregroundMuted` | cream@65% | ink@60% | cream@78% |
| Accent | `SagaTheme.x.accent` | `#E0A050` amber | `#C25A3A` terracotta | `#1E1410` ink |

### To ADD to `SagaTheme` (used heavily by this screen, not yet in the token file)
Please extend `SagaTheme` with these fields and values per theme. Exact values from the prototype:

| New field | Role | Ink | Cream | Terra |
|---|---|---|---|---|
| `surface` | card background | `#261B16` | `#EFE3CE` | `#9E4128` |
| `surfaceAlt` | nested/elevated | `#2F221C` | `#E8D8BD` | `#8A3520` |
| `foregroundSubtle` | tertiary text / axis labels | cream@40% (`0x66F4EAD8`) | ink@40% | cream@55% |
| `border` | hairlines | cream@12% (`0x1FF4EAD8`) | ink@12% | cream@20% |
| `track` | empty bar/heatmap cell, progress track | cream@9% (`0x17F4EAD8`) | ink@8% | cream@16% |
| `accentFg` | text/icon ON an accent fill | `#1E1410` | `#F4EAD8` | `#C25A3A` |

### Heatmap intensity scale (5 steps, low→high)
Used by the contribution grid and month calendar. Ink theme:
```
level 0: cream@6%   (0x0FF4EAD8)   // ~ same as `track`
level 1: amber@28%  (0x47E0A050)
level 2: amber@50%  (0x80E0A050)
level 3: amber@72%  (0xB8E0A050)
level 4: amber 100% (#E0A050)
```
Cream theme uses terracotta at the same opacities; Terra uses cream at 10/30/50/72/100%. Provide as `List<Color> heat` on `SagaTheme`.

### Type scale (Manrope unless noted)
| Use | Size / weight / tracking |
|---|---|
| Screen title ("History") | 27 / w800 / -0.03em |
| Big stat ("9h 11m", "30h 40m") | 30–34 / w800 / -0.03em |
| Card stat number ("6", "71") | 23 / w800 / -0.03em |
| Section / list headline | 14.5–16 / w700 / -0.01em |
| Body / captions | 13 / w400–500 |
| Mono label (UPPERCASE) | JetBrains Mono 11 / w400 / +0.18em / uppercase, color = `foregroundSubtle` |
| Day-number (calendar/list) | 19–20 / w800 |
| Tabular numbers | enable `FontFeature.tabularFigures()` on all durations/times |

### Spacing, radii
- Screen horizontal padding: **20px**. Card inner padding: **18–20px**. Compact card: **13–14px**.
- Radii: hero cards **20**, standard cards/rows **16**, chips/cells **8–9**, pills/dots **99**.
- Vertical rhythm between blocks: **16–24px**; caption-to-chart gap: **26px**.

---

## Screen 1 — Listening History

**Route:** replaces the old `ListeningHistory` route (and absorbs the retired `InProgress` route — see Screen 2 for routing). **Entry points:** the home "Listening" tile/header (Screen 2).

**App bar:** custom (not Material). Row: back chevron · title **"History"** (Manrope 27 w800) · a **segmented control** on the right with three segments **Day / Month / Total**. Segmented control = pill container `background: surface`, radius 99, 3px padding; active segment `background: accent`, text `accentFg` w700 14; inactive text `foregroundMuted`. (Flutter: a custom 3-button `Row` in a rounded `Container`, or `SegmentedButton` restyled — custom is closer to spec.)

Body is a vertical scroll (`ListView`/`CustomScrollView`), padding 20 horizontal, 32 bottom.

### 1A · DAY segment (default)
Top→bottom:

1. **Streak banner** (flat card, `surface`, radius 16, padding 14×16; row layout):
   - Leading: flame icon, `accent`, 22px.
   - Middle: **"4-day streak"** (16 w800) over **"Longest run · 9 days"** (12.5, `foregroundMuted`).
   - Trailing: a **7-dot strip** (last 7 days, oldest→newest), each dot 9×9 radius 3; listened = `accent`, missed = `track`.
   - *Hidden if the "milestones" preference is off (see State).* 

2. **"This week" card** (`surface`, radius 20, padding 20):
   - Header row (space-between): left column = mono label **"THIS WEEK"**, then **total** "9h 11m" (30 w800, tabular), then caption "5 days · 1h 32m / day" (13 `foregroundMuted`, single line). Right = current book cover, 48×48, radius 9.
   - **26px gap**, then a **weekly bar chart**: 7 vertical bars (Mon–Sun), `gap 10`, height ~104. Each bar max-width 26, radius 7, `background: accent`; today = full opacity, other listened days = 38–42% opacity, upcoming = `track`. Day letters below (12 w700; today in `accent`, else `foregroundSubtle`). Bars animate in (grow from bottom, ~0.7s, staggered 0.05s).

3. **"Recent days" list** — mono label header, then rows. Each **day row** is tappable and expands:
   - Collapsed row: date column (40px wide, centered: day-number 20 w800 + weekday 10.5 w700 `foregroundSubtle`; today's number in `accent`) · book cover 38×38 r7 · chapter title (14 w700, ellipsis) above a thin progress bar (the day's minutes ÷ best-day, height 5, `accent` on `track`) · trailing duration (14 w800, tabular) + "+22%" delta (12 w700 `accent`, *toggleable*) · a chevron that rotates 180° when open.
   - Empty days (no listening): 50% opacity, no cover (show a small track-colored bar), no chevron, not tappable.
   - **Expanded** (relocated from the old In Progress screen): a `surface` panel showing "N sessions · {chapter}" then the **session log** — alternating **Started / Paused** rows, each with a play/pause glyph, label, "Xm listened" subcopy on Started, and a right-aligned timestamp (e.g. 21:24). Build pairs from each session's start time + duration.

### 1B · MONTH segment
A **navigable** month (not a single fixed month):

1. **Month stepper** (row, space-between): ‹ prev button · centered **"May 2026"** (21 w800, nowrap) over **"30h 40m · 24 days"** (12.5 `foregroundMuted`) · next button ›. Prev enabled back ~11 months; **next disabled at the current month** (can't listen in the future) — render disabled arrow at 30% opacity.
2. **Calendar card** (`surface`, r20): weekday header row (S M T W T F S, 10.5 w700 `foregroundSubtle`), then a 7-column grid of day cells. Each cell: square (`aspectRatio 1`), radius 9, `background = heat[level]` by that day's minutes; day number centered (12.5 w700; `accentFg` when level≥3 else `foregroundMuted`). **Today** gets a 2px `accent` ring. **Future days** render as transparent with a 1px dashed `border` and subtle number.
3. **Stat cards** (row of 3, each `surface` r16): **Listened {N} days · Best day {h m} · Per day {avg}** — all derived from the month's daily minutes.
4. **"Books this month"** — list of books touched that month; each row: cover 48 · "Vol. N · Title" + a progress bar · status ("Finished" in `accent` / "In progress" in `foregroundMuted`).
5. **"By week"** — 4–5 rows: "Wk N" label · horizontal bar (week total ÷ peak, `accent` @60%) · week total (right, tabular).

All month numbers **recompute when you change month**.

### 1C · TOTAL segment (lifetime — this is where the retired Progress content lands)
1. **Lifetime stat cards** (row of 3): **Finished {6} books · All time {71} hours · Per day {1h 36m}**.
2. **Finished books shelf** *(relocated from In Progress "Completed")* — mono label "FINISHED BOOKS" + "{6} of 7", then a **horizontal scroll** of completed covers (86×86 r10) with "Vol. N" + title (2-line clamp) beneath each.
3. **Contribution heatmap** (`surface` r20): mono label "LAST 13 WEEKS" + "{71}h total"; a 13-column × 7-row grid of `heat[level]` cells (cell 13, gap 4, radius 3); a "Less ▢▢▢▢▢ More" legend right-aligned.
4. **Records** (row of 2 cards): **Longest streak · 9 days** (flame icon) and **Best day · 2h 43m** (spark icon).
5. **"When you listen"** (`surface` r20): label, headline "Mostly in the evening", a single stacked horizontal bar split Morning/Afternoon/Evening/Night (evening segment full `accent`, others `accent`@32%), with labels + per-bucket durations beneath.

---

## Screen 2 — Home screen changes

**Why it changes:** retiring In Progress removes the destination of the old **"1 book in progress"** tile. Today the tile row is also inconsistent — the bars tile is tappable but the heatmap tile isn't, and nothing signals they open History.

**Goal:** make Listening a single, consistent, obviously-tappable doorway into **Listening History**, while keeping **Continue Listening** (resume the current book) as the home screen's primary action.

### Final layout (chosen)
Listening History is a *secondary* feature, and the top of a tall phone is the hardest one-handed reach — so the Listening entry is a **compact, glanceable strip near the top**, and **Continue Listening is the hero in the comfortable thumb zone**.

Content order, top → bottom:
1. **Header** — "saga ▸" wordmark + bookmark / settings / logout icons (unchanged).
2. **Listening strip** — a slim card (`surface`, radius 16, padding 13×16) as one row: flame icon (`accent`, 20) · **"4-day streak"** (15 w800) over **"9h 11m this week"** (12.5 `foregroundMuted`) · a small 7-bar **sparkline** (no labels, height ~32, today full / others `accent`@40%) · trailing `›` chevron. **The whole strip is one tap target → Listening History.** No precision tapping needed, which suits the top zone.
3. **Continue Listening** — the existing hero card (cover + title + author + progress + Playing), now sitting higher and within thumb reach. This stays the visual and functional priority.
4. **Recently Added** — unchanged.

**Remove** the old three-tile row entirely (heatmap / this-week / "1 book in progress"). The contribution heatmap and full weekly bars now live *inside* Listening History; the home surface only needs the glanceable summary.

> Rationale & alternatives explored (Options A/B/C, and the "full card on top" vs "Continue-first" orderings) are preserved in the prototype's 2nd and 3rd canvas sections for reference. The chosen layout = prototype section 3, **option "Slim stats strip + Continue hero."** Do **not** build the large full-width Listening card on top — it over-weights a secondary feature and strands a big tap target in the unreachable top zone.

---

## Interactions & behavior

- **Segmented control (Day/Month/Total):** swaps the body; remember last-selected per session.
- **Home Listening strip:** entire strip is tappable → Listening History (platform ripple/press state).
- **Day row expand/collapse:** tap toggles the session log; chevron rotates 180° (~200ms). Today expanded by default.
- **Month stepper:** ‹ / › step one month; next disabled at current month; everything recomputes.
- **Tap targets:** day rows, the home Listening strip. Use the platform ripple/press state consistent with the rest of the app.
- **Chart entrance animations:** bars grow from the bottom (~0.7s, eased, staggered); heatmap/calendar cells fade+scale in (~0.4s, staggered). **Respect reduced-motion** (`MediaQuery.disableAnimations`) — skip entrance animations, render final state. (This mirrors how `AnimatedSagaMark` already behaves.)
- **Empty/low-data states:** days with no listening render at 50% opacity with a placeholder bar; a brand-new user with little history should still see the scaffold (streak = 0, empty heatmap) rather than blank space — this was the original screen's failing.

---

## State management & data model

The screen is read-only over the user's playback history. Shape needed (names illustrative):

```
ListeningDay {
  DateTime date;
  int minutes;                 // sum of sessions
  String? bookId;              // book listened (usually one/day)
  String? chapterLabel;        // e.g. "Ch. 4 · The Impending Death"
  int progressDeltaPct;        // % of the book gained that day
  List<Session> sessions;      // [{ DateTime start, int durationMin }]
}
```
Derived/aggregate values the views need:
- **This week** total + per-day minutes (Mon–Sun).
- **Streak**: current consecutive listened-days; longest ever.
- **Month**: per-day minutes for any month (for calendar + stats + by-week).
- **Time-of-day** buckets (Morning 5–12 / Afternoon 12–17 / Evening 17–22 / Night else), summed minutes.
- **Lifetime**: books finished, total hours, avg/day, best day; last ~13 weeks of daily intensity for the heatmap.
- **Finished books** list (id, vol, title, cover) — was the In Progress "Completed" list.

Session Started/Paused rows in the log are derived from each `Session`'s `start` and `start + durationMin`.

---

## Flutter implementation notes

- **Charts are simple enough to avoid a charting dependency.** Bars = `Row` of `Container`s with `BoxConstraints`/heights (or a thin `CustomPaint`). Heatmap/calendar = `GridView`/`Wrap` of rounded `Container`s colored from the `heat` scale. The "when you listen" bar = a `Row` of flex-weighted `Container`s in a `ClipRRect`.
- **Segmented control:** custom `Row` of `GestureDetector`/`InkWell` pills in a rounded `Container` (closer to spec than `SegmentedButton`).
- **Day-row expansion:** `AnimatedSize` + `AnimatedRotation` on the chevron.
- **Month math:** standard `DateTime` (first weekday, days-in-month, offset stepping). Disable forward nav past the current month.
- **Now-playing affordance:** where a "playing" indicator appears (e.g. Continue Listening), reuse the existing `AnimatedSagaMark(state: SagaMarkState.playing)` — don't redraw bars.
- **Tabular figures:** apply `FontFeatures` so durations/times don't jiggle.
- **Theme:** read everything from `SagaTheme.of(...)` (after you add the new fields); never hardcode hex. Ship Ink as the dark default; verify Cream and Terra.

---

## Assets

- **Book covers:** sample Overlord art in `reference_prototype/covers/` is for prototype only — use real Plex cover art at runtime.
- **Icons:** back/chevron/play/pause/flame/spark are simple strokes — use your existing icon set or `Icons.*` equivalents. The flame/spark are decorative accents on streak/records.
- **Brand mark / fonts:** already in the app via `saga_brand` + Manrope/JetBrains Mono.

---

## Files in this bundle

```
design_handoff_listening_history/
├── README.md                          ← this file (self-sufficient spec)
└── reference_prototype/
    ├── Saga Listening History.html    ← open in a browser to view all directions + home options
    ├── saga-shared.jsx                ← tokens, sample data model, shared widgets (phone, charts, chips, session log)
    ├── saga-directions.jsx            ← Direction A/B/C (implement B); MonthView, StreakDay, FinishedShelf, etc.
    ├── saga-home.jsx                  ← home scaffold bits (wordmark, nav, Continue card, mini charts)
    ├── saga-home-options.jsx          ← Current + 3 home tile-row options
    ├── saga-history-app.jsx           ← canvas assembly + Tweaks (theme/toggles)
    ├── design-canvas.jsx              ← prototype canvas shell (not part of the app)
    ├── tweaks-panel.jsx               ← prototype tweak panel (not part of the app)
    ├── covers/                        ← SAMPLE Overlord covers (replace with Plex art)
    └── design_handoff_saga_brand/
        └── tokens.css                 ← brand tokens (mirror of saga_colors.dart) for the prototype
```

**Source of truth for the chosen design = Direction B** in `saga-directions.jsx` (`DirStreak`, `MonthView`, `StreakDay`, `FinishedShelf`, `BooksThisMonth`) and the home **Option C/B** in `saga-home-options.jsx`. The brand source of truth remains `design_handoff_saga_brand/` and the app's `lib/saga_brand/`.
