# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

**Hygge** — a native **SwiftUI + Mapbox** iOS app for the real town of **St. Joseph, MN**: one calm place for everything happening in town (a daily timeline, a shared calendar anyone can add to, a live town map, a daily quest). This is a **native port of the Expo / React Native app** that lives in a **separate repo** at `~/Documents/my-business/apps/mobile`.

- **Xcode project:** `Hygge.xcodeproj` · **scheme:** `Hygge` · **bundle id:** `Jesse.Hygge` · **iOS deployment target: 26.5** · Swift 5.
- **Only SPM dependency:** [`mapbox-maps-ios`](https://github.com/mapbox/mapbox-maps-ios).
- **Shared backend:** the same Supabase project as the Expo app (`lxdgwhvqjqmqliobwjpi`). The two apps are backend-twins — schema, RLS, and query semantics match `@hygge/core` in the Expo repo. **Keep design tokens and query behavior in sync with that repo** (each Swift source that ports a JS file says so in its header).

### Two-repo rule
This is the **native iOS / map** codebase. The Expo/React-Native/web product is the other repo. Map, Mapbox, and native-iOS work happen **here**; RN/web work happens **there**. They look nearly identical on the simulator — this app's first tab is **"Today"**, the Expo app's is **"Home"**.

## Build, run, verify

There is **no unit-test suite** (no XCTest target). "Verified" means: **builds clean (0 warnings) + confirmed in the running simulator via screenshots** — the same discipline the `MAP_BUILD_LOG.md` records.

**Prefer XcodeBuildMCP** (`build_run_sim`, `build_sim`, `screenshot`) over raw shell for Apple tooling. Raw fallbacks:

```bash
# Build for the simulator
xcodebuild -project Hygge.xcodeproj -scheme Hygge -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17' build

# Launch on a booted sim (see debug flags below), then screenshot
xcrun simctl launch <udid> Jesse.Hygge -open-tab map
xcrun simctl io <udid> screenshot /tmp/map.png
```

**Installing the build you just made (raw tooling) — the DerivedData trap.** This repo has accumulated **several `Hygge-<hash>` DerivedData folders** (multiple worktree checkouts), so `find … -name Hygge.app | head` grabs a **stale** one and you screenshot a days-old binary (symptom: your change is missing, e.g. old theme colors). Resolve the *real* output dir and confirm its timestamp:

```bash
DIR=$(xcodebuild -project Hygge.xcodeproj -scheme Hygge -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17' -showBuildSettings \
  | awk -F' = ' '/ BUILT_PRODUCTS_DIR =/{print $2; exit}')
xcrun simctl install <udid> "$DIR/Hygge.app"   # install OVER the app — do NOT `uninstall`
```

`simctl uninstall` wipes the app container: the `hygge.onboarded` UserDefaults flag + local mirrors go with it, bouncing a signed-in user back to the onboarding wizard. If that happens, restore with `xcrun simctl spawn <udid> defaults write Jesse.Hygge hygge.onboarded -string 1` and relaunch.

**DEBUG-only launch arguments** (for headless screenshot verification, no UI driving needed):
- `-open-tab map|activities|calendar` — start on a given tab (`MainTabsView.initialTab()` in `App/RootView.swift`).
- `-force-nonadmin` — force the non-admin branch so admin-gated UI (the map "+") can be verified without a second account (`SJMapView.isAdmin`).
- `-explore-filter events|clubs|trails|parks` — start the Activities ("Explore") tab on a given category chip so each card state can be screenshotted headlessly (`ActivitiesView.initialFilter()`).
- `-explore-timeframe today|week|month|upcoming` — start the Explore tab with a given event time-frame filter applied (`ActivitiesView.initialTimeFrame()`).
- `-map-sheet places` — open the map's bottom sheet on the Places list (`MapSheet.initialMode()`).
- `-map-detent peek|medium|full` — open the map's bottom sheet at a given detent so each rest state (and the peek-line ⇄ list cross-fade) can be screenshotted headlessly (`MapSheet.initialDetent()`).
- `-map-open <spotid>` — preselect a map spot so its detail card renders for a screenshot (`SJMapView.debugSelectedSpot()`; ids are `downtown|saintbens|chapel|wobegon|millstream|saintjohns`).
- `-map-center <lat>,<lon>` — start the map camera elsewhere so the town pill's reverse-geocoding can be screenshotted over another city (`SJMapView.debugInitialCenter()`).
- `-map-zoom <z>` — start the map camera at a given zoom so the pin-hierarchy rest dots, the label zoom-threshold (T=14.5) cross-fade, and label collision can each be screenshotted headlessly (`SJMapView.debugInitialZoom()`; default 13.5).
- `-map-save <spotid>` — (repeatable) force a spot into the **Saved** pin state (white badge + ink `bookmark.fill` corner) without a real save, so the Saved marker renders for a screenshot (`SJMapView.debugSavedIds()`).
- `-map-force-live <spotid>` — (repeatable) force a spot **Live** (coral badge + pulse + name label) regardless of real events, so the Live marker can be screenshotted headlessly (`SJMapView.debugForceLiveIds()`).
- `-calendar-face upcoming|grid` — start the Calendar tab on a given face of the Upcoming ⇄ Calendar toggle (`CalendarView.initialFace()`).
- `-calendar-open <YYYY-MM-DD>` — preselect a calendar day so the selection outline + day sheet render for a screenshot (`CalendarView.applyDebugLaunchState()`).
- `-calendar-legend` — open the calendar's "Reading the calendar" info sheet (`CalendarView.applyDebugLaunchState()`).
- `-insights-sample[-nointerests|-sparse|-empty]` — inject a fixed `InsightsData` sample into the Calendar "Upcoming" Insights face so every state screenshots on a signed-out sim: populated (default), no-interests (chart falls back to town totals), sparse (honest zeros), and empty-calendar (`CalendarView.insightsData`; samples in `InsightsData.swift`). Pair with `-calendar-face upcoming`.
- `-insights-page <n>` — start the spotlight-wheel hero on page n (1-based), so each hero page (Yours · In town · Next up) can be screenshotted headlessly (`SpotlightWheel.applyInitialSelection`).
- `-insights-wheel-loop` — auto-advance the spotlight wheel every 1.5s (wrapping) so its paging can be recorded headlessly; skipped under Reduce Motion (`SpotlightWheel.startLoopIfRequested`).
- `-insights-scroll-calendar` — scroll the Upcoming face to the mini-month card on launch so its two dot kinds (neutral = town happening, coral = your day) screenshot headlessly (`UpcomingInsightsView.debugScrollIfNeeded`).
- `-bento-expand journaled|visited|written` / `-bento-autoexpand …` — force / auto-fire (after ~1.5s) a bento interest-tile expansion so the tap-to-expand motion + the "Next" doorway can be screenshotted/recorded (`BentoStatGrid`; slot ids map to tiles 0/1/2).
- `-open-menu` — unfold the town menu drawer on launch (Home's top-right button; `MainTabsView.debugOpenMenu()`); compose with `-menu-autoclose` to fire the collapse ~1.6s after open (records the close headlessly).
- `-tap-menu` — fire the menu button's *tap* ~1.2s after Home appears (plays the button bounce + three-dot fade, then opens the drawer), for recording the tap animation; compose with `-slow-tap` to stretch that reaction ~4× so it can be captured frame-by-frame (`Masthead.debugAutoTap` / `slowTap`).
- `-open-profile` — present the community Profile sheet on launch (now a town-menu destination; `MainTabsView.debugOpenProfile()`). Compose with `-profile-expand` (activity list expanded), `-profile-bottom` (scrolled to the sign-out row), `-profile-edit` (the editor open), or `-profile-edit-interests` (the editor's interest picker open) to screenshot those states (`ProfileView` / `EditProfileView`).
- `-almanac-write` — force the Almanac's **daily write** on launch regardless of the once-per-day stamp (and bypassing Reduce Motion), so the greeting-types-then-read-writes reveal can be recorded headlessly (`AlmanacSection` / `AlmanacReveal`). The gate is UserDefaults `hygge.almanac.lastWrittenDay` (= `DateHelpers.localDate()`); to force the *static* (already-written) path instead, stamp today: `xcrun simctl spawn <udid> defaults write Jesse.Hygge hygge.almanac.lastWrittenDay -string $(date +%F)`.
- `-atmosphere <k:v,…>` — force the **Living Basemap** to a given mood so every time-of-day/season/weather combination can be screenshotted headlessly (`AtmosphereOverride` / `AtmosphereModel`, bypasses the live providers + timers). Keys: `season:winter|spring|summer|autumn`, `phase:dawn|day|golden|dusk|night`, `sky:clear|cloudy|overcast|fog|rain|snow|storm`, `intensity:light|moderate|heavy`, `temp:<°F>`, `daylight:<0–1>` (dayFactor), `isday:0|1` — any subset (unspecified fields fall back to the live/computed value). Example: `-atmosphere season:winter,phase:night,sky:snow,temp:24,daylight:0.0,isday:0`.

### First-checkout setup — required or the build fails
- **`Hygge/Config/MapboxConfig.swift` is gitignored** (it holds the Mapbox token) — a fresh clone must recreate it: `let MAPBOX_ACCESS_TOKEN = "pk...."`. Without it the map is blank / the build won't link the token.
- **`.impeccable/` build hazard:** the "impeccable" tool drops `.impeccable/hook.cache.json`. If one lands **inside** the `Hygge/` file-system-synchronized group, Xcode copies duplicate `hook.cache.json` into the bundle and the build fails with **"Multiple commands produce …"**. Fix: `find Hygge -type d -name .impeccable -exec rm -rf {} +`. (`.impeccable/` is gitignored.)

## Architecture

`HyggeApp` (`@main`) registers fonts, sets the Mapbox token, injects `AuthStore.shared`, and renders `RootView`, which is the **auth gate**: `booting` → splash; signed-in → onboarding (first run) or `MainTabsView`; signed-out → `LoginView`. `MainTabsView` is four tabs (`Tab`: home/activities/calendar/map) under a custom frosted `HyggeTabBar`, plus a global "+" composer sheet.

### Backend — hand-rolled, no Supabase SDK (`Hygge/Backend/`)
The entire backend is written by hand over `URLSession` to match `@hygge/core` 1:1 — there is **no `supabase-swift` dependency**.

- **`SupabaseHTTP`** — the low-level client: `auth(...)` hits GoTrue (`/auth/v1`), `rest(...)` hits PostgREST (`/rest/v1`). Both send the public `apikey` + a `Bearer` token; PostgREST calls take a fresh access token and an optional `Prefer` header.
- **`AuthStore`** (`@MainActor`, singleton `.shared`) — the single auth source: email + password (confirmation ON), **Keychain-persisted `Session`**, and **coalesced token refresh** (GoTrue rotates the refresh token, so concurrent refreshes funnel through one in-flight task; a hard failure clears the session and routes back to Login). Always get tokens via `validAccessToken()`.
- **`CommunityAPI`** — the domain API (events, RSVPs, clubs, quests, trails), mirroring the Expo `createCommunityApi`. `Admin.isAdmin(email)` gates admin writes (self-approved events). Also owns the per-user "My activity" reads behind the profile (`getMyUpcomingRsvps` · `getMyClubs` · `getMyQuestCount`).
- **`ProfileAPI`** — the community-profile layer (name · avatar · interests) over **`town_profiles`** (own-row RLS): `getMyProfile()` / `upsert(...)`. **Community identity lives in `town_profiles`, NOT the wellness app's `profiles` table** — the shared Supabase project backs two apps, and `profiles` belongs to the other one. `RootView.hydrateIfNeeded()` mirrors the row into `Interests` (UserDefaults) once per session for offline matching/greetings.
- **`RealtimeClient`** (`@MainActor`) — a **hand-written Phoenix-channel client** over `URLSessionWebSocketTask` (Supabase Realtime speaks Phoenix `vsn=1.0.0`). Joins `postgres_changes` on `club_events` with the user's JWT (RLS still filters what arrives), heartbeats, pushes a fresh token periodically, and reconnects with capped exponential backoff. See `SupabaseConfig.realtimeURL`.
- **`SupabaseConfig`** — project URL + **public anon key** (safe to ship; RLS is the real boundary) and the derived `rest/auth/storage/realtime` URLs.
- Supporting: `Session`, `Storage` (image upload), `Moderation` (Claude edge function), `Reminders`, `Interests`, `TrailServices`, `KnownVenues`, `DateHelpers`, `Models`.

### Features — one folder per screen, `View` + `Model` (`Hygge/Features/`)
The house pattern is a `SomethingView` paired with a `SomethingModel` (`@MainActor final class … ObservableObject`) that owns state + API calls. Folders: `Home`, `Activities`, `Calendar`, `Add`, `Map`, `Auth`, `Onboarding`, `Place`, `Profile`, `Components`.

**The Map (`Features/Map/`)** — the most involved feature, and where the realtime pipeline lives:
- **`SJMapView`** — the Mapbox map, a layer-based **pin hierarchy** (`PinDisplay`: a recessive 6pt rest dot for every spot via a `CircleLayer`; saved/live/selected pins wake into full badges + collision-safe `SymbolLayer` labels gated at zoom T=14.5; precedence selected > live > saved > rest; selection is a single `setFeatureState` flip, never a re-render), live pulse, and the Life360-style chrome: a floating top row (filter chip · town pill · compose "+"), floating help + recenter, and the persistent bottom sheet (`MapSheet`). The town pill reverse-geocodes the map center (`MapModel.updateTown` → `GeocoderService.town`, debounced), so it names whatever town you pan over — "Saint Joseph" at home, the neighboring city when you move. The "+" opens `QuickAddSheet` for admins (`isAdmin`) and the global composer (`onCompose`) for everyone else. A `SpotFilter` chip narrows which pins + Places show. **Living Basemap** (`Features/Map/Atmosphere/`, spec `docs/superpowers/specs/2026-07-13-living-basemap-design.md`): the map is alive before anyone touches it — `AtmosphereModel` composes time-of-day (`SolarClock`, offline NOAA sun times), season (`SeasonClock`), and real weather (`OpenMeteoWeatherProvider` behind a `WeatherProvider` protocol; WeatherKit drops in later) into a `TownAtmosphere` that modulates the cartography (`BasemapPalette`), a `TimeWashOverlay`, `WeatherParticles` (snow/rain, Reduce-Motion static), and a weather **whisper** under the town pill (muted ink, never coral). Anchored to `MapSpots.center` — no schema, no backend, no location permission.
- **`MapSheet`** — the always-visible, draggable bottom sheet, ported to Life360's People/Places pattern. **The sheet is the surface**: three detents the grabber snaps between (**peek** ~120pt · **medium** ~50% · **full**, which stops just below the map's floating chrome so the town pill/filter/compose never clip and a band of live map always shows). **Peek is one glanceable line — what's live right now, not a list** (`peekLine`: live coral dot + breathing ring when something's happening, else a calm gray dot; primary/secondary copy off `liveEvents`/`state`); it cross-fades into the list as you pull up (opacity driven by a 0→1 `p` over peek→medium). Snap is momentum-aware (nearest rest height using `predictedEndTranslation`); VoiceOver drives it via `accessibilityAdjustableAction` on the grabber. Three list/detail states, all real data: **Today** (today's happenings, coral dot = live now), **Places** (the curated catalogue + each spot's live-now count), and **spot detail** (blurb, happenings, save-bookmark, Directions) shown when a pin/row is selected — selecting lifts to full. The old pop-up detail card is subsumed here.
- **`MapModel`** (`@MainActor`) — owns the `RealtimeClient` subscription + today's events. A `club_events` change touching **today** triggers a 300 ms-debounced re-sync (`getTodayEvents()`), so a new happening lights its pin and a deleted/ended one goes quiet **with no refresh**. Handles teardown, background socket-drop + foreground resubscribe, and the **midnight rollover**.
- **`MapSpots` / `KnownVenues`** — the **curated venue coordinates** (mirrors the Expo `lib/geo.ts`). Never trust a runtime geocoder for a known St. Joe venue — resolve here first; geocoding is only the fallback for unknowns.
- **`QuickAddSheet`** — admin-only bottom sheet to post an event straight onto the map (title, spot picker, date, time) → inserts an approved `club_events` row → the realtime pipeline lights the pin.

**Town menu (`Features/Home/TownMenuView.swift` + `Features/Components/CornerDrawer.swift`)** — Home's **top-right button is now a single menu button** (`Masthead.onMenu`); the old `+` composer and search circles were removed and their functions moved *inside* the menu. The button carries a small **vertical three-dot affordance (⋮)** and, on tap, plays a **little scale bounce** while the **dots fade away**, then hands off to the drawer a beat later (`Masthead.tap()`, ported from the reference); the dots restore when the drawer closes (driven by `menuOpen`). Tapping it unfolds the **town menu drawer**, a **corner "genie" reveal ported frame-by-frame from a reference recording** (the reference is a left-anchored avatar→nav drawer; **mirrored here to the top-right**). `MainTabsView.showMenu` → **`CornerDrawerOverlay`** (generic; hosts any content, hands it an animated `close`) wrapping **`TownMenuView`** (avatar+name header → left-aligned rows: Calendar · Activities · Town map · Add an event · Invite a neighbor · Your profile → `Hygge` wordmark pinned at the bottom, echoing the reference's "Genie"). Rows route via `TownMenuAction` → `MainTabsView.handleMenu` (tab switches swap instantly behind the collapsing drawer; sheets/overlays wait out the close via `afterMenuClose`). **Profile is now one of those destinations** — a standard `.sheet(ProfileView())`, no longer the drawer itself.
  - Motion (`CornerDrawerOverlay`, measured off the reference): a **~56%-width, near-full-height** panel pinned at the top-right corner that starts as a compact card and **unfolds top-down** — its **HEIGHT unfolds** (a growing rounded-rect clip, `startHFrac 0.16`) while a **mild uniform scale** (`0.80→1`, topTrailing anchor ⇒ no distortion) grows it out of the corner; **width stays full** (so left-aligned rows never clip; centred content would). Over a **flat, washed light-grey blur** (`.regularMaterial` + `Hue.canvas` veil — the home recedes). Springs: height `spring(0.52,bounce 0.16)`, scale `spring(0.44,0.14)`, close `spring(0.26,0)` (slow-to-open, fast-to-close); 40pt continuous radius; Reduce Motion → cross-fade. Left-aligned menu content makes the reveal cascade row-by-row, matching the reference. **Verify with a reference-vs-sim frame montage** (record → AVAssetImageGenerator → `comp.swift` two-row REF/HYG contact-sheet at matching progress); DEBUG `-open-menu` + `-menu-autoclose` drive it headlessly.

