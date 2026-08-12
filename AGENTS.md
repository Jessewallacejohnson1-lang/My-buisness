# AGENTS.md

This file is the working guide for Codex agents in this repository. Treat the live tree and `CLAUDE.md` as corroborating sources; if either guide disagrees with code, surface the mismatch instead of inventing a path or API.

## Project

**Block Party** is a native SwiftUI + Mapbox iOS app for St. Joseph, Minnesota: a finite daily town briefing, shared activities/calendar, live town map, community profile, and local onboarding. It is the native twin of the Expo/React Native app in `~/Documents/my-business/apps/mobile`.

- Xcode project: `BlockParty.xcodeproj`
- Scheme and module: `BlockParty`
- Bundle identifier: `Jesse.BlockParty`
- Deployment target: iOS 26.5
- Swift: 5
- Test target: `BlockPartyTests`
- Only SPM dependency: `mapbox-maps-ios`
- Shared Supabase project: `lxdgwhvqjqmqliobwjpi`

The native and Expo apps share schema, RLS, and query semantics. Seven Swift comments deliberately reference `@hygge/core`: that is still the real npm package name in `~/Documents/my-business/packages/core/package.json`. Those comments are accurate; do not rename them until the package itself changes.

### Two-repo rule

Mapbox, native iOS, and this app's first tab (**Today**) belong here. React Native/web work belongs in the Expo repo, whose equivalent first tab is called **Home**. Keep backend behavior and shared design/query decisions in sync, but do not edit the other repo as a side effect of native work.

## Before changing anything

Run these first:

```bash
git status --short --branch
git worktree list
git branch -a
```

Parallel sessions routinely leave unrelated WIP. Preserve it. If the current tree is dirty and the requested change would overlap those files, use a clean worktree/branch or ask the user how to handle the entanglement; never sweep someone else's edits into a commit. Worktree paths change often, so use `git worktree list` rather than remembered names. Before XcodeBuildMCP builds, confirm its active checkout with `session_show_defaults`.

## Build, test, run, verify

Run the app-hosted test target with:

```bash
xcodebuild test -project BlockParty.xcodeproj -scheme BlockParty \
  -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO
```

For one test/class, append `-only-testing:BlockPartyTests/DateHelpersTests/testAdminGate` or `-only-testing:BlockPartyTests/DateHelpersTests`.

Tests cover date/admin rules, the Today briefing contract/model/feel/live-payload parity, utility providers/preferences/motion/contrast, onboarding persistence, town-timezone formatting, the legacy-key migration, and town-rain physics. Visual fidelity still requires a clean 0-warning build plus simulator screenshots. Scroll, touch arbitration, and map gestures require a real-device check.

Prefer XcodeBuildMCP (`build_run_sim`, `build_sim`, `screenshot`) for Apple tooling. Raw simulator fallback:

```bash
xcodebuild -project BlockParty.xcodeproj -scheme BlockParty -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17' build

xcrun simctl launch <udid> Jesse.BlockParty -open-tab map
xcrun simctl io <udid> screenshot /tmp/map.png
```

### DerivedData trap

Multiple worktrees produce multiple `BlockParty-<hash>` DerivedData folders. Never locate the app with `find ... -name BlockParty.app | head`; that often installs a stale binary. Resolve the output for the checkout you just built:

```bash
DIR=$(xcodebuild -project BlockParty.xcodeproj -scheme BlockParty -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17' -showBuildSettings \
  | awk -F' = ' '/ BUILT_PRODUCTS_DIR =/{print $2; exit}')
xcrun simctl install <udid> "$DIR/BlockParty.app"
```

Install **over** the existing app. `simctl uninstall` destroys the container, including the session, `bp.onboarded.<uid>`, and local mirrors. If recovery is necessary, sign in again and only restore a user-scoped onboarding flag when the remote profile confirms completion:

```bash
xcrun simctl spawn <udid> defaults write Jesse.BlockParty "bp.onboarded.<uid>" -string 1
```

For a physical device, keep DerivedData outside `BlockParty/` so Xcode's file-system-synchronized group cannot absorb build output:

