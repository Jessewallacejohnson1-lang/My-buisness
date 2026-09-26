# Nav chrome reference — Alta (Mobbin), measured 2026-09-20

Source frame: `_raw/alta-home.png`, Mobbin screen `3c6b9d18-c980-4e73-8809-c1a809cf76d4`
(a second frame, `d96620c9`, corroborates every number below to within a pixel).

**Scale.** The export is 1180 × 2676 px. The bottom 120 px is Mobbin's "curated by
Mobbin" strip and is **not device**. The device frame is the top 2556 px — an iPhone
15 Pro, 393 × 852 pt at @3x. `1180 / 393.33 = 3.000` exactly. Do not divide the 2676
height by 3.

Every number here was measured with the subpixel coverage scanner in `_raw/cov.swift`
(ink coverage = `1 - luma/255`, edges resolved to a fraction of a pixel) and the
angular scanner in `_raw/arc.swift`. Nothing here was eyeballed.

## Three ways the frame differs from what we expected

1. **The bell carries no badge.** A colour census over a 90 × 100 px window around it
   returns only `#FFFFFF`, `#000000` and their antialias neighbours — zero red pixels,
   in both frames.
2. **The top bar has no magnifying glass.** Its top-left mark is a calendar
   (19.8 × 19.5 pt). The magnifier is the fourth *tab-bar* slot. A 1:1 copy can
   therefore only mean the drawing, never the placement or the size.
3. **Neither glyph is an SF Symbol.** See the comparisons at the bottom.

## Magnifier

Normalising unit `r` = the lens ring's **centreline** radius, following the
`MapPinShape` idiom (proportions in ratio space so the mark holds its shape at any
size).

| | measured | in `r` |
| --- | --- | --- |
| ink box | 59.47 × 59.42 px = 19.82 × 19.81 pt (square) | 2.501 |
| lens centre | (821.67, 2365.97) px | — |
| lens centreline radius | 24.19 px = 8.06 pt | 1.000 |
| stroke | 4.26 px = 1.42 pt (cuts: 4.09 / 4.13 / 4.43 / 4.38) | 0.176 |
| inner arc radius | 14.52 px | 0.600 |
| inner arc path | **5° → 95°**, clockwise from 12 o'clock, round caps | — |
| handle cap centre | 45.34 px from the lens centre at 44.80° | 1.874 |
| handle visible length past the ring | 19.02 px = 6.34 pt | — |

`strokeFraction = 0.176 / 2.501 = 0.0704`.

The inner arc is what rules SF `magnifyingglass` out: no SF glyph has it, and it is
present at identical geometry in both frames, so it is part of the mark rather than a
transient search state.

**Arc angle, derived.** The scanner reports ink from 357.5° to 103.0°. Round caps add
`atan(2.13 / 14.51) = 8.35°` at each end, so the underlying path is 5.85° → 94.65°.
Authored as 5° → 95°, which predicts the measured ink to within 0.9°.

**Model check.** Predicted extents 795.35 / 855.86 / 2339.65 / 2400.16 against measured
795.88 / 855.35 / 2340.01 / 2399.43 — every edge within 0.55 px.

## Bell

Normalising unit `b` = the body's half-width.

| | measured | in `b` |
| --- | --- | --- |
| ink box | 51.4 × 62.1 px = 17.12 × 20.69 pt | — |
| body half-width `b` | 19.87 px = 6.62 pt | 1.000 |
| stroke | 3.85 px = 1.28 pt (cuts: 3.65 / 3.76 walls, 3.96 crown, 3.93 base, 3.92 clapper) | 0.194 |
| dome | a **true semicircle**, centred at y = 222.47, tangent to the walls | radius 1.000 |
| straight wall | dome centre 222.47 → **y = 239.8**, where the splay begins | 0.871 |
| splay | outward from (1.000, 0.871) to the base bar, a clean 0.4725 px per px | — |
| base bar | y = 248.18, half-length 24.0 px | y 1.294, half 1.208 |
| clapper | a semicircle centred on the base bar's centreline | radius 0.473 |

`height = 1 + 1.294 + 0.473 + 0.194 = 2.961`, `width = 2 × 1.208 + 0.194 = 2.610`,
`strokeFraction = 0.194 / 2.961 = 0.0655`.

The dome really is an exact semicircle: fit one of radius `b` at y = 222.47 and it
predicts the measured outer edge to 0.06 px at y = 215 and 0.10 px at y = 210. There
are no eyeballed control points in this shape — five numbers describe all of it.

