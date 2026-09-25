# Architecture

Read this before adding a file, changing a screen, or deciding where a new feature's shape
belongs.

## Project

**Block Party** — a native **SwiftUI + Mapbox** iOS app for the real town of **St. Joseph,
MN**. It is a **native port of the Expo / React Native app** in a separate repo at
`~/Documents/my-business/apps/mobile`.

> **The app is mid-rebuild.** The 2026-09-17 strip-down emptied Today, gutted two tabs to
> reserved blank slots, and moved the map off the tab bar. Parts of these rule files describe
> surfaces that no longer render. **`docs/GUTTING-LEDGER.md`** is the record of what went,
> why, and how to recover it — open it when something is missing, not as background.

- **Project, scheme, bundle id and deployment target:** `docs/rules/identifiers.md`.
- **Only SPM dependency:** [`mapbox-maps-ios`](https://github.com/mapbox/mapbox-maps-ios).
- **Shared backend:** the same Supabase project as the Expo app. The two apps are
  backend-twins — schema, RLS and query semantics match `@hygge/core` in the Expo repo.
  **Keep design tokens and query behaviour in sync with that repo** `[prose]`; each Swift
  source that ports a JS file says so in its header.

### Three-repo rule

This is the **native iOS / map** codebase, and it is the **spec** the other two are ported
from. Map, Mapbox and native-iOS work happens **here**.

- **Expo / React-Native / web** — `~/Documents/my-business`. RN and web work happens there.
  The two look nearly identical on the simulator; this app's first tab is **Town**, the Expo
  app's is **Home**.
- **Android (Kotlin / Jetpack Compose)** — `~/Documents/block-party-android`. Port target.

### Android port rule — do it without being asked

**After changing any SwiftUI screen in this repo, port the change to the Android repo in the
same session.** `[prose]` Do not wait for a request and do not ask whether the port is
wanted; it is. Treat an un-ported iOS change as unfinished work, and report the port in the
same summary as the iOS change: which screen, which Kotlin files, and whether the
side-by-side screenshot check was run.

Before writing Kotlin, read `~/Documents/block-party-android/CLAUDE.md` — it holds the stack,
the Swift→Kotlin translation rules (spring-curve conversion, `matchedGeometryEffect` →
`SharedTransitionLayout`, blur → Haze) and the screenshot verify loop. Follow it rather than
improvising a translation.

Two things are never ported:
- **Server-side logic.** `[prose]` Both apps call the same Supabase project and the same edge
  functions. Kotlin calls them; it never re-implements them.
- **Screens that are mid-rebuild.** `[prose]` A surface being actively gutted or rebuilt is
  ported once it settles, not on every intermediate commit. Note the skip in your summary so
  it is visible rather than silent. *(Delete this bullet to make the rule unconditional.)*

## The shell

`BlockPartyApp` (`@main`) registers fonts, sets the Mapbox token, installs the
unauthorized-response handler, injects `AuthStore.shared`, optionally runs the DEBUG place
seeder, and mounts `RootView` directly.

- **There is no splash** (Jesse, 2026-09-18). `LaunchScreen.storyboard` is bare `Hue.paper`
  with no mark, so frame zero and the app's first real frame are the same colour and the
  hand-off is invisible.
- **Sign-in is switched OFF** (Jesse, 2026-09-18, "for now"): `RootView.requiresSignIn =
  false`, so the gate hands straight to `MainTabsView` with or without a session. **It is a
  switch, not a deletion** `[prose]` — `LoginView`, `AuthStore`, the keychain session and
  every authed API path are untouched; flip it back to `true` and sign-in returns as it was.
  Signed out, the app is honest rather than broken: authed reads fail into their own empty
  states, the profile tab reads "Add your name" with zeroed counts, and its **Sign out** row
  is hidden.
- **The target uses a checked-in `BlockParty/Info.plist`**, not `GENERATE_INFOPLIST_FILE`,
  with a file-system-synchronized **membership exception** so the plist isn't also copied as
  a bundle resource. `[prose]`

### The tab bar

`MainTabsView` owns **four** tabs (`Tab`: town/daily/business/you), the custom
`BlockPartyTabBar`, the full-screen map cover, and town-menu presentation. **Town** (`house`) is the town feed, **Daily** (`newspaper`) is the personalised paper
(town feed ∩ what the neighbour follows), **Business** (`briefcase`) is the owners' side of
Main Street — not a shopfront directory — and **You** mounts `ProfileView(showsClose: false)`,
since a tab has no close.

- **Daily and Business render `BlankTab` deliberately** — the slot's name plus its one-line
  promise — because the bar and its motion are built and the screens are not. **Do not "fix"
  that by deleting the cases.** `[prose]`
- **The bar is four equal slots built from `Tab.allCases`** `[test]`, pinned by
  `TabBarTests`. The centre Create disc was removed on 2026-09-24 when posting was paused,
  so **there is no compose entry anywhere in the app** — not in the bar, not on the map, not
  in the town menu. Do not add one back without Jesse saying posting is on again.
- **Every tab carries `.accessibilityShowsLargeContentViewer()`** `[prose]` — the long-press
  enlargement that frozen chrome owes the reader. Labels keep
  `.lineLimit(1).minimumScaleFactor(0.85)` so the bar's height holds instead of wrapping.
- **The map is not a tab.** `SJMapView` is presented as a `.fullScreenCover` from the Town
  top bar's map button, so it carries its own close and owns its own state.

### Backend — hand-rolled, no Supabase SDK (`BlockParty/Backend/`)

The entire backend is written by hand over `URLSession` to match `@hygge/core` 1:1 — there is
**no `supabase-swift` dependency**. `[prose]`

- **`SupabaseHTTP`** — the low-level client: `auth(...)` hits GoTrue (`/auth/v1`), `rest(...)`
  hits PostgREST (`/rest/v1`).
- **`AuthStore`** (`@MainActor`, singleton `.shared`) — the single auth source: email +
  password, **Keychain-persisted `Session`**, and **coalesced token refresh** (GoTrue rotates
  the refresh token, so concurrent refreshes funnel through one in-flight task). **Always get
  tokens via `validAccessToken()`.** `[prose]`
- **`CommunityAPI`** — the domain API (events, RSVPs, clubs, quests, trails), mirroring the
  Expo `createCommunityApi`, plus the per-user "My activity" reads behind the profile.
- **`ProfileAPI`** — the community-profile layer over **`town_profiles`** (own-row RLS).
  **Community identity lives in `town_profiles`, NOT the wellness app's `profiles` table**
  `[prose]` — the shared Supabase project backs two apps, and `profiles` belongs to the other
  one.
- **`RealtimeClient`** (`@MainActor`) — a hand-written Phoenix-channel client over
  `URLSessionWebSocketTask`. Joins `postgres_changes` on `club_events` with the user's JWT
  (RLS still filters what arrives), heartbeats, and reconnects with capped exponential
  backoff. **One production subscriber** since the strip-down: `MapModel`. `YourDayLogic.
  changeIsRelevant` and its tests survive the module that used to be the second — copy that
  shape if a subscriber comes back.
- **`SupabaseConfig`** — project URL + **public anon key** (safe to ship; RLS is the real
  boundary) and the derived `rest`/`auth`/`storage`/`realtime` URLs.
- Supporting: `Session`, `Storage`, `Moderation`, `Reminders`, `Interests`, `TrailServices`,
  `KnownVenues`, `DateHelpers`, `Models`, `LocationPermission` + `UserLocation`.

## Features — one folder per screen, `View` + `Model` (`BlockParty/Features/`)

The house pattern is a `SomethingView` paired with a `SomethingModel` (`@MainActor final
class … ObservableObject`) that owns state and API calls. Top-level folders: `Home`, `Add`,
`Auth`, `Board`, `Civic`, `Components`, `Map`, `Onboarding`, `Place`, `Profile`, `Share`.

- **`Civic/Parked/` is unreferenced on purpose and must not be swept up as dead code.**
  `[prose]` It has its own README; read it before touching anything under it. The utility
  subsystem lives verbatim and still tested under `Features/Civic/Parked/Utility/`, and
  `user_utility_prefs` still holds real per-user configuration that a rebuild must re-hydrate.
- **If onboarding is rebuilt, `ONBOARDING.md` is the spec — read it first.** `[prose]` Its
  locked rule: the primary CTA occupies one fixed position for the whole flow and never moves
  between steps (only its title and enabled state change), with the shell owning the chrome
  and footer so step views cannot draw their own button. `Onboarding/` survives today only
  because `MapIntroView`, `InterestPickerView` and `OnboardingChrome.swift` live there.

### Town feed (`Features/Home/Briefing/` + `Feed/`) — empty by design

The strip-down deleted every module that used to render here. What remains is chrome:
`HomeView` is a compatibility shell over `FeedView`, which still holds `TodayTopBar`.

**The machinery under that empty screen is intact and is the point.** `FeedRegistry` still
owns the only production array — now a literal `[]` — and the module protocol, the
phase/visibility contract, the erased-view renderer and the order/offset tie-break all still
work. **Adding a module back is one entry in that literal and nothing else** `[prose]`;
`FeedView` never changes. `FeedModuleID` keeps its five named constants as stable names for
exactly that, and unknown string-backed ids still decode and are skipped safely.

**The briefing read contract is untouched and still fires.** `BriefingAPI.today()` still makes
one authenticated `POST` to `rpc/get_today_briefing`; the model still paints the disk cache
first, reconciles with the RPC, keeps cached content through an outage, and owns optimistic
vote/RSVP updates with rollback. **Keep that contract rather than ripping it out** `[prose]` —
a rebuilt module should find its data already there.

**Every `FeedRoute` presents its own sheet.** `[prose]` There is no longer a route with a nil
`destination` that `FeedView` hands to `MainTabsView` for a tab change; the three surviving
cases each carry a destination and open as a modal.

### Town top bar (`Features/Home/TodayTopBar.swift`)

Chrome that **leaves on a downward scroll and comes back on an upward one** (Jesse,
2026-09-21, naming Instagram). The brand mark is **centred against the bar** rather than laid
out in the row — an `HStack` would park it wherever the trailing button's width left it.

- **The bar's height is a constant 58 and must stay one.** `[prose]` It is a `safeAreaBar`,
  so its height IS the feed scroll's top inset. This bar is the live evidence for the
  scroll-geometry loop in `docs/rules/swift-traps.md`.
- **`safeAreaBar`, not `safeAreaInset`.** `[prose]` An inset gets no scroll-edge effect —
  the first attempt shipped content sliding under a bare status bar with no blur at all, and
  the build stayed green.
- **The bar has no fill and draws no hairline.** `[prose]` Content passes underneath it and
  `.scrollEdgeEffectStyle(.soft, for: .top)` blurs and washes that content toward the page.
  Jesse: "no clean cut white line, a fade gradient like Instagram."
- **The rule is DIRECTION, not distance.** `TodayHeader.chromeHidden(wasHidden:previousOffset:
  offset:)` is pure and total — down past `directionThreshold` (4pt) hides, up shows, the
  first `hideAfter` (24pt) and any rubber-band pull past the top always show, and
  sub-threshold jitter holds the current state. `previousOffset` comes free from
  `onScrollGeometryChange`'s old value, so `FeedView` stores only the answer and writes it
  only when it flips — no per-frame invalidation.
- **The chrome is REMOVED when hidden, not faded in place, and it has to be** `[prose]` — the
  glass-compositing rule is in `docs/rules/swift-traps.md`. `TodayTopBar` branches on
  `chromeHidden` inside a fixed-height `ZStack` and animates the `.transition`. Note the
  offset expression it keeps: `contentOffset.y` rests at `-contentInsets.top`, so the
  `+ geometry.contentInsets.top` term is what makes 0 mean "at rest" — drop it and the trace
  reads on the wrong schedule.
- **Chrome that has left must not take taps** `[prose]` — `.allowsHitTesting(!chromeHidden)`
  and `.accessibilityHidden(chromeHidden)` sit on the control row.
- **Three controls, and the two new ones are bare ink in 44pt touch boxes, not discs.**
  `[prose]` A search magnifier leads, the wordmark centres, a notifications bell holds the
  trailing corner, and the map disc sits inboard of it. Bare marks are what the width budget
  allows: a second 50pt disc trailing overlaps the centred lockup on most phones, and a disc
  **leading** trips `TodayHeaderTests.testBrandLockupLeavesTheLeadingHeaderAreaBlank`. Every
  measurement behind that is in `refs/chrome/REFERENCE-SPEC.md`. `TodayBarMetric.inset` is
  the OPTICAL margin and `rowInset` the real padding; the difference is the invisible
  overhang of those touch boxes.
- **The map button is a true circle, 50×50** — the one deliberate exception to this system's
  12pt rounded squares, and big enough to clear the 44pt target on its own.
- **The map disc is a solid `Hue.brandDisc` circle, exactly #FCE804, carrying
  `Hue.onBrandDisc` ink — no glass, no material, no tint** (2026-09-24). `[test]`
  `TodayHeaderTests.testMapDiscIsExactBrandYellow` pixel-samples the colour. The translucent
  `mapWash` disc before it went mustard over photographs, and a Liquid Glass surface
  composites outside its own view's layer, so it arrived and left out of step with the rest
  of the bar.
- **The bar's glyphs are drawn in-house** (`MapPinGlyph`, and `MagnifierGlyph` / `BellGlyph`
  in `Features/Home/BarGlyphs.swift`) because the SF equivalents are different silhouettes,
  not the same shape at another weight. `MapPinGlyph` is a pin outline and a concentric ring
  as **two subpaths of one `Path`**, so a single stroke renders both at identical weight.
  **The bell has no badge**, because the app has no notifications feature to badge honestly.

