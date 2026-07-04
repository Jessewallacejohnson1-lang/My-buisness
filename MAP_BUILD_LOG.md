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

---

## VISUAL SYSTEM — Life360-clean, warm coral (2026-07-04)

Mission: replace emoji/filled-SF-Symbol markers with a clean icon system, coral accent,
bottom card, floating recenter button. All four phases land in a single build.

### Design tokens added

**HyggeColor.swift** — new `// MARK: Map visual system` section:

| Token | Hex | Role |
|-------|-----|------|
| `Hue.accent` | `#FF6B57` | Live indicators + primary tappable elements |
| `Hue.accentPressed` | `#E5503C` | Directions button pressed state |
| `Hue.accentSoft` | `#FFF0EC` | Soft tint (reserved) |
| `Hue.surface` | `#FFFFFF` | Floating bubbles, card, recenter button |
| `Hue.bgSubtle` | `#F6F7F8` | Subtle backgrounds (reserved) |
| `Hue.gray` | `#6B7280` | Secondary text (happening times) |
| `Hue.grayLight` | `#9CA3AF` | Caption text (spot description) |
| `Hue.mapInk` | `#1A1D21` | Primary text + icons |
| `Hue.mapHairline` | `#E5E7EB` | Borders + grabber pill |

**HyggeMetrics.swift** — two new shadow extensions:
- `mapFloatShadow(pressed:)` — y=2, blur=10/14, 10%/18% (floating elements)
- `mapSheetShadow()` — y=−2, blur=16, 8% (bottom sheet)

DISCIPLINE RULE enforced: `grep` for stray hex codes and old palette tokens
(`moss`, `clay`, `honey`, `paper`, `sky[0-9]`, `ink[23]`) in `Features/Map` → **0 matches**.

---

### Phase 1 — Icon system

`SJPin.symbol: String` replaced by `PinCategory` enum with computed `symbol: String`.
All SF Symbols use non-filled, `.medium` weight — clean line appearance.

**Icon mapping table (Lucide analogue → SF Symbol):**

| Category | Lucide icon | SF Symbol | Used by |
|----------|-------------|-----------|---------|
| `.trail` | `TreePine` | `figure.hiking` | Wobegon Trail |
| `.park` | `Trees` | `tree` | (reserved) |
| `.downtown` | `Store` | `storefront` | Downtown |
| `.coffee` | `Coffee` | `cup.and.saucer` | (reserved) |
| `.fitness` | `Dumbbell` | `dumbbell` | (reserved) |
| `.college` | `GraduationCap` | `graduationcap` | Saint Ben's, Saint John's |
| `.chapel` | `Building` | `building.columns` | Sacred Heart Chapel |
| `.default` | `MapPin` | `mappin` | fallback |

Zero emoji remain. Zero `book.fill`, `cup.and.saucer.fill`, `building.columns.fill` (filled).

---

### Phase 2 — Marker bubbles

- **Base:** 44px `Hue.surface` circle, 1px `mapHairline` border, `mapFloatShadow()`,
  20px icon in `mapInk` at weight `.medium`. No pointer tail; bubble anchors at center.
- **Live:** 2px `accent` border, accent icon, 10px accent dot badge offset `(+17, −17)`
  (top-right edge of 44px circle) with 2px `surface` ring.
- **Pulse:** `PulseRing` recolored to `LIVE_COLOR` (now coral). Opacity `0.35→0`,
  scale `1→2.2`, 1.5 s linear loop, local `@State` — zero sibling re-renders.
- **Selected:** `scaleEffect(1.15)`, `mapFloatShadow(pressed: true)` (deeper shadow).
  `MapTriangle` shape removed.

---

### Phase 3 — Bottom card

`MapBottomCard` private struct. Slides up from bottom via `.move(edge: .bottom)` +
`.opacity` transition, spring `response: 0.4, dampingFraction: 0.85`.

- White sheet, `UnevenRoundedRectangle(topLeadingRadius: 20, topTrailingRadius: 20)`,
  `mapSheetShadow()`. Background uses `.ignoresSafeArea(edges: .bottom)` to fill
  behind the home indicator; content padding stops at safe area.
- Grabber pill: 36×4 `mapHairline`, centered, 8pt from top.
- Name: `displaySemi(20)` `mapInk`. Description: `sans(13)` `grayLight`.
- Happenings: 6px accent dot • `sansMedium(15)` `mapInk` left, `sans(13)` `gray` right,
  13pt row gap.
- Directions: full-width 50pt `AccentPillStyle` (accent → accentPressed on press),
  `sansSemibold(16)` white. Opens `maps://` via `@Environment(\.openURL)`.

Sample data: Downtown (live) carries 2 happenings. Quiet spots show name + description only.

---

### Phase 4 — Chrome

- **Recenter:** moved from header to floating bottom-right, 16pt trailing + 16pt above
  safe-area bottom (tab bar). 44px `surface` circle, `mapHairline` border,
  `mapFloatShadow()`, `location` icon (non-filled) in `mapInk`. Press clears selection.
- **Header:** title-only "Saint Joseph" in `displaySemi(20)` `mapInk` + `ultraThinMaterial`
  + `mapHairline` bottom line.
- **Loading/error:** no change needed — no explicit loading/error states existed.

**Build:** ✓ (0 errors, 0 warnings) | **Grep audit:** ✓ (0 stray values in map components)

---

## Final state

- Style: `light-v11` (single constant `MAP_STYLE_URL`)
- Pins: 5, geocoded + user-confirmed coordinates, category-based SF Symbol icons
- Live pulse: Downtown only today (coral); wire `isLive` to real event data by checking
  today's events against each spot's ID in `SJMapView` or a parent ViewModel
- `LIVE_COLOR = Hue.accent` — one-line rebrand
- One theme file (`HyggeColor.swift`) governs all map colors; `HyggeMetrics.swift` governs
  all map shadows. Zero hardcoded values in `Features/Map`.
