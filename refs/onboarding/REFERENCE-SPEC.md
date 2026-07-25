# Onboarding reference — measured spec

Everything here was measured off the reference frames with a pixel-scanning script,
not estimated by eye. Numbers are **points** (measured @3x ÷ 3).

Frames: `refs/onboarding/duolingo/S01.png … S20.png`, 1180×2556.
Originals (uncropped, with the Mobbin watermark) are in `duolingo/_raw/`.

---

## 1. The frame order in the build prompt is wrong — corrected here

The build prompt states: *"Twenty screenshots, nodes `3311:3` through `3311:22`, in
reading order = screens 1–20."*

**They are not in reading order.** The Figma frames are a Mobbin export in a different
sequence. Building `S05` against the 5th node would have produced Duolingo's
daily-goal screen instead of the connection question.

Each frame was identified by its actual content and mapped to the spec's screen
numbers. The mapping is a clean bijection — every raw frame is used exactly once,
which is strong corroboration that it is right:

| Spec screen | raw file | What the frame actually shows |
|---|---|---|
| S01 Splash | raw01 | Green field, wordmark bottom |
| S02 Welcome | raw10 | Owl + wordmark + tagline, GET STARTED / I ALREADY HAVE AN ACCOUNT |
| S03 Talking | raw07 | "Hi there! I'm Duo!" |
| S04 Talking | raw14 | "Just 7 quick questions before we start your first lesson!" |
| S05 Q1 unselected | raw19 | Language list, header + chevron, CONTINUE disabled |
| S06 Q1 selected | raw02 | Same list, French selected |
| S07 Interstitial | raw15 | "COURSE BUILDING…" + "7 million people" |
| S08 Q2 level bars | raw12 | "How much French do you know?" 1→5 bars |
| S09 Q3 multi unselected | raw18 | "Why are you learning French?", CONTINUE disabled |
| S10 Q3 multi selected | raw08 | Same rows with check badges + reacted bubble |
| S11 Talking | raw17 | "Let's set up a learning routine!" |
| S12 Q4 cadence | raw05 | 5/10/15/20 min per day + Casual…Intense, "I'M COMMITTED" |
| S13 Interstitial | raw03 | "That's **50 words** in your first week!" |
| S14 Notification pre-prompt | raw20 | Mock iOS alert + arrow at Allow |
| S15 Location slot | raw13 | The widget promo — copy its LAYOUT only |
| S16 Promises | raw16 | Three icon + title + subtitle rows |
| S17 Q5 cards unselected | raw04 | Super Duolingo / Learn for free, CONTINUE disabled |
| S18 Q5 cards selected | raw11 | Reacted bubble + Learn for free selected |
| S19 Q6 cards | raw09 | Start from scratch / Find my level + RECOMMENDED |
| S20 Finale | raw06 | "Since you know a few words, let's start at Score 10!" |

Note S20: its line reacts to the *level* answer from S08 — the exact mechanic the spec
specifies for Block Party's finale keyed to `town_level`.

---

## 2. Device + verification setup

The frames are **1179×2556 @3x = 393×852pt**, i.e. iPhone 15 Pro class. A dedicated
simulator was created so our screenshots are pixel-comparable with no rescaling:

```
xcrun simctl create "BP-Onboarding" \
  com.apple.CoreSimulator.SimDeviceType.iPhone-15-Pro \
  com.apple.CoreSimulator.SimRuntime.iOS-26-5
```

Its UDID is in `.bp-sim-udid` (gitignored). Status bar is pinned to the reference's
`9:41` via `simctl status_bar override` so clock/battery never pollute a diff.

Note the iPhone **16** Pro is 402×874, not 393×852 — the 6.3" redesign. Do not use it.

### Sample large SOLID areas when checking colour

Our solid fills render at **exactly** their token values. Verified: the splash ground,
the S02 GET STARTED face and the bench's Continue face all read `#E67633`, matching
`BP.orange` to the byte.

An earlier pass in this repo's history concluded there was a systematic colour shift
(`#E67633` reading as `#E88347`). **That was a measurement error and is not true.** It
came from a `Counter.most_common()` census over a coarse grid, which is dominated by
antialiased pixels: a 2pt border and text glyphs are mostly edge, so they read
persistently lighter than their token. `BP.teal` "reading" `#80CBBD` was a 2pt row
border; `Hue.ink` "reading" `#282828` was antialiased label text.

