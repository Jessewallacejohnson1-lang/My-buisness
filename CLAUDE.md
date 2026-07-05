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

**DEBUG-only launch arguments** (for headless screenshot verification, no UI driving needed):
- `-open-tab map|activities|calendar` — start on a given tab (`MainTabsView.initialTab()` in `App/RootView.swift`).
- `-force-nonadmin` — force the non-admin branch so admin-gated UI (the map "+") can be verified without a second account (`SJMapView.isAdmin`).
- `-explore-filter events|clubs|trails` — start the Activities ("Explore") tab on a given category chip so each card state can be screenshotted headlessly (`ActivitiesView.initialFilter()`).
- `-explore-timeframe today|week|month|upcoming` — start the Explore tab with a given event time-frame filter applied (`ActivitiesView.initialTimeFrame()`).

### First-checkout setup — required or the build fails
- **`Hygge/Config/MapboxConfig.swift` is gitignored** (it holds the Mapbox token) — a fresh clone must recreate it: `let MAPBOX_ACCESS_TOKEN = "pk...."`. Without it the map is blank / the build won't link the token.
- **`.impeccable/` build hazard:** the "impeccable" tool drops `.impeccable/hook.cache.json`. If one lands **inside** the `Hygge/` file-system-synchronized group, Xcode copies duplicate `hook.cache.json` into the bundle and the build fails with **"Multiple commands produce …"**. Fix: `find Hygge -type d -name .impeccable -exec rm -rf {} +`. (`.impeccable/` is gitignored.)

## Architecture

`HyggeApp` (`@main`) registers fonts, sets the Mapbox token, injects `AuthStore.shared`, and renders `RootView`, which is the **auth gate**: `booting` → splash; signed-in → onboarding (first run) or `MainTabsView`; signed-out → `LoginView`. `MainTabsView` is four tabs (`Tab`: home/activities/calendar/map) under a custom frosted `HyggeTabBar`, plus a global "+" composer sheet.

### Backend — hand-rolled, no Supabase SDK (`Hygge/Backend/`)
The entire backend is written by hand over `URLSession` to match `@hygge/core` 1:1 — there is **no `supabase-swift` dependency**.

- **`SupabaseHTTP`** — the low-level client: `auth(...)` hits GoTrue (`/auth/v1`), `rest(...)` hits PostgREST (`/rest/v1`). Both send the public `apikey` + a `Bearer` token; PostgREST calls take a fresh access token and an optional `Prefer` header.
- **`AuthStore`** (`@MainActor`, singleton `.shared`) — the single auth source: email + password (confirmation ON), **Keychain-persisted `Session`**, and **coalesced token refresh** (GoTrue rotates the refresh token, so concurrent refreshes funnel through one in-flight task; a hard failure clears the session and routes back to Login). Always get tokens via `validAccessToken()`.
- **`CommunityAPI`** — the domain API (events, RSVPs, clubs, quests, trails), mirroring the Expo `createCommunityApi`. `Admin.isAdmin(email)` gates admin writes (self-approved events).
- **`RealtimeClient`** (`@MainActor`) — a **hand-written Phoenix-channel client** over `URLSessionWebSocketTask` (Supabase Realtime speaks Phoenix `vsn=1.0.0`). Joins `postgres_changes` on `club_events` with the user's JWT (RLS still filters what arrives), heartbeats, pushes a fresh token periodically, and reconnects with capped exponential backoff. See `SupabaseConfig.realtimeURL`.
- **`SupabaseConfig`** — project URL + **public anon key** (safe to ship; RLS is the real boundary) and the derived `rest/auth/storage/realtime` URLs.
- Supporting: `Session`, `Storage` (image upload), `Moderation` (Claude edge function), `Reminders`, `Interests`, `TrailServices`, `KnownVenues`, `DateHelpers`, `Models`.

### Features — one folder per screen, `View` + `Model` (`Hygge/Features/`)
The house pattern is a `SomethingView` paired with a `SomethingModel` (`@MainActor final class … ObservableObject`) that owns state + API calls. Folders: `Home`, `Activities`, `Calendar`, `Add`, `Map`, `Auth`, `Onboarding`, `Place`, `Components`.

**The Map (`Features/Map/`)** — the most involved feature, and where the realtime pipeline lives:
- **`SJMapView`** — the Mapbox map, spot markers, live pulse, bottom detail card, and the chrome (recenter + admin "+"). `isAdmin` gates the "+".
- **`MapModel`** (`@MainActor`) — owns the `RealtimeClient` subscription + today's events. A `club_events` change touching **today** triggers a 300 ms-debounced re-sync (`getTodayEvents()`), so a new happening lights its pin and a deleted/ended one goes quiet **with no refresh**. Handles teardown, background socket-drop + foreground resubscribe, and the **midnight rollover**.
- **`MapSpots` / `KnownVenues`** — the **curated venue coordinates** (mirrors the Expo `lib/geo.ts`). Never trust a runtime geocoder for a known St. Joe venue — resolve here first; geocoding is only the fallback for unknowns.
- **`QuickAddSheet`** — admin-only bottom sheet to post an event straight onto the map (title, spot picker, date, time) → inserts an approved `club_events` row → the realtime pipeline lights the pin.

### Design system (`Hygge/Theme/`) — ported from the Expo app
- **`HyggeColor`** (`Hue.*`) — warm linen palette: `paper*` surfaces, `ink`/`ink2`/`ink3` text, and **accents with one job each** — `moss` (positive/primary), `sky` (brand/focus), `honey` (warmth), `clay` (warning). Plus a **Map visual system**: `Hue.accent` **coral (#FF6B57)** appears **only** on live indicators + primary/tappable elements; everything else is `surface`/`gray`/`mapInk`.
- **`HyggeFont`** — `registerHyggeFonts()` + `Font.display/…` helpers. Strict roles (display / body / mono), mirroring the RN font rules; **every number is mono**.
- **`HyggeMetrics`** — the shadow + metric tokens (e.g. `mapFloatShadow`, `mapSheetShadow`).

Do **not** hardcode hex/spacing that a `Hue`/metric token already covers. The only allowed raw hexes in the map are the three Mapbox base-map cartography colors.

## Conventions & gotchas

- **On-brand bar** (inherited from the Expo app): warm, calm, quiet, neighborly, hyper-local. No badges/streaks/feeds/notification-spam. **Real data only — never seeded/inflated counts.** Voice is a neighbor, not a brand.
- **Live-glow is for *now*, not "today".** A pin pulses only while an event is happening (`start ≤ now ≤ start + 2h`, `DateHelpers.isLiveNow`). Coral is reserved for live/tappable.
- **Dates are user-timezone.** Use `DateHelpers.localDate()` / `nowMinutes()` (pinned to `TimeZone.current`); never derive "today" from a UTC ISO string.
- **Realtime DELETE carries only the primary key.** A DELETE's `old_record` contains just `id` — match deletes by `id` (a full refetch is idempotent). The table is set to `REPLICA IDENTITY FULL` and `club_events` is in the `supabase_realtime` publication (both already applied to the live project; see `MAP_BUILD_LOG.md`).
- **Admin is an email allowlist**, not a security boundary — `Admin.isAdmin` in `DateHelpers.swift` (self-approved events are an intentional product decision shared with the Expo app). RLS is the real boundary.
- **`MAP_BUILD_LOG.md`** is the running, chronological record of map work (fixes, the realtime pipeline, the anti-slop pass, applied SQL). Continue it when doing map work; it's the source of truth for what's been verified.
