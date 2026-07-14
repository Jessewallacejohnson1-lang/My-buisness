# Map pin hierarchy — rest dots, awake markers, collision labels

**Date:** 2026-07-13 · **Surface:** `Features/Map/` · **Reference feel:** Snapchat Map, Life360.

## Problem

Every map pin renders at full weight (a 44pt `MapPinBadge`), so the map reads flat —
nothing recedes, nothing earns attention. We want **most pins to recede to a small dot**
and only **a few to stand out** (saved / live / selected), with a clean visual hierarchy and
labels that never overlap.

## Pin states (one enum, one resolver)

```
enum PinDisplay { case rest, saved, live, selected }
```

Resolved in ONE place. Precedence **Selected > Live > Saved > Rest**:

| State | Trigger | Marker | Label |
|---|---|---|---|
| **Rest** | default | 6pt dot (Mapbox `circle-radius = 3`), fill `#1A1D21`@0.65, `#FFFFFF` 0.5pt stroke (survives beige land / sage parks / blue water) | none |
| **Saved** | in `SavedStore` (`hygge.saved.ids`) | full 44pt white badge + category icon in `mapInk`, **ink** `bookmark.fill` mini-badge top-right (NOT coral — coral is reserved) | name, if zoom ≥ T |
| **Live** | a real `club_events` event at the spot is happening now (`DateHelpers.isLiveNow`, `start ≤ now ≤ start+2h`) | full badge, coral `#FF6B57` (2pt ring, coral icon, coral dot badge, pulse ring) | name, if zoom ≥ T |
| **Selected** | user tapped it | full badge, **1.15×**, raised shadow, renders above all | name, **always** (ignores T) |

