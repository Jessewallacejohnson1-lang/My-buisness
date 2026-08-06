# Town rain — reference measurements

The map's town-rain drop (`Features/Map/TownRain/`) is a frame-by-frame port of a reference
screen recording, in the same spirit as the corner drawer and the share reveal. The MOTION
constants are fits against the numbers below rather than choices, and `TownRainPhysicsTests`
pins each inside its measured spread so a later "tidy-up" that drifts the feel fails the
suite. Three constants ARE choices, because the reference could not supply them:
`burstCount` (its clip ends mid-burst), `floorInset` (this app's contact surface is its own
map sheet), and `spawnXRange`'s lower bound. Those are called out where they appear.

**Reference:** `ScreenRecording_08-03-2026 10-55-12_1.MP4` — 6.84 s, 1206×2622 @ 59.84 fps,
a third-party iOS app dropping food emoji down its screen. Only the motion was ported; none
of that app's art, copy or layout is reproduced here.

## Method

1. **Extract** every frame at 60 Hz (`AVAssetImageGenerator`, zero time tolerance), quarter
   scale for the tracking pass.
2. **Background plate** = the per-pixel *median* across all frames. Sprites are transient, so
   the median is the static UI; anything far from it is a sprite. (Also why the reference
   app's idle logo wiggle had to be masked out — a *moving* static element survives the
   median.)
3. **Blobs** = 8-connected flood fill over pixels ≥ 26/255 from the plate, ≥ 12 px area.
4. **Tracks** = nearest-neighbour linking with a constant-velocity prediction, tolerant of
   up to 5 dropped frames.
5. **Fit** each flight segment with least squares, `y = y₀ + v₀·t + ½g·t²` and `x = x₀ + vₓ·t`,
   splitting the track at its lowest point (the floor contact).

Scripts: `scripts/track_rain.swift` (steps 1–3) and `scripts/fit_rain.py` (steps 4–5).

```bash
swiftc -O scripts/track_rain.swift -o /tmp/track
/tmp/track reference.mp4 60 0.075 0.88 > /tmp/blobs.tsv
python3 scripts/fit_rain.py /tmp/blobs.tsv
```

## What the reference does

Sprites enter **at rest** just above the top edge and fall under gravity — they are not
launched. Each carries a constant leftward horizontal velocity, tumbles slowly in flight,
bounces once off the top of the app's bottom bar, tumbles much faster afterwards, and exits
stage left. At steady state one enters every ~0.21 s and five to seven are airborne at once.

### Per-track fits — the six clean, full-length tracks

| track | spawn | fall g (pt/s²) | vₓ (pt/s) | bounce v (pt/s) | fit RMS |
|-------|-------|----------------|-----------|-----------------|---------|
| 0  | 1.783 s | 1044.3 | −236.4 | −435.0 | 4.1 px |
| 5  | 4.817 s | 1071.7 | −214.7 | −427.2 | 10.1 px |
| 6  | 5.017 s | 1098.3 | −206.9 | —      | 5.6 px |
| 7  | 5.217 s | 1101.3 | −257.0 | —      | 5.9 px |
| 8  | 5.433 s | 1130.0 | −281.1 | —      | 9.8 px |
| 9  | 5.650 s | 1106.0 | −296.7 | −428.8 | 8.7 px |

Four further tracks were too short or too low-contrast to fit (they spawned on the left and
drifted off-screen almost immediately) and are excluded rather than averaged in.

### Derived constants

| quantity | measured | shipped |
|---|---|---|
| gravity | 1044–1130 pt/s², mean **1092** | `gravity = 1090` |
| restitution | 0.336, 0.328, 0.324 → **0.33** | `restitution = 0.33` |
| horizontal drift | −207…−297 pt/s, **always leftward** (10/10 tracks) | `driftRange = -300…-205` |
| spawn cadence | 0.200, 0.200, 0.217, 0.217 s | `spawnInterval = 0.21` |
| sprite size | bbox 96–112 px @3x → 32–37 pt | `ballSize = 36` |
| entry | at rest, ~½ sprite above the top edge | `y = -size/2, vy = 0` |
| tumble | ~110°/s in flight, ~720°/s after contact | `flightSpinRange`, `bounceSpinRange` |
| concurrent | 5–7 airborne | 14 balls × 0.21 s ⇒ 5–7 |