```bash
DD=/tmp/dd-device
xcodebuild -project BlockParty.xcodeproj -scheme BlockParty -configuration Debug \
  -destination 'id=<HARDWARE_UDID>' -derivedDataPath "$DD" \
  -allowProvisioningUpdates build
xcrun devicectl device install app --device <COREDEVICE_UUID> \
  "$DD/Build/Products/Debug-iphoneos/BlockParty.app"
xcrun devicectl device process launch --device <COREDEVICE_UUID> Jesse.BlockParty
```

`xcodebuild -destination id=` uses the hardware UDID from `xcrun xctrace list devices`; `devicectl --device` uses the CoreDevice UUID from `xcrun devicectl list devices`. Unlock the device before remote launch. Automatic signing may create/refresh the `Jesse.BlockParty` provisioning profile on the first post-rename build.

### First-checkout requirements

Two gitignored files under `BlockParty/Config/` must exist or the build fails:

- `MapboxConfig.swift`: declares `MAPBOX_ACCESS_TOKEN`.
- `GooglePlacesConfig.swift`: declares `GOOGLE_PLACES_API_KEY`.

Copy them from an authorized sibling checkout; never commit them. The Google Cloud Places key still needs `Jesse.BlockParty` added to its iOS bundle-id restrictions (outstanding as of 2026-08-09). Until that console action lands, all runtime venue photography under the new bundle id will be blank.

The `.impeccable/` tool cache is another build hazard. If `.impeccable/hook.cache.json` lands inside the file-system-synchronized `BlockParty/` group, Xcode may fail with “Multiple commands produce …”. Remove only those nested caches:

```bash
find BlockParty -type d -name .impeccable -exec rm -rf {} +
```

## DEBUG launch arguments

All of these compile out in Release. They exist because this simulator setup has no gesture/scroll automation.

- **Shell/previews:** `-open-tab map|activities|calendar`; `-show-home`; `-show-splash`; `-show-loader`; `-show-loading-cover`; `-show-skeletons`; `-show-map-intro`; `-share-demo`; `-open-speeddial` with optional `-speeddial-loop`.
- **Today briefing:** `-briefing-preview [-briefing-state sample|one_event|zero_events|voted|none|degraded]`; `-briefing-gallery [-gallery-state <label-fragment>]`; `-header-hairline`.
- **Legacy feed regression:** `-feed-card-gallery`; `-feed-card-autoplay`; `-today-feed-preview|-today-feed-empty|-today-feed-skeleton`.
- **Almanac/utility:** `-almanac-write|-almanac-static|-almanac-fail`; `-almanac-part morning|afternoon|evening`; `-almanac-demo-line <text>`; `-utility-row-preview`; `-utility-expand|-utility-customize|-utility-empty`.
- **Activities:** `-explore-filter events|clubs|trails|parks|saved`; `-explore-timeframe today|week|month|upcoming`; `-explore-search-open`; `-explore-search <query>`; `-explore-search-committed <query>`.
- **Map browse/camera:** `-map-sheet places`; `-map-detent peek|medium|full`; `-map-open <spotid>`; `-map-open-poi [name-substring|id]`; `-map-detail-expanded` (combine with either open flag); `-map-center <lat>,<lon>`; `-map-zoom <z>`; `-map-bearing <deg>`; `-map-pitch <deg>`; `-map-autozoom`; `-force-nonadmin`.
- **Map states/rain:** repeatable `-map-save <spotid>` and `-map-force-live <spotid>`; `-town-rain`; `-town-rain-preview`; `-poi-logo-stub`. Civic spot IDs are `downtown|saintbens|chapel|wobegon|millstream|saintjohns`.
- **Calendar:** `-calendar-face upcoming|grid`; `-calendar-open <YYYY-MM-DD>`; `-calendar-legend`; `-calendar-compose` (combine with an open day); `-calendar-sample`; `-calendar-replay`; `-insights-sample`; `-bento-expand <journaled|visited|written>`; `-bento-autoexpand <journaled|visited|written>`; `-entries-expand`.
- **Menu/profile:** `-open-menu` with optional `-menu-autoclose`; `-tap-menu` with optional `-slow-tap`; `-open-profile` with `-profile-expand|-profile-bottom|-profile-edit|-profile-edit-interests|-profile-moderation|-profile-autoclose`.
- **Onboarding:** `-show-onboarding [-onboarding-step name|interests] [-onboarding-filled]`; `-bp-flow [-bp-step <BPStep-case>]`; `-bp-restart`; `-bp-seed-resume <index>`; `-bp-hold`; `-bp-components [-bp-page 0...5]`; `-bp-motion press|progress|badge|typing`.
- **Backend write:** `-seed-places` invokes the DEBUG place seeder. It mutates backend data; do not treat it as a screenshot-only flag.