So: **sample the middle of a large solid region**, not a census. And note that colour
fidelity against the *reference* is not a goal anyway — the spec dictates `bpOrange`
and `bpTeal` rather than deriving them from Duolingo's green and blue.

### One capture trap that does bite

A screen mid-transition composites over the flow's paper ground and reads washed out —
S01's orange sampled as pale peach until `-bp-hold` was added to park the splash past
its 1.2s auto-advance. If a colour looks desaturated, check you are not screenshotting
during an animation before you touch a token.

---

## 3. Measured component metrics

All verified against our own render at the same scale — deltas noted.

### Page
- Side margin **16pt** for buttons, rows and cards.

### BPButton (S02)
| Property | Reference | Ours |
|---|---|---|
| Overall height | 48.0pt (144px) | 48.0pt ✓ |
| Face | 44pt | 44pt ✓ |
| Bottom edge | 4pt (12px) | 4pt ✓ |
| Width | 361.3pt | 361.0pt (1px, export rounding) |
| Corner | circular R ≈ 37px ≈ 12.3pt | 12pt circular |
| Face → edge darkness | ×0.81 | ×0.82 |

Face `#5ACD05` → edge `#5CA600`. The press **translates the face down over its edge**
by 4pt; the outer bounds never change.

### BPProgressBar (S06 short fill, S16 long fill)
- Capsule **16pt** tall. Track `#E7E4E7` ≈ `Hue.hairline`.
- Bar runs x **60.3pt → 377pt** (317pt wide), back arrow to its left.
- **Highlight stripe:** sampled `#5ACD05` → `#7ED733` = white at ~20% over the fill.
  Sits **4pt** down from the fill's top, **5pt** tall. This is the "texture".
