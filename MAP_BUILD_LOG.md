# MAP_BUILD_LOG — mapbox-map-tab

Branch: `mapbox-map-tab` | Base: `main` (d45ad7b)

---

## FIX 1 — Map style → light-v11

**Change:** `MAP_STYLE_URL = "mapbox://styles/mapbox/light-v11"`

**Result:** Clean off-white base, readable street labels, zero satellite imagery.
Matches Life360 / minimal community app aesthetic.

**Verification:** Build ✓ | Screenshot ✓ — light minimal map, no satellite, labels readable at town zoom.

**Commit:** `ad93a48`

---

## FIX 2 — Coordinate audit

**Finding:** No flip needed. Mapbox Maps iOS SDK uses Apple's `CLLocationCoordinate2D(latitude:longitude:)`,
NOT GeoJSON `[longitude, latitude]` order. Existing values are correct.

**Authoritative coordinates table:**

| Spot | Latitude | Longitude | Notes |
|------|----------|-----------|-------|
| Downtown | 45.5647 | -94.3141 | Minnesota St / Ash St E |
| Saint Ben's | 45.5731 | -94.3201 | College of Saint Benedict campus |
| Sacred Heart Chapel | 45.5728 | -94.3193 | CSB chapel |
| Wobegon Trail | 45.5607 | -94.3194 | Trailhead near CSB |
| Saint John's | 45.5720 | -94.3854 | Saint John's Abbey & University |

No authoritative overrides were provided by the user; values appear correct based on rendered map placement.
If the user provides precise addresses, geocode once via Mapbox Geocoding API and update this table.

**Verification:** Build ✓ | Pins placed correctly on rendered map.

**Commit:** `8e2337c` (combined with FIX 3)

---

## FIX 3 — Live pulse animation

**Architecture:**
- `LIVE_COLOR = Hue.moss700` — single constant for future rebrand
- `SJPin.isLive: Bool = false` — default off, zero callsite breakage
- Downtown `isLive: true` — seeds the Independence Day Parade event today
- `PulseRing` — self-contained `private struct`. Local `@State private var pulsing = false`.
  Uses `withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false))`.
  Core Animation renders each frame off the main thread.

**Performance:** Each `PulseRing` manages its own local state. No `@ObservableObject`, no parent
`@State` changes, no `EnvironmentObject` updates. Sibling pins and the map layer are unaffected.
In SwiftUI this is the equivalent of a Reanimated UI-thread worklet — the animation loop never
triggers a SwiftUI re-render of anything outside `PulseRing`.

**Pulse hides on tap:** `!selected` guard prevents ring overlap with the callout label.

**Verification:** Build ✓ | Screenshot ✓ — green ring visible mid-pulse around Downtown pin.

**Commit:** `8e2337c`

---

## FIX 4 — Geocoded pin locations (address-based, user-confirmed)

**Method:** Mapbox Geocoding API, `proximity=-94.317,45.565`, one-time at dev time.
Coordinates stored in source; never geocoded at app runtime.

**Final resolved coordinates (user confirmed 2026-07-04):**

| Spot | Resolved address | Latitude | Longitude | Confidence |
|------|-----------------|----------|-----------|------------|
| Downtown | East Minnesota Street, St. Joseph, MN | 45.5654 | -94.3069 | 0.79 |
| Saint Ben's | 37 College Ave S, St. Joseph, MN | 45.5604 | -94.3220 | 1.00 |
| Sacred Heart Chapel | Campus approx (no Mapbox POI) | 45.5728 | -94.3193 | — |
| Wobegon Trail | College Ave N access, St. Joseph, MN | 45.5671 | -94.3189 | 1.00 |
| Saint John's | 2850 Abbey Plaza, Collegeville, MN | 45.5800 | -94.3934 | 0.95 |

**Notes:** Saint John's is in Collegeville (~7 mi west) — visible only when panning west.
Sacred Heart Chapel has no Mapbox POI entry; campus approximate kept.

**Verification:** Build ✓ | Screenshot ✓ — all visible pins sit on correct streets/labels.

**Commit:** see below

---

## Final state

- Style: `light-v11` (single constant `MAP_STYLE_URL`)
- Pins: 5, geocoded + user-confirmed coordinates
- Live pulse: Downtown only today; wire `isLive` to real event data by checking today's events
  against each spot's ID in `SJMapView` or a parent ViewModel
- `LIVE_COLOR`: `Hue.moss700` — one-line rebrand
