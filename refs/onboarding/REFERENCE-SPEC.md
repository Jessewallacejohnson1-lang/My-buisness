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

### Colour cannot be compared pixel-to-pixel — geometry can

Simulator screenshots and the reference PNGs are in different colour encodings and
neither carries an ICC profile. Near-neutrals land within ~1–7/255, but saturated
colours shift materially (our `#E67633` orange reads back as `#E88347`, a ~35 L1
delta; `Hue.ink` text reads `#282828`).

This is a capture artifact, not a token bug — the token relationships are intact
(our face→edge ratio 0.82 vs the reference's 0.81). **Do not chase it.** It does not
matter for fidelity either, because the spec *dictates* our colours (`bpOrange`,
`bpTeal`) rather than deriving them from the reference. Compare geometry in pixels;
compare colour against token values.

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