- Fill stays a round lozenge at low progress (S06's fill is only 17pt wide), so the
  fill width must be floored at the bar height.

### BPRow (S06)
| Property | Reference | Ours |
|---|---|---|
| Overall height | 56.0pt (168px) | 56.0pt ✓ |
| Pitch / gap | 68pt / 12pt | 68pt / 12pt ✓ |
| Side margin | 16.3pt | 16.0pt ✓ |
| Border (top/sides) | 2pt | 2pt ✓ |
| **Bottom edge** | **4pt** | 4pt ✓ |
| Corner inset @12/20/30px | 8 / 3 / 0 px | 7 / 2 / 0 px |
| Icon chip | 41.0pt | 41.0pt ✓ |
| Chip inset from row edge | 17.0pt | 17.0pt ✓ |
| Chip → label gap | 16.3pt | 16pt |

Rows carry the **same 4pt 3D bottom edge as the buttons** — easy to miss, and a large
part of why they read as physical keys.

Selected recipe sampled: fill `#E1F4FF`, border `#1DB3FB` — the accent at ~12% over
white, with the accent itself as the border.

### Corners are CIRCULAR, not continuous
At 14pt `.continuous` our row was still 1px inset 36px down the edge where the
reference had reached full width by 30px. `.continuous` spreads curvature over a
longer run and never completes as sharply. This flow therefore uses
`.circular` — a deliberate, measured departure from the app's `.continuous` house rule.

---

## 4. Still provisional — re-measure before shipping

- `cardRadius` / card internals (measure against S17)
- `bubbleRadius` and tail size (measure against S05)
- `BPMockDialog` geometry (measure against S14) — it intentionally keeps
  `.continuous` corners because it mimics a real iOS alert
- Type sizes and tracking throughout — set by eye so far, not measured
- The soft tick under the typing bubble: `BPBubble.onTick` is wired but unbound.
  The app ships no audio infrastructure and no sound asset.

---

## 5. Verification harness

`-bp-components -bp-page N` renders the component bench one screenful at a time.

Page 0 is the **metrics bench**: full-width primitives at fixed offsets with no labels
or chrome, so the measurement scripts can be re-run against our own render and the
numbers compared directly instead of eyeballed.

Pagination is not cosmetic — this simulator setup has **no scroll or gesture
automation**, so a single long ScrollView could only ever be screenshotted at its top
and everything below the fold would go unverified while still looking covered.

---

## 6. Phase 1 additions (S01–S08)

Measured during the S01–S08 diff loop:

| Thing | Measured | Note |
|---|---|---|
| Bubble text size | ~19–20pt | Cap-height 14px @3x on S05's "W". First assumed 17pt — wrong, and it changes the whole bubble footprint |
| S03 bubble (1 line) | 180.7 x 54pt, **centred**, tail at its own **centre** | Content-sized, not full width |
| S05 bubble (2 lines) | 221.7 x 81.7pt, tail on the left at **0.43** of height | Text column 181.7pt |
| Bubble padding | ~20pt horizontal, ~16pt vertical | Derived from outer width minus text run |
| S05 mascot | 81.7 x 101.7pt, left inset 28.3pt, 13.3pt gap to bubble | Ours is square, so 74pt side carries similar mass |
| S03 mascot | ~110pt wide, centred under the bubble, ~20pt below it | |
| S01 mascot | 165.3 x 107.7pt, centred to the pixel, centre y = 413.5pt (0.485 of 852) | Symmetric margins 114.0pt each side |
| Back affordance | a full **arrow** (shaft + head), not a chevron | ~21pt |
| Top bar centre-line | 87pt from the top of the screen | |
| Status bar / top safe area | 59pt | |

### The bubble hugs its text

The single most visible miss in the first S01–S08 pass: our bubbles filled the available
width. Every reference bubble is content-sized. Fixed by capping the text column
(`BP.Metric.bubbleTextWidth`) instead of using `maxWidth: .infinity`.

Our copy is longer than Duolingo's, so line COUNT cannot always match — bubble geometry
is matched instead, and a prompt is allowed to wrap where theirs did not.

### S07 has no top chrome in the reference

S07 shows **no back arrow and no progress bar** — the region below the status bar is
empty. This contradicts §3 of the build prompt ("Present on S5–S20"). Currently built
per the SPEC (bar present). Open question for Jesse.

---

## 7. Phase 4 audit results

### Contrast (WCAG 2.1)

| Pair | Ratio | Threshold | Verdict |
|---|---|---|---|
| `bpTealText` on `bpTealTint` (selected row label) | **5.36:1** | 4.5 normal | PASS |
| `bpGray` on `paper` (taglines, captions) | 4.88:1 | 4.5 normal | PASS |
| `bpGray` on `fill` (disabled button label) | 4.51:1 | 4.5 normal | PASS |
| `ink` on `paper` (row labels) | 18.06:1 | 4.5 normal | PASS |
| **white on `bpOrange`** (primary button, 15pt bold caps) | **2.998:1** | 3.0 large | **marginal FAIL** |
| `bpOrange` on `surface` (secondary button label) | 2.998:1 | 3.0 large | **marginal FAIL** |

The white-on-orange pair misses by **0.07%** — a rounding-scale shortfall, not a visible
one. Left UNCHANGED because `bpOrange` is spec-locked and brand-derived (the Joetown
logo). For context, Duolingo's own green is **2.09:1** against white, so the reference
fails this far harder than we do.

One-character fix if wanted: `#E67633` → `#E47533` gives 3.05:1 and is 0.9% darker,
i.e. visually indistinguishable. `bpTealText` was already tuned to clear 4.5:1 as the
spec instructed.

### Reduce Motion — PASS

Verified with `ReduceMotionEnabled = 1`: bubbles render their full line with no type-on,
check badges appear filled, selected rows carry the tint/border/label recipe, and the
button press keeps its travel (the translation is the affordance, so it is retained, with
the spring flattened to a linear settle). **No state is gated on an animation that will
not fire.**

### Dynamic Type — NOT SUPPORTED (inherited)

At `accessibility-extra-extra-extra-large` the layout is **identical** to default —
nothing scales, so nothing breaks. That satisfies the checklist item as written
("Dynamic Type doesn't break layouts") but only in the trivial sense: a user who needs
larger text does not get it.

This is inherited from the app, not introduced here — the whole codebase uses fixed
`.system(size:)` / `.custom(_, size:)` with exactly one `@ScaledMetric` in 154 files. It
is a real accessibility gap and it is app-wide, so fixing it is a separate decision.

### Haptics

`Haptics.light()` on every button and row press-DOWN (with the travel, matching the
reference), `Haptics.selection()` on back, `Haptics.success()` on S20's "Join the party".
All route through the app's existing warm-primed generators, which no-op in Low Power Mode.