### Other surfaces

- **Town menu** (`TownMenuView` + `GlassShowcaseOverlay`) — still wired, still **UNREACHABLE
  in the UI**; the avatar was its only entry point, and its "Add an event" row went on
  2026-09-24 with posting, leaving three actions (`TownMenuAction`: map, invite, profile).
  What the drawer alone still reaches is the appearance switch. DEBUG `-open-menu` raises it; re-attaching is a one-line `onMenu`
  hook wherever its next entry point lands.
- **Profile** (`Features/Profile/`) — the **You** tab, and still presentable as a sheet.
  `ProfileView` shows identity plus **real** activity via the My-activity reads — **no
  fabricated counts** `[prose]`, so an empty state reads "0". `EditProfileView` writes
  **server-first** (upload avatar → `ProfileAPI.upsert`) and surfaces a real save failure
  instead of a false success.
- **Share** (`Features/Share/`) — the app-wide **share reveal**. Any share calls
  **`ShareCenter.shared.present(SharePayload(...))`**: a preview card of *exactly what's being
  shared* springs up over a dimmed backdrop in a dedicated overlay **`UIWindow`** (above the
  tab bar **and** any `.sheet`), with a target row (Messages · Save image · More). **The
  preview view is also what's rendered to the shared image** — what you see is what you send.
  **Add a new share in one line** via a `SharePayload` factory; preview cards stay
  typographic except for the canonical app mark. The reveal spring is `response 0.58,
  damping 0.76` and the scrim `easeOut 0.40`; **Reduce Motion cross-fades with no scale**.