**Profile (`Features/Profile/`)** — reached from the town menu's "Your profile" row (a standard sheet). `ProfileView` shows identity (`ProfileAPI` → `town_profiles`) plus **real** activity via the `CommunityAPI` My-activity reads — no fabricated counts, so an empty state reads "0". `ProfileView(onClose:)` still accepts an injected close (used if presented as an overlay) but defaults to `@Environment(\.dismiss)`. `EditProfileView` writes **server-first** (upload avatar → `ProfileAPI.upsert`) and surfaces a real save failure instead of a false success; it reuses onboarding's `InterestPickerView` with `showsProgress: false` to drop the wizard step-bar.

**Share (`Features/Share/`)** — the app-wide **"share reveal"** (ported ~99% from a Duolingo reference recording). Any share calls **`ShareCenter.shared.present(SharePayload(...))`**: a preview card of *exactly what's being shared* springs up over a dimmed backdrop in a dedicated overlay **`UIWindow`** (above the tab bar **and** any `.sheet`), with a Duolingo-style target row (**Messages · Save image · More**). The preview view is also what's rendered to the shared image (`ImageRenderer`) — what you see is what you send. `ShareCenter` (`@MainActor` singleton) owns the window + present/dismiss + the reveal spring (`response 0.58, damping 0.76`; scrim `easeOut 0.40`; **Reduce-Motion cross-fades**, no scale); `ShareRevealView` is the scrim/card/sheet; `ShareTargets` holds the Messages (`MFMessageComposeViewController`), Save-image (`PHPhotoLibrary`, needs `INFOPLIST_KEY_NSPhotoLibraryAddUsageDescription`), and More (`UIActivityViewController`) actions. **Add a new share in one line** via a `SharePayload` factory (`.event(...)`, `.appInvite()`) — preview cards stay **typographic (no drawn art)**. Motion is verified with the sim frame-montage method (spec: `docs/superpowers/specs/2026-07-11-share-reveal-animation-design.md`).