Use the targeted preview/gallery flags for states below the fold, then verify actual scrolling and gestures on a device.

## Architecture

### App shell and auth

`BlockPartyApp` (`BlockParty/BlockPartyApp.swift`) registers fonts, sets the Mapbox token, installs the PostgREST unauthorized handler, injects `AuthStore.shared`, and optionally runs the DEBUG place seeder.

`RootView` is the gate:

1. launch loader while auth boots/minimum loader time runs;
2. signed-in users hydrate their own `town_profiles` row, then see the signed-in onboarding if needed or `MainTabsView`;
3. signed-out first-time users see the 20-screen pre-auth `BPOnboardingFlow`;
4. returning signed-out users see `LoginView`.

`MainTabsView` owns four tabs (`home`, `activities`, `calendar`, `map`), the custom `BlockPartyTabBar`, the town-menu/profile presentations, map detail shell, and compose speed dial/sheets.

### Backend (`BlockParty/Backend/`)

There is no Supabase Swift SDK. The app talks to GoTrue, PostgREST, Storage, and Realtime with `URLSession`:

- `SupabaseHTTP`: low-level auth/REST calls with public `apikey`, bearer token, and optional `Prefer`.
- `AuthStore`: singleton auth source, Keychain session persistence, coalesced refresh-token rotation, and hard-failure sign-out. Always request a token through `validAccessToken()`.
- `CommunityAPI`: events, RSVPs, clubs, quests, trails, and profile activity reads, matching the Expo twin's query semantics.
- `BriefingAPI` / `BriefingPayload`: the Today tab's single-RPC read contract and daily-touch vote write.
- `ProfileAPI`: community identity in `town_profiles`, not the unrelated wellness app's `profiles` table.
- `RealtimeClient`: Phoenix-channel client with heartbeats, token pushes, reconnect backoff, and RLS-filtered `postgres_changes`.
- `SupabaseConfig`: project and derived REST/auth/storage/realtime URLs; the anon key is public by design and RLS is the security boundary.

### Persisted identifier migration

The current identifiers are:

| Purpose | Current value |
|---|---|
| App bundle and log subsystem | `Jesse.BlockParty` |
| Keychain session account | `bp.session` |
| Product-namespaced UserDefaults | `bp.*` |
| Realtime topic | `realtime:bp-<table>` |

**There is no migration shim, and one is not possible.** iOS scopes `UserDefaults` to the app container and Keychain items to an access group derived from the bundle id. `Jesse.BlockParty` is therefore a *different app* with an empty container and cannot read anything `Jesse.Hygge` stored. Bridging would need a shared keychain access group declared in **both** builds; the shipped build has none and cannot retroactively gain one. A migration was written, proven unreachable, and removed — do not re-add it. The rename is a clean break: existing installs re-authenticate and re-onboard, accepted at 4 accounts / 2 active, pre-launch. Never introduce new `hygge.*` identifiers.

### Today briefing (`BlockParty/Features/Home/Briefing/` + `Feed/`)

Today is a finite editorial briefing, not an infinite feed. `HomeView` is a compatibility shell over `FeedView`, which keeps `TodayTopBar` fixed above the scroll view and renders `FeedRegistry.visibleModules` in this order:

```text
almanac → yourDay → trivia → spotlight → signOff
```

`FeedModuleID` is string-backed so unknown newer IDs decode safely. `FeedRegistry` owns the only production module array; adding a module means adding its implementation and one registry entry, without editing `FeedView`. Each module owns its phase, visibility, loading/error/empty rendering, spacing, reveal index, and erased view. The utility subsystem remains intact under `Features/Home/Utility/`, but Today does not mount it or hydrate `UtilityPrefsStore`.