Gravity landing on ~1090 pt/s² is a strong hint the reference is UIKit Dynamics with a
default `UIGravityBehavior` magnitude of 1.0 (= 1000 pt/s²), nudged slightly.

The reference's clip ends while sprites are still spawning, so its **burst length is
unknown**. 14 was chosen here — it holds the measured density for the length of the 0.8 s
camera fly and a beat after, then clears.

## Verifying the shipped build

There is no tap automation in this setup and the drop's trigger is a real touch on the town
pill, so `-town-rain-preview` (a `RootView` gate) renders the field full-screen and loops a
burst. Record it and run the *same* tracker over the result:

```bash
xcrun simctl launch <udid> Jesse.Hygge -town-rain-preview      # add -poi-logo-stub for offline
xcrun simctl io <udid> recordVideo --codec h264 /tmp/rain.mp4
/tmp/track /tmp/rain.mp4 60 0.055 0.85 > /tmp/sim.tsv
python3 scripts/fit_rain.py /tmp/sim.tsv
```

Measured off the build at `integration/block-party` (commit `15f0da9`), restricted to long clean tracks (n ≥ 24
samples), across two runs — the second after the review pass retuned `spawnXRange` and gave
each ball its own post-bounce tumble:

| quantity | reference | run 1 | run 2 |
|---|---|---|---|
| gravity | mean 1092 pt/s² | median 1096 | median 1128 (1054–1306) |
| restitution | 0.324–0.336 | 0.334 | — |
| drift | −207…−297 pt/s | −213…−300 | −216…−307 |
| cadence | 0.200–0.217 s | 0.183–0.233 | 0.167–0.233 |
| balls per burst | unknown | exactly 14 | exactly 14 |
| tracks reaching the floor | 3 of 6 | 6 of 25 | **15 of 30** |

**Read the gravity column as agreement, not as drift.** The two quantities a trace derives
from the same tracks disagree in *direction*: run 2's fitted g sits 3.5% ABOVE the modelled
1090, while its fall durations (median 0.83 s from first detection) sit ~5% above the 0.79 s
that same 1090 predicts — i.e. they imply gravity is simultaneously too strong and too weak.
That is the signature of a noise-dominated fit, not of a model that moved. The model
integrates one constant `g` for every ball by construction, and
`testGravityMatchesTheMeasuredReferenceRate` pins it at 240 Hz where there is no tracker in
the loop. Treat this table as a ±5% sanity check on the shipped runtime — it confirms the
display link is feeding the integrator sane timesteps — and treat the unit tests as the
statement of the physics.

The one row that IS a clean signal is the last: raising `spawnXRange`'s lower bound from
0.25 W to the measured 0.55 W took the share of balls that survive to bounce from ~24% to
50%, matching the reference's 3-of-6.

**Two artifacts to expect when reading a shipped-build trace**, neither of them a defect:

- **Sprite size reads ~25 pt, not 36 pt.** The white disc is only ~5/255 away from `Hue.paper`,
  far under the blob threshold, so the tracker locks onto the *mark inside* the ball. 25.2 pt
  is what a 36 pt disc holding a white-padded 256 px PNG should measure.
- **The per-track gravity spread is wider than the reference's.** The tracked centroid is the
  mark inside a *rotating* disc, so it wobbles a few points around the true centre; short
  segments pick that up as fit noise. The model integrates one constant `g` for every ball
  by construction — see `testGravityMatchesTheMeasuredReferenceRate`.

Fall time differs on purpose: the reference's floor sat 108 pt above its screen bottom, this
app's is the map sheet's peek edge at 162 pt, so spawn→contact is 1.14 s here against 1.19 s
there. The constants that produce it are identical.
