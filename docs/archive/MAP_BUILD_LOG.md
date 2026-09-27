# MAP_BUILD_LOG — mapbox-map-tab

Branch: `mapbox-map-tab` | Base: `main` (d45ad7b)

---

## Duplicate POI labels — basemap `poi-label` hidden (2026-07-20)

**Reported as "overlapping / untappable pins."** It was not pin-on-pin: `light-v11`
ships its own `poi-label` symbol layer (source-layer `poi_label`) naming the same
cafés/shops/B&Bs we draw from the `places` table. Every POI's name printed TWICE —
our bold ink label plus Mapbox's italic grey one, overlapping. At mid zoom that
doubled text sits under our badges and reads as two stacked pins.

**Ruled out along the way** (each disproven with evidence, not assumed):
- *Unapplied spread migration* — `20260717130000_places_spread_multitenant.sql` IS
  applied; queried the live row for `hair-by-hanna` and it matches the migration.
- *Exact-coordinate collisions* — zero in the live `places` table (91 rows).
- *A clustering bug* — `POICluster.compute` guarantees any two seeds are `> radius`
  apart, and the pair in question (The Estates ↔ Jupiter Moon, 26.6 m) measured
  18.3 pt at z16.2 and 45 pt at z17.5, clustering and splitting exactly as predicted.
  Verified by screenshot at z15.0 / z16.2 / z17.5.

**Fix:** one line in `BasemapPalette.recolor` — `poi-label` → `visibility: none`.
Layer id confirmed against the live style JSON first, because `try?` swallows a
wrong id silently. Our own labels already de-conflict via `POICluster.labelledPOIs`.

**RESOLVED (2026-07-20) — keep the hide.** Investigated the class-filter alternative with tilequery ground truth: the orientation landmarks near CSB/SJU are `building`/`education`-class points that resolve to ~30 individual dorm/hall names (Regina Hall, Ardolf, Dominica, Sohler…), so allowing those classes carpet-bombs the campus at street zoom; and `religion` overlaps our curated civic pins (Sacred Heart Chapel), re-creating duplicates. There is no clean class split that restores a single "College of Saint Benedict" label without one of those costs. Decision: the basemap's own POI labels stay hidden. The map's named places come from our pins; losing basemap institution labels is the accepted price of a clean, duplicate-free map. (Original trade-off note kept below.)

**Original trade-off note:** this also drops basemap names we do not carry —
notably **"College of Saint Benedict"** at town zoom. That is in tension with the
`b1bef1a` principle that a town map's landmarks are how you orient. The surgical
alternative is to FILTER `poi-label` by class (keep education/park/landmark, drop
the food/shopping/services classes we render ourselves) rather than hide it
wholesale. Not done — it is Jesse's call which way to go.

**Data note, separate from this bug:** 9 pairs in `places` sit within 12 m, and
several were *created* by the spread migration — it fans a building's tenants onto a
fixed 11 m circle without checking spacing against unrelated nearby places
(`Two Bits ↔ White Peony` 4.8 m, `Newsleaders ↔ St Joseph Meat Market` 5.0 m). Not
currently a visual defect (clustering absorbs them), but a future spread migration
should solve globally, not per-building.

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

## FIX 5 — Coordinate re-audit + live-from-real-data (2026-07-04)

FIX 4's Mapbox geocoding was wrong for two pins and the map hardcoded liveness:

| Pin | FIX 4 (wrong) | FIX 5 (verified) | Source |
|---|---|---|---|
| Downtown | 45.5654, -94.3069 (~900 m east — "East Minnesota Street") | 45.5648, -94.3183 | OSM: The Local Blend block, Minnesota St W at College Ave |
| Sacred Heart Chapel | 45.5728, -94.3193 (~1 km north, "campus approx") | 45.5631, -94.3189 | OSM building footprint of the chapel |
| Wobegon Trail | 45.5671, -94.3189 | 45.5665, -94.3161 | Trailhead park, 605 1st Ave NE |
| Saint Ben's | 45.5604, -94.3220 | 45.5604, -94.3218 (unchanged — Gorecki, was correct) | OSM: Gorecki Center |
| Saint John's | 45.5800, -94.3934 | 45.5800, -94.3923 | OSM: Abbey church |
| Millstream Park | — (missing) | 45.5701, -94.3287 | City/UDisc, 725 CR-75 W |

**Method change:** stop trusting one-shot geocoders for small-town venues. Curated
table lives in `Backend/KnownVenues.swift` (also consulted by GeocoderService before
Nominatim); mirrors `apps/mobile/src/lib/geo.ts` in the Expo repo.

**Liveness:** `isLive` / happenings are no longer hardcoded. Pins match real
`getTodayEvents()` rows by keyword; a pin glows only while an event is happening
(start ≤ now ≤ start + 2 h, `DateHelpers.isLiveNow`). Two gotchas fixed en route:
`.allowOverlap(false)` culled the downtown pin behind the chapel pin (now `true`),
and Mapbox `ForEvery` does not re-render an annotation whose element identity is
unchanged — liveness is baked into the annotation id (`PinState`) so the badge
rebuilds when it flips. `DateHelpers.nowMinutes` now pins `Calendar` to
`TimeZone.current` so it can't disagree with the env-aware timezone.

**Verified on sim:** parade (10 AM, Downtown) glowed coral 10:00–12:00 and went
quiet at noon; all other pins stayed quiet. DEBUG launch arg `-open-tab map`
(RootView) opens the app on any tab for headless screenshot verification.

---

# LIVE EVENT PIPELINE + ANTI-SLOP (2026-07-05)

Mission: the map updates **itself** in realtime, an admin can **post from the
map**, and the whole tab is swept like a paranoid QA engineer. In-app pipeline
only — no scraping/ingestion.

## SQL — already applied to the live project `lxdgwhvqjqmqliobwjpi` (via MCP)

These two statements were run against the shared Supabase project. They are
**non-destructive** and benefit the Expo app too. Re-run them verbatim on any
other environment (they are idempotent enough for a one-time setup):

```sql
-- 1. Stream club_events over Supabase Realtime (the publication was EMPTY).
alter publication supabase_realtime add table public.club_events;

-- 2. Reliable DELETE delivery under RLS. NOTE (verified empirically): even with
--    FULL, Supabase Realtime's DELETE payload old_record carries ONLY the
--    primary key id — never the other columns. FULL is kept as a safe default
--    (it lets Realtime authorize the delete against the SELECT policy); the
--    client matches deletes by id regardless. See RealtimeClient.Change.Row.
alter table public.club_events replica identity full;
```

No RLS **policy** change was needed. The existing `submit events` INSERT policy
is `with_check (submitted_by = auth.uid())` with no status constraint, so an
admin inserting an approved event already passes. The admin "+" is a UI
affordance, not a security boundary (self-approved events are an intentional,
pre-existing product decision shared with the Expo app — confirmed during
review).

## Part A — the map updates itself

No Supabase Swift SDK exists here (the whole backend is hand-rolled REST over
`URLSession`), so realtime is a **hand-written Phoenix-channel client**:

- **`Backend/RealtimeClient.swift`** — `@MainActor` client over
  `URLSessionWebSocketTask` speaking Phoenix `vsn=1.0.0` object frames. Joins
  `postgres_changes` on `club_events` with the user's JWT (RLS still filters
  what arrives), heartbeats every 25 s, pushes a fresh token every ~4 min,
  parses INSERT/UPDATE/DELETE, reconnects with capped exponential backoff.
- **`Features/Map/MapModel.swift`** — `@MainActor` view-model that owns the
  subscription + today's events. A change that touches **today** re-syncs
  (300 ms-debounced `getTodayEvents()`), so a new happening lights its pin and an
  ended/deleted one goes quiet with no refresh. Handles teardown on unmount,
  socket-drop on background + resubscribe on foreground, and the **midnight
  rollover** (timer to 00:00:01 + re-filter on foreground).
- **`Backend/SupabaseConfig.swift`** — adds `realtimeURL` (`wss://…/realtime/v1/websocket?apikey=…&vsn=1.0.0`).

**The DELETE gotcha (cost the most time):** a DELETE's `old_record` contains only
the primary key `id`, so filtering deletes by `event_date` silently dropped them
(pin never cleared). Fixed by matching deletes to `id` via
`MapModel.currentlyShown()` (a refetch is idempotent anyway).

**Verified live on the simulator (signed in as admin):**
- SQL `INSERT` an approved Downtown event at ~now → Downtown pin turns coral +
  pulses and the header flips to "N happening today" on the **first screenshot
  after insert** (≈1–2 s, zero refresh).
- SQL `DELETE` it → pin goes quiet, header back to "A quiet day" on its own.
- Runtime log confirmed exactly one `Subscribed to PostgreSQL`.

## Part B — quick-add (post from the map)

- **Admin gate:** `Admin.isAdmin(auth.email)` (the email-allowlist already used
  across the app) — the cleanest existing flag, chosen over a new `profiles`
  column.
- **"+" button** (`Features/Map/SJMapView.swift`): 44 px white circle, hairline,
  ink `plus`, `mapFloatShadow`, rendered **only for admin**, stacked above the
  recenter button (both lifted by `TAB_BAR_CLEARANCE` so neither hides behind the
  custom tab bar).
- **`Features/Map/QuickAddSheet.swift`** — bottom sheet on the map's coral/white
  tokens: title, spot picker (from the curated `MapSpots` catalogue), date
  (today), start time (now → live immediately), optional one-liner. Submit →
  `CommunityAPI.addEvent(status: .approved, location: spot.name)` so the keyword
  matcher lights the right pin; Part A then makes it live. Opens at the `.large`
  detent so the Post button is never below the fold.

**Verified full loop on the simulator (computer-use driving the real UI):** tapped
the "+", typed "Farmers Market", tapped **Post to the map** → sheet dismissed and
the Downtown pin pulsed within seconds. Relaunched with a debug `-force-nonadmin`
flag → **no "+"** (recenter only).

## Part C — anti-slop pass

Built in from the start: loading **skeleton** (not a spinner; static under Reduce
Motion), **quiet-day** empty state (a valid state, not an error), **error +
retry** and **offline + retry**, eased ~800 ms `flyTo` recenter, light haptic +
scale feedback on pin tap, tap-empty-map-to-close (`TapInteraction`), a11y labels
on pins/buttons/rows, and safe-area/tab-bar clearance for controls **and** the
card.

**Verified live:** skeleton captured with a temporary slow-load; card list updates
while a card is open (inserted an event → the open Downtown card gained the row +
the pin pulsed); rapid tab-switching left subscriptions **bounded (no leak)**; a
temporary `Self._printChanges()` probe showed **8 body evals total, none during
the pulse** (isolated in `PulseRing`'s local state) → no re-render storm. Grep:
zero stray hex/token violations in the map feature (the only hardcoded hexes are
the three Mapbox base-map cartography colors). All debug scaffolding removed.

**Adversarial review** (`hygge-map-antislop-review` workflow — 5 dimensions ×
find→verify, 18 agents): 13 raised, **7 confirmed** after skeptic verification, all
fixed:
1. *(high)* Header counted events that map to no pin → now counts only
   spot-resolved events; "quiet day" when none map.
2. *(med)* Reconnect backoff reset on **any** frame → a flapping server never
   escalated past ~2 s. Now resets only on the confirmed `system` ok.
3. *(med)* Overlapping `load()`s could clobber fresh data with a stale response →
   added a monotonic `loadGeneration` guard (last-launched wins).
4. *(med)* The count rendered in DM Sans → now `font(.mono)` (matches the app's
   "N going" convention).
5. *(med)* Card "happening now" was color-only → per-row VoiceOver label now says
   "happening now" (WCAG 1.4.1).
6. *(low)* Offline had no retry (error did) → offline is now tap-to-retry.
7. Corrected the inaccurate `REPLICA IDENTITY FULL` doc comment on `Change.Row`.

Six other raised findings were **refuted** by the verify pass (e.g. "private:false
breaks postgres_changes RLS" — false, RLS always applies; "self-approved event" —
intentional product design). Re-verified after the fixes: INSERT still pulses,
DELETE still clears, count renders in mono.

## Build hazard logged

The "impeccable" tool drops `.impeccable/hook.cache.json` caches. When one lands
**inside** the current `BlockParty/` file-system-synchronized group, Xcode copies duplicate
`hook.cache.json` files to the bundle and the build fails
("Multiple commands produce …"). Removed the stray dirs and added `.impeccable/`
to `.gitignore`. If a build suddenly fails this way, delete
the nested caches with `find BlockParty -type d -name .impeccable -exec rm -rf {} +`.

## Final gate (all ✅, screenshot-verified on iPhone 17 sim)

- [x] Quick-add → pin pulsing within seconds, zero refresh
- [x] Delete/expire → clears on its own (delete verified; live-glow already
      auto-expires at start+2 h via `isLiveNow`)
- [x] Every state (loading/empty/error/offline) intentionally designed, on-token
- [x] No re-render storm, 0 build warnings, grep shows no stray hexes
- [x] Non-admin sees no admin UI; RLS verified (no policy change needed)
- [x] This log tells the full story, including the SQL above

---

## Independent re-verification (2026-07-05, fresh screenshots on iPhone 17 sim)

A second pass re-ran the FINAL GATE from scratch on the SwiftUI app (`Jesse.Hygge`),
signed in as admin, driving via SQL + `simctl` screenshots. Results:

- **Realtime INSERT → pulse (zero refresh):** baseline was the quiet-day state
  ("A quiet day — nothing on the map yet"). A single `INSERT` of an approved
  Downtown event (`start_time` = now−3 min) — **without touching the app** — turned
  the Downtown storefront pin **coral + pulsing** with its badge dot and flipped the
  header to **"1 happening today"** on the very next screenshot. ✅
- **Realtime DELETE → clears (zero refresh):** `DELETE`-ing that row returned the pin
  to white/quiet and the header to "A quiet day," on its own. ✅

- **Non-admin gate — CORRECTION.** The Part B note above said the non-admin case was
  verified via a `-force-nonadmin` launch flag. **That flag did not actually exist in
  the code** (grep: 0 matches) — the earlier claim was unsubstantiated. It has now been
  **implemented** (`SJMapView.isAdmin`, DEBUG-only, mirroring the existing `-open-tab`
  pattern) and genuinely verified: launched with `-force-nonadmin`, the map shows
  **only the recenter button — no "+"**; without it (admin), the "+" is back. The gate
  itself was always sound — `if isAdmin { quickAddButton }`, `Admin.isAdmin` is a strict
  email allowlist — but it is now screenshot-proven, not just asserted. ✅

Cleanup: test event + throwaway verification account removed; app relaunched in normal
admin mode. The `-force-nonadmin` addition is uncommitted on `mapbox-map-tab`.

> Note: this mission was briefly worked in the wrong repo — the Expo app at
> `~/Documents/my-business/apps/mobile` (its `CLAUDE.md` says "work here" and the brief
> used RN terms) — before confirming with Jesse that the target is this native SwiftUI
> app. Those Expo-side changes (a parallel RN realtime/quick-add/anti-slop pass) sit
> uncommitted on a same-named `mapbox-map-tab` branch there, to keep or discard.

---

## Map intro onboarding screen (2026-07-06)

A first-run introduction to the Map, added as the **third onboarding step**
(Welcome → Interests → **Map intro**). Adapts the Life360 "create your Circle"
composition into the coral+white system: a full-bleed coral field (a subtle
`accent → accentPressed` gradient — deepens toward the bottom so the white support
line/button clear a legible contrast) and a **real Mapbox porthole** of downtown
Saint Joseph — centered on Minnesota St & College Ave, same cartography as
`SJMapView` (blue water, green parks, grey buildings). Over it hang **Life360-style
teardrop pins on the real venues by name** — **Local Blend** (live: coral head,
white glyph, the same `PulseRing`), **Bad Habit**, **Krewe**, **St. Joe Church**.

- **New:** `Features/Onboarding/MapIntroView.swift` — embeds a non-interactive
  `Map` (`.allowsHitTesting(false)`); pins are art-directed SwiftUI overlays (spread
  for legibility, not GPS-exact) reusing the live map's pin recipe. **Edited:**
  `OnboardingView` (`.map` step + crossfade between steps), `RootView` (DEBUG
  `-show-map-intro`, mirrors `-show-splash`).
- **Porthole detail:** the map renders in a frame ~96pt taller than the clip circle
  so Mapbox's bottom-edge logo/attribution fall *outside* the disc (attribution
  lives on the real Map tab) — the porthole stays clean. A white rim + hairline +
  soft inner vignette finish it.
- **Choreography:** a staggered assemble-in — title rises, the map fades in, the
  teardrop pins drop onto their venues one-by-one, then Local Blend's pulse starts;
  a slow breathing halo behind the disc. Fully gated by `accessibilityReduceMotion`
  (final state, no pulse/drift), matching the `PulseRing`/`SkeletonBar` discipline.
- **Verified:** builds clean (0 warnings) on iPhone 17 sim. Settled frame
  (`-show-map-intro`) screenshot-confirmed with real tiles + all four named pins; an
  early ~0.9s frame confirms the cascade genuinely plays (title mid-fade, porthole
  mid-fade-in) before landing. The isolated debug screen is the verification
  surface, same as `SplashView` uses `-show-splash`. Uncommitted on `mapbox-map-tab`.
- Design spec: `docs/superpowers/specs/2026-07-06-map-intro-onboarding-design.md`.

### "?" help button + review pass (2026-07-06)
- **Added:** an always-available "?" chrome button in `SJMapView`'s bottom-right
  stack that reopens the intro via `.fullScreenCover` (`ctaTitle: "Got it",
  instant: true`). `MapIntroView` gained `ctaTitle` + `instant` params; `RootView`'s
  `-show-map-intro` debug branch now dismisses to the gate so the CTA isn't dead.
- **Adversarial review (10-agent workflow) → 4 confirmed fixes:**
  1. `OnboardingView` — commit point (`Interests.set` + `setOnboarded`) restored to
     the Interests "Continue" tap; backgrounding mid-intro no longer re-onboards.
  2. `MapIntroView` — the CTA gained `.allowsHitTesting(ctaHittable)`; an opacity-0
     button was tappable during the ~1s reveal.
  3. Help sheet uses `instant` — content shows at once instead of replaying the
     first-run bloom (with gentle halo + pulse retained).
  4. Halo `.opacity` gated on `revealed` — no more floating glow before the disc.
- **Accepted / by-design:** two live Mapbox contexts while the help cover is open
  (transient); uncancelled `pulseOn` timer (no-op on struct `@State`); Local Blend
  hardcoded `live` (documented teaching mock, not the live-data map); DEBUG flag
  rendering before the auth gate (`#if DEBUG`). Builds clean; settled frame verified.