**Correction, 2026-09-20.** The first pass modelled this as vertical walls running the
whole way down to a base bar that overshot them by 0.258 `b` on each side — the little
"flick" at the bar's ends. Re-scanning row by row shows that is not what happens: the
centreline half-width is 19.87 / 19.98 / 20.84 / 21.87 at y = 238 / 240 / 242 / 244, so
the wall is dead vertical until y ≈ 239.8 and then **splays outward** at 0.4725 px per
px, meeting the bar at 24.0. The flick is the end of that splay, not a separate
overhang. Checks: the splay line extrapolates to the bar's measured y of 248.18 at half
= 24.0, and the resulting width of 2.610 `b` = 51.86 px sits 0.5 px off the measured ink
box of 51.36. The old model predicted 53.85 px — 2.5 px wide.

The bounding box the scanner reports for the bell is **51.36 × 62.06 px, and the height
is contaminated**: rows 261–263 carry 0.02–0.04 coverage, which is antialias noise above
the scanner's 0.02 floor. The real ink runs y 200.66 → 260.0 = 59.3 px = 2.985 `b`,
against the model's 2.961. Use 59.3, not 62.06.

## Create button (tab bar centre)

| | measured |
| --- | --- |
| disc | 121 px = **40.3 pt** |
| plus arm span | 47.3 px = 15.8 pt (0.391 × disc) |
| plus stroke | 5.6 px = 1.86 pt, **butt caps** (SF `plus` has round caps) |
| vertical placement | disc centre y 2369.5 vs glyph row centre y 2369.8 — **contained in the bar**, not raised above it |
| clearance | disc bottom sits 42 pt above the screen edge, 8 pt clear of the 34 pt home-indicator zone |

## Layout, for context only

Alta's top bar: four ink boxes all starting at y = 201 px = 67.0 pt (8 pt below the
59 pt safe-area top), 20 pt side insets, right-hand marks at a 36 pt centre-to-centre
pitch. Its wordmark is 51.9 × 22.3 pt. Block Party's is 151 × 31 pt — roughly three
times wider, so the reference's roomy top bar is **not** a guide to our spacing.

Its tab bar is five equal 78.7 pt slots across the full width, with no labels at all.

## Why not SF Symbols

Both were rendered at 60 pt and measured in the same ratio space.

`magnifyingglass` @regular — stroke/lens-radius **0.264** against Alta's **0.176**
(50% heavier); box 2.877 × 2.905 `r` against Alta's 2.501 square; no inner arc.

`bell` @regular — has a crown nub Alta lacks; its skirt half-width flares from 54.5 to
68.2 px over 20 px of descent where Alta's is constant at 19.87; strokeFraction 0.083
against Alta's 0.0655.

This is the same silhouette test the `MapPinShape` comment applies, and both symbols
fail it for the same reason the `map` symbol did.

## The weight conflict

`MapPinGlyph` renders `24 × (0.207 / 2.379)` = **2.088 pt** of ink. The magnifier at
its reference size draws `19.81 × 0.0704` = **1.39 pt**; the bell `20.69 × 0.0655` =
**1.36 pt**. The pin is ~50% heavier than either, and after this change all three sit
in the same 58 pt bar.

Alta does not have this problem because its top bar has no disc — its four marks are
all bare thin strokes at 1.28–1.42 pt, one visual language.

Ways out, with the arithmetic:

- **Ship at reference size — what was built.** The pin stays 2.088 pt. It sits on a
  yellow disc while the others sit bare on paper, so on the simulator they read as
  different object classes rather than as three mismatched marks. Open for revision on
  a screenshot, which is the only place this can honestly be settled.
- Match absolute stroke: the magnifier box grows to 29.7 pt, the bell to 31.9 pt. Each
  glyph keeps its internal proportions, but they become the largest things in the bar.
- Lighten the pin: size 15.9 pt, or `MapPinShape.stroke` 0.207 → 0.137 head radii.
  Either breaks the pin's own 1:1 with the reference it was approved against.

Settle it on a screenshot, not on paper.

---

## Tab bar — Tripadvisor (Mobbin) and Apple's own bar, measured 2026-09-25/26