`BriefingAPI.today()` sends one authenticated POST to `rest/v1/rpc/get_today_briefing`, passing the St. Joseph timezone. The RPC returns the complete `BriefingPayload`: almanac/weather/touch/spotlight/fallback are degradable, featured may be empty, and `caughtUp` is required so the briefing always ends. `BriefingModel` renders the disk cache first, reconciles with the server, keeps cached content during outages, and applies vote/RSVP changes optimistically with rollback. The utility row is intentionally independent and owns its own loading/cache/realtime.

The legacy card feed (`TodayFeedView`, `FeedEventCard`, and related files) still compiles under `BlockParty/Features/Home/Feed/` for regression and rollback. The registry files in that folder are the production Today composition.

### Feature folders (`BlockParty/Features/`)

Current top-level features are `Activities`, `Add`, `Auth`, `Board`, `Calendar`, `Components`, `Home`, `Map`, `Onboarding`, `OnboardingFlow`, `Place`, `Profile`, and `Share`. The usual house pattern is a SwiftUI view plus a `@MainActor` `ObservableObject` model that owns API state.

### Map (`BlockParty/Features/Map/`)

- `SJMapView` is a SwiftUI Mapbox `Map`, with static `BasemapPalette`, civic and POI SwiftUI view annotations, client-side clustering, town reverse geocoding, compass/recenter/help chrome, admin/non-admin compose routing, and the persistent map sheet.
- `MapSheet` is an in-tree draggable surface with peek/medium/full detents and Today/Places browse states. Civic/POI detail is lifted into the shared tab-shell presentation. Sheet gesture arbitration and the VoiceOver adjustable action are custom; it is not `presentationDetents`.
- `MapModel` owns today's events and `RealtimeClient`. A relevant change debounces a full today re-sync; it handles background/foreground lifecycle and midnight rollover.
- `MapSpots` and `KnownVenues` own trusted St. Joseph coordinates. Resolve known places there before geocoding unknown text.
- `POILogoCache` reads `places.logo_url`; logo acquisition/upload is an offline script pipeline, not runtime scraping.

The map is SwiftUI `Map(viewport:)` inside `MapReader`, not UIKit `MapView`. Configure gestures with `.gestureOptions`, camera with the `Viewport` binding/viewport animations, frame rate with `.frameRate`, and bounds via `proxy.map.setCameraBounds`. Do not paste UIKit Mapbox recipes into this view.

### Town menu, profile, and share

`TodayTopBar` owns the exact full-colour app mark, fixed town title, and top-right menu button. `GlassShowcaseOverlay` frosts the app and hosts the content-height `TownMenuView` panel from the top-right; tab routes switch behind the closing overlay while sheets wait until it closes. Profile is a normal sheet and uses real `town_profiles` plus real activity reads—never fabricated counts.

`ShareCenter` presents the app-wide share reveal in its own `UIWindow`, above tabs and sheets. The preview view is also rendered to the shared image. Add new share types through `SharePayload` factories.

## Design system (`BlockParty/Theme/`)

- `BlockPartyColor` / `Hue`: six neutral tokens (`ink`, `paper`, `surface`, `inkSecondary`, `hairline`, `fill`) plus plum/berry `accent` #8E3B6B. The accent is meaning-scoped to live, active, selected/saved, and primary CTA states—never decorative washes or body copy.
- `BlockPartyFont`: Jost for display/wordmark/headlines and SF Pro for body/UI/data. Use the exact bundled Jost PostScript names; a wrong name silently falls back.
- Brand mark: the lossless master is `docs/brand/source-render-1254.png`; `scripts/brand/exact.swift` derives the 1024px opaque app icon and in-app assets. Live surfaces use the exact glossy lowercase `bp` raster—never tint, trace, redraw, or substitute the retired hollow-square/script-BP variants.
- `BlockPartyMetrics`: shared radii/shadows, including map float/sheet shadows. `Radius.bento` is intentionally outside the 12/16/20 sequence.

