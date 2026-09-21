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