### Design system (`Hygge/Theme/`) — ported from the Expo app
- **`HyggeColor`** (`Hue.*`) — warm linen palette: `paper*` surfaces, `ink`/`ink2`/`ink3` text, and **accents with one job each** — `moss` (positive/primary), `sky` (brand/focus), `honey` (warmth), `clay` (warning). Plus a **Map visual system**: `Hue.accent` **coral (#FF6B57)** appears **only** on live indicators + primary/tappable elements; everything else is `surface`/`gray`/`mapInk`.
- **`HyggeFont`** — the app is the **platform system font** everywhere (SF Pro): the `Font.display/sans/mono/…` helpers all map to `.system(size:weight:)`, so **weight carries the hierarchy** and numbers stay tabular via `.monospacedDigit()`. The **one** custom face is the logo — **Atkinson Hyperlegible Bold** (`Font.logo`), used by `HyggeLogoBadge`. The badge's `.brandBadge()` corner stamp was **removed from every tab** in the Life360 map pass (the map's top-right corner now holds screen chrome); `HyggeLogoBadge` itself is kept but currently unused. `registerHyggeFonts()` registers the bundled Atkinson ttf (the old Spectral / DM Sans / Geist Mono ttf were removed in the coral rebrand — don't reintroduce a bundled UI font). The **coral app icon** (`Assets.xcassets/AppIcon.appiconset`) is the same wordmark, white on `Hue.accent`.
- **`HyggeMetrics`** — the shadow + metric tokens (e.g. `mapFloatShadow`, `mapSheetShadow`).

Do **not** hardcode hex/spacing that a `Hue`/metric token already covers. The only allowed raw hexes in the map are the **base-map cartography colors** — the warm Google-/Life360-style palette now in `BasemapPalette` (land beige, sage parks, soft-blue water, light-gray buildings) as the *summer·noon·clear* anchor, which the Living Basemap modulates by time·season·weather before `recolorBasemap` applies it to the Mapbox layers.

## Conventions & gotchas

- **On-brand bar** (inherited from the Expo app): warm, calm, quiet, neighborly, hyper-local. No badges/streaks/feeds/notification-spam. **Real data only — never seeded/inflated counts.** Voice is a neighbor, not a brand.
- **Park/venue photos are human-verified — a picture must actually *look good* to a person, not just resolve.** The runtime picker (`GooglePlacesService.bestScenicPhoto`) is geometry-only: it prefers a large landscape frame but **cannot** tell a scenic vista from a photo of a trash barrel, a portrait phone shot (which crops to an ugly middle band), or a dreary off-season snap. So when wiring park/venue imagery, a person must **eyeball the actual chosen photo**. When the Google auto-pick looks poor, **override it** by bundling a hand-picked landscape photo in `Resources/Images` + a `KnownLocalPhoto` entry — Google Places photos may **not** be bundled/persisted per ToS, so bundled overrides come from city/owner-supplied sources (record the source + any permission caveat in the code comment). `scripts/review_park_photos.py` assembles a contact sheet of every park's *live* photo (bundled or Google-resolved) for that review.
- **Live-glow is for *now*, not "today".** A pin pulses only while an event is happening (`start ≤ now ≤ start + 2h`, `DateHelpers.isLiveNow`). Coral is reserved for live/tappable.
- **Dates are user-timezone.** Use `DateHelpers.localDate()` / `nowMinutes()` (pinned to `TimeZone.current`); never derive "today" from a UTC ISO string.
- **Realtime DELETE carries only the primary key.** A DELETE's `old_record` contains just `id` — match deletes by `id` (a full refetch is idempotent). The table is set to `REPLICA IDENTITY FULL` and `club_events` is in the `supabase_realtime` publication (both already applied to the live project; see `MAP_BUILD_LOG.md`).
- **Admin is an email allowlist**, not a security boundary — `Admin.isAdmin` in `DateHelpers.swift` (self-approved events are an intentional product decision shared with the Expo app). RLS is the real boundary.
- **`MAP_BUILD_LOG.md`** is the running, chronological record of map work (fixes, the realtime pipeline, the anti-slop pass, applied SQL). Continue it when doing map work; it's the source of truth for what's been verified.

## graphify

This project has a knowledge graph at graphify-out/ with god nodes, community structure, and cross-file relationships.

Rules:
- For codebase questions, first run `graphify query "<question>"` when graphify-out/graph.json exists. Use `graphify path "<A>" "<B>"` for relationships and `graphify explain "<concept>"` for focused concepts. These return a scoped subgraph, usually much smaller than GRAPH_REPORT.md or raw grep output.
- If graphify-out/wiki/index.md exists, use it for broad navigation instead of raw source browsing.
- Read graphify-out/GRAPH_REPORT.md only for broad architecture review or when query/path/explain do not surface enough context.
- After modifying code, run `graphify update .` to keep the graph current (AST-only, no API cost).