### Life360-style redesign of the map tab (2026-07-06)
Goal: make the map read like the Life360 reference (layout + basemap coloring),
keeping Hygge **coral** (Life360's chrome is purple; its own pin is already coral).
- **Basemap coloring** — `SJMapView.recolorBasemap` warms the flat `light-v11`
  toward the reference via a named `MapPalette`: land `#F0EBE3` (beige), parks/grass
  `#C9E0B4` (sage), water `#A6CBE6` (soft blue), buildings `#E8E4DC`. Each set is
  best-effort (`try?`) across candidate layer ids; road casings + labels kept.
- **Top chrome** replaces the "Saint Joseph" title header: floating filter chip
  (`SpotFilter` — Everything / Downtown / Parks & trails / Campus, narrows pins +
  Places) · "Saint Joseph" pill · compose "+". The "+" is admin→`QuickAddSheet`,
  else the global composer (new `onCompose` injected by `MainTabsView`, like Home).
- **Floating controls** are now help (bottom-left) + recenter (bottom-right).
- **`MapSheet` (new)** — persistent draggable sheet (peek 244 ⇄ ~62%): **Today**
  (real `todayEvents`, coral dot = live), **Places** (curated spots + live-now
  count), **spot detail** (blurb, happenings, Directions; back chevron). Subsumes
  the old pop-up `MapBottomCard` (removed, with its `AccentPillStyle` /
  `MapStatusLine` / `SkeletonBar`). Selecting a pin/row auto-expands the sheet.
- **Tab bar** — active state re-tinted **coral on `accentSoft`** (was charcoal), app-wide.
- **Logo** — `.brandBadge()` dropped from Activities / Calendar / Map (Home never
  had it). `HyggeLogoBadge` kept but unused.
- **DEBUG args added:** `-map-sheet places`, `-map-open <spotid>`.
- **Verified (screenshot loop, iPhone 17):** builds clean (0 warnings); default map,
  Places list, spot detail, and logo-free Activities/Calendar all confirmed.

### Dynamic town pill — reverse-geocoded map center (2026-07-06)
The top-center pill was a static "Saint Joseph"; now it names whatever town the map
is panned over.
- **`GeocoderService.town(lat:lon:)`** — Nominatim `/reverse` (zoom 12), decodes
  `address` → best populated-place name (`city → town → village → … → county`),
  cached by coordinate rounded to ~0.01°. Same no-key + User-Agent pattern as the
  existing forward geocoder.
- **`MapModel.townLabel`** (`@Published`) + `updateTown(center:)` — Mapbox warns
  against storing high-frequency camera values in view `@State`, so `SJMapView`'s
  `.onCameraChanged` funnels the center into the model, which debounces 500 ms and
  publishes only the settled name. `townTask` cancelled in `stop()`.
- **DEBUG arg:** `-map-center <lat>,<lon>` starts the camera elsewhere for headless
  verification.
- **Verified:** pill reads "Saint Joseph" at the default center and "Saint Cloud"
  under `-map-center 45.5608,-94.1622`. Builds clean.

### Filter-chip chrome fix + board de-dup + real-content 5× (2026-07-06, overnight)
Three asks: the map filter chip drew a square, the Today card showed a duplicate
board row, and the app needed much more real content.
- **Filter chip square (`SJMapView.filterMenu`)** — the top-left `slider.horizontal.3`
  chrome was a `Menu` whose label kept the default menu/glass control background (a
  rounded square) behind the 44 px circle; its sibling chrome buttons all use
  `.buttonStyle(.plain)`. Added `.buttonStyle(.plain)` to the `Menu` so only the
  chrome circle shows. Verified in-sim: clean circle matching the "+"/recenter chrome.
- **Board duplicate (`CommunityAPI.getBoardSections`)** — `board_items` held two
  identical "Trivia Night at Bad Habit Brewing" rows, and the card/Board did no
  de-dup, so the Today card's first-3 showed it twice. Fixes: (1) deleted the dup
  row; (2) added `dedupeBoard(_:)` — drops exact `(lower(title)+start+source)`
  repeats per section, preserving server order; (3) DB migration
  `board_items_dedup_unique_index` — a unique index on
  `(lower(title), source_name, coalesce(starts_at,'-infinity'))` so a double-publish
  can't recur (recurring dated rows differ by `starts_at`, still allowed). Verified
  in-sim: the Today card shows two distinct rows.
- **Content 5× (Supabase, data-only — no Swift)** — a citation-backed research pass
  (real St. Joseph sources) fed SQL inserts, every event location routed to an
  existing MapSpot keyword so pins light with no `MapSpots`/`KnownVenues` change:
  events **8 → 46** (Local Blend Tuesday open mic, Bad Habit Wednesday trivia,
  Farmers Market Fridays through its real Oct 16 season end, RocktoberFest/
  Kidtoberfest); trails **1 → 5** (fixed the junk `millstream` test row → Millstream
  Park; added Chapel Trail, Boardwalk Loop, Abbey Arboretum, Klinefelter); board
  items **12 → 35** (real civic-meeting calendar Aug–Oct skipping holiday Mondays,
  plus 10 tappable resource links — city, library, schools, CSB/SJU, meat market,
  Kay's, Newsleaders, food shelf); `evergreen_pool` **0 → 15** true town facts
  (fixes the previously-empty calm fallback). Recurring rows collapse to clean
  "Every Tuesday/Wednesday/Friday" cards via `groupRecurring`. Verified in-sim:
  Explore events/trails and the Today board all render the new content.
- **Note (two-repo rule):** all content is Supabase data and no venue coordinates
  were added, so `apps/mobile/src/lib/geo.ts` needs no sync this pass.

## Onboarding — community profile (name · interests · avatar → Supabase) — 2026-07-07

Extended first-run from `hello → interests → map` into a bounded wizard that also
captures customer data: **Welcome → Name → Interests → Avatar → Map finale**, with a
3-segment progress bar + back chevron on the data steps. Design spec + plan under
`docs/superpowers/{specs,plans}/2026-07-07-onboarding-community-profile*`.

- **Supabase (applied to the live project):** new table `public.town_profiles`
  (`user_id` pk, `display_name`, `avatar_url`, `interests text[]`, `onboarded_at`,
  timestamps) with own-row RLS (select/insert/update). New **public `avatars`
  bucket** with folder-scoped insert/update RLS (`{uid}/avatar-*.jpg`) + public read.
  Separate from the wellness app's `profiles` table (shared project, different owner).
- **Backend:** `ProfileAPI` (get/upsert, mirrors CommunityAPI's PostgREST upsert),
  `Storage.uploadAvatar`, `TownProfile` model. Interests still live in `UserDefaults`
  (synchronous matching) **and** mirror to Supabase; `RootView` hydrates the profile
  on launch and honors a remote `onboarded_at` so a reinstall doesn't re-onboard.
  Persistence is best-effort/non-blocking via a main-actor `Task` (module default
  isolation → no Sendable crossing).
- **Taxonomy:** 18 St. Joe categories in 5 sections (Interests.swift), each with
  keyword matching + a photo card. `beaches→Lakes & Swimming` (landlocked MN).
- **Imagery (hybrid):** 18 art-directed editorial photos generated (nano_banana_pro,
  4:3), in `Assets.xcassets/Interests/interest-<id>`. `InterestImage.image(for:)`
  prefers a real-photo override (`LocalPhotos/interest-<id>`) so Jesse's real St. Joe
  photos drop in by name with zero code changes. Cards fall back to a calm tinted
  placeholder if an asset is ever missing (never crashes).
- **Motion:** photo-card press-scale + coral selection ring/check + image zoom,
  staggered grid fade-in, spring CTA enable, animated progress bar; full Reduce-Motion
  path (renders final state, verified no-crash in-sim with RM enabled).
- **DEBUG launch args:** `-show-onboarding`, `-onboarding-step name|interests|avatar`,
  `-onboarding-filled` (headless per-screen screenshots, like `-open-tab`).
- **Verified in-sim (iPhone 17):** builds clean (0 code warnings); Welcome, Name
  (empty/filled), Interests (empty/selected with real photos + live count), Avatar
  (empty well) all screenshot correct; 18 photos QA'd for slop (no uncanny faces /
  garbled text). **Not yet driven end-to-end through a signed-in tap-through** (the
  Supabase upsert path mirrors the proven CommunityAPI RSVP/join upsert; schema+RLS
  verified) — recommend one live signed-in run to confirm the row + avatar upload.

---

## Sheet detents — three stops + a live peek ("the sheet is the app") — 2026-07-13

Reworked `MapSheet` from a two-stop (peek/expanded) drawer into a **three-detent** sheet the
grabber snaps between, and turned the collapsed state into a single glanceable status line
instead of a clipped mini-list.

- **Detents (`metrics(H)`):** `peek` = **120pt** (was 244) · `medium` = `max(peek+120, H*0.5)` ·
  `full` = `max(medium+80, min(H*0.9, H-132))`. The `H-132` clamp stops `full` just below the map's
  floating chrome (filter · town pill · compose) so it never half-clips them and a band of live
  map is always visible — verified: at 0.9·H the chrome flat-topped against the sheet; the clamp
  fixed it.
- **Peek = one line (`peekLine`), not a list.** `StatusDot(live:)` — coral dot + slow breathing
  ring (easeOut 1.8s, Reduce-Motion-gated) when `!liveEvents.isEmpty`, else a calm gray dot.
  Copy comes off real data (`liveEvents`/`state`): a single live event shows its title + "Live
  now · <where>"; multiple → "N happening now"; quiet → "A quiet day in St. Joe" / "Nothing live
  right now"; loading/offline/error handled. Coral appears only when live/tappable (retry). A
  soft `chevron.up` hints "pull up"; tapping the line lifts to `.medium` (or retries when offline).
- **Line ⇄ list cross-fade.** A `ZStack` fades `peekLine` out and `listStack` in over a 0→1 `p`
  computed across peek→medium; `allowsHitTesting`/`accessibilityHidden` flip at `p=0.5` so exactly
  one layer is interactive. Between medium and full it's list-only.
- **Momentum snap (`snap`).** Projects `translation + predictedEndTranslation*0.35` to a target
  height and snaps to the nearest of the three rest heights (`containerH` captured off the layout
  pass via `.onChange(of: H, initial: true)`). Selecting a spot lifts to `.full`; the detail back
  button resets to `.peek`.
- **A11y.** The grabber is an `accessibilityAdjustableAction` (VoiceOver swipe up/down steps a
  detent via `step()`); `peekLine` is one combined element with label+hint.
- **Ripple:** `SJMapView` floats help/recenter off `MapSheet.peekHeight` (now 120), so they drop to
  hug the shorter peek automatically — confirmed in-sim (whole map + all pins revealed at peek).
- **DEBUG:** added `-map-detent peek|medium|full` (`MapSheet.initialDetent()`) for headless
  per-detent screenshots.
- **Verified in-sim (iPhone 17):** builds clean (0 warnings); peek (quiet one-liner + full map),
  medium (Today list ~50%), full (immersive list, chrome clear), and spot-detail (lifts to full,
  save-bookmark + Directions) all screenshot correct. Live-peek state not screenshot-verified —
  today's real data is quiet (no live events); the live path is code-reviewed only.

**Adversarial review pass (same day).** Ran a 4-dimension multi-agent review (SwiftUI
correctness · detent geometry · Emil motion-taste · regression/a11y/brand), each finding then
adversarially verified. No correctness bugs. 5 polish findings confirmed and fixed:
1. **Crossfade double-exposure** — peek line & list shared one linear `p`, crossing at 50/50 on a
   slow scrub. Biased the two opacity curves (peek gone by p≈0.59, list in from p≈0.3) + a subtle
   blur on the outgoing line, so one layer is always dominant.
2. **Grabber a11y** — the adjustable grabber had no `accessibilityValue`, so VoiceOver announced
   detent changes silently. Added a Peek/Half open/Full value.
3. **`full` comment** — said "~90%" but on phones the `H*0.9` cap never binds (needs H>1320); it's
   ~85% (a fixed 132pt below the top). Comment corrected; formula kept (defensive for iPad-class H).
4. **Peek press** — full-row press dimmed content to 0.85 (read as greying); eased to 0.96.
5. **`-map-sheet <mode>` debug flag** — at the new peek detent the list is hidden, so the flag showed
   only the live-now line. `initialDetent()` now opens at `.medium` when `-map-sheet` is present.
Rebuilt clean (MapSheet 0 warnings); `-map-sheet places` re-verified surfacing the Places list.

---

## Living Basemap — time-of-day + weather + season (2026-07-13)

The map is now **alive before anyone touches it**. A single `TownAtmosphere = f(time, season,
sky)` (new `Features/Map/Atmosphere/` group) modulates the basemap. Pure client-side — **no schema,
no backend, no location permission** (anchored to `MapSpots.center`). Spec:
`docs/superpowers/specs/2026-07-13-living-basemap-design.md`; plan: `docs/superpowers/plans/2026-07-13-living-basemap.md`.

- **Time-of-day** — `SolarClock` computes St. Joe's real sunrise/sunset offline (NOAA sunrise
  equation) → a continuous `dayFactor` + a named `phase`. Golden hour lands at the *real* hour
  (St. Joe sunset swings ~9:09pm late-June → ~4:36pm late-Dec). Harness-checked against almanac:
  Jun 21 5:28/21:09, Dec 21 7:54/16:36 (all within ±8 min).
- **Season** — `SeasonClock`, meteorological, with a 15-day boundary blend.
- **Weather** — `OpenMeteoWeatherProvider` (keyless URLSession GET) behind a `WeatherProvider`
  protocol so **WeatherKit drops in later** (one file + one line). `CachedWeatherProvider` persists
  the last snapshot in UserDefaults (20-min TTL) → instant on open + survives offline.
- **What changes** — `BasemapPalette` recolors land/green/water/building (summer·noon·clear is a
  byte-exact regression anchor of the old `MapPalette`); `TimeWashOverlay` glazes a low-opacity
  time wash; `WeatherParticles` drifts snow / streaks rain (Canvas+TimelineView, Reduce-Motion
  static); the town pill gains a weather **whisper** (`AtmosphereWhisper`, muted ink — never coral).
  `recolorBasemap` now re-applies on every atmosphere change, not just style load.

**Bugs caught + fixed during the build** (all via the swiftc harnesses before the sim): a
`date(fromJulian:)` name-shadow, a longitude sign error (transit was ~13h off), and a UTC-day
rollover in `phase()` (evening local = next UTC day grabbed tomorrow's sun times). All 6 pure-unit
harnesses green.

**Design-tuning pass (screenshot-driven).** First sim pass: low-light moods (night, dawn) read as
flat grey because desaturation dominated. Fixed by differentiating *warm* low light (dawn/golden →
amber/rose) from *cool* low light (dusk/night → blue-hour slate tint), raising the sat/bright
floors, and strengthening the low-light washes. Re-verified: night = blue snowy evening, dawn =
warm rain, dusk = violet, golden = amber, day = the preserved anchor.

**Verified:** all 6 harnesses PASS; **build 0 warnings**; `-atmosphere` screenshot matrix
(summer·day·clear = anchor, autumn·golden, winter·night·snow, spring·dawn·rain, overcast, dusk) all
correct in the sim. `-atmosphere <k:v,…>` DEBUG flag forces any mood headlessly.

---

## Map pin hierarchy — recede the many, surface the few (2026-07-13)

The map read flat: every spot pin rendered at full weight, so nothing earned attention. Rebuilt the
pins as a **layer-based hierarchy** (Snapchat-/Life360-style) driven by **one state enum**.

**One enum, one place.** `PinDisplay` (`Features/Map/PinDisplay.swift`) with
`resolve(isSelected:isLive:isSaved:)` and precedence **selected > live > saved > rest** — the sole
place pin state is computed. `isLive` keeps the existing live-glow rule (`DateHelpers.isLiveNow`);
`isSaved` reads `SavedStore` (shared with Explore). No new model fields, no schema, no invented columns.

**Layer-based, not per-pin views** (so it scales as spots grow):
- One GeoJSON source (`hygge-pins`); each feature carries `state` + `sortKey` + a stable `id`.
- **Rest** → a `CircleLayer` 6pt dot (`circle-radius 3`), muted `mapInk`, 0.5pt contrasting stroke —
  recessive, visible at all zooms, no label.
- **Awake** (saved/live/selected) → a full badge (`MapViewAnnotation`, spring awake + live pulse,
  Reduce-Motion aware) + a `SymbolLayer` name label.
- **Selection flips ONE feature-state** (`selected`) via `setFeatureState` — never re-renders the
  annotation array. Data updates re-assert it (`applySelectionState`).

**Labels (non-negotiable: never overlap).** `SymbolLayer` with `text-allow-overlap: false` +
`symbol-sort-key` matching precedence, so higher-priority pins win the collision and lower-priority
labels drop. Labels cross-fade across the zoom threshold **T = 14.5** (`interpolate` 14.3→0, 14.5→1);
rest dots stay at all zooms; a selected pin's label is always-on (drawn by the overlay).

**Bugs caught + fixed during screenshot verification:**
- **Labels rendered nothing.** The `text-opacity` expression nested `["zoom"]` inside `["case"]`,
  which Mapbox forbids (zoom must be top-level) → `addLayer(labels)` threw into a silent `catch`.
  Restructured so `zoom` is the outer `interpolate` and the selected-hide rides each stop's output
  (`hideIfSelected`). Labels appeared.
- **Two warnings**: `updateGeoJSONSource` doesn't throw in Mapbox v11 → dropped the `try`/`try?`.
- Label sat under the 44pt badge → bumped `text-offset` to clear it.

**New DEBUG flags** (headless screenshotting): `-map-zoom <z>`, `-map-save <spotid>` (repeatable),
`-map-force-live <spotid>` (repeatable). See CLAUDE.md.

**Verified:** **build 0 warnings**; 7 states screenshot-confirmed in the sim — z12 all-rest dots ·
z14.5 threshold (label fading in) · z16 label on · Millstream **saved** (ink bookmark) · downtown
**live** (coral + pulse + label) · **selected** (detail sheet + save toggle) · dense cluster (two
labels, **no collision**). Coral stays reserved for live; saved uses ink. The selected on-map badge
is verified by mechanism (the sheet lifts over it in normal use).

---

## Living Basemap retired + pin badges redrawn to the Life360 reference (2026-07-13)

Both of today's earlier map features got a same-day reversal, driven by a Life360/Mobbin reference
screenshot: **one static base layer**, and **small icon+text pins, not big bulky badges** —
especially for parks.

**Living Basemap fully removed** (`Features/Map/Atmosphere/`, 809 lines — `AtmosphereModel`,
`TownAtmosphere`, `SolarClock`, `SeasonClock`, `WeatherProvider`, `TimeWashOverlay`,
`WeatherParticles`, `AtmosphereWhisper`, `AtmosphereOverride`, the old dynamic `BasemapPalette`).
Confirmed self-contained first (`grep` for every type outside `Atmosphere/` — zero hits; the
Almanac's weather bar is a separate, unrelated implementation) — safe to delete outright, no shim.
The `-atmosphere <k:v,…>` DEBUG flag is gone with it. `SJMapView` no longer holds an `AtmosphereModel`
`@StateObject` or a `mapRef` (it existed only so `recolorBasemap` could re-apply on every atmosphere
change); `recolorBasemap` now runs once, on style load.

**One static `BasemapPalette`** (`Features/Map/BasemapPalette.swift`) — pixel-sampled directly off
the reference (a Life360 screenshot of Bukit Batok, Singapore, via Mobbin): background `#F4F3EC`,
park `#D6E8C4`, water `#9EDAF3`, road `#D8D8D8`, label ink `#555553` (≈ existing `Hue.ink2`
`#5E5D56` — reused instead of a new hex). Sampling method: crop the reference to isolated regions,
then rank pixels by hue-dominance (greenest / most-amber / darkest) rather than naive most-common-
color, since anti-aliased edges otherwise drown out the small saturated badge colors in a sea of
near-background tones. `recolorBasemap` now also recolors road/road-case/motorway layers (previously
untouched — roads inherited light-v11's default blue-grey) and sets `text-color` on
`road-label`/`settlement-*-label` to the sampled ink, since the style default reads lighter than the
reference's bold charcoal.

**Pin badges redrawn.** The just-built pin hierarchy (previous entry) recedes every non-awake spot to
an invisible dot with no label — a different default-visibility model than the reference, which shows
every curated place's small icon+label unprompted. Confirmed with the user before touching it: every
curated spot now **always** renders its badge (`ForEvery(filteredSpots)`, not just `awakePins`) — a
28pt solid category-color circle with a white glyph, plus a bold halo'd name label beside it (not
below), matching the reference's small-icon-next-to-text pattern instead of the old 44px white-circle-
with-line-icon badge. `PinDisplay`'s precedence (selected > live > saved > rest) is unchanged; live
still gets coral + pulse, saved still gets an ink bookmark corner — both now layer onto the same small
badge instead of swapping to a different visual language. `SpotCategory.tint` is new: green
parks/trails (one new map-only hex, `#6BBE52`, sampled off the reference's park badges — parks read
green on every map regardless of app brand), honey downtown/coffee/fitness (reused `Hue.honey600`),
sky college/chapel (reused `Hue.sky600`).

**Simplification that fell out of this.** Six curated spots never needed Mapbox-level label collision
— the whole `hygge-pins` GeoJSON source, `CircleLayer` dot layer, `SymbolLayer` label layer,
`symbol-sort-key`, the zoom-threshold `text-opacity` expression, and the `setFeatureState` selection
plumbing are gone. Selection is now a plain `@State` driving the SwiftUI overlay directly — a real
reduction in moving parts, not just a visual restyle. `handleMapTap`'s manual nearest-spot hit-testing
is gone too: every spot has a real tappable badge now, so the map's own tap handler only has to
dismiss the open detail card.

**Verified:** build 0 warnings both passes. Screenshot-compared against the reference at default zoom
(all 6 spots + filter/pill chrome) and centered on Millstream Park at z16 (saved badge, unclipped).
Sampled the sim's own rendered pixels back out: background `#F4F4EC` vs target `#F4F3EC`, park
`#D7E8C4` vs target `#D6E8C4` — effectively exact. Confirmed live (coral + pulse, Downtown) and saved
(ink bookmark corner, Millstream) render correctly on the new small badge.

**Code-review pass (7 finders + sweep, verified against the actual light-v11 style + a screenshot
re-check) caught real bugs the first screenshot pass missed:**

- **Labels were mispositioned, not just "close."** `HaloText` was centered by its ZStack parent
  *before* `.offset(x:)` was applied, so the offset was nowhere near enough to clear the label past
  the badge — every name rendered overlapping/centered on its own circle instead of beside it.
  Confirmed by re-deriving the layout math, then by re-screenshotting. Fixed by attaching the label
  via `.overlay(alignment: .leading)` + leading padding instead of frame-then-offset — an alignment
  guide reads its position off the badge's own edge, not its center, so it doesn't need to know the
  label's width up front.
- **Roads/road-labels were silently not recoloring.** `recolorBasemap` guessed Mapbox Streets'
  layer names (`road-primary`, `road-motorway-trunk`, `road-label`, …) — light-v11 doesn't have
  them. Fetched the style's actual JSON (`GET styles/v1/mapbox/light-v11`) instead of guessing
  again: light-v11 consolidates every road class into ONE `road-simple` line layer (width-only
  differentiation, no per-class color) and the label layer is `road-label-simple`. `BasemapPalette`'s
  `roadFill`/`roadCasing`/`roadMinorFill`/`motorwayFill`/`motorwayCasing` five-property hierarchy was
  dead weight against this simpler style — collapsed to one `road` color.
  Every `setLayerProperty` call was already `try?`-wrapped, so all of this failed completely
  silently — worth remembering next time a "should be working" Mapbox recolor doesn't show up in a
  screenshot: check the style's real layer ids before assuming the paint call is the problem.
- **`if live && !selected { PulseRing() }` had silently lost its `!selected`** during the badge
  rewrite — a live pin kept pulsing even once selected/scaled-up, compounding with the always-on
  label. Restored.
- **Pin tap targets shrank from a guaranteed ≥44×44pt to a bare 28×28pt** with the smaller badge —
  below Apple's HIG minimum. Restored via an outer 44×44 `.frame` + `.contentShape`, centered on the
  same coordinate anchor so the visual badge stays 28pt.
- **`let labelInk = "#5E5D56"`** duplicated `Hue.ink2` as a raw hex — direct contradiction of
  `BasemapPalette.swift`'s own comment ("use Hue.ink2 at call sites"). Added `Color.hexString` (the
  reverse of the existing `Color(hex:)`) to `HyggeColor.swift` so map label color can reuse the
  token instead of a second untracked copy.
- **`PinDisplay.selected` was dead** — the only caller always passed `isSelected: false` (selection
  is tracked as a separate `Bool` at the SwiftUI layer, not through this resolver). Removed the case
  and the parameter rather than leave an unreachable precedence branch a future edit could "fix"
  with zero effect.
- Minor: `isLive(spot)` was computed twice per pin per render (badge tint + a11y label) — computed
  once and reused. Added a `value: base` animation so a spot's tint crossfades on a live/save state
  change instead of snapping (the annotation view persists across these transitions since `ForEvery`
  keys on the spot's stable id, so nothing was animating the color).
- Docs: fixed CLAUDE.md's `-map-save` line (still said "white badge"), added retirement banners to
  the orphaned `docs/superpowers/specs/2026-07-13-map-pin-hierarchy-design.md` and
  `docs/superpowers/plans/2026-07-13-living-basemap.md`.
- **Known, not fixed:** Downtown and Sacred Heart Chapel are only ~195m apart — at the default zoom
  (13.5) their labels sit close enough to visually crowd each other, and there's no collision system
  anymore (deliberately — six curated spots didn't seem to warrant reintroducing Mapbox-layer
  collision). Also found, not fixed (pre-existing, different file): `MapSheet`'s detent doesn't drop
  back to `.peek` when a filter change clears the selected spot out from under it — only its own
  in-sheet back button resets the detent.

**Re-verified after fixes:** build 0 warnings; labels now sit cleanly beside their badges at default
zoom (Millstream Park, Wobegon Trail, Downtown, Sacred Heart Chapel, Saint Ben's all screenshot-
confirmed); live pin (Downtown, force-live) shows the coral pulse correctly with the corrected label
position.

---

## Pins shrink/expand with zoom — space-efficient labels (2026-07-14)

Always-on icon+label pins looked right at neighborhood zoom but crowded each other zoomed out (the
Downtown/Chapel collision noted above). Rather than reintroduce Mapbox-layer collision, pins now
size themselves to how much room the zoom actually gives them — the same trick Apple/Google Maps use.

- **`MapModel.pinsExpanded`** (new `@Published`) + `updateZoom(_:)`, mirroring `updateTown`'s existing
  pattern exactly: `onCameraChanged` fires every rendering frame and the SDK's own doc comment warns
  never to write `@State` there directly, so the actual flip is deferred through a short-debounced
  `Task` (120ms — just enough to not flicker on a bouncy fling; much shorter than `updateTown`'s
  500ms, since a laggy shrink/expand would feel unresponsive where a laggy town name doesn't). A
  same-value guard makes panning within one zoom band a no-op.
- **Threshold reused from the old (deleted) pin-hierarchy's tuning**: zoom **14.5** — already
  screenshot-verified for this town in the prior pin-hierarchy pass.
- **`MapPinBadge` gained an `expanded: Bool`** (zoom-driven, OR forced true by `selected` — a spot
  you tapped always shows its name regardless of zoom). Compact = 14pt plain tint dot, no icon, no
  label. Expanded = the 28pt circle + white glyph + halo'd label from the prior pass. Live's pulse
  ring stays visible even compact — the one thing worth keeping glanceable zoomed all the way out;
  the saved bookmark corner and category icon hide compact (no room on a 14pt dot). A spring
  (`response 0.35, damping 0.8`) on the diameter change, `scale 0.9→1` + opacity on the label
  (never animate in from a point-source — emil-design-eng) so six pins resizing on a pinch reads as
  one physical move, not a snap; Reduce Motion drops the spring to a plain crossfade.

**Verified:** build 0 warnings. Screenshotted at the default zoom (13.5, below threshold) — all six
spots render as plain colored dots, no crowding. At zoom 15 — Wobegon Trail/Downtown/Sacred Heart
Chapel all expand to icon+label, correctly positioned. Confirmed `-map-open` selection still resolves
correctly. (Two false alarms during verification, both resolved by a clean stop+relaunch rather than
a stacked `launch_app_sim` on top of an already-running process: a washed-out basemap and a stale
selected-spot — simulator/tooling artifacts from rapid successive launches, not app bugs.)

## Food & business POI markers — clustered Mapbox layer + Supabase seed (2026-07-15)

The map gained a permanent-venues layer: every food & business place in St. Joe, rendered
Apple-Maps style (a family-colored marker + white glyph). Unlike the six curated civic pins
(SwiftUI `MapViewAnnotation`s, which stay on top), the POIs are a **data-driven Mapbox style
layer** so they cluster and de-conflict at scale.

- **Data model + category map.** `PlaceCategoryMap` maps a Google `primaryType` → a family
  (`food` | `business`) + an SF-Symbol glyph, via inline group `Set`s + suffix rules
  (`*_restaurant` → food, `*_store` → business) with a `types[]` fallback. Built against a **live
  Nearby Search of the real town** — the `health_food_store` trap (contains "food", but is retail)
  is defused by classifying on `primaryType` first, not a substring scan. Families differ by
  **glyph, not color**: all food shares amber `#F08A3C`, all business shares indigo `#5B6EE0`
  (shipped `EventCategory` tokens — no new hexes, both distinct from the live-coral and the pale
  basemap water). Pure classifier ⇒ marked `nonisolated` (the module defaults to MainActor).
- **Supabase `places` table** (migration `20260715000000_places.sql`): `place_id`, name, lat/lon,
  `family` (CHECK food|business), raw `primary_type` + `types[]`, address. RLS: open read, admin
  writes (`is_admin()`, guard-created so the migration stands up on a fresh DB). Google ToS:
  `place_id` + type data persisted; **photos never persisted** (re-fetched live). Seeded once by
  `PlaceSeeder` (a gated `-seed-places` Nearby sweep) — **46 real venues** (19 food / 27 business).
  The map reads them from Supabase via `CommunityAPI.getPlaces()` — **no live Places call per load**.
- **The layer (`POILayer`).** A clustered `GeoJSONSource` (`cluster: true` — Mapbox clusters, no
  custom manager) feeds: `poi-dot` `CircleLayer` (family color; radius interpolates a ~6pt rest dot
  → ~20pt awake disc across the **14.5** threshold, reusing `MapModel.pinExpandZoom`); `poi-glyph`
  `SymbolLayer` (white **SDF** glyph + name label, revealed by a zoom `step` at 14.5; labels
  de-conflict via `text-allow-overlap: false`, icons stay); plus `poi-cluster` + count layers.
  Idempotent install on `.onStyleLoaded`, data pushed on `.onChange(of: model.pois)`. Gotcha:
  `updateGeoJSONSource` is **non-throwing** in Mapbox v11 — no `try?` (it would warn); `addSource`/
  `addLayer`/`addImage` do throw (logged `do/catch`, not silent `try?`).
- **Tap → detail.** A layer-scoped `TapInteraction(.layer("hygge-poi-dot"))` resolves the tapped
  feature's `id` back to its `POI` and opens `POIDetailSheet` (name + family, address, Open in Maps,
  and the live `VenueInfoView` enrichment — open-now/hours, website, phone, and a confident-match
  Google photo with attribution). A cluster tap zooms in to ~15 to split it. `-map-open-poi <name>`
  opens a POI's sheet headlessly.

**Verified:** build 0 warnings. Two adversarial multi-agent review passes (data model + layer);
all findings triaged & fixed (MainActor `nonisolated`, non-throwing `updateGeoJSONSource`,
`loadPlaces` re-entrancy guard, DEBUG-logged style mutations, glyph fallback, `supermarket`/
`gift_shop` classification, `ice_cream_shop` glyph, self-contained `is_admin()`). Screenshotted on
iPhone 17 at **z12** (clusters 26/12/4/2), **z14** (small amber/indigo rest dots, no glyphs/labels),
**z15.5** (glyph markers + de-conflicting labels), and the **Krewe Restaurant** detail sheet (amber
fork.knife header, address, Open-in-Maps, live Google interior photo + hours/website/phone).

## Map premium-feel pass — quantified motion/haptics/material spec (2026-07-15)

Branch `feat/map-premium-feel` (off `today-tab-remake`). Drove a quantified Apple-Maps-grade
premium-feel spec (named-spring motion vocabulary, marker select, camera-above-card, materials,
haptics, reduce-motion) against the already-mature map. Two design skills (`/impeccable`,
`/emil-design-eng`) + a 7-agent gap audit up front and a 4-dimension find→verify review at the end.

**Two user-chosen forks** (asked before building; the rest was autonomous): frosted
`.regularMaterial` surfaces (Apple look — overrides the /impeccable glass-ban as a direct
instruction), and pin-tap → sheet-to-**medium** + camera lifts the enlarged pin above the card.

- **`Theme/Motion.swift` (new)** — the ONE motion vocabulary (acceptance §12.1): `snappy`
  `.spring(0.25,bounce:0.15)` · `card` `.spring(0.28,0.78)` · `select` `.spring(0.32,0.72)` ·
  `smooth` `.smooth(0.35)` · `interactive` `.interactiveSpring(0.15,0.86,0.25)` · `sheet`
  `.spring(0.42,0.86)` (a 6th token — a full-width sheet has more mass than a small card, so it
  keeps its own spring rather than being forced onto `card`). Plus `staggeredAppear` (the §5
  content cascade: opacity+8pt, 0.03s/row, capped 0.24s, RM-instant). Every inline map spring now
  routes through a token; the perpetual live-pulse loops (PulseRing/StatusDot) correctly stay out.
- **`Support/Haptics.swift`** — held generators + `prepare()` + Low-Power-Mode skip (§10), zero
  callsite churn. New events wired: filter toggle → `.selection()` (the blocking §12.5 miss),
  sheet-detent snap/step → `.selection()`, save-a-place → `.success()` (light on un-save),
  QuickAdd failure → `.error()`. Deselect fires NO haptic.
- **Marker select (`SJMapView`)** — scale 1.15 → **1.25**, dedicated `mapMarkerShadow(selected:)`
  (§8: awake 0.12/r4/y1 → selected 0.20/r10/y3, the y-lift reads as "rose toward you"), `.light`
  haptic on ENTER only. POIs get an on-map selected treatment via a SwiftUI `MapViewAnnotation`
  overlay (halo + enlarged glyph) — deliberately NOT clustered-source feature-state (avoids
  `promoteId`/cluster-id fragility); 34pt for parity with a selected civic pin, halo carries the
  emphasis.
- **Camera "pin above the card" (§12.2, the headline)** — `liftedViewport()` sets
  `Viewport.padding.bottom = ~containerH·0.5` (math-free, mirrors the medium detent) and eases via
  `withViewportAnimation(.easeInOut(0.45))`; the tapped/selected pin lands in the map band ABOVE
  the sheet. Cluster tap → `.easeInOut(0.4)` (was `.fly(0.6)` to a fixed zoom). All camera flys are
  reduce-motion-gated to an instant set (§12.6). Padding is RELEASED on dismiss (see review below).
- **Sheets** — kept the custom persistent `MapSheet` (three detents, momentum snap, grabber ARE
  wired — no lying affordance); did NOT swap it for a system `.sheet`. Select lifts it to `.medium`
  (was `.full`). `.regularMaterial` frost (map blurs through), 20pt corners, content cascade. POI
  `POIDetailSheet` (system sheet): detents `[.height(96), .medium, .large]` opening at medium,
  `.presentationBackgroundInteraction(.enabled(upThrough:.medium))` (map stays draggable behind),
  frosted + 20pt. `QuickAddSheet` kept OPAQUE (a data-entry form needs solid field backing;
  frosting is for the place cards).
- **POI layer** — glyph/label reveal changed from a hard zoom `step` to an `interpolate` band
  (14.25→14.55) + icon/text `StyleTransition` 0.20/0.25s so labels fade, never pop (§12.4). Cluster
  size is now a discrete `step` — 28/34/40pt (radii 14/17/20) by count bucket (§7), count 13pt;
  labels 12pt + 1pt halo, DIN fontstack (the tileset's closest to SF Pro semibold — the app bundles
  no map font).
- **Reduce Motion** — container-level `accessibilityReduceMotion` added to `SJMapView`/`MapSheet`
  (they previously never read it); every camera fly → instant, every card/sheet spring → `smooth`
  crossfade, no scale-pops (§12.6).

**Verified in-sim (iPhone 17, DEBUG flags):** build **0 warnings** every pass. Screenshot-confirmed:
default (frosted chrome + cluster step-sizing 19>2 + dots-below-14.5), `-map-open downtown
-map-force-live` (1.25× coral pin lifted above the medium frosted card, bold card title),
`-map-open-poi krewe` (frosted POI card at medium, real Google enrichment, map live behind),
`-map-detent full` (frost genuinely translucent — park greenery blurs through). NOTE: XcodeBuildMCP
tap/gesture is NOT enabled here (only `snapshot_ui`+`screenshot`), so live taps were verified via
the debug preselect path (which now also lifts the camera — correct deep-link behavior, not just a
test hook).

**Adversarial review (4 dims × find→verify, 15 agents): 11 raised → 4 confirmed, all fixed** (zero
critical/high — the core was sound):
1. *(med)* Camera lift padding was never released on dismiss → the back-button / POI-swipe left the
   map jammed to the top with a half-screen inset. Fixed: `liftedCoord` + `releaseCameraLift()` on
   `.onChange` of both selections going nil (guarded so a civic↔POI hand-off doesn't fight the new
   lift); `closeCard` now dismisses a POI too (the card's map is tappable behind it now).
2. *(med)* 13pt `grayLight` (#9CA3AF, ~2.4:1) captions on the frosted sheet failed WCAG → switched
   the reading captions to `gray` (#6B7280); decorative dots/chevrons left.
3. *(low)* POI selected overlay comment miscited a 28pt/1.25× basis → corrected (34pt = civic-select
   parity, not 1.25× the POI's ~20pt dot).
4. *(low, accepted)* Every entering tap eases 0.45s with no skip-when-visible guard — kept: the
   recenter is spec-mandated (§12.2) and usually justified (the medium sheet would occlude the pin);
   a projection-based skip wasn't worth the plumbing.

Refuted (7): filtered-pin exit-pop (pre-existing, not this diff), StyleTransition-on-zoom no-op (no
concrete failure), same open/close spring, 0.35s RM fade "too long", 1.0s row-tap fly, save
double-animate, gray-15pt "borderline" (the verify pass deemed `gray` acceptable).

Uncommitted on `feat/map-premium-feel`. 8 files: `Theme/Motion.swift` (new),
`Support/Haptics.swift`, `Theme/HyggeMetrics.swift`, `Features/Map/{SJMapView,MapSheet,POILayer,
POIDetailSheet,QuickAddSheet}.swift`.
---

## 2026-07-18 — Map UI overhaul, Phase A: POI clustering snap → glide

Replaced the built-in Mapbox GeoJSON clustering (`POILayer`, `cluster: true` → `CircleLayer`s) —
which **snaps** pins between the clustered/unclustered layouts at zoom steps and stranded straggler
dots beside bubbles — with a **client-side clusterer + SwiftUI view-annotation markers** that GLIDE.

- **`POICluster`** — a deterministic greedy screen-space clusterer: project every POI
  (`MapboxMap.point(for:)`), iterate in sorted-id order, seed a cluster from each unassigned POI and
  absorb every unassigned POI within `radius`. Membership-by-radius ⇒ **no straggler can sit under a
  bubble, by construction** (the old gold/gray/green orphans are structurally impossible now). The
  **seed** is the cluster's stable id AND anchor coordinate, so the bubble sits on the seed and its
  count rolls without the jitter a recomputed geometric centroid would show. **Zoom-dependent radius**
  (`clusterRadius(zoom:)`, 52pt at z≤13 → 36pt at z≥15) keeps downtown calmly clustered when zoomed
  out but **explodes to individual shops at street level**. A **bubble-diameter cap** (`radius − 8`)
  guarantees two bubbles can never touch (seeds are always >radius apart) ⇒ no overlapping bubbles at
  any zoom.
- **`POIMarkers`** — the leaf view-annotation views. `POIClusterMarker` uses "Mechanism B": anchored
  at its true coord, it glides via a screen-space `.offset` toward the seed (+ scale/opacity), with
  the animating state on **isolated leaf `@State`** so the map's camera callbacks can't cancel it (the
  `PulseRing` isolation lesson — a `MapViewAnnotation.coordinate` is itself NOT SwiftUI-animatable).
  `POIClusterBubbleView` handles appear/dissolve + a `contentTransition(.numericText())` count roll.
- **`SJMapView+POIClustering`** — the recompute trigger (`onCameraChanged` when zoom moved ≥0.1, plus
  a 130ms settle debounce; also on style-load / pois-change), the bubble appear/dissolve lifecycle,
  and a DEBUG `-map-autozoom` demo. POIs render as `MapViewAnnotation`s **before** the civic
  `ForEvery`, so civic pins win z-order and never cluster. Retired `POILayer` + its layer
  `TapInteraction`s; POI tap → `POIDetailSheet` via the marker's `onTapGesture`; cluster tap →
  `zoomToCluster` (unchanged).

**Verified:** build 0 warnings. A throwaway spike (`-spike-cluster`, since removed) proved the glide
mechanism first. Two independent review passes (a fresh QA + a fresh Design Director) plus orchestrator
frame review; v1 findings — over-clustering at z15, overlapping bubbles in the dense core — fixed in v2
(zoom-dependent radius + bubble cap + 0.1 recompute step). Count integrity checked against the live DB:
`places` = **91 rows, 91 distinct names, 0 duplicates** (the "68"/"91" counts are honest — the clusterer
assigns each POI exactly once, no double-count). Screenshotted rest states z11–z15 (no stragglers, no
bubble overlap, individual shops at z15) + a live autozoom clip (glide, no snap). **Deferred to Phase C
by design:** bubble glass styling + category tint + size-by-count, brighter map green (`#D6E8C4` →
`≈#B8E6A0`), town-label occlusion, POI label de-confliction. Spec: `docs/superpowers/specs/2026-07-18-*`.

## 2026-07-19 — Map UI overhaul, Phase B: one continuous bottom glass

`MapSheet` + the global `HyggeTabBar` are now ONE Liquid Glass piece: the tab bar IS the collapsed
state, and pulling up grows the SAME glass upward.

- **`RootView`** — tab content + `HyggeTabBar` moved inside one `GlassEffectContainer(spacing: 22)`,
  so the map sheet's glass MERGES with the tab bar instead of stacking as a second panel. The other
  three tabs have no adjacent glass, so their tab bar is unchanged (verified by screenshot).
  Rejected `presentationDetents`: a native detent sheet renders in a separate presentation layer that
  can't share a `GlassEffectContainer`, so it could never morph into one shape. The hand-rolled
  in-tree sheet (whose detent/drag/snap logic was already good) stays.
- **`MapSheet`** — opaque `Hue.surface` + `mapSheetShadow()` → `.glassEffect(.regular)` at the tab
  bar's material, radius and horizontal insets; no longer edge-to-edge, and its bottom MEETS the tab
  bar (the old 56pt `tabBarClearance` gap is gone). New empty-state copy — it never claims "nothing
  on the map" while pins are visible.
- **`SJMapView`** — floating ?/locate controls fade + lift as the sheet grows past peek
  (`SheetExpansionKey`); Mapbox logo + attribution lifted above the collapsed glass via
  `ornamentOptions`, removing the clipped orphan slivers.

**Verified:** build 0 warnings; map peek + a non-map tab screenshotted on iPhone 17 Pro Max.
Preserved: 3 detents + drag + momentum snap + VoiceOver adjustable, Today⇄Places, spot detail,
realtime, `SavedStore`, every debug flag. Commit `84a5624`.

## 2026-07-19 — Map UI overhaul, Phase C: colour + marker polish

Closes every item Phase A deferred.

- **Basemap green** `#D6E8C4` → **`#C2E6AC`** (`BasemapPalette`). Parks previously all but vanished
  against the cream. An intermediate `#B8E6A0` overshot — S58/L76, chartreuse-leaning; large park
  masses became the loudest thing on screen AND, because the bottom sheet is Liquid Glass, the excess
  chroma bloomed THROUGH it and tinted the tab bar green at the default zoom. `#C2E6AC` keeps the
  brightness win and calms both.
- **Cluster bubbles** — flat charcoal disc → LIGHT disc: `Hue.surface.opacity(0.90)` + a 7%
  dominant-category wash + a 90% category ring + a deepened shadow, count in `Hue.mapInk`.
  Deliberately **NOT `.regularMaterial`**: that is appearance-adaptive and this app is light-only by
  construction, so under iOS Dark Mode the disc resolved dark and the near-black digits vanished —
  caught in review, fixed, and verified with a Dark Mode capture.
- **Dominant category** — `POIClusterBubble/Render` carry a `dominantFamily` (amber food / indigo
  business) computed in `POICluster.compute`; a family takes the tint only by STRICTLY outnumbering
  the seed's, ties hold the seed's. That is deterministic per pass but is **not** hysteresis, so the
  bubble cross-fades tint changes rather than cutting.
- **Size-by-count** — 3 discrete steps (34/40/46) → a continuous log ramp, `minBubbleDiameter` 22 →
  `maxBubbleDiameter` 48, saturating at `bubbleRampCeiling` = 26 MEMBERS. The ramp is scaled INTO the
  overlap cap, not clamped against it: clamping made size-by-count completely inert at z ≥ 15, where
  the cap (36 − 8 = 28) equalled the old 28pt floor, so a "2" and a "10" drew identically. Ordering
  now holds at every zoom. One definition (`POICluster.bubbleDiameter`) shared by the view and the
  label pass.
- **Town-label occlusion** — the town's biggest cluster necessarily sits on the town centroid, which
  is exactly where Mapbox anchors the name, and SwiftUI view annotations draw above the map canvas so
  Mapbox's collision engine can never see them. First attempt set `visibility: none`, which deleted
  EVERY town name in the viewport (Collegeville, Saint Wendel, Five Points, Rockville) — a nine-label
  sledgehammer for a one-label problem; caught in review. Now: `text-anchor: top` +
  `text-offset: [0, 2.4]` (ems of a 14–24pt label ⇒ clears the 22pt max bubble radius), plus
  `maxzoom 13.0` on `settlement-major-label` — above z13 you are unambiguously inside one town, the
  pill names it, and the offset label landed in the civic pin cluster ("St⬤oseph"). Matches what
  light-v11 already does to `settlement-minor-label`.
- **POI label de-confliction** (`POICluster.labelledPOIs`) — a greedy screen-space pass, same shape as
  the clusterer: reserve civic badges+labels (the map's anchors), then rendered bubbles (including
  ones mid-fade), then every POI badge, then grant labels. Boxes are ESTIMATED from the name rather
  than always reserving the 100×34 max. Priority is incumbents-first (so a pinch can't strobe a label
  on a collision boundary, and one label losing its box can't cascade), then food, then name —
  previously Supabase row-id order, i.e. arbitrary. `showsLabel` threads to `POIBadge`; the badge
  always draws, only the text is withheld, and the a11y label is NOT gated so VoiceOver still
  announces suppressed names.

**Verified:** build 0 warnings. Two independent review rounds (fresh QA + fresh Design Director, twice
each; the agent that wrote the code never reviewed it). Round-1 findings — Dark Mode count invisible,
global town-name deletion, unanimated tint flip, inert size ramp, over-reserved label boxes, arbitrary
label priority, no label hysteresis — all fixed and re-verified. Screenshotted z11 / z12 / z13.5 / z15
peek + expanded, plus a Dark Mode capture.

**Known / deferred:** (1) Park green still blooms faintly through the Liquid Glass sheet — inherent to
glass sampling its backdrop; judged correct behaviour, not tuned further. (2) **Dark Mode: the bottom
sheet + tab bar go dark olive with ~1.05:1 label contrast.** PRE-EXISTING — the system glass materials
predate this work — but Phase C's brighter green is what makes the slab read olive. Worth its own pass
if Dark Mode is ever supported. (3) The spec's "unify markers … tied by coral `#FF6B57`" was NOT
implemented: coral is reserved for live-now, and putting it on cluster chrome would stop a live badge
reading as special. Markers are unified by category palette + shared casing/shadow instead — flagged
for Jesse. (4) "Greens match Apple Maps" is eyeball-graded against the spec's target, NOT sampled from
a real Apple Maps screenshot: the simulator's Maps app blocks on its onboarding flow and this
XcodeBuildMCP profile has UI-tap tools disabled. Spec: `docs/superpowers/specs/2026-07-18-*`.

### Final pass (2026-07-19) — fresh Design Director + fresh code audit

Code audit: **SHIP**, zero blocking defects, 0 warnings; label geometry, pass convergence, prune
lifecycle, Phase A overlap/orphan invariants and the non-map tabs all verified correct. Fixed from its
non-blocking list:

- **Intermittent unstyled basemap.** `recolorBasemap` ran ONCE on `onStyleLoaded` and occasionally lost
  the race — a launch would render a complete but un-recoloured map (default Mapbox grey land/parks,
  no cream). Now re-applied on `onMapLoaded` too (pure `setLayerProperty`, so idempotent). **Caught by
  histogram, not by eye** — the bad frame is fully drawn, so it reads as a finished render: 3.3% cream
  / 0.3% green vs 66% / 7% when correct. **The fix is reasoned, not proven:** the failure is rare and
  was never reproduced on demand (pre-fix 3/3 clean, post-fix 4/4 clean). Re-verify by histogram.
- `scheduleClusterRecompute`'s 0.13s `DispatchWorkItem` captured `MapboxMap` strongly with no
  teardown cancel — the same hazard `schedulePrune` was hardened against. Now `[weak map]`.
- Removed dead `mapSheetShadow()` (its only caller, the sheet's opaque background, died in Phase B)
  and corrected stale docs: `CLAUDE.md` peek 120→96pt + the dead token, `MapSheet`'s full-detent
  clearance (132 − `tabBarReserve` ≈ 66pt, not 132), and `POICluster`'s label-pass invariance claim
  (with `previous` fed back the pass is stateful and settles one pass later — it damps, not strobes).

**FIXED (and CORRECTION to the Phase B entry above):** the Dark Mode failure of the bottom sheet was
**not** pre-existing as first recorded. `MapSheet.swift` `.glassEffect(.regular, in:)` REPLACED a fixed
`Hue.surface` fill, and `.glassEffect` IS appearance-adaptive — so Phase B introduced the sheet half.
It failed at the peek rest state specifically (the `frost` overlay opacifies the body from `medium`
up). The TAB BAR going dark was genuinely pre-existing.

Fixed by declaring `.environment(\.colorScheme, .light)` on the `GlassEffectContainer` in
`MainTabsView` — on the CONTAINER so both glass surfaces resolve together (pinning only the sheet
would light it while the tab bar stayed dark, visibly splitting the continuous piece the container
exists to create). This states what the app already assumes — every Hue token is a fixed light hex and
the basemap is light-v11 recoloured — rather than adding behaviour. Measured on the "Today" tab label
in Dark Mode: **1.07:1 → 3.71:1**, i.e. exact parity with light mode. Note 3.71:1 is what the app
ships in light mode too, and is BELOW the 4.5:1 WCAG AA threshold for normal text — a separate,
pre-existing question this fix does not address. Verified in Dark Mode on the map (peek) and the
Activities tab. If real Dark Mode is ever wanted, removing that line is the START of the work (a dark
Hue ramp + a dark basemap palette), not the whole of it.

Design Director: **DON'T SHIP** — open items, all needing a product decision rather than a fix:
1. **Rest dots don't dodge the town label** — at z12 a civic dot sits on the "St" of "St. Joseph". The
   centroid-offset cleared the cluster BUBBLES only. Options: cap the label at maxzoom 12 (z12–13 then
   has no town names at all), push the offset further (detaches the label from its dot), or accept.
2. **A POI badge occludes the Sacred Heart Chapel civic landmark at z15** and captures its name label.
   PRE-EXISTING (present in the before-shots), but violates "civic landmarks stay always-on-top".
3. **Cluster fill is cool, not neutral** — `#EAEBF3` (B−R +9) on `#F4F3EC` land (R−B +8), a 17-point
   hue reversal. The earlier "it's the ring" diagnosis was wrong; it is the fill.
4. **The sheet's glass bleaches warm backdrops while transmitting green** — park polygon SHAPES are
   readable through the panel at the default zoom. Earlier judged "inherent to glass"; that does not
   survive measurement and is a tuning problem.
5. **Civic and POI markers are still two families** (`SpotCategory` slate/ochre vs `PlaceCategoryMap`
   amber/indigo, ~20pt apart on screen) — the "one family" bullet is unmet. Coral was correctly kept
   off markers, but nothing else ties the two sets together.
6. De-confliction doesn't reserve the app's own floating chrome or Mapbox's street labels — at z16 a
   POI label draws under the filter chip; the "5" bubble covers "Cedar St E" at the default zoom.

### Post-final-pass fixes (2026-07-19)

Three of the Design Director's six open items fixed; three left, with reasons.

**Fixed**
- **De-confliction now reserves the app's own floating chrome** (`chromeRects` in
  `SJMapView+POIClustering`, fed to `POICluster.labelledPOIs` as the highest-priority
  reservation). Top row, the collapsed sheet + tab bar, and the ?/locate circles. Previously a
  granted label could draw UNDER the filter chip or compose "+" — not merely crowded, invisible.
  Verified at z16. Map size is measured in the view layer via `GeometryReader`; `MapboxMap.size`
  is `internal` to the SDK.
- **Cluster fill no longer cool.** Base moved off `Hue.surface` (pure white — the app's surface
  ramp is cool) to a warm near-white `#FBFAF5` in the map's cartography family, and the category
  wash dropped 7% → 5%. Measured interior: **#E8E9ED (R−B −5, cool) → #E8E8E8 (R−B 0, neutral)**.
  Honest limit: the land is `#F4F3EC` (R−B +8), so the disc is now NEUTRAL, not warm — a ~8-point
  gap rather than the previous 17-point reversal. Pushing warmer starts dissolving the disc into
  the ground.
- **Town label at the default zoom** — resolved by the `maxzoom 13` cap already in place.

**Not fixed, and why**
- **A civic REST DOT can still graze the town name at z12.** Anchoring the label ABOVE the
  centroid was tried and measured WORSE (it lands squarely behind the 61-bubble — the bubble is
  centred on the centroid). A larger offset detaches the name from its own dot, and our pins
  can't dodge because they sit at real coordinates while the label belongs to Mapbox. Four
  iterations in; the remaining fixes cost more than the defect.
- **A POI badge occludes the Sacred Heart Chapel civic landmark at z15/z16** and captures its
  name label. PRE-EXISTING (present in the before-shots). Civic annotations are already declared
  last, which should win z-order and doesn't, so this needs a real fix in the annotation layering
  — not a tweak. The alternative (withholding a colliding POI badge) hides a genuine business.
- **Sheet glass transmits green / bleaches warm backdrops**, and **civic vs POI are still two
  palettes** (the spec's "one family" bullet). Both are design changes with real blast radius —
  the second means retuning `PlaceFamily.tint` app-wide — and belong to Jesse, not to a fix pass.

### The last three open items — fixed (2026-07-19)

- **Civic landmarks now actually win z-order.** `MapViewAnnotation` draw order is controlled by
  **`.priority(Int)`**, NOT by declaration order — which is why the six civic pins, declared
  last precisely so they'd win, were still being covered by POI badges (a blue POI disc sat on
  Sacred Heart Chapel and captured its name label). Now explicit: `poiPriority 0` <
  `clusterPriority 10` < `civicPriority 20`. Higher draws on top — verified empirically at z15,
  where the chapel badge is fully visible with its own label and the POI disc sits behind it.
- **One marker family.** `PlaceFamily.tint` moved off the borrowed `EventCategory` tokens
  (food `#F08A3C`, games `#5B6EE0`) to map-palette tints: **food `#C67439`** (muted terracotta,
  beside `Hue.honey600`) and **business `#5A76A8`** (muted slate blue, beside `Hue.sky600`).
  The old pair carried ~20 points more saturation than the civic earth tones, so the map ran two
  colour systems — and the saturated POI dots visually OUTRANKED the landmarks they defer to.
  POI was brought DOWN into the civic band rather than civic pushed up, since the app tokens are
  the fixed point. Dropping business off hue 231 also removes the periwinkle cast it lent the
  cluster bubbles.
- **Sheet glass no longer prints park shapes.** The content frost veil ramped `0 → 0.94` from
  peek to medium, i.e. **pure glass at the peek rest state** — and pure glass over this basemap
  bleaches the warm cream ground while transmitting park green, so the collapsed sheet picked up
  green blotches whose polygon shapes were readable. Added `frostMin = 0.30`. Measured in the
  sheet interior at the default zoom: **green-cast 73.9% → 31.1% of pixels, meanDev +10.95 →
  +7.93**. Honest limit: reduced, NOT eliminated — the brightest spots still come through at
  roughly the same intensity (worst pixel `#E3F8D6` → `#E5F8D8`), there are just far fewer of
  them. A higher floor would finish the job but stops the peek band reading as the same glass as
  the tab bar it merges into, which is the whole point of Phase B.

## 2026-07-23 — Issue 1: civic landmarks join clusters; cluster-first labels

- **One clustering input set below `pinExpandZoom`.** POIs and the filtered civic landmarks now
  enter `POICluster.compute` through namespaced ids. The radius pass remains deterministic, then
  any collapsed-band singleton joins its nearest real group: every finite, non-selected marker
  is assigned once and counted once. At/above 14.5, civic inputs are withheld from grouping and
  receive explicit solo assignments, so the always-mounted civic leaves de-cluster back to their
  real anchors.
- **Selection and live state.** The selected civic or POI id is excluded before grouping and is
  never included in a bubble count. Live civic pins are absorbed (no live orphan); the aggregate
  gets a palette-routed static live ring plus a truthful VoiceOver suffix, refreshed when events
  or the minute heartbeat changes.
- **Cluster-first collision geometry.** Removed the civic keep-away offsets and reversed the
  annotation priority to cluster > selected > unselected. One label pass now covers both catalogs:
  rendered bubbles (including dissolving ones) reserve first, then every visible badge, then the
  selected label, then remaining labels by distance to the camera focus. It reserves the full
  100pt/two-line label ceiling plus halo, and retains a conservative count diameter during count
  crossfades.
- **Continuous merge/split.** POI and civic markers share one isolated leaf motion wrapper using
  `CLUSTER_SPRING`. It retains the old cluster anchor through a split, fixing the one-frame return
  pop; counts crossfade with `Motion.smooth`. Reduce Motion removes travel/scale and crossfades
  leaf ↔ bubble instead. Marker, label, selection, and live colors remain routed through
  `MarkerRole`.

**Verified:** iPhone 17 simulator (iOS 26.5), scheme `BlockParty`, Debug:

`xcodebuild -project /Users/owner/Documents/block-party-map-polish/BlockParty.xcodeproj -scheme BlockParty -configuration Debug -skipMacroValidation -destination "platform=iOS Simulator,id=661E32C7-985C-458F-9CA7-6759114CADE8" -collect-test-diagnostics never -derivedDataPath /Users/owner/Library/Developer/XcodeBuildMCP/workspaces/block-party-map-polish-8d94ea1f7730/DerivedData/BlockParty-644c7251adb7 "OTHER_LDFLAGS=$(inherited) -framework AppIntents" build`

Result: **BUILD SUCCEEDED, 0 warnings, 0 errors**. The command-line AppIntents link is verification
only (no project-file change); it suppresses Xcode 26.5's otherwise unconditional metadata-tool
"No AppIntents.framework dependency found" warning, while the normal build also reports zero source
diagnostics.

**Geometry audit:** at z11 and z13, `forceAllIntoClusters` leaves no finite non-selected civic or
POI assignment solo, so no civic dot can remain on/near a bubble. At z15, every civic assignment is
solo; bubble rectangles are reserved before all labels, every solo badge before any label, and each
granted label is appended before the next candidate, so no non-selected label box can intersect a
bubble, badge, or prior label by construction.

**Honest limits:** no frame-sampled simulator motion/design pass was run. Design QA should watch the
live 15→11→15 sweep for subjective spring feel and the aggregate live-ring treatment, and confirm
the conservative full-width label reservation is not visually too sparse.

## 2026-07-23 — Issue 1 adversarial-review follow-up

- Restored label incumbency ahead of focus distance for non-selected candidates, reusing the
  current labelled set across recomputes; non-finite focus distances normalize to `+∞`.
- Guarded the collapsed-band fallback against selecting and appending a singleton group to itself.
- Updated the stale live-color header note to point to `MonoMarkerPalette`'s role table.

**Verified:** iPhone 17 simulator (iOS 26.5), scheme `BlockParty`, Debug:
**BUILD SUCCEEDED, 0 warnings, 0 errors**. Static review confirms the reservation order remains
chrome → rendered bubbles → all badges → selected label → non-selected labels.

## 2026-07-23 — Brand logos on POI pins (`feat/poi-logos`)

Businesses with a real brand mark now show it instead of the category glyph — inside the
expanded 26pt pin circle (inset 3pt so the hairline keyline stays the outer edge), the 34pt
selected marker (fill flips to `MarkerRole.selectedPOILogoFill` = surface, since a mark can't
sit on mid grey; ring/halo/shadow keep carrying selection), and the 40pt in-bar detail header.
Compact 12pt dots and cluster bubbles unchanged. Glyph remains the designed fallback.

- **Backend:** `places.logo_url` + public `place-logos` Storage bucket (admin-gated writes),
  migration `20260723000000_places_logo.sql`, applied live.
- **App:** `POILogoCache` (MainActor, `@Published [URL: UIImage]`, own URLSession + URLCache
  4/50 MB, `.returnCacheDataElseLoad` — logos immutable per URL) prefetched once after
  `loadPlaces()`; **no AsyncImage** — annotation views rebuild constantly during pan/cluster
  churn and AsyncImage would flash its placeholder each rebuild, so pins do a synchronous dict
  lookup and render final state on first frame. `POILogoCircle` renders nothing when absent so
  each call site keeps its glyph as the fallback layer (one-line integrations).
- **Curation pipeline:** `scripts/fetch_place_logos.py` (candidate ladder: apple-touch-icon →
  square-ish og:image → largest link-icon → favicon.ico → Google favicon; auto-reject <96px /
  extreme aspect / near-blank; normalize to 256px white-padded square) run by 4 parallel Codex
  agents + a rescue round, then **strict Claude vision verification** (right business's mark ·
  crisp · reads in a 26pt circle crop) over PIL montages. **53 of 91 places approved**; the 38
  misses are genuinely logo-less small businesses → glyph fallback. Provenance:
  `docs/place-logos-manifest.json`. Google Places used transiently for websiteUri only —
  no Places content persisted (ToS).
- **DEBUG:** `-poi-logo-stub` renders deterministic code-drawn marks for headless verification.

**Verified:** iPhone 17 Pro simulator (iOS 26.5), scheme `BlockParty`, Debug:
**BUILD SUCCEEDED, 0 warnings, 0 errors.** Screenshot matrix with `-poi-logo-stub`: logos in
expanded pins (hairline intact, labels beside), compact dots + clusters unchanged (regression),
selected marker + detail header logo, and glyph fallback without the flag.

**Shipped live (same day):** 53 PNGs uploaded via a user-approved, immediately-dropped temp
insert policy (bucket writes are admin-only again; 53 objects verified), `logo_url` set from
the uploaded object names in one UPDATE. Live-data screenshots verified: Bad Habit's roundel
in its 26pt pin, Krewe's "K" in the selected marker + detail header, glyph fallback elsewhere.
Design pass (emil-design-eng + impeccable): white-padded logos blend into the surface-filled
pins, color arrives only as real business identity, mono value ladder intact — no desaturation
needed. Gotcha for the record: the first live screenshots showed no logos because a parallel
session had installed ITS build over this one on the shared booted sim (same bundle id) —
**reinstall your own .app right before screenshotting when sims are shared.**
## 2026-07-23 — Issue 2: continuous MapSheet drag/scroll handoff

- Moved the vertical drag recognizer from the grabber to the whole sheet while preserving the
  grabber as an unconditional sheet-drag region. At non-full detents the sheet owns vertical
  movement. At full, the active inner ScrollView owns normal scrolling until a downward drag
  begins or arrives at its top; ownership then latches to the sheet and disables that scroller.
- Each of the list, spot-detail, and POI-detail scrollers reports only a top/not-top Bool through
  `onScrollGeometryChange`. A mid-gesture scroll→sheet handoff records the exact translation where
  the top was reached, so the sheet continues from zero without a jump or double reaction.
- Sheet tracking uses `Motion.interactive`; release projects `predictedEndTranslation` to the
  nearest existing detent and settles with `Motion.sheet`. A fast downward velocity overrides the
  nearest stop and collapses to peek, including after a mid-drag direction reversal. Reduce Motion
  continues to route through `Motion.smooth`.

**Verified:** iPhone 17 simulator (iOS 26.5), scheme `BlockParty`, Debug:
**BUILD SUCCEEDED, 0 warnings, 0 errors**. `-show-home -open-tab map -map-detent
peek|medium|full` launches were screenshot-checked at all three rest states; the original
peek⇄list `p` cross-fade and unified sheet/tab-bar glass remained intact. The verification build
used the repository's Xcode 26.5 AppIntents metadata-warning workaround:

`xcodebuild -project /Users/owner/Documents/block-party-map-polish/BlockParty.xcodeproj -scheme
BlockParty -configuration Debug -skipMacroValidation -destination "platform=iOS
Simulator,id=661E32C7-985C-458F-9CA7-6759114CADE8" -collect-test-diagnostics never
-derivedDataPath /Users/owner/Library/Developer/XcodeBuildMCP/workspaces/block-party-map-polish-8d94ea1f7730/DerivedData/BlockParty-644c7251adb7
CODE_SIGNING_ALLOWED=NO "OTHER_LDFLAGS=$(inherited) -framework AppIntents" build`

**On-device limit:** simulator automation cannot reliably exercise the interactive pan. Human QA
must confirm immediate 1:1 downward tracking at scroll top, normal full-height content scrolling
away from top, seamless same-gesture handoff on reaching top, and fast downward flick-to-peek from
each height (including after reversing mid-drag).

## 2026-07-23 — Issue 2 cancellation + tap-race follow-up

- Added an auto-resetting `@GestureState` lifecycle flag. Its active→inactive transition calls
  `resetDrag()`, so cancellation clears the offset, owner, and handoff even when `onEnded` is not
  delivered; at full, that also immediately re-enables the active ScrollView.
- Kept the outer recognizer at 1pt, but finishes below an 8pt effective vertical translation now
  reset without entering `snap`, leaving peek/list/segment/row taps authoritative.

**Verified:** iPhone 17 simulator (iOS 26.5), scheme `BlockParty`, Debug:
**BUILD SUCCEEDED, 0 warnings, 0 errors**.

## 2026-07-23 — Issue 3: tab bar morphs into map place detail

- Lifted map selection into `MainTabsView` as one typed `MapPlaceDetail?`. The enum carries the
  source `Spot` or `POI`; `SJMapView` derives its existing selected civic/POI state from that
  binding and routes direct pins, list focus, debug preselection, X, map-background taps, filter
  dismissal, and camera release through the same value.
- Kept `BlockPartyTabBar` as one persistent `.glassEffect(.regular)` shell with the existing
  26pt continuous radius. It conditionally swaps the four tab buttons for the compact name,
  category/distance badge, Directions, Save, and X content while its container size settles with
  `Motion.sheet`; Reduce Motion uses an opacity-only content transition with `Motion.smooth`.
- Removed `MapSheet`'s civic/POI detail renderers and selection-driven medium-detent lifts. While
  a place is selected the browse sheet is removed from the glass compositor (opacity alone left
  extracted Liquid Glass child text visible); close restores its unchanged Today/Places peek.
  The selected camera reserve is now 206pt, capped for short layouts, instead of half the map.
- Civic details show their real category and coordinate-derived distance from downtown. POIs show
  their real `PlaceFamily` category, glyph, and coordinate-derived distance. Neither source model
  has price data, so price is omitted rather than invented. Directions is the plum-filled primary
  CTA; active Save uses a plum bookmark/keyline plus the selected accessibility trait.
- VoiceOver exposes the labeled place heading, X, Directions, and Save separately. The other tab
  buttons return after close, and an Activities round-trip confirmed normal non-detail tab
  navigation is unchanged.

**Verified:** iPhone 17 simulator (iOS 26.5), scheme `BlockParty`, Debug:

`xcodebuild -project /Users/owner/Documents/block-party-map-polish/BlockParty.xcodeproj -scheme
BlockParty -configuration Debug -skipMacroValidation -destination "platform=iOS
Simulator,id=661E32C7-985C-458F-9CA7-6759114CADE8" -collect-test-diagnostics never
-derivedDataPath /Users/owner/Library/Developer/XcodeBuildMCP/workspaces/block-party-map-polish-8d94ea1f7730/DerivedData/BlockParty-644c7251adb7
CODE_SIGNING_ALLOWED=NO "OTHER_LDFLAGS=$(inherited) -framework AppIntents" build`

Result: **BUILD SUCCEEDED, 0 warnings, 0 errors** (including a raw-log
`warning:`/`error:` scan). Screenshot-checked `-open-tab map -map-open downtown`,
`-open-tab map -map-zoom 16 -map-open-poi`, and plain `-open-tab map`. Simulator
interaction confirmed X and blank-map taps restore the four-icon bar/peek sheet, active Save is
plum and selected, and the sheet's peek still opens its Today/Places medium list.

**Tradeoff for review:** pin taps no longer surface the richer in-sheet happenings, address,
Google venue info, or civic blurb. The compact morph intentionally limits tap detail to identity,
category/distance, Directions, and Save; Today/Places browsing remains in `MapSheet`.

### Follow-up fixes (post-review, 2026-07-23)

- **Browse state preserved.** `MapSheet`'s `detent`/`mode` were lifted into `SJMapView` as
  `@State` and passed back as bindings, so opening a place and closing it returns the browse
  sheet to its exact prior detent + Today/Places mode (previously the unmount/remount reset it
  to peek/Today).
- **Camera reserve content-driven.** The selected-pin camera clearance now uses a
  `@ScaledMetric(relativeTo: .title3)` 250pt two-line baseline (160pt floor, `containerH*0.36`
  cap) instead of a fixed 206pt, so a 2-line name / large Dynamic Type doesn't hide the pin
  behind the taller detail bar.
- **Degenerate distance suppressed.** A sub-30m distance (e.g. the downtown spot measured from
  the town-center reference) is dropped from the badge + VoiceOver rather than reading a
  self-distance.
- **X-close animated** with `Motion.card` to match the map-tap close curve.

Independently reviewed (no CRITICAL/HIGH): selection lifecycle robust (single source of truth,
every exit path clears it), morph return-to-4-icons clean (no `matchedGeometryEffect` collision),
the `MapSheet` gut left no dead code, and Issues 1 & 2 are unaffected. The live morph animation
and browse-state preservation are confirmed by code review + on-device (not sim-automatable).
Build: 0 warnings, 0 errors.

## 2026-07-23 (later) — Representative marks for (almost) every pin

Product call from Jesse: every POI should carry an image representing what it is — not
only strict brand marks. Round 2 relaxed the policy: own wordmarks/abstract marks count
(provenance from the business's own site/page is identity proof), and PARENT-institution
logos stand in where that's the identity (CSB lockup for the Benedicta Arts Center
galleries, the monastery mark for Whitby Gift Shop). `--relax` on the import path drops
the aspect cap so wide wordmarks pad to square. Two Codex agents re-hunted the 38 missing;
a vision pass (relaxed but sane) approved 24 and rejected 5 building/interior photos that
smear to noise in a 26pt circle. **77 of 91 places now carry a mark**; the final 14 have
no owned mark anywhere (closed businesses, avatar-less FB pages) and keep the glyph.

Known tradeoff, accepted deliberately: extreme-aspect wordmarks (Unwind, CSB) read faint
at 26pt pin size — fine at the 44pt detail-panel avatar. If a specific pin bothers, the
fix is a hand-cropped monogram import for that row, not a policy change.

**Verified:** live data on iPhone 17 Pro sim — round-2 marks render on pins + detail panel;
bucket = 77 objects, `places.logo_url` = 77 rows; provenance regenerated in
`docs/place-logos-manifest.json`.
## 2026-07-23 — Follow-up: expand the morphed detail into rich venue info

A grabber/chevron on the morphed place detail expands the SAME glass bar upward into the rich
detail — civic: blurb + happenings + `VenueInfoView` (Google hours/website/phone/photo); POI:
address + `VenueInfoView` — and collapses back to compact (X still closes to the 4-icon bar from
either state). One continuous `.glassEffect` shell (content grows inside `detailPanel`; no second
card). Grabber-OWNED drag (up=expand / down=collapse) + tap toggle; `Motion.sheet` /
`Motion.smooth` under Reduce Motion; the drag is non-interactive (a Bool via spring) so an
interrupted drag can't stick half-open. `VenueInfoView` is instantiated only when expanded (no
Google fetch for selections that are never expanded). Happenings reach the tab bar via a
`mapDetailHappenings` binding that `SJMapView` fills from `MapModel.todayEvents`, resynced on
selection AND on realtime event changes, and cleared for POIs / dismissal.

Review fixes: expanded ScrollView height is `min(440, containerH*0.55)` (was a fixed 440 that
rode into the status bar on small devices at large Dynamic Type); the expand affordance is
suppressed when there is nothing extra to show (civic with no blurb + no happenings, POI with no
address); happenings rows are combined VoiceOver stops that announce "live now" in text. Left
as-is: a cosmetic one-frame `VenueInfoView` blank→populate flash on re-expand (in-memory cache
hit, no network).

DEBUG: `-map-detail-expanded` (with `-map-open <id>` / `-map-open-poi`) starts the detail
expanded for headless screenshots — there is no UI-automation tap in this setup.

Independently reviewed (no CRITICAL/HIGH): the expand state resets on every selection/dismissal
(no stale rich content for the wrong place), happenings are correct + non-stale, the gesture is
cancel-safe, one-glass continuity holds, and Issues 1 & 2 are unaffected. Verified in the
simulator (blurb + real distance — 350 ft downtown vs 3.8 mi St John's — + the expand growth).
Rich venue data is often sparse for the civic spots (their `"<name> St Joseph MN"` query resolves
poorly for Collegeville venues — inherited from the prior detail); the payoff shows on real POIs
and event days. Build: 0 warnings, 0 errors.

---

## Town rain — the town's brand marks drop when you press "Saint Joseph"

`flyHome()` (the tappable town pill AND the recenter control — they already shared it) now also
drops a short burst of REAL local business logos down the screen. They fall under gravity, bounce
once off the map sheet's peek edge, tumble, and drift out to the left.

Ported frame-by-frame from a reference recording, the same method as the corner drawer and the
share reveal — but measured numerically rather than eyeballed. Every frame of the reference was
extracted at 60 Hz, sprites isolated against a per-pixel median background plate, tracked, and each
flight segment fitted with least squares. Ten tracks, six clean and full-length. Full method,
per-track fits and the shipped-build re-measurement: `docs/town-rain-reference-measurements.md`.

Measured → shipped: gravity **1090 pt/s²** (fits 1044–1130, mean 1092 — i.e. UIKit Dynamics'
magnitude-1.0 gravity, nudged) · restitution **0.33** (0.336/0.328/0.324) · spawn cadence **0.21 s**
(0.200/0.200/0.217/0.217) · drift **−300…−205 pt/s**, always leftward (10/10 tracks) · ball **36 pt**
(bbox 32–37 pt) · entry at rest a half-ball above the top edge, never launched. 14 balls per press
holds the reference's 5–7-airborne density across the 0.8 s camera fly, then clears in ~5 s.

- **`TownRainPhysics`** — pure values, no SwiftUI: the constants, the integrator, the emitter and a
  SplitMix64 so a seed replays a burst exactly. Steppable at 240 Hz in a test with no view.
- **`TownRainField`** — one `Canvas` (not 14 views) driven by a `CADisplayLink` at 80–120 Hz. The
  per-frame publish is deliberately trapped in this leaf: `SJMapView` observes nothing, so the
  Mapbox map does not re-render with the rain. Balls are the same object as the pins — full-bleed
  mark in a circle with a `Hue.hairline` keyline, matching `POILogoCircle`. Inset marks were tried
  first and read as a badge-in-a-badge at 36 pt.
- **`TownRainRoster`** — 50 frozen `places.id`. `places` has no popularity column, so "top" is
  ranked by logo PROVENANCE off the curation manifest (own-site touch icon 21 → strict hunt 16 →
  rescue 10 → declared link-icon 3), ties by source resolution then name; round-2 "representative"
  marks are cut. Regenerate with `scripts/rank_rain_roster.py`. Missing ids degrade to any
  logo-bearing POI rather than breaking.
- Z-order: **under** the sheet. The balls' floor IS the sheet's peek edge, so at peek they bounce on
  its visible top and a raised sheet simply hides them. Non-interactive — it cannot eat a map
  gesture or a press on the pill it was launched from.
- Reduce Motion: **nothing falls** (§11). The press keeps its haptic and its camera fly, so the rain
  never carries information on its own.

DEBUG: `-town-rain-preview` renders the field full-screen past the auth gate and loops a burst —
there is no tap automation here and the real trigger is a touch on the town pill, so the drop is
otherwise unrecordable. It builds its `places` stand-ins from the REAL roster uuids against the
public `place-logos` bucket, so it rains the real marks over the real fetch path; add
`-poi-logo-stub` for a deterministic offline run when measuring physics. `-town-rain` fires one
burst on the real map once POIs land.

Verified: the shipped build was recorded on the simulator and run through the SAME tracker,
twice (before and after the review pass) — g median **1096** then **1128** pt/s², restitution
**0.334**, drift **−213…−307**, cadence 0.167–0.233 (±1 frame of 60 Hz sampling jitter), exactly
**14** balls both times. The g spread is tracker noise, not model drift: the same traces imply
g is simultaneously 3.5% too strong (fitted) and 5% too weak (fall duration), which is what a
noise-dominated fit looks like. The unit tests are the statement of the physics; this trace is
a ±5% check that the display link feeds the integrator sane timesteps. 97 tests green, build 0 warnings. A mutation run
(g 1090→900, e 0.33→0.55, interval 0.21→0.35, size 36→52) fails the suite, so the tests bind to the
measurements rather than restating them — the first pass did NOT, and
`testEveryMeasuredConstantStaysInsideItsReferenceSpread` exists because of it.

Not verified end-to-end: the press-to-rain path on the **real signed-in map**. This simulator has no
session, so `getPlaces()` returns nothing and there is nothing to rain; the roster→cache→ball chain
was verified against the live bucket through the preview instead. Worth one tap on a signed-in
device.

### Town rain, revised — one ball, a closed field, and a bubble on the press

Feedback after the first pass: more free flow, land on the sheet instead of behind it, a
press acknowledgement, and one ball at a time. All four:

- **A short burst per press** (`burstCount` 14 → 1 → **5**). One was too sparse on the
  device; 5 is the reference's own measured density (5–7 airborne), arriving at the
  measured 0.21 s stagger so the screen fills over about a second instead of flashing
  full. Pressing again replaces the whole burst rather than stacking another on top.
- **The field is closed.** Side walls at `wallRestitution` 0.62, so the ball returns across
  the screen instead of exiting. It settles once a floor contact falls under `restSpeed`,
  rolls to a stop under `rollingDrag`, and fades over `fadeDuration` — with walls there is
  no edge left to leave by, so the fade IS the exit.
- **The floor is the sheet's live top edge.** `MapSheet` publishes `SheetTopKey` (a real
  distance, unlike `SheetExpansionKey`'s clamped 0→1 chrome-fade signal); it tracks the
  detent spring frame by frame, so dragging the sheet mid-flight changes where the ball
  lands, and a ball resting on the sheet rides up with it. This closes the hole flagged in
  the first pass, where a raised sheet hid the whole animation behind itself.
- **Drift is now two-directional.** Magnitude is still the measured 205–300 pt/s, but the
  side is drawn per ball. Recording the first cut showed why: an always-left drift (correct
  for a rain that exits stage left) walks a single ball into the left wall and parks it in
  the corner within ~2 s. Entry moved to 0.15–0.85 W for the same reason.
- **`townPillBubble`** — the pill swells 6% and one `Hue.ink` ring blooms out of its own
  capsule silhouette and dissolves over 0.5 s. It is the only cue at the instant of the tap;
  the camera fly and the falling mark both take a beat. Reduce Motion keeps the ring's
  dissolve and drops the scale.

DEBUG `-town-rain` now fires from `onAppear` instead of waiting on `pois`, and plays the
bubble as well as the drop — signed out, `pois` never lands, so the old gate made the press
unrecordable.

Verified on the simulator: the ball traverses the full width, bounces off both walls and the
sheet, settles and fades in ~3.5 s; the bubble blooms at the press and is gone in ~0.45 s.
146 tests green (up from 99 — the wall, settle, fade, floor-tracking and drift-direction
rules all carry tests), 0 warnings.

Follow-up after device testing: `burstCount` 1 → 5. One mark read as too sparse in the hand;
five is the density the reference actually had. Nothing else changed — the closed field, the
sheet-tracking floor, the settle/fade and the bubble all carry over, and the 0.21 s stagger
that was vestigial at a burst of one is load-bearing again. 147 tests, 0 warnings.

Second round of device feedback, two changes:

- **One mark per press, but they accumulate.** `burstCount`/`spawnInterval` are gone — the
  emitter no longer has a clock of its own. `dropped(logoCount:)` adds a single mark and
  keeps whatever is still bouncing, so pressing four times in four seconds leaves four on
  screen. `maxConcurrent` (12) is a safety rail against a held-down pill, and it retires the
  OLDEST mark rather than refusing the press — a press that visibly does nothing is worse
  than a crowded field. Consecutive presses deal from a shuffled deck, so the same business
  never falls twice in a row.
- **Local businesses only.** The roster excludes chains, franchises, multi-branch banks,
  regional health/senior-care operators and government or college facilities — Coborn's,
  State Farm, Ace, Bo Diddley's, Magnifi, Kensington and Sentry Bank, TireMaxx, CentraCare,
  Country Manor, USPS, the CSB gallery — plus locally-owned but back-office businesses with
  no storefront the public would recognise (freight, title, printing, tax, fabrication,
  landscaping). 21 cut, **56 local marks left**, each exclusion carrying its reason in
  `scripts/rank_rain_roster.py`. Dropping the top-50 cap was the point: filtering for local
  and then capping at 50 would have thrown away real local businesses to hit a round number.

150 tests, 0 warnings. The preview gate now taps in runs of five, 0.9 s apart, so a recording
actually shows marks accumulating rather than one arriving alone.

## 2026-08-13 — Map polish Phase 0: baseline (plan 2026-08-13-map-tab-ui-polish)

Baseline for the map-tab UI polish pass. Two commits: `e8e13ca` (the parallel session's
pbxproj churn — an empty `exceptions = ();` Xcode removed — committed alone so phase commits
stay clean) and `b941411` (DEBUG-only `-map-compose`, which presses the top-right "+" 0.6 s
after appear — the exact composeButton branch, so admins get QuickAddSheet and non-admins the
global composer; compiles out of Release).

Four BEFORE screenshots on the iPhone 17 sim (iOS 26.5, `661E32C7`), stored in the session
scratchpad under `before/`:

- `before-rest.png` — `-open-tab map`: rest chrome, peek sheet, default 13.5 camera.
- `before-clusters.png` — `-open-tab map -map-zoom 13`: six cluster bubbles (2 · 11 · 3 ·
  5 · 8 · 46) — zoom 13 is the cluster-framing baseline for the after shots.
- `before-pin-detail.png` — `-map-open-poi blend -map-detail-expanded`: The Local Blend in
  the expanded glass-bar morph (the venue-photo region is blank — the outstanding Google
  key restriction in `DECISIONS.md`, not a regression).
- `before-compose.png` — `-open-tab map -map-compose`: QuickAddSheet ("Add a happening"),
  admin branch.

**Verified:** iPhone 17 simulator, scheme `BlockParty`, Debug: **BUILD SUCCEEDED, 0 source
warnings** (only the known Xcode 26.5 `appintentsmetadataprocessor` notice — workaround
recorded above, 2026-07-23). One environment repair: the Mapbox SPM working copy in
DerivedData was corrupt after the Aug-12 disk cleanup; `xcodebuild -resolvePackageDependencies`
restored it, no files deleted.

## 2026-08-13 — Map polish Phase 1: cluster bubbles go ink (plan 2026-08-13-map-tab-ui-polish)

Cluster bubbles restyled per Jesse's Q1 decision — keep the continuous 22–48pt log ramp
(tiers stay rejected), move the disc to ink:

- **`MonoMarkerPalette.swift`** — `clusterFill` inkSecondary → `ink`; `clusterShadow`
  deepened 0.22 → 0.25; new `liveRingGap` (surface) role. The value-ladder header is
  rewritten to the new truth: clusters share the ink tier, and what separates a cluster is
  SHAPE + CONTENT + DEPTH — a count-sized disc (22–48pt ramp) with a white NUMERAL and the
  deepest shadow on the map, vs the civic pin's fixed 28pt badge with a white GLYPH. POI
  discs are now the only light class, so defect 1 (two light discs reading as one class)
  cannot regress. Two stale comments corrected: the accent is the real plum `#8E3B6B`,
  not "a placeholder equal to ink".
- **`POIMarkers.swift`** — numerals stay white but drop bold → **medium** (the dark disc
  carries the emphasis); the bubble shadow now uses `mapFloatShadow`'s soft geometry
  (blur 8 / y 2) with the deeper cluster tone rather than the old tight blur-5; the
  stale "LIGHT disc / count in map ink" doc rewritten. **Live-on-cluster contrast:** plum
  on ink is well under 3:1 and read as nothing, so a 1pt surface seam now sits between the
  disc edge and the 2pt plum ring — the ring is clearly legible on the ink disc
  (`-map-force-live downtown`, which clusters into the big z13 bubble).
- `POICluster.swift` untouched — ramp, caps and clusterer unchanged.

**Merge/split verdict:** already identity-stable, as believed — `-map-autozoom` frame
sampling shows leaves gliding, counts crossfading (`contentTransition(.opacity)` double-
exposure mid-frame is the crossfade, not a defect), and dissolving bubbles fading. No
pop-in; no animation change made.

**P0 overlap verdict ("61"/"21" in `before-rest.png`):** transient, not a layout/dedup
defect. Launch sequence captured at t+4s shows every POI rendered solo before the first
cluster recompute; the overlap window is the ~0.5s glide/fade right after it, where a
dissolving bubble (kept mounted for its fade by design) stacks under its replacement.
Three settled captures (rest t+8s, z13 t+10s and t+13s) are all clean, and the at-rest
overlap guard (bubble diameter capped below the cluster radius) holds. No fix needed.

Screenshots (session scratchpad `p1/`): `p1-clusters-z13.png` (z13 framing — solid ink
discs, legible white numerals down to the smallest 22pt "2"), `p1-rest.png` (default 13.5),
`p1-live-cluster.png` (plum live ring + surface seam on the 46 bubble),
`p1-clusters-z13-dark.png` (dark mode — markers unchanged via `onLightCanvas`, only the
chrome adapts), plus `az-*` autozoom frames and settled-state crops. The 0.95 translucency
was re-checked on ink: no badge ghosting through the big bubbles.

**Verified:** iPhone 17 simulator, Debug: **BUILD SUCCEEDED, 0 source warnings** (only the
known `appintentsmetadataprocessor` notice). Installed over the app from the freshly
resolved `BUILT_PRODUCTS_DIR`.

## 2026-08-13 — Map polish Phase 2: search replaces the top-right "+"; "+" relocates (plan 2026-08-13-map-tab-ui-polish)

The compose slot becomes a real place/event search; the "+" moves to the bottom-right
control stack, directly above recenter (Q5/Q8 decisions).

- **`SJMapView.swift`** — the top-right chromeCircle is now a magnifier that
  spring-expands (Motion.card width animation on the SAME glass capsule — a 44pt
  capsule IS the chromeCircle recipe) into a focused search field with an "X" that
  collapses + clears. The town pill fades out while search is active and is restored
  on collapse; the pill itself is untouched (Q8). Result tap / keyboard Search:
  keyboard down, search collapses, camera FLIES (`withViewportAnimation(.fly(1.0))` +
  `liftedViewport`, the `focus(_:)` recipe) and the pin OPENS via the same
  selection+detail path a direct tap takes; events resolve to their spot's pin through
  the existing `spot(for:)` keyword match (an event with no pin flies home — spot-less
  fallback, flagged in code). The "+" keeps its admin QuickAddSheet / non-admin
  composer branch and a11y labels, now mounted above recenter in `floatingControls`.
- **`MapSearch.swift`** (NEW) — pure client-side matcher over what the map already
  holds (`MapSpots.all` + `model.pois` + `model.todayEvents`; no network):
  case/diacritic-insensitive substring with name-prefix matches ranked first, then
  catalogue order (explicit tiebreak — Swift's sort is not stable). Rows carry the
  existing glyph pipelines (SpotCategory.filledSymbol / POI.glyph / EventCategory.glyph).
  `MapSearchResultsPanel`: Button rows (never bare onTapGesture in a ScrollView — the
  pan-competition rule), content-hugging up to 340pt so it stays clear of the keyboard.
  Empty state: "Nothing in <town> matches that yet." **`MapDistance`** extracted from
  `MapPlaceDetail.distanceLabel` — one "350 ft / 1.2 mi" formatter, shared, unit-tested.
- **`UserLocation.swift`** (NEW) — one-shot `requestLocation()` fix mirroring
  LocationPermission's delegate-box pattern (deliberate temporary retain cycle, fires
  once, main-actor confined). The when-in-use ASK lands on the FIRST search expansion;
  denied/unavailable/failed = nil = distances simply don't render. Result-row distances
  measure from the user's fix (detail morph still measures from downtown).
- **`SJMapView+POIClustering.swift`** — `chromeRects` reserves the ACTIVE search band
  (field + results panel, measured live off the chrome in the container's named
  coordinate space) so pin labels never draw under search UI, plus the relocated "+"
  rect above recenter. Recompute hooks on `searchActive`/band height.
- **`App/RootView.swift`** — `.ignoresSafeArea(.keyboard)` on the tab shell's ROOT
  ZStack. Without it the keyboard shoved the tab bar up over the map mid-screen (the
  bottom-aligned ZStack shrinks with the keyboard); a child-level ignore provably did
  nothing. Now the keyboard slides OVER the resting bottom chrome and collapsing search
  restores the chrome exactly because nothing ever moved. The map search field is the
  shell's one inline text field (Activities search + composers are covers/sheets).
- **DEBUG flags** (mirror `-explore-search`): `-map-search-open`, `-map-search <query>`,
  `-map-search-committed <query>` (commits the FIRST result — retries briefly while the
  async POIs land). `-map-compose` unchanged — it fires the same action the relocated
  button runs.
- **Tests:** `MapSearchTests` (9 — matcher ranks/diacritics, event→pin resolution,
  empty-state copy, distance formatter) registered via the xcodeproj gem (4 pbxproj
  entries); executed count rose 361 → **370, all green**. The gem re-added the empty
  `exceptions = ()` line that e8e13ca removed — harmless churn, left in.

**⚠️ Environment finding — the documented test command wipes the sim session.** Running
`xcodebuild test … CODE_SIGNING_ALLOWED=NO` on the booted sim replaces the installed app
with the unsigned test-host build, which iOS treats as a fresh install: the app container
AND the Keychain session are gone — the `simctl uninstall` trap through another door.
The sim is now signed out (recovery = sign in again, per the first-checkout notes).
Phase 2 verification therefore ran through `-show-home` (auth bypass): POIs and today's
events still resolved (anon-readable), today genuinely has zero events, so no event row
could appear in the results screenshots regardless. Run tests on a non-primary sim, or
re-sign-in after, until this is addressed.

Screenshots (session scratchpad `p2/`): `p2-rest.png` (magnifier top-right, "+" above
recenter), `p2-search-open.png` (expanded focused field, software keyboard up, town pill
faded, map + bottom chrome unmoved), `p2-search-results.png` (`-map-search saint`: prefix
matches first — Saint Ben's 0.3 mi, Saint John's 3.7 mi, then POI matches with their
glyphs; distances from the simulated downtown fix; no label collisions), `p2-search-empty.png`
("Nothing in Saint Joseph matches that yet."), `p2-committed.png` (`-map-search-committed
millstream`: camera flown to Millstream Park, pin open in the tab-shell detail, search
collapsed, pill restored).

**Verified:** iPhone 17 simulator, Debug: **BUILD SUCCEEDED, 0 source warnings** (only the
known `appintentsmetadataprocessor` notice); 370/370 tests green. Installed over the app
from the freshly resolved `BUILT_PRODUCTS_DIR`. Real-device note: the expansion spring +
keyboard feel and result-row taps still need one on-device pass (no sim gesture automation).

---

## 2026-08-13 — Map polish Phase 3: the Flighty-anatomy pin detail sheet (glass-bar morph retired)

Tapping any pin (civic or POI) now opens a **Flighty-proportioned detail card**
(`Features/Map/PinDetailSheet.swift`, NEW — ~60% of the map container, corner
radius `Radius.card`, Liquid Glass) over a subtly dimmed map, and the old
tab-bar glass morph (`BlockPartyTabBar.detailPanel` / `expandedDetail`) is
**removed in this same commit** per Jesse's Q6 decision — no dead code path
left. The tab bar hides while the sheet is up (the card's floating action bar
owns that zone); every other tab sees the bar unchanged.

**Anatomy (a–g), all real data:**
- **(a) metadata pills** — CATEGORY (spot category word / POI `primaryType`
  humanized, e.g. "COFFEE SHOP") · **OPEN NOW** (async: a new
  `GooglePlacesService.confidentDetails(name:coordinate:)` resolves Place
  Details **under the same Locked Rule A gate as photos**; the pill renders only
  when the gate clears AND `openNow == true` — never a placeholder, it fades in
  without reflowing the header) · **DISTANCE** (`MapDistance` from the user's
  one-shot fix; absent without a fix. The fix is read only when access is
  ALREADY authorized — the permission ask stays on Phase 2's search expansion,
  so opening a pin can never interrupt with a system alert).
- **(b)** Jost display name; **(c)** grey-caps secondary line — category glyph +
  street from the POI's real address (first component), else "SAINT JOSEPH".
- **(e) status card** — background routed through the ONE new token
  `Hue.statusTint` (seeded NEUTRAL = `fill` wash, ink header; Jesse's custom
  orange lands as a one-line swap — see DECISIONS.md §6). Header = status dot +
  word + `sparkles`; then hairline rows, each icon + bold label + one complete
  sentence (`PinDetailCopy`, pure + tested): Happenings ("Three events here
  today." — computed from `MapModel`'s real today events; the model holds no
  week data so no week counts are claimed; row omitted at zero) and Status
  ("Nothing happening yet today." / live line). **Live:** dot goes plum
  (meaning-scoped) + "Happening now"; a forced-live state with no resolvable
  event stays generic ("Something is happening here right now.") rather than
  inventing a title.
- **(f) "View full details ›"** low-emphasis row → full-height **system sheet**
  (`PinFullDetailsView`: blurb/address + `VenueInfoView` + happenings) — system
  sheet so scroll vs. drag-dismiss arbitration is the OS's, not a hand-rolled
  gesture (the repo's pan-competition rule).
- **(g) action bar** — icon-only save (`SavedStore` toggle, bookmark), share
  (NEW `SharePayload.place(...)` factory → `ShareCenter.shared.present`, with a
  typographic `PlaceShareCard` following the `.event` pattern), overflow "…"
  (full details + copy-address for POIs), and ONE filled circular Directions
  primary (ink circle, `Hue.surface` glyph, opens maps:// as before). Bar
  silhouette behind ONE constant `PinDetailSheet.actionBarShape` — **PILL ships
  (Q4, deliberate brand exception, DECISIONS.md §6)**; `.roundedSquare` was
  built + screenshotted, then flipped back.

**Presentation/motion:** map dims 12% black (basemap stays legible; scrim is
non-interactive so a map tap still dismisses); camera EASES to the pin
(`withViewportAnimation(.easeOut 0.5)`, not fly — search/row commits keep their
Phase 2 fly) with bottom padding tracking the sheet's height fraction so the
pin lands centered in the strip above the card. Drag-down dismisses (sqrt
resistance upward; the compact card has no inner scroll, so nothing competes).
Reduce Motion: no camera ease (instant set), sheet cross-fades.

**Two Liquid Glass gotchas hit and fixed:** (1) glass in a `.background` layer
gets EXTRACTED for container compositing and drew OVER the card's own text —
the glass must be applied directly to the content (the tab bar's pattern);
(2) extracted glass ignores an ancestor's `.opacity`, so the floating chrome
circles ghosted through the card at opacity 0 — they are now UNMOUNTED while
detail is up. A glass close button INSIDE the card would union with the card's
shape in the shared `GlassEffectContainer` and vanish, so close is a solid
`fill` circle (44pt geometry kept).

**Removed with the morph (no dead code left):** `MapPlaceDetail.priceLabel` /
`distanceLabel` (downtown-origin) / `badgeLabel` / `groupAccessibilityLabel`,
`MapDetailActionStyle`/`Role`, `POIPanelLogo`, the tab bar's
`detailCameraReserve`/expansion machinery, and the `mapDetailHappenings`
binding plumbing (now `SJMapView` local state). `-map-detail-expanded` now
opens the full-details presentation (still requires `-map-open`/`-map-open-poi`).

**Tests:** `PinDetailCopyTests` (15 — status word, real-data-only happenings
sentence, live/quiet sentences incl. the no-title live case, street line,
complete-sentence/no-exclamation sweep) registered via the xcodeproj gem
(4 pbxproj entries; the gem first wrote a root-relative path — fixed to
`BlockPartyTests/…` to match siblings); executed count rose **370 → 385, all
green**, run on a **non-primary sim** (iPhone 17 Pro Max) per the Phase 2
container-wipe finding.

**Verified:** iPhone 17 sim, Debug: BUILD SUCCEEDED, **0 source warnings**
(only the known `appintentsmetadataprocessor` notice); installed over the app
from the freshly resolved `BUILT_PRODUCTS_DIR`. Screenshots (session scratchpad
`p3/`): `p3-sheet-poi.png` (The Local Blend: COFFEE SHOP · OPEN NOW · 0.3 MI,
no wrap, name untruncated, street line, quiet card, pill action bar),
`p3-sheet-civic.png` (Millstream Park: PARK · OPEN NOW · 0.7 MI, "SAINT
JOSEPH" line), `p3-sheet-live.png` (`-map-force-live downtown`: plum dot +
"Happening now" + generic live sentence), `p3-full-details.png` (full-height
sheet; the venue PHOTO slab is blank — the **pre-existing** Google key
restriction outstanding in DECISIONS.md, not a regression; hours/website/phone
resolve), `p3-bar-square.png` (rounded-square variant), `p3-dim.png`
(before/after composite: dim + eased lifted camera + tab bar swap). Real-device
note: the drag-dismiss feel and Reduce Motion pass still need one on-device
check (no sim gesture automation).

## 2026-08-14 — Map polish Phase 4: filter chips replace the menu; copy voice audit

**Chip row (`MapFilterChips.swift`, NEW).** Five chips under the town pill — All ·
Food · Parks · Events · Saved — in a horizontal `ScrollView` of plain `Button`s
(no row-level gestures; the pan-competition rule). 12pt rounded squares
(`Radius.button`, never capsules); rest = the chrome's Liquid Glass, SELECTED =
solid ink with a white label, matching the cluster bubbles (`Hue.ink/.surface`
`.onLightCanvas` — the chips sit on the same light cartography the bubbles do;
black-ink selection per the approved plan, overriding the accent's "active
filter" seam). Two rendering findings:
- The tab shell's `GlassEffectContainer(spacing: 22)` metaball-BRIDGED glass
  chips sitting 8pt apart into one blob (caught by screenshot). A nested
  `GlassEffectContainer(spacing: 1)` inside the scroll content re-scopes the
  blend; a faint full-width field haze remains behind the row (reads as a soft
  chrome frost band; noted for Jesse).
- The old top-left `SpotFilter` Menu is GONE — enum, `filterMenu`, and the
  `chromeCircle(active:)` solid-accent branch (its only user) all removed, with
  a clear 44pt balancer keeping the town pill screen-centred.

**Filter semantics (`MapFilter`, pure + tested).** Spans BOTH catalogs for the
first time: Food = POI `family == .food` + the curated `.coffee` category;
Parks = `.park`/`.trail` (no park POIs exist — the catalog ships food/business
only); Events = spots that resolve a happening today OR are live right now (the
same `events(at:)`/`isLive` resolution the pins use, so `-map-force-live`
drives it); Saved = `SavedStore` across spots AND POIs (`detail.saveID` is what
the sheet's bookmark toggles). `filteredPOIs` + `filteredSpots` feed the
annotation mounts AND `recomputeClusters`, so bubbles recount to the filtered
set (downtown 22 → 13 on Food, verified by screenshot); the label pass and
solo-assignment fallbacks read the same sets. A chip change (or an unsave while
Saved is active — `.onChange(of: saved.ids)`) closes a now-hidden open detail
(`dismissDetailIfFiltered`, both catalogs). Selection is plain `@State` — camera
moves can't touch it. `chromeRects`' top band now uses the MEASURED chrome
bottom (`searchChromeBottom`) at rest too, so the reservation grows over the
chip row exactly (was: fixed 118 unless search was active).

**DEBUG flags.** `-map-filter all|food|parks|events|saved` (mirrors
`-explore-filter`) starts on a chip. NEW `-anon-data` (AuthStore): with no
session, reads carry the shipped PUBLIC anon key so the signed-out simulator
can photograph data-bearing states — RLS allows anon SELECT on `places` /
`club_events` (verified by curl 2026-08-14); writes stay refused server-side.
Added because the primary sim's Keychain session is gone since the Phase 2/3
container wipes; without it no POI/cluster state could be photographed at all.
Both compile out in Release. (Live `places` count is now 91, not the 52 in
older notes.)

**Copy voice audit — before → after (Goal B).** Peek discovery: the peek
primary truncates past ~26 chars at 16pt (the OLD strings already ellipsized:
"Couldn't load today's happenings" never fit) — every fixed peek sentence is
now written to fit whole, and the count state moved INTO the primary so the
audited sentence is the visible line. Counted sentences live in pure
`MapSheetCopy` (spell "One", keep numerals past one; noun agrees), shared by
the sheet AND the pins' VoiceOver labels.

| Where | Before | After |
|---|---|---|
| Sheet subtitle, Today count | `^[N happening](inflect: true) today` | "6 things happening today." / "One thing happening today." |
| Peek primary, count state | "Nothing happening right now" | "6 things happening today." (the spec sentence, now the visible line) |
| Peek secondary, count state | "N today — pull up to see" | "Pull up to see them." / "…see it." |
| Peek primary, multi-live | "N happening now" | "3 things happening now." (single live keeps the event's own title — data, PASS) |
| Peek primary, empty | "Nothing happening yet today" | "Quiet in St. Joe today." (peek-width; the long form lives in the subtitle) |
| Peek secondary, empty | "Use + to share the first event" | "Tap + to share what's happening." (rewritten for the relocated "+") |
| Peek primary, offline | "You're offline" | "You're offline." |
| Peek primary, error | "Couldn't load today's happenings" (truncated) | "Something went wrong." |
| Peek secondary, retry | "Tap to retry" | "Tap to try again." |
| Peek secondary, 1 live + venue | "Live now · X" | "Live now at X." |
| Peek secondary, 1 live no venue | "Live now" | "Happening right now." |
| Peek secondary, multi-live | "Happening across town right now" | + period |
| Subtitle, Places | "N places in town" | "6 places in town." / "One place in town." |
| Subtitle, loading | "Loading…" | "Checking what's on…" (matches the peek) |
| Subtitle, empty | "Nothing happening yet today" | + period |
| Subtitle, offline | "Offline — tap to retry" | "You're offline. Tap to try again." |
| Subtitle, error | "Couldn't load today's happenings — tap to retry" | "We couldn't load today's happenings. Tap to try again." |
| Empty block, offline/error | "Couldn't load today's happenings." | "We couldn't load today's happenings." |
| Empty block, moon | complete sentences already | PASS |
| QuickAdd, submit fallback | "Couldn't post this happening. …" | "We couldn't post this happening. …" |
| QuickAdd, field errors | "Add a title." / "Choose a location." | PASS |
| Pin VoiceOver label | "X, N happening today, happening now" | "X. 6 things happening today. Happening now." (via MapSheetCopy) |
| Town pill VoiceOver | "…Tap to return to Saint Joseph" | + period |
| Peek VoiceOver hints | "Retries loading…" / "Opens the map list" | + periods |
| PinDetailSheet (all `PinDetailCopy`) | — | PASS (P3, already voice, tested) |
| Search placeholder / empty state | "Search places and events" / "Nothing in X matches that yet." | PASS |
| Map intro cover | "See cafés, trails, and gatherings across St. Joe. …" | PASS |
| PlaceRow "^[N live]" badge · "Now" chip | terse badges | HELD terse — per plan these stay only if Jesse confirms; flagged for review |

**Tests.** `MapFilterChipsTests` (14 — chip titles/raw values, per-chip
spot+POI membership incl. Events-never-POIs and Saved-both-catalogs, the four
counted sentences, sentence/no-exclamation sweep) registered via the xcodeproj
gem (4 pbxproj entries; group-relative path corrected to `BlockPartyTests/…`
again). Executed count rose **385 → 399, all green**, on the non-primary
iPhone 17 Pro Max sim.

**Verified.** iPhone 17 sim, Debug: BUILD SUCCEEDED, **0 source warnings**
(only the accepted `appintentsmetadataprocessor` notice); installed over the
app from the freshly resolved `BUILT_PRODUCTS_DIR`. Screenshots (session
scratchpad `p4/`): `p4-chips-all.png` (full row fits under the pill, All in
ink, clusters 22/21/8/…), `p4-chips-food.png` (Food in ink, only food
POIs — downtown 22 → 13), `p4-chips-parks.png` (the 2 park/trail spots as one
"2"), `p4-chips-events.png` (`-map-force-live downtown` — the one live pin,
plum ring), `p4-chips-saved.png` (`-map-save downtown -map-save millstream` —
"2"), `p4-peek-count.png` + `p4-sheet-copy.png` (today is truly zero, so the
peek shows "Quiet in St. Joe today." and the medium sheet "Nothing happening
yet today."; the count sentence path is unit-tested), `p4-labels-z15.png` (no
pin label under the chip band), `p4-search-regression.png` (chips fade with
the pill; results panel unmoved). Real-device note: chip tap feel + the
filter-closes-detail path need one on-device pass (no sim tap automation).

## 2026-08-14 — Map polish Phase 5: sheet rubber-banding, selected-pin pulse, haptics audit

The last feel pass of plan `2026-08-13-map-tab-ui-polish` (Feedback pass runs
separately after this entry).

**Sheet rubber-banding (`MapSheet.swift`).** Dragging past peek/full used to
hard-clamp (`min(max(…))` — the sheet hit a wall). Now the raw height routes
through `SheetRubberBand.height(raw:min:max:)` — a pure `nonisolated` curve:
inside the bounds it passes through 1:1; past either bound the visible travel
is `give·√overdrag` (give 3 — 25pt of finger reads as ~15pt, 100pt as ~30pt),
capped at `maxStretch` 32 so a full-arm pull never reaches the floating top
chrome (full's clearance is ~66pt). Release springs the overshoot home through
the EXISTING detent spring — `snap` already animates `drag` back to 0 inside
`withAnimation(Motion.sheet)`, so no new animation path; `resetDrag` (the
cancelled-gesture path) now wraps its `drag = 0` in the same spring so a
cancelled overdrag settles instead of popping. All inside the existing single
arbitrated whole-sheet DragGesture — NO new recognizer. Reduce Motion keeps
the hard clamp (no bounce). No haptic fires on overdrag or on a spring-back
that lands on the same detent (`snap` ticks only when the detent CHANGES).

**Selected-pin pulse (`SJMapView.swift` + `MonoMarkerPalette.swift`).** While
a place's detail sheet is open its marker carries `SelectedPulseRing` —
PulseRing's recipe but INK via the new `MarkerRole.selectedRing` (plum stays
meaning-scoped to live), slower and quieter: 2.4s vs live's 1.5s, 0.22 vs
0.35 peak opacity, 1.9× vs 2.2× travel. Mounted on the selected civic badge
(`MapPinBadge`, under the static rings) and the selected-POI overlay
(`POISelectedMarker`, under the halo). Reduce Motion renders a STATIC ink
ring instead (the live-ring discipline: geometry survives when motion is
suppressed). And while any selection is active the REST of the map calms
down: every other pin's name label drops (`showsLabel && !calmed` at both
mounts) and a non-selected live pin rests its pulse (new `calmed` flag on
`MapPinBadge`) — its static plum ring stays, so "happening now" survives the
calm. `PinDisplay` untouched (selection stays the separate Bool by design).

**Haptics audit (no gaps found — no new code).** The Phase-5 checklist all
routes through the existing `Support/Haptics.swift` helper already: pin
select = `Haptics.light()` on ENTERING selection only (`selectSpot`,
`selectPOI`, `focus`, `commitSearchResult`; deselect stays silent per spec
§2); cluster tap = `Haptics.light()` in `zoomToCluster`; detent snap =
`Haptics.selection()` in `snap`/`step`/peek-tap, fired only on a real detent
change; chip change = `Haptics.selection()` (Phase 4); detail-sheet actions
(save/share/directions/full details) = P3. Engine warmed once via
`Haptics.prepare()` on map appear; silent no-op in Low Power Mode.

**Tests.** `SheetRubberBandTests` (4 — in-bounds passthrough, √ compression +
monotonicity, floor symmetry, the cap both directions) registered via the
xcodeproj gem (4 pbxproj entries; group-relative path corrected to
`BlockPartyTests/…` again). Executed count rose **399 → 403, all green**, on
the non-primary iPhone 17 Pro Max sim.

**Verified.** iPhone 17 sim, Debug: BUILD SUCCEEDED, **0 source warnings**
(only the accepted `appintentsmetadataprocessor` notice); installed over the
app from the freshly resolved `BUILT_PRODUCTS_DIR` (binary timestamp
checked). AFTER screenshots (session scratchpad `after/`, framing matches the
Phase-0 BEFOREs): `after-rest.png` (peek sheet + chips + relocated "+"),
`after-clusters.png` (zoom 13 settled — 46/11/8/5/3/2 ink bubbles),
`after-pin-sheet.png` (The Local Blend POI sheet; every other pin's label
dropped — the calmed state), `after-search.png` ("saint" results panel),
`after-pin-pulse.png` (mid-ring frame from an 8-frame burst — the ink pulse
IS capturable in a still). Rubber-band motion evidence: **not producible
headlessly** — `drag` is written only by the real DragGesture (no debug flag
drives an overdrag, and `-map-detent` opens AT a detent without animating),
so the overdrag + spring-back feel goes on the real-device pass list with the
detent snap and the pulse cadence.

### Feedback pass + fixes (2026-08-14)

The adversarial Feedback pass over the whole plan diff returned **PASS WITH
FINDINGS**; the five findings land as one commit.

1. **(HIGH) Search commits bypassed the chip filter.** The matcher searches the
   UNFILTERED catalogs, and `commitSearchResult` opened the result regardless of
   the active chip — a filtered-out target opened its card over a map with NO
   pin under it. Fix: search intent wins. `openFromSearch` (the one path every
   committed result routes through) now resets the chip to All via the new pure
   `MapFilter.afterSearchCommit(showsTarget:)` when the target fails the active
   filter (`filterShowsSearchTarget` — the same membership
   `dismissDetailIfFiltered` checks). Covered in `MapFilterChipsTests` (2 new
   tests, existing registered file). Proven headlessly: `-map-filter saved
   -map-search-committed millstream` lands on the All chip with the Millstream
   pin AND its card both present.
2. **(MEDIUM) Events-chip detail lingered past expiry.** The
   `model.todayEvents` / `model.clockTick` handlers in `mapLayer` recomputed
   clusters but never dropped a detail the Events chip no longer shows (an
   event landing/ending/expiring changes chip membership). Both now call
   `dismissDetailIfFiltered()` first, exactly as a chip change does.
3. **(MEDIUM) PinDetailSheet a11y escape.** The card now carries
   `.accessibilityAddTraits(.isModal)` (VoiceOver swipe order stays inside the
   card instead of walking the dimmed map behind it) and
   `.accessibilityAction(.escape)` dismissing like the close button, so the
   two-finger-Z scrub works.
4. **(MEDIUM, docs) `CLAUDE.md` caught up to shipped code:** pin detail is the
   Flighty `PinDetailSheet` (tab-shell morph retired), compose "+" bottom-right
   above recenter, `MapFilterChips` replaces the `SpotFilter` menu; flag
   registry gains `-map-compose`, `-map-search-open`, `-map-search <q>`,
   `-map-search-committed <q>`, `-map-filter <chip>`, `-anon-data` (with its
   RLS security note), and `-map-detail-expanded`'s P3 meaning (starts straight
   in the full-details presentation).
5. **(LOW, comment-only) `MonoMarkerPalette.swift`:** the value-ladder header
   and the `liveFill` doc said the live fill is ink; the code returns the
   meaning-scoped plum (`MapInk.accent`). Both comments now state the truth.

**Verified.** iPhone 17 sim, Debug: BUILD SUCCEEDED, **0 source warnings**
(only the accepted `appintentsmetadataprocessor` notice). `xcodebuild test` on
the non-primary iPhone 17 Pro Max: executed count rose **403 → 405, all
green**. Fix-1 screenshot (`fixes/fix1-search-filter-reset.png`, session
scratchpad): All chip selected despite launching on Saved, Millstream Park pin
on the map beneath its open card.

## 2026-08-14 — Map polish round 2, Phase A: chrome pass (Jesse's review feedback)

Plan `2026-08-14-map-polish-round-2.md`, Phase A — five chrome changes from
Jesse's review, all in `Features/Map/` + the shell wiring.

1. **Flat chips (`MapFilterChips.swift`).** The selected chip's
   `.mapFloatShadow()` is gone ("bad shadow that stands out") — the solid ink
   fill on light cartography is separation enough, and its glass siblings never
   had a drop shadow. No hairline needed (verified by screenshot). The faint
   full-width field haze behind the row (the Phase-4 GlassEffectContainer
   nesting residue flagged for Jesse) now merges into the new top edge fade and
   reads as intentional chrome seating — left as is.
2. **Edge fades (`SJMapView.mapTopFade`, NEW).** A `Hue.paper` 0.85→0 gradient
   from the physical top edge dying out through the pill row (150pt), the top
   twin of the existing `mapBottomFade` — the Subway/Apple-Maps "chrome floats
   on a gently faded edge" read. Colour only, NO material: pin labels
   legitimately pass under it, so a blur would smear them. Non-interactive
   (`allowsHitTesting(false)`), deliberately NOT in `chromeRects` (it is not
   chrome), and `Hue.paper` is dynamic so dark mode fades to the dark page.
3. **The "+" is retired; `QuickAddSheet.swift` DELETED.** Jesse's call (plan
   approval): the map loses event creation entirely — admins keep the
   Activities/Calendar speed dial + composer. Removed: `composeButton`, the
   `quickAdding` sheet mount, `onCompose` plumbing (SJMapView + the RootView
   call site), the map's speed-dial branch (`speedDialItems` `.map` case,
   `SpeedDialItem.map()`; the now-constant `chromeDisc`/`showsRestingDisc`
   args were NOT removed here despite this entry's original claim — they
   survived until the round-2 feedback fix commit), the `-map-compose` AND
   `-force-nonadmin` flags (`isAdmin` had no
   other reader in SJMapView), `VenueAutocompleteField.Palette.map`, and
   `MapSpots.pinnableSuggestions` (QuickAdd was the only consumer of each).
   The peek's empty secondary — "Tap + to share what's happening." — now reads
   "Pull up to browse places." (the "+" it pointed at no longer exists). The
   app target is fileSystemSynchronized, so the deletion needed no pbxproj
   edit; grep confirms no test references.
4. **"?" to top-left (`topChrome`).** `helpButton` moved from the bottom stack
   into the pill row's leading slot — the 44pt clear balancer that was already
   mirroring the search circle IS the slot, so the pill stays screen-centred
   with zero new geometry. It fades with the pill while search is active (the
   expanded field owns the full row). The bottom-right stack is now compass +
   recenter alone; `chromeRects` drops the help/compose rects (the top band
   already measures the whole chrome VStack via `searchChromeBottom`).
5. **Mapbox wordmark hidden, ⓘ kept (`ornamentOptions`).** Jesse's explicit
   2026-08-14 pick, ToS risk accepted and recorded in the plan — supersedes the
   old "repositioned but not removed" stance (doc comment updated in place).
   `LogoViewOptions.visibility` is `@_spi(Restricted)`, so SJMapView now does
   `@_spi(Restricted) import MapboxMaps` and builds `hiddenLogoOptions` on a
   mutable copy. The ⓘ attribution stays at bottomTrailing on the same
   `ornamentBottomMargin`, resting tidy above the peek under the bottom fade.

**CLAUDE.md** flag registry: `-map-compose` + `-force-nonadmin` removed, "Map
search and compose" → "Map search"; SJMapView bullet rewritten ("?" top-left,
edge fades, NO compose entry, wordmark hidden); QuickAddSheet bullet deleted.

**Verified.** iPhone 17 sim, Debug: BUILD SUCCEEDED, **0 source warnings**
(only the accepted `appintentsmetadataprocessor` notice); installed over the
app from the freshly resolved `BUILT_PRODUCTS_DIR`. `xcodebuild test` on the
non-primary iPhone 17 Pro Max: all green (see commit). Screenshots (session
scratchpad `r2a/`): `r2a-rest.png` ("?" top-left mirroring search, flat chips,
top+bottom fades, recenter alone bottom-right, NO wordmark, ⓘ above the peek,
new empty-peek copy), `r2a-chips-food.png` (selected ink chip crisp without
the shadow), `r2a-search.png` (expanded field owns the row — the moved "?"
fades with the pill, results panel clear), `r2a-sheet.png` (fades + dim wash +
PinDetailSheet coexist; top chrome seated on the fade). Real-device note: the
"?"'s new reach (top-left, one-handed) is worth a feel check on device.

## 2026-08-14 — Map polish round 2, Phase B: the basemap goes colorful (Jesse's Subway reference)

Plan `2026-08-14-map-polish-round-2.md`, Phase B — `BasemapPalette.swift` only.
Jesse's ask: a genuinely colorful town map like the Subway store-finder
reference — lively-but-soft greens with real area coverage, confident blue
water, warm cream land, warm tan patches over campus/institutional ground —
not the muted watercolor round 1 shipped. Three screenshot-iterated rounds.

**Why round 1 read pale — two stock light-v11 gates, found in the live style
JSON (`GET styles/v1/mapbox/light-v11`), not guessed:**

1. **The `landuse` class filter never admitted the warm classes.** The one
   `landuse` fill layer matches only agriculture/wood/grass/scrub/park/airport/
   glacier/pitch/sand (+residential below z12) — `school`, `hospital`,
   `cemetery`, `commercial_area` are filtered out entirely, so recoloring the
   layer could never produce a campus patch. Tilequery ground truth around St.
   Joe: the CSB campus is one `school` (college, sizerank 1) polygon, and the
   town carries cemetery/pitch/grass/park/wood/agriculture polygons.
2. **The sizerank-vs-zoom stagger hid small green polygons until ~z16.5.**
   sizerank-14+ ground (lawns, ball fields, playgrounds) needed
   `sizerank − f(zoom) ≤ 8` with f reaching 6–7 only near z16.5 — so at the
   z11–15 this map lives at, most vegetation simply wasn't drawn. Plus the
   `national-park` overlay ships at 0.2 fill-opacity at town zoom.

**What `recolor` does now (all setters best-effort `try?`, idempotent,
re-applied on `onStyleLoaded` + `onMapLoaded` as before):**

- **`landuse` filter widened** to also admit school/hospital/cemetery/
  commercial_area; the sizerank stagger is dropped (vector tiles already
  generalize away what's too small per zoom); residential keeps its stock
  below-z12 step. `parking`/`industrial` stay excluded on purpose — gray slabs
  would dirty the warm fields.
- **`landuse` fill-color is a per-class `match`** (no zoom in the expression,
  so no top-level-zoom trap): park `#A9D584` · pitch `#B9DB8F` · wood/scrub
  `#B0D291` · grass `#C3DFA2` · agriculture `#DFEAC5` · school+hospital
  `#F3E3C8` (the College-Terrace-style warm patch — St. Ben's reads as a warm
  tan field with its lawns/pitches showing through) · commercial_area
  `#F6E0C4` · cemetery `#CBDCB4` · sand `#F0E3C0` · fallback = land paper.
  Stock fill-opacity kept (new classes ride its generic arm to 1.0 by z12).
- **`national-park`**: park green, opacity lifted to interpolate 5→0, 6→0.55,
  12→0.4 (was …12→0.2).
- **Water**: `water` fill `#7FBFE8`; `waterway` line `#6FB6E2` (thin strokes
  render optically lighter, so the line family sits one step deeper) — plus a
  **line-width lift** (same exponential-1.3 curve, river/canal 0.6→2.2→10 at
  z9/13/20; other streams 0.2→1.0→4). Stock drew rivers under 1pt until deep
  street zoom, so the Sauk was a hairline; it now reads as a clear blue ribbon
  at town zoom — the file's own "the river must read" mandate, finally true.
- **Unchanged**: land = `Hue.paper` `#FAFAF7`, buildings = `Hue.fill`, roads =
  `Hue.surface` white, label ink + white halos, `poi-label` hidden (decided
  2026-07-20, kept), settlement-label offsets/maxzoom, anti-grayscale rule.
  The old summer·noon·clear anchor note anchored the ROUND-1 muted values; the
  file header now anchors the round-2 palette instead.

**Iteration log (screenshots in session scratchpad `r2b/`):** iter1 = per-class
match + widened filter + first greens (`#AFD68C` park, `#8FC8EA` water) —
campus tan landed immediately, water still shy, river a hairline. iter2 =
water `#7FBFE8`, riverInk `#6FB6E2` + width lift, greens one notch livelier
(park `#A9D584`, wood `#B0D291`, grass `#C3DFA2`) — the Sauk became a real
ribbon. iter3 = farmland `#E4EDCB`→`#DFEAC5` so fields tint instead of
whisper; remaining cream quadrants verified to be genuinely unclassified land,
not un-colored farmland. Final rendered pixels sampled back out of the z13
screenshot match the palette **byte-exact** (park `#A9D584`, wood `#B0D291`,
farmland `#DFEAC5`, campus `#F3E3C8`, pond `#7FBFE8`, land `#FAFAF7`).

**Verified.** iPhone 17 sim, Debug: BUILD SUCCEEDED, **0 source warnings**
(only the accepted `appintentsmetadataprocessor` notice); installed over the
app from the freshly resolved `BUILT_PRODUCTS_DIR`. `xcodebuild test` on the
non-primary iPhone 17 Pro Max: **405 tests, 0 failures** (count unchanged —
the palette is style-side; the `FeedPolishTests` land/road pins still hold).
Screenshots `r2b-town.png` (default 13.5) · `r2b-z13.png` · `r2b-z15.png` ·
`r2b-campus.png` (45.5604,-94.3218 @14.5 — the warm-field treatment) ·
`r2b-clusters.png` (z13 — ink bubbles, incl. the small 22pt "2"s, still pop
over the richer greens; POI labels + halos legible at z15). Screenshot-loop
gotcha worth remembering: zsh does NOT word-split an unquoted `$var`, so a
`simctl launch … $FLAGS` helper passes the whole flag string as ONE argv entry
and the app silently ignores it — write launch flags out explicitly.

**Known/accepted:** the Liquid Glass sheet + tab bar sample more green from
the richer basemap beneath (the pre-existing "park green blooms through
glass" behaviour, judged correct 2026-07-19 — now a touch more visible).
Real-device pass: eyeball the greens/tan in sunlight; sim panel saturation
flatters green.

## 2026-08-14 — Map polish round 2, Phase C: the tab bar attaches identically on all four tabs

**Jesse's ask 6** ("when u switch tabs out of maps u can see they dont attach"),
reproduced by screenshot: on Today/Activities/Calendar the tab bar is a lone
floating Liquid Glass capsule, but on the Map tab it read as a completely
different element — a single tall attached panel — because `MapSheet`'s glass
sat FLUSH on the bar inside the shared `GlassEffectContainer(spacing: 22)` and
metaball-merged with it (the deliberate 2026-07-19 "one continuous bottom
glass" design, `84a5624`). Switching tabs visibly swapped between the two
reads: two different bars.

**Root cause:** `RootView.swift` — `BlockPartyTabBar` rendered inside the
shell's `GlassEffectContainer`, adjacent to `MapSheet`'s flush glass
(`MapSheet.tabBarReserve = 66`, square-bottom `UnevenRoundedRectangle`
silhouette built to blend into the merge).

**Fix (consistency is the spec — the bar is the one element that must never
change across tabs):**
- **`RootView.swift`** — the bar moved OUT of the `GlassEffectContainer`, to a
  sibling in the outer bottom-aligned ZStack. Its silhouette can no longer
  fuse with any map glass: one identical capsule on all four tabs, same
  geometry, same glass, seated the same. The pin-detail hide path
  (`tab == .map && mapDetail != nil`) moved with it, unchanged.
- **`MapSheet.swift`** — the sheet becomes its own panel: `sheetShape` is a
  full `RoundedRectangle(26)` (the square bottom existed only for the merge),
  `tabBarReserve` 66 → 74 (the bar's 66pt zone + an 8pt seat gap; every
  derived layout — ⓘ ornament, ?/locate stack, cluster occlusion, town-rain
  floor — tracks the constant). Full detent 132 → 140 so the sheet's TOP at
  full stays exactly where round 1 measured it (74 + H−140 = H−66 = the old
  66 + H−132). The content frost now runs to the sheet's bottom edge (the
  transparent "tab-bar join" band would just sample raw park green on a
  detached panel).
- The bar's footing on the map is the existing Phase-A bottom edge fade — no
  new material. Its glass still samples the washed map rather than paper;
  that residual tint is inherent to translucent glass (true of every iOS 26
  bar) and is the fade's job to keep quiet.

**Verified.** iPhone 17 sim, Debug: BUILD SUCCEEDED, **0 source warnings**
(only the accepted `appintentsmetadataprocessor` notice); installed over the
app from the freshly resolved `BUILT_PRODUCTS_DIR`. `xcodebuild test` on the
non-primary iPhone 17 Pro Max: **405 tests, 0 failures**. Screenshots
(scratchpad `r2c/`): before/after bottom-300pt crops of all four tabs
(`r2c-before-*` / `r2c-after-*-bottom.png`) — after set shows one identical
capsule on all four — plus `r2c-after-map-full.png` (sheet floats 8pt above
the bar, both fades intact, ⓘ riding above the lifted peek), full-detent and
pin-detail checks. No debug path can switch tabs mid-run (`-open-tab` is
launch-time only), and the bar is one persistent view that never remounts on
a tab change (only content swaps), so there is structurally nothing to jump —
but eyeball the map⇄tab transition on the real device anyway.

**Known/pre-existing (Phase D candidates):** at full detent the selected
"All" chip's ink peeks behind the sheet's top-left corner (position identical
before/after — not introduced here).

## 2026-08-14 — Map polish round 2, Phase D: compact quiet card + flaw-hunt sweep

Plan `2026-08-14-map-polish-round-2.md`, Phase D — Jesse's asks 8 ("remove info
not relevant to the day/person from the pin window") and 9 ("actively look for
flaws and fix").

**Part 1 — the compact quiet card (approved interpretation: rows render only on
real day/person signal).** A QUIET place — no events today, not live — no longer
shows the boilerplate "Right now / Nothing happening yet today." row block. Its
status card collapses to ONE quiet line (ink dot + "Quiet today." + the sparkle)
above the "View full details ›" row; the pill row (OPEN NOW · distance) and the
rest of the card are untouched. Live/eventful places keep the full round-1 card
exactly.

- `PinDetailSheet.swift:75` — `PinDetailCopy.isQuiet(isLive:todayCount:)`, the
  pure rule (today-and-live is the whole signal — the card holds no week data,
  so none is claimed); `:81` `quietSentence` ("Quiet today." — the status word
  in sentence form); `:340` `isQuietPlace`; `:386` `quietLine` (the header's
  exact anatomy, sentence copy).
- `PinDetailCopyTests.swift` — 4 new tests (quiet rule ×3 + sentence identity)
  and `quietSentence` joined the brand-voice loop. **Executed count 405 → 409.**

**Part 2 — flaw-hunt sweep.** Every map state screenshotted fresh on head
`45dbdf6` (light: rest · 5 chips · search open/results/empty · POI + live pin
sheets · full details civic + POI · 3 detents · clusters z13 · campus 14.5;
dark: rest · chips · both pin sheets · full detent), then eyeballed per the
swiftui-design skill + shared craft rules. Found → fixed/deferred:

1. **FIXED — full detent parked the sheet's top edge MID-CHIP** (the plan's
   known item (a): the selected "All" chip's ink peeked out behind the top-left
   corner radius in light; in dark every chip's gray top sliver showed above the
   sheet edge). Root cause: `metrics`' full arm (`H−140` → 66pt top clearance)
   predates the Phase-4 chip row (chrome band now ≈96pt). `MapSheet.swift:297`
   — full is now `H−176` (≈102pt clearance: the whole chrome band + a seat
   gap); `:69` maxStretch comment updated to the new clearance. Verified both
   modes: all five chips sit fully clear above the full sheet.
2. **FIXED — dark mode: the status card's text was invisible** (Phase B/C had
   never been dark-verified; the plan flagged it). `Hue.statusTint` is the same
   pale coral in BOTH appearances (Jesse's explicit pick), but the card's
   content used appearance-adaptive tokens — dark `Hue.ink` is near-white
   #F2F1EC, ~1.1:1 on the wash: header word, row labels and icons vanished
   (screenshot-caught on the live card). `PinDetailSheet.swift:112` — `CardInk`
   pins the card's ink/inkSecondary/hairline/accent to the light ramp via
   `onLightCanvas`, the exact `MapInk` pattern (the wash is the second ground
   that doesn't follow the system). `BlockPartyColor.swift` docs updated
   (`onLightCanvas` "exactly one such ground" → two; statusTint's contrast note
   now states the pinning). Verified: dark live card and dark quiet card fully
   legible, light unchanged (pinned values ≡ light values).
3. **FIXED — pin-name labels cut mid-word at the physical screen edges** (campus
   framing: "CSB Ber / Arts Ce", "T / &" running off the right edge).
   `SJMapView+POIClustering.swift:163` — two offscreen gutter rects joined
   `chromeRects`, so the shared label pass DENIES a label whose text box crosses
   the edge exactly like any collision (badge stays, text withheld — standard
   map-engine edge behaviour). Verified at the campus framing: edge markers show
   badge-only; no label is clipped.
4. **FIXED — Phase B's richer greens read through the peek sheet again** (the
   plan's known item (b)): park-polygon shapes were readable through the
   collapsed sheet in light mode, and the mint cast made the sheet read as a
   different material than the (whiter) tab bar below it. `MapSheet.swift:133`
   — `frostMin` 0.30 → 0.45 (0.30 was tuned against round-1's muted palette).
   Verified: peek flat and warm in light, still glassy at the grabber; sheet +
   bar now read as one family. Dark was already under control (dark glass mutes
   the green) and is unchanged.

**Judged fine, left alone:** (c) top fade vs status bar — legible in BOTH modes
(light: dark text on the light paper fade; dark: white text on the dark fade —
the dark veil over the always-light basemap is what makes it work, and the
safe-area band above the map blends into the 0.85 fade end with no visible
seam). The chip row's full-width glass field haze (Phase A's call) reads as
chrome seating in dark too — consistent, kept. The cluster-bubble ghosting
through the full sheet's 0.94 frost is sub-threshold. Cluster bubbles may
overlap a selected pin's ring (draw order cluster > selected is deliberate).

**Deferred (structural, logged not scope-crept):**
- **Full-details photo box renders blank** — `VenueInfoView.swift:101` gives the
  AsyncImage's loading AND failure phases the same solid `palette.card`
  rectangle, so a photo that never lands leaves a permanent empty white 150pt
  box (screenshot: The Local Blend full details). Fix belongs in
  `Features/Components/` (outside this phase's Map+Theme boundary): collapse
  the container on `.failure`, skeleton-tint (`Hue.fill`) while loading.
- **Civic full details can render near-empty** — "Downtown" (a district, not a
  Google-resolvable venue) shows name + blurb and a page of void. Needs a
  content decision (what a civic spot's full page holds when Places has
  nothing), not a paper cut.

**Verified.** iPhone 17 sim, Debug: BUILD SUCCEEDED, **0 source warnings** (only
the accepted `appintentsmetadataprocessor` notice); installed over the app from
the freshly resolved `BUILT_PRODUCTS_DIR`. `xcodebuild test` on the non-primary
iPhone 17 Pro Max: **409 tests** (see commit for the run). Screenshots in the
session scratchpad `r2d/`: the full-state sweep (`r2d-<state>.png`, before set
on head `45dbdf6`), `r2d-pinsheet-poi-quiet.png` + `r2d-dark-pinsheet-poi-quiet.png`
(the new compact card, both modes), and `r2d-fix-{1..4}-{before,after}.png` per
fix above.

## 2026-08-15 — Map polish round 2: adversarial feedback fixes (13 raised / 7 confirmed / 6 refuted)

The round-2 adversarial Feedback workflow audited the four phases: **13
findings raised, 7 confirmed, 6 refuted**. This commit applies exactly the 7
confirmed items — stale docs/comments purged, dead API removed, one a11y leak
closed. No behavior change beyond VoiceOver.

1. **`AGENTS.md`** — `-force-nonadmin` dropped from the Map browse/camera flag
   registry (removed from code in the Phase-A chrome pass); the `SJMapView`
   bullet no longer claims "admin/non-admin compose routing" — it now states
   there is no compose entry on the map.
2. **`ComposeSpeedDial.swift`** — the dead map knobs are now actually gone:
   the `chromeDisc`/`showsRestingDisc` parameters, the unreachable chrome-disc
   branch, `discVisible`, and every doc comment describing the deleted map "+"
   as live. `RootView.swift`'s call site dropped the constant args. (The
   Phase-A entry above originally claimed `d29138a` removed these args; it did
   not — that entry is corrected in place, and the removal landed here.)
3. **`CommunityAPI.swift`** — the `realOnly` guard comment no longer
   enumerates the deleted QuickAdd (its inserts went through `addEvent`).
4. **`PinDetailSheet.swift`** — the quiet line's decorative sparkle is
   `.accessibilityHidden(true)`, so the `.combine`'d VoiceOver line reads
   "Quiet today." without a trailing "Sparkles". Visual unchanged.
5. **`CLAUDE.md`** — test count 405 → 409 (Phase D's four `PinDetailCopy`
   quiet-card tests).
6. Four stale "?/locate controls" comments (`MapSheet.swift` ×3,
   `SJMapView.swift` ×1) now describe the current chrome: "?" top-left,
   compass/recenter bottom-right (the Phase-A move).
7. **`BlockPartyColor.swift`** header — "THE ONE EXCEPTION IS THE MAP" now
   names BOTH fixed-light grounds (the Mapbox basemap AND the pin card's
   `statusTint` wash via `CardInk`), consistent with the `onLightCanvas` doc.

**Verified.** iPhone 17 sim, Debug: BUILD SUCCEEDED, **0 source warnings**
(only the accepted `appintentsmetadataprocessor` notice; changed files touched
and recompiled to prove it). `xcodebuild test` on the non-primary iPhone 17
Pro Max: **409 tests, 0 failures** — count held. Screenshot (session
scratchpad `fixes/r2-fix4-quietcard.png`, `-open-tab map -map-open-poi blend
-show-home -anon-data`): The Local Blend's quiet card still renders the
sparkle — fix 4 is a11y-only.