Do not hardcode a hex or spacing value at a view call site when a token or named palette covers it. Controlled raw colours live in role-specific palette/config files: `BlockPartyColor.swift`, `BasemapPalette.swift`, `WeatherBackground.swift`, utility gradient definitions, and `OnboardingFlow/Theme/BPOnboardingPalette.swift`; logo fallback art and the garbage-truck illustration are content exceptions. Do not make the basemap grayscale; that experiment was reverted because landmarks disappeared. Category is carried by glyph, while live/active/selected state may use the accent.

## Conventions and gotchas

- **Brand:** warm, calm, neighborly, hyper-local. No inflated counts, streaks, spam, or fake activity. Real data only.
- **Photos:** Google Places Photo API is the runtime default. Use `VenuePhoto` and the confidence-gated lookup; `search()` alone is not trusted enough to display a photo. Display `authorAttributions`. Persist place IDs, never Places photo names. Bundle only a human-reviewed, non-Google local override with its source recorded.
- **Google restriction:** adding `Jesse.BlockParty` to the Places API key restriction is outstanding and blocking for venue photography. Creating the new App Store Connect record is also outstanding; the old listing/TestFlight builds are intentionally orphaned by the bundle-id decision. See `DECISIONS.md`.
- **Map logos:** generate, review, and upload with `scripts/fetch_place_logos.py`, `logo_montage.py`, and `upload_place_logos.py`; do not turn this into runtime scraping.
- **Live means now:** use the plum fill/static ring/pulse only during `start <= now <= start + 2h` via `DateHelpers.isLiveNow`, not for every event happening sometime today.
- **Town dates:** use `DateHelpers.localDate()` / `nowMinutes()` or the explicit `Town.timeZone` as the feature requires. Never derive a local day from a UTC ISO prefix.
- **Realtime DELETE:** `old_record` may contain only the primary key. Match by ID and re-fetch; do not expect a full deleted row.
- **Admin:** email allowlist is a UX gate, not security. RLS is the boundary.
- **Applied migrations:** never edit `supabase/migrations/*` retroactively. Add a new migration. Historical migration contents mean case-insensitive searches for the former name will always have legitimate hits.
- **Map log:** continue `MAP_BUILD_LOG.md` for map work and record what was actually built/screenshot-verified.
- **MainActor defaults:** module-wide isolation is enabled. Mark stateless helpers/members `nonisolated`, and resolve actor-isolated defaults inside function bodies rather than default arguments.
- **Mapbox throws:** `updateGeoJSONSource(withId:geoJSON:)` is non-throwing in Mapbox v11; `addSource`, `addLayer`, `addImage`, and camera-bound calls throw. A stray `try?` around a non-throwing call creates a warning and violates the 0-warning bar.
- **Timeouts:** `withTaskGroup` drains children and cannot enforce a real deadline against cancellation-ignoring work. Race an unstructured task with a sleeper/continuation and make the operation observe cancellation.
- **Scrollable cells:** never attach a pan-competing whole-card gesture to a feed/briefing cell. Use `ButtonStyle.isPressed` and `.simultaneousGesture` where appropriate, then verify scrolling on device.
- **Wrong build:** every worktree uses `Jesse.BlockParty`; installing any build overwrites the same simulator/device app. Confirm checkout, branch, output directory, and XcodeBuildMCP defaults before deciding a change “didn't take.”

## Strategy and history

Read `docs/playbook.md` before design or launch-strategy work. Its original advice to retain the old bundle id was superseded by Jesse's 2026-08-09 pre-launch full-purge decision; `DECISIONS.md` is authoritative for current identifiers and outstanding console work.

`MAP_BUILD_LOG.md`, `REVIEW.md`, and dated files under `docs/superpowers/` are historical records. Do not rewrite old entries to pretend the app was always called Block Party. Correct only claims presented as current/operational facts.

## graphify

When `graphify-out/graph.json` exists, use `graphify query`, `graphify path`, or `graphify explain` before broad source searching. Prefer `graphify-out/wiki/index.md` for navigation and `GRAPH_REPORT.md` only for broad architecture. After code changes, run `graphify update .`; documentation-only changes do not require an AST graph update.