`TabBarMetric` in `BlockParty/App/RootView.swift` holds these numbers in capsule-local
points (x = 0 at the capsule's leading edge). Sources, all in
`/Users/owner/BP app/references/` in the main checkout (untracked):

- the Reference, `tripadvisor-glass-tabbar.png`: 1179 × 2676 px, but the Mobbin footer
  starts at y 2556, so the device is the top 2556 px, 393 × 852 pt @3x;
- Apple's 4-tab bar, `tab-bar/shot_outline_white.png` and `shot_baseline_white.png`
  (iPhone 16 @3x), and its scrub recording `tab-bar/scrub.mp4`;
- Apple's bar in the `TabProbe` app on the 420 pt iPhone Air eyes sim, `tab-bar/air/`.

The full brief is `tab-bar/MEASURED.md`; § numbers point into it. Pixels are @3x
(px / 3 = pt). Every value is MEASURED unless marked.

### Geometry

| | value | source |
| --- | --- | --- |
| capsule, 393 pt | x 63–1115, y 2307–2492 px = 351 × 62 pt; 21 pt from each side and from the bottom; ends fully round (r 31) | Reference §1.2 = Apple §2.1 |
| capsule, 420 pt | 378 × 62 pt at 21 / 21 / 21 | `air/` |
| Selection bubble, 393 | x 75–361, y 2319–2480 px = 95.7 × 54 pt, inset 4 pt, capsule | Apple §2.2 |
| Selection bubble, 420 | ~102 × 54 pt, inset 4 pt | `air/` |
| tab centres, 393 | 217 / 466.5 / 713.5 / 959 px on screen = 72.3 / 155.5 / 237.8 / 319.7 pt, 82.5 pt apart; 51.3 / 134.5 / 216.8 / 298.7 capsule-local | Apple §2.2 |
| tab centres, 420 | 55.3 / 144.3 / 233.3 / 322.3 pt capsule-local, 89 pt apart | `air/` |
| icons | glyph box 54–58 px = 18–19.3 pt, stroke ~4.5 px: a 20 pt SF Symbol, `.regular` (ESTIMATED match); centre y 2379 px, 24 pt below the capsule top | Reference §1.4 |
| labels | cap top y 2431, baseline 2452 px (48.33 pt below the capsule top); cap height 21–22 px ≈ SF Pro 10 pt (ESTIMATED); stems 2.9–3.3 px unselected (Medium), 3.7–4.0 px selected (Semibold); 8 pt below the icon | Reference §1.5, Apple §2.5 |

**The width rule** (ESTIMATED from the two widths; GUESSED at others): bubble width =
`(capsule − 8) / 4 + 10`, the end bubbles touch the 4 pt inset, and the four centres are
evenly spaced between. It lands within 0.6 pt of every measured centre at 351 and 378.

### Glass and colour

| | value | source |
| --- | --- | --- |
| glass tone | Reference over the fireworks photo: luminance 5th / 50th / 95th percentile 169 / 181 / 206; over the white page 236 (232–241) | §1.6 |
| glass flip, BP | plain `.glassEffect(.regular)` over a near-black Town card (`-feed-scrolled-y 1200`) flipped dark: 23/255, ink invisible. With a white underlay behind it: 20% → 40/255 (still flipped), 30% → 178/255 (held). Shipped at 35% | BP eyes sim, 2026-09-26 |
| bubble vs bar | Reference 0.80×: 156 inside against 193–198 just outside, same row. Black at 20% reproduces it. Apple's own bubble over white is 0.93× (235 on 253) | §1.8, §2.3 |
| rim | 1 pt (3 px) near-white line on every side, +60–75 above the glass over dark ground. BP draws white at 60% (opacity GUESSED) | §1.9 |
| dim band | Reference only: full-width, white 255 → ~187 from y 2170 to 2470 px (723 → 823 pt), no blur. Tripadvisor's, not iOS's. Not copied (Jesse) | §1.11 |
| shadow | Reference fit: black ~10–12%, blur ~16–20 pt, +6 pt down (ESTIMATED). BP adds none; the glass casts its own | §1.10 |

### Motion

| | value | source |
| --- | --- | --- |
| Lens while held | 1.20× the bubble's width, 1.30× its height; constant size while held | `air/` hold (d); scrub §3.4 |
| Lens growth on touch-down | 89% at 37 ms, 96% at 70 ms, no overshoot. BP: spring response 0.06, damping 1 | `air/` hold (d) |
| quick tap | the Lens is drawn on a plain tap too: lifts within ~37 ms, stretches to ~136–141 pt wide while travelling, arrives ~270–280 ms, re-forms the grey bubble at ~323–353 ms, then squashes 0.87× wide / 1.14× tall and settles within 1 px by ~860 ms. BP does not draw the squash | `air/` tap (b) |
| BP travel | spring response 0.45, damping 0.8 (tuned, not measured); arrives ~252 ms on the eyes sim | BP eyes sim, 2026-09-26 |
| bar swell | 1.042× at +70 ms, 1.039× held (1.025× with the finger far above), ~1.015× peak on a quick tap, back to 1.0 within ~160 ms of release. BP: 1.04 | `air/` |
| magnification | content under the Lens ~1.2× (Account label 120 → 146 px, head 29 → 34 px) | scrub §3.7 |
| Lens at the ends | stops 9 pt past the last centre (328.7 pt on screen at 393); the left end is mirrored (GUESSED) | scrub §3.5–3.6 |
| Lens over white | reads ~245: lighter than the resting bubble (233–235), just below the bar (251–253) | scrub §3.7 |
| release | the Lens collapses within ~76 ms; the bubble settles by ~0.38 s with a ~1.7 pt undershoot | scrub §3.6 |
| release far above | Apple switches tabs on a release 150 pt above the bar, so there is no cancel zone | `air/` drag-up (c) |

**Not measured:** how far the Lens lags a real finger (the scrub swipe was synthetic);
the bubble spring's own parameters (only its arrival times); the width rule between and
beyond 393 and 420 pt.
