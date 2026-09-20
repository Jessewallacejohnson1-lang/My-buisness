# AGENTS.md

This file is the working guide for Codex agents in this repository. Treat the live tree and `CLAUDE.md` as corroborating sources; if either guide disagrees with code, surface the mismatch instead of inventing a path or API.

## Project

**Block Party** is a native SwiftUI + Mapbox iOS app for St. Joseph, Minnesota: a Today tab, a live town map, and a community profile. Onboarding and the launch splash were deleted on 2026-09-18. It is the native twin of the Expo/React Native app in `~/Documents/my-business/apps/mobile`.

**The app is mid-rebuild.** The 2026-09-17 strip-down emptied the Today feed, deleted the Activities and Calendar features (their tab slots stay, rendering a blank placeholder), and moved the map off the tab bar into a full-screen cover opened from Today. `docs/GUTTING-LEDGER.md` records what was removed and how to recover it; open it when you are asked what happened to a surface, not as background reading. If this guide still describes something you cannot find in the tree, assume the strip-down took it and say so.

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

427 tests (down from 437 when onboarding and the splash were deleted on 2026-09-18) cover date/admin rules, the Today briefing contract/model/feel/live-payload parity/registry, utility providers/preferences/motion/contrast, the horizon/solar/scrub layer, Your Day's realtime relevance filter, town-timezone formatting, the map polish pass, and town-rain physics. Several of those suites now exercise **unmounted** code — the horizon, Your Day, trivia and utility layers outlived the surfaces that used to mount them, and the tests are what proves they still work. Keep them green; do not delete a suite because its screen is gone. Visual fidelity still requires a clean 0-warning build plus simulator screenshots. Scroll, touch arbitration, and map gestures require a real-device check.

Prefer XcodeBuildMCP (`build_run_sim`, `build_sim`, `screenshot`) for Apple tooling. Raw simulator fallback:

```bash
xcodebuild -project BlockParty.xcodeproj -scheme BlockParty -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17' build

xcrun simctl launch <udid> Jesse.BlockParty -open-map
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

Install **over** the existing app. `simctl uninstall` destroys the container, including the session and the local profile/interest mirrors, so the next launch is signed out. Nothing else needs restoring: the `bp.onboarded.<uid>` flag stopped gating anything when onboarding was deleted on 2026-09-18.

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

All of these compile out in Release. They exist because this simulator setup has no gesture/scroll automation. The 2026-09-17 strip-down took a large block of flags down with the views they staged; `docs/debug-flags.md` is the full catalogue and has been pruned to match. If a flag below does nothing, check the source before assuming it is broken — it may have been deleted.

- **Shell/previews:** `-header-collapsed` pins the Town header to its scrolled-away state (wordmark + map disc gone, bar collapsed); `-open-tab town|daily|business|you` (the map is no longer a tab, so `-open-tab map` is dead); `-tab-cycle` walks the bar end to end every 1.4s so the pill travel and page slide can be recorded; `-open-map` raises the map cover on launch and is now the only headless way in; `-show-home`; `-show-loader`; `-show-loading-cover`; `-show-skeletons`; `-show-map-intro`; `-share-demo`; `-open-speeddial` with optional `-speeddial-loop`.
- **Today:** `-briefing-preview [-briefing-state sample|one_event|zero_events|voted|none|degraded]` — the payload still loads, but with the registry empty this now renders the top bar over an empty feed; `-header-hairline`. `-briefing-gallery` / `-gallery-state` died with the module galleries.
- **Legacy feed regression:** `-feed-card-gallery`; `-feed-card-autoplay`; `-today-feed-preview|-today-feed-empty|-today-feed-skeleton`.
- **Parked layers (unmounted, flag-only):** `-horizon-sky-gallery` and `-horizon-card-gallery`, each with `-horizon-sky-gallery-page 2`, are the only entry into the Horizon layer now that the Your Day card is gone; `-utility-row-preview` and `-utility-expand|-utility-customize|-utility-empty` likewise for the parked utility row. The almanac flags (`-almanac-*`) are dead — that view was deleted.
- **Map browse/camera:** `-map-sheet places`; `-map-detent peek|medium|full`; `-map-open <spotid>`; `-map-open-poi [name-substring|id]`; `-map-detail-expanded` (combine with either open flag); `-map-filter all|food|parks|events|saved`; `-map-center <lat>,<lon>`; `-map-zoom <z>`; `-map-bearing <deg>`; `-map-pitch <deg>`; `-map-autozoom`.
- **Map states/rain:** repeatable `-map-save <spotid>` and `-map-force-live <spotid>`; `-town-rain`; `-town-rain-preview`; `-poi-logo-stub`. Civic spot IDs are `downtown|saintbens|chapel|wobegon|millstream|saintjohns`.
- **Day sheet:** `-day-sheet-preview [-day-sheet-state upcoming|inprogress|completed|empty|cta]`; `-day-sheet-hold`; `-day-sheet-demo`. Flags are now the only way in — the rail that used to open the sheet is deleted.
- **Menu/profile:** `-open-menu` with optional `-menu-autoclose` — the ONLY way in since the avatar was removed on 2026-09-18; `-open-profile` with `-profile-expand|-profile-bottom|-profile-edit|-profile-edit-interests|-profile-moderation|-profile-autoclose`.
- **Onboarding:** gone. The flow, the wizard, and every `-show-onboarding` / `-bp-*` flag were deleted on 2026-09-18.
- **Backend write:** `-seed-places` invokes the DEBUG place seeder. It mutates backend data; do not treat it as a screenshot-only flag.

Use the targeted preview/gallery flags for states below the fold, then verify actual scrolling and gestures on a device.

## Architecture

### App shell and auth

`BlockPartyApp` (`BlockParty/BlockPartyApp.swift`) registers fonts, sets the Mapbox token, installs the PostgREST unauthorized handler, injects `AuthStore.shared`, and optionally runs the DEBUG place seeder.

`RootView` is the gate:

1. everyone gets `MainTabsView` immediately — **sign-in is off** since 2026-09-18 (`RootView.requiresSignIn = false`), so `LoginView` is unreachable;
2. a signed-in user additionally hydrates their own `town_profiles` row in a background task.

There is no splash, no launch loader gate, and no onboarding. The storyboard's paper-coloured frame zero is the only thing before the app. The auth stack itself is intact and restorable — flip `requiresSignIn` back to `true`. While it is off, signed-out screens show their own empty states and the profile's Sign out row is hidden.

`MainTabsView` owns four tabs (`town`, `daily`, `business`, `you`), the custom `BlockPartyTabBar`, the town-menu presentation, the full-screen map cover, and compose speed dial/sheets.

`Tab.map` was deleted on 2026-09-17; `home`/`activities`/`calendar` were re-cut into the four above on 2026-09-18. **Town** (`house`) = the town feed (`HomeView`); its top bar carries the one map control — a 50pt glossy `Hue.mapWash` disc with the hand-drawn `MapPinGlyph`, deliberately NOT a `.glassEffect` surface (glass absorbed the highlight and refracted the glyph — measured). **Daily** (`newspaper`) = the neighbour's own paper. **Business** (`briefcase`) = the town's business network, the owners' side of Main Street. **You** = `ProfileView(showsClose: false)`. Daily and Business render `BlankTab` — the slot's name plus its promise line — deliberately: the bar is built, those screens are not. Do not remove the cases or the bar buttons.

The bar itself: a Liquid Glass CAPSULE with a `matchedGeometryEffect` capsule pill. The pill and the page slide share one spring (0.44/0.86) so they travel together; the icon's outline→filled swap runs on its OWN 0.22s snappy curve, because inheriting the page spring left the outgoing glyph half-faded mid-travel and the icon read as missing. Reduce Motion drops the bounce and the press scale and crossfades the page.

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

**Today renders nothing below its top bar, on purpose.** The 2026-09-17 strip-down deleted all seven feed modules — almanac, Your Day, town notes, For You, spotlight, trivia, sign-off — and their views (`AlmanacSection`, `DailyGreeting`, `SpotlightCard`, `TriviaCard`, `DailyTouchCard`, `CaughtUpFooter`, `HappeningSoonSection`, `TownNotesDeck`, `ForYouSection`, and the galleries that staged them). `HomeView` is still a compatibility shell over `FeedView`, and `FeedView` still keeps `TodayTopBar` fixed above the scroll view; the column beneath is empty.

The composition machinery is deliberately untouched. `FeedRegistry` still owns the only production module array — now an empty literal, with a comment saying why — and `FeedRegistry.visibleModules`, the module protocol, and the erased-view renderer all still work. Adding a module back is its implementation plus one registry entry, with no edit to `FeedView`. `FeedModuleID` is still string-backed so unknown newer IDs decode safely, and it keeps `.almanac`, `.yourDay`, `.trivia`, `.spotlight`, `.signOff` as stable names. Each module still owns its phase, visibility, loading/error/empty rendering, spacing, reveal index, and erased view.

Routes changed shape: **every `FeedRoute` case now presents its own sheet.** The old nil-`destination` case that `FeedView` handed up to `MainTabsView` for a tab change went out with the Activities tab. The survivors are `.civicTab`, `.editInterests`, and `.event(UpcomingEvent)`.

`BriefingAPI.today()` still sends one authenticated POST to `rest/v1/rpc/get_today_briefing`, passing the St. Joseph timezone, and `FeedController` still constructs and loads `BriefingModel`. The RPC still returns the complete `BriefingPayload`: almanac/weather/touch/spotlight/fallback are degradable, featured may be empty, and `caughtUp` is required so the briefing always ends. `BriefingModel` renders the disk cache first, reconciles with the server, keeps cached content during outages, and applies vote/RSVP changes optimistically with rollback. The data arrives; nothing is mounted to draw it. Leave the contract in place — a rebuilt module should find its payload already loading.

The utility subsystem moved out of Today earlier and now sits, verbatim and still tested, under `BlockParty/Features/Civic/Parked/Utility/`, waiting on the unbuilt Civic tab. It is unreferenced on purpose; read `Features/Civic/Parked/README.md` before touching it, and note that `user_utility_prefs` still holds live per-user configuration a rebuild must re-hydrate.

The legacy card feed (`TodayFeedView`, `FeedEventCard`, and related files) still compiles under `BlockParty/Features/Home/Feed/` for regression and rollback.

### Feature folders (`BlockParty/Features/`)

Current top-level features are `Add`, `Auth`, `Board`, `Civic`, `Components`, `Home`, `Map`, `Onboarding`, `Place`, `Profile`, and `Share`. `OnboardingFlow/` was deleted on 2026-09-18; `Onboarding/` keeps only `MapIntroView` (map help), `InterestPickerView` + cards (Edit Profile), and `OnboardingChrome`. The usual house pattern is a SwiftUI view plus a `@MainActor` `ObservableObject` model that owns API state.

`Activities/` (11 files) and `Calendar/` (10 files) were deleted on 2026-09-17, along with `Backend/CalendarExport.swift` and `Components/ActivityTile.swift`. `Civic/` holds the unbuilt Civic destination stub plus `Civic/Parked/` — code kept intact for a screen that does not exist yet. Nothing under `Parked/` is dead code; treat its README as binding.

### Map (`BlockParty/Features/Map/`)

- The map is **presented, not tabbed**, since 2026-09-17. Its signature is `SJMapView(onClose: (() -> Void)? = nil, bottomBarInset: CGFloat = 0)`, raised as a `.fullScreenCover` from Today's top-bar map button. It carries its own close "X" leading in the top chrome and owns `mapDetail` as internal `@State`; the shell no longer holds the selected pin. `MapSheet.tabBarReserve` (74) still exists but is **no longer the default** — it is the value a host passes as `bottomBarInset` when the map sits over a bottom bar, and nothing does today.
- `SJMapView` is a SwiftUI Mapbox `Map`, with static `BasemapPalette`, civic and POI SwiftUI view annotations, client-side clustering, town reverse geocoding, close/help/compass/recenter chrome, and the persistent map sheet. There is no compose entry on the map (the "+" and `QuickAddSheet` were retired in round 2, 2026-08-14); event creation is the shell's `ComposeSpeedDial` and the town menu's Compose row.
- `MapSheet` is an in-tree draggable surface with peek/medium/full detents and Today/Places browse states. Civic/POI detail opens `PinDetailSheet` over the dimmed map, inside the map's own hierarchy. Sheet gesture arbitration and the VoiceOver adjustable action are custom; it is not `presentationDetents`.
- `MapModel` owns today's events and `RealtimeClient`. A relevant change debounces a full today re-sync; it handles background/foreground lifecycle and midnight rollover.
- `MapSpots` and `KnownVenues` own trusted St. Joseph coordinates. Resolve known places there before geocoding unknown text.
- `POILogoCache` reads `places.logo_url`; logo acquisition/upload is an offline script pipeline, not runtime scraping.

The map is SwiftUI `Map(viewport:)` inside `MapReader`, not UIKit `MapView`. Configure gestures with `.gestureOptions`, camera with the `Viewport` binding/viewport animations, frame rate with `.frameRate`, and bounds via `proxy.map.setCameraBounds`. Do not paste UIKit Mapbox recipes into this view.

### Town menu, profile, and share

`TodayTopBar` is chrome with an empty leading side and two trailing controls: a map button — a `Radius.button` (12) rounded square under `.glassEffect(.regular, in:)` with the SF Symbol `map`, 38×38 of glass inside a 44pt tap target, labelled "Open the town map" — and the profile avatar, which still opens the town menu. The JoeTown wordmark lockup was retired on 2026-09-17, and the centring math it needed went with it. The map button only reports its tap; the shell owns the cover. `GlassShowcaseOverlay` frosts the app and hosts the content-height `TownMenuView` panel from the top-right; tab routes switch behind the closing overlay while sheets wait until it closes. Profile is a normal sheet and uses real `town_profiles` plus real activity reads—never fabricated counts.

`ShareCenter` presents the app-wide share reveal in its own `UIWindow`, above tabs and sheets. The preview view is also rendered to the shared image. Add new share types through `SharePayload` factories.

## Design system (`BlockParty/Theme/`)

- `BlockPartyColor` / `Hue`: six neutral tokens (`ink`, `paper`, `surface`, `inkSecondary`, `hairline`, `fill`) plus plum/berry `accent` #8E3B6B. The accent is meaning-scoped to live, active, selected/saved, and primary CTA states—never decorative washes or body copy.
- `BlockPartyFont`: Jost for display/wordmark/headlines and SF Pro for body/UI/data. Use the exact bundled Jost PostScript names; a wrong name silently falls back.
- Brand mark: the lossless master is `docs/brand/source-logo-1254.png` — black "BlockParty." on a yellow field (Sep 19, 2026). `scripts/brand/wordmark.py` derives all three assets from it: the 1024px opaque `AppIcon`, the 880px `LaunchMark` crop, and `Wordmark` (letterforms on alpha, template-rendered). Live surfaces use those exact rasters—never tint, trace, redraw, or substitute the retired wave-figure, lowercase-`bp`, or script-BP variants. `BlockPartyMark` means the app icon; `BlockPartyWordmark` means the logo on our own page.
- `BlockPartyMetrics`: shared radii/shadows, including map float/sheet shadows. `Radius.bento` is intentionally outside the 12/16/20 sequence. It was sized to keep the Calendar Insights boxes and the Today utility tiles identical; Calendar is deleted and the tiles are parked, so `Radius.bento` and `Motion.bentoExpand`/`tilePress` have one consumer left. Keep them — they are the spec the parked tiles rebuild against.

Do not hardcode a hex or spacing value at a view call site when a token or named palette covers it. Controlled raw colours live in role-specific palette/config files: `BlockPartyColor.swift`, `BasemapPalette.swift`, `WeatherBackground.swift`, and utility gradient definitions; logo fallback art and the garbage-truck illustration are content exceptions. Do not make the basemap grayscale; that experiment was reverted because landmarks disappeared. Category is carried by glyph, while live/active/selected state may use the accent.

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