## Feed content rules

- **The Town feed shows one-time news, not a standing calendar.** `[prose]` **This rule is
  decided but NOT in this branch** — `townSurfacing` and `Features/Home/Feed/FeedSurfacing.swift`
  live only on the unmerged branch `feat/tab-town` (commit `8e52b7a`), so do not expect to find
  them here, and do not re-implement them from scratch either: adopt that branch. `dedupeRecurring`
  and `FeedSectioning`, the stages it sits between, *are* here. How it behaves when it lands: A one-time posting is carried on its debut
  day and again from seven days out through the event day; it is hidden in the quiet middle
  and gone after the event. **A recurring series is carried on its debut day only** — a weekly
  club is announced once and must never reappear week after week. The filter is stateless
  date arithmetic, deliberately: there is no per-neighbour "seen" state to sync. `debut` is,
  for a series, the **earliest** `createdAt` in the group — using the surviving occurrence's
  own `createdAt` would re-announce the club every time someone adds another Saturday.
  **Adding a fourth window, or making it per-user, is a product change** — read the Town
  principle in `PRODUCT.md` first.
- **Admin is an email allowlist, not a security boundary** `[prose]` — `Admin.isAdmin` in
  `DateHelpers.swift`. Self-approved events are an intentional product decision shared with
  the Expo app. **RLS is the real boundary.**