**Live wins while live** (user's call): a saved∩live spot renders **live**, and reverts to the
saved treatment the moment the event ends. So the precedence chain already encodes it — no
stacking branch. Selection still beats live (a tapped live pin shows the selected badge; its
pulse is suppressed while selected, matching today's behavior).

## Architecture — style layers + a thin SwiftUI overlay

Mapbox **v11.25.1**. The non-negotiable **label-label collision** (Mapbox `text-allow-overlap:false`
+ `symbol-sort-key`) is a `SymbolLayer` feature, and "rest dot always visible / label drops
independently" needs dot and label on **separate layers** — neither is possible with SwiftUI
`MapViewAnnotation`. So:

- **`GeoJSONSource` `pins`** — 6 point features, `identifier = spot.id`, properties
  `{ state: "rest"|"saved"|"live", sortKey: Number, name: String }`. `state` is the resolver's
  output **with selection ignored** (selection is layered on separately). Rebuilt only when
  saved-set / liveness / filter changes (6 features — cheap). `promoteId`/feature `id` so
  feature-state can target a pin.
- **`CircleLayer` `pin-dots`** — the recessive rest dot for **every** pin, at **all zooms**
  (radius 3). Awake pins' 44pt badge (overlay, drawn above all Mapbox layers) fully covers the
  6pt dot, so no dot toggling is needed; when a pin sleeps, the badge disappears and the dot is
  revealed. (At the min wake scale 0.6 the badge is ~26pt — still covers the centered 6pt dot,
  so it never peeks.)
- **`SymbolLayer` `pin-labels`** — text labels, **filtered to `state != "rest"`** (only awake
  pins get labels). `text-field = name`, `text-allow-overlap = false`, `icon-allow-overlap`
  n/a (no icon in this layer), `symbol-sort-key` from `sortKey` (**lower wins** in Mapbox
  collision → `live = 0`, `saved = 1`). Label placed below the badge via `text-offset`.
- **SwiftUI overlay (`MapViewAnnotation`, awake pins only, ≤6, usually 0–2)** — the rich
  `MapPinBadge` for saved / live / selected: preserves `mapFloatShadow`, the wake spring, the
  selected scale, and the live `PulseRing`. This is "the few that stand out." Reuses the badge
  we already ship.

### Selection = flip ONE property (the Mapbox gotcha, handled)

feature-state is **paint-only** in Mapbox (layout props like `text-size` / `*-allow-overlap` /
`symbol-sort-key` can't read it). So selection never touches layout:

1. `setFeatureState(sourceId: "pins", featureId: id, state: ["selected": true])` on the one
   tapped feature.
2. `pin-labels.text-opacity` reads `["feature-state","selected"]` (paint) → the selected
   feature's **in-layer label fades to 0**.
3. The **overlay** draws the rich selected badge **and** its always-on label (SwiftUI, above
   everything, no collision) → "selected label always, ignores T, above all others."

No source re-diff on selection; saved/live changes are infrequent 6-feature source updates.

## Zoom threshold & label crossfade

- **T = 14.5.** `pin-labels.text-opacity = interpolate(linear, zoom, T-0.2 → 0, T → 1)` — a
  soft 0.2-zoom band instead of a hard step, which is what prevents strobing when a pinch hovers
  on the line (the pragmatic stand-in for true directional hysteresis; revisit only if
  screenshots strobe). Property transition ~150ms so it crossfades, never pops. Selected
  overrides via feature-state (label always on, in the overlay).
- Rest **dots stay visible at all zooms** (circle layer has no zoom gate).

## Hit targets

Rest dots are 6pt visual but must tap at ≥44×44. Awake badges (overlay) already have a large
SwiftUI tap area. For rest dots: on map tap, `queryRenderedFeatures` over a **44×44 rect**
centered on the tap point against `pin-dots` → resolve the spot id → select. (No extra hit layer
needed; the rect query gives the enlarged target.)

## Motion (all Reduce-Motion-gated → crossfade only)

- **rest → awake** (badge appears): opacity 0→1 + scale **0.6→1.0**, spring ~**220ms**, damping
  tuned for **<5% overshoot**. SwiftUI `.transition(.scale(0.6).combined(with:.opacity))` +
  `.spring(response: 0.22, dampingFraction: 0.72)`. RM → opacity crossfade, no scale.
- **selected**: 1.0 → **1.15**, **160ms ease-out** (`.easeOut(duration: 0.16)`). RM → no scale
  (shadow/label change only).
- **live pulse**: keep `PulseRing` (coral 0.35→0, scale 1→2.2, 1.5s). RM → static, no pulse.

## Saved wiring (no backend, no schema)

- Reuse device-local **`SavedStore`** (`hygge.saved.ids`, `ExploreKit.swift`) with the 6
  map-spot ids. `SavedStore` is already an observable singleton.
- Add a **Save/bookmark toggle** to the spot detail header in `MapSheet.detailContent` (top-right
  of the name row), reusing the `bookmark`/`bookmark.fill` + `symbolEffect(.bounce)` language
  from `SaveBookmarkButton` — but **ink, not coral**, on the map (coral stays live-only).
- The map observes `SavedStore.shared`; toggling a spot rebuilds the source `state` for that pin
  (rest ↔ saved), so its marker updates live.

## State ownership

- One `PinDisplay` enum + one resolver `display(for spot:, selectedId:, isLive:, isSaved:)`.
  The GeoJSON `state` property uses the resolver with `selectedId = nil` (base state); the
  overlay + feature-state add the `.selected` layer. No state logic scattered across views.
- `MapModel` continues to own `todayEvents` + the realtime/clock pipeline (liveness source).
  Selection stays `SJMapView.@State selectedSpot`. `SavedStore.shared` is the saved source.

## DEBUG launch args (headless screenshot verification)

Add to the existing family in `SJMapView`:
- `-map-zoom <z>` — start the camera at a given zoom (pairs with existing `-map-center`).
- `-map-save <spotid>` — seed a spot into `SavedStore` at launch (DEBUG) so the saved marker renders.
- `-map-force-live <spotid>` — force `isLive` true for a spot so the live marker + pulse render
  without a real live event.
Existing `-map-open <spotid>` covers the selected state.

## Acceptance (screenshots)

z12 (all rest) · z14 (at threshold) · z16 (labels on) · one selected · one saved · one live ·
one dense downtown cluster (downtown + chapel + saintbens at z16) proving labels don't collide.
Build clean (0 warnings) + confirm each in the simulator, per repo discipline.
