# Architecture

Read this before adding a file, changing a screen, or deciding where a new feature's shape
belongs.

## Project

**Block Party** — a native **SwiftUI + Mapbox** iOS app for the real town of **St. Joseph,
MN**. It is a **native port of the Expo / React Native app** in a separate repo at
`~/Documents/my-business/apps/mobile`.

> **The app is mid-rebuild.** The 2026-09-17 strip-down emptied Today, gutted two tabs to
> reserved blank slots, and moved the map off the tab bar. Parts of these rule files describe
> surfaces that no longer render. **`docs/archive/GUTTING-LEDGER.md`** is the record of what went,
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
- **One `NavigationStack` wraps the whole shell** (`MainTabsView.body`, `RootView.swift`)
  `[prose]`, with `.navigationDestination(for: FeedCardItem.self)` opening the event page,
  so a pushed page covers the tab bar and the edge swipe brings Town back under the finger.
  Its bar is hidden with `.toolbar(.hidden, for: .navigationBar)`, never
  `navigationBarBackButtonHidden`, which kills the swipe; `SwipeBack` keeps the swipe alive
  with the bar hidden (`DECISIONS.md`, 2026-09-26). **Never nest a second `NavigationStack`
  inside a tab or a pushed page:** push onto this one with `NavigationLink(value:)` and add
  a destination beside the existing one. A sheet is its own presentation and may carry its
  own stack.
- **The target uses a checked-in `BlockParty/Info.plist`**, not `GENERATE_INFOPLIST_FILE`,
  with a file-system-synchronized **membership exception** so the plist isn't also copied as
  a bundle resource. `[prose]`

### The tab bar

`MainTabsView` owns **four** tabs (`Tab`: town/daily/search/you), the custom
`BlockPartyTabBar`, the full-screen map cover, and town-menu presentation. **Town** (`house`) is the town feed, **Daily** (`newspaper`) is the personalised paper
(town feed ∩ what the neighbour follows), **Search** is BP's traced magnifier (`MagnifierGlyph`,
thicker when selected, as Instagram's is) — it took Business's slot on 2026-09-29, when the
Town bar's leading control became a friends mark — and **You** mounts
`ProfileView(showsClose: false)`, since a tab has no close. Business has no slot for now.

- **Search** (`Features/Search/`, 2026-10-02) is Jesse's Search mockup v7 and its Figma
  frames: a field and filter pills over sideways rows (People, Businesses, Restaurants,
  Coffee, Clubs) of the Town's places from Supabase `places`. Its model lives in
  `MainTabsView` so the places aren't fetched again on every visit. A row's title pushes
  its whole list onto the shell's stack (`SearchShelf`, declared in `SearchPage`). A
  business logo opens `BusinessPage`, an overlay inside the tab, under the tab bar,
  driven by one spring value (`LiveSpring`) so a drag can grab it mid-flight. Logos come
  from Storage through `places.search_logo` (`DECISIONS.md` 2026-10-02, moved 2026-10-08)
  and load through `POILogoCache`, the map pins' cache; restaurant and business
  photos are Google's, each with its `PhotoCredit`. People, events and clubs are DEBUG
  samples until their reads exist; a release build leaves those rows and pills out.
- **Daily** (`Features/Daily/DailyPage.swift`) shows its page
  when it has something real to show and `BlankTab` otherwise: DEBUG shows a sample
  Spotlight, release keeps the placeholder until the Spotlight read exists. Its spec is
  `docs/plans/daily-tab/SPEC.md` in the BP app folder; sections join one at a time.
- **The bar is four slots built from `Tab.allCases`** `[test]`, pinned by
  `TabBarTests`. The centre Create disc was removed on 2026-09-24 when posting was paused,
  so **there is no compose entry anywhere in the app** — not in the bar, not on the map, not
  in the town menu. Do not add one back without Jesse saying posting is on again.
- **It is BP's own bar, not Apple's `TabView`, copying Instagram's iOS 26 bar with BP's
  icons** (2026-09-27; Apple's `TabView` was rejected on 2026-09-25, the why is in
  `DECISIONS.md`). One floating glass capsule, the same gap from each side and from the
  physical bottom edge. **Every size, inset, scale and timing is a `TabBarMetric` constant**
  (`RootView.swift`), capsule-local, with its source in its comment; the slot rule is
  `[test]` pinned. Change a number there, not in a doc. **It never hides, but it shrinks**
  to `TabBarMetric.compactScale` while the Town feed reads down, on the same signal that
  sends the top bar away (`TabBarCompactKey`), and a finger on it brings it back.
- **The glass stays light and the ink never changes.** `[prose]` `.glassEffect(.regular)`
  sits on a white underlay (`TabBarMetric.glassUnderlay`), without which it flips dark over
  a near-black photo. Icons are `Hue.ink.onLightCanvas` (#111111), never adaptive
  `Hue.ink`, which drew white on flipped glass. Removing either brings the flip back.
- **Icons only, all one ink; the selected icon is its filled symbol** `[test]`, over the
  sliding Selection bubble (translucent black). No labels, no yellow, no bounce, no colour
  animation (Jesse, 2026-09-27). **You** draws the neighbour's photo when there is one
  (`TabAvatar`), the person icon otherwise.
- **One touch drives the bar; there are no per-tab `Button`s.** `[prose]` On touch-down the
  grey bubble gives way to a clear glass Lens at Apple's Lens size, lighter than the bar as
  Instagram's is, that follows the finger; icons near it magnify, and the bar swells and
  lightens (Apple's interactive glass, plus a thicker white layer under it). On
  release the grey bubble takes over in the same frame and slides to the picked tab. Release picks the tab nearest the
  finger's x `[test]`; there is no cancel zone, because Apple's bar has none. The haptic
  and the page slide stay in `MainTabsView.select`. Reduce Motion drops the Lens, growth,
  magnification and swell, and the bubble crossfades to the new tab.
  **Never animate `.glassEffect` across the bar** `[prose]`: glass draws at its final layout
  position, so a glass Lens riding the bubble's spring jumped to the finger while the bubble
  slid (2026-09-26). The Lens works because it is placed straight at the finger and never
  travels: the sliding is the grey bubble's job. It also stays mounted at zero size between
  touches, because glass inserted fresh drew two frames late (2026-09-27).
- **Each tab is one VoiceOver element with its own action** (synthetic children of an
  `.isTabBar` container), **and each slot keeps `.accessibilityShowsLargeContentViewer`**
  `[prose]` — the long-press enlargement that frozen chrome owes the reader. **The icons are
  frozen** (`Font.glyph`), like Apple's; nothing scales them with the text size.
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

### Town feed (`Features/Home/Feed/`)

The Town tab's list of everything coming up in the Town, in an order worked out for each
person (BP app `docs/plans/town-feed`). `HomeView` is a compatibility shell over `FeedView`,
which holds `TodayTopBar` and the feed.

- **What is in it and in what order is the database's** `[test]`: `get_town_feed`
  (`supabase/migrations/20261008120000_town_feed.sql`, stories in `supabase/tests/`) applies
  ticket 05. Approved events from their show-from day until they leave (at their end, else 2
  hours after they start, else Town midnight); a series once, at its next date, worded
  "Every 1st & 3rd Monday"; soonest first, the ones you go to last. Android calls the same
  function. **Never filter, re-sort or re-word it in the app** `[prose]`: change the function
  and its tests.
- **`TownFeed` is the app's one module for it** `[test]` (`TownFeedEventsTests`). `MainTabsView`
  holds it, so coming back to Town shows the list it left while it reads again; a failed read
  keeps the list and shows the bar's offline pill; a card goes when its `leaves_at` passes, and
  the feed reads again then and on return to the foreground. Its read is injected: live, DEBUG
  `-town-samples`' sample events, or `-town-offline` (samples kept, every read failing).
- **When the order changes is ticket 11's** `[test]`: a fresh order only on pull to refresh, or
  on coming back after 30 minutes or more away (a launch counts) while still at the top. Any
  other read keeps the order on screen: cards update in place, ones that went drop out, new ones
  wait for the next fresh order. This keeps the database's last order; it never re-sorts.
  Back within 30 minutes the feed lands on the card it left (`topCardID`), which a tab switch
  used to lose. The last list is kept per account on disk (`TownFeedCache`, raw bytes like
  `BriefingCache`), so a relaunch shows it at once, offline too.
- `DailyFeedColumn` shows its items in the order given. Events only for now; posts, updates
  and news join when they exist.

**The module machinery above the feed is intact.** `FeedRegistry` still
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

- **The bar's height is a constant 58 and must stay one.** `[prose]` It is a
  `safeAreaInset`, so its height IS the feed scroll's top inset. This bar is the live
  evidence for the scroll-geometry loop in `docs/rules/swift-traps.md`.
- **`safeAreaInset`, and the bar brings its own soft edge (`StatusEdge`, `BarEdge`).**
  `[prose]` The system's `.safeAreaBar` + `.scrollEdgeEffectStyle(.soft)` flipped the bar dark
  over photos (2026-09-24), and it cannot shrink when the bar leaves: the bar's height is the
  scroll's inset. The edge copies Instagram's, MEASURED (2026-09-29,
  `references/soft-top-edge/SPEC.md` in the BP app folder): the feed is blurred (7.5pt sigma
  at the top) and mixed toward the page (45%), both thinning in a straight line to nothing
  at the bar's lower edge; the photo keeps its colour. Two parts, so the bar's share can
  leave with the bar: the **status edge sits OVER the bar** (always there, ending 4pt below
  the status bar) and the **bar edge sits behind it** only while it floats.
- **Every material blurs ~19pt, so the edge is not a material** `[test]`. It is a stack of
  UIKit blurs, each stopped part of the way in by a paused `UIViewPropertyAnimator`
  (`PartialBlurView`), masked into bands so their sigmas add up to a straight line
  (`EdgeBlur.layers`, `TodayHeaderTests.testStackedBlursThinInAStraightLine`). Two traps:
  the animator must start on the NEXT run-loop turn after the view lands in a window (SwiftUI
  inserts views with UIKit animations off, and the effect jumps to full), and one blur must
  span the whole height (two stacked views meeting mid-edge drew a seam, each blurring only
  its own side). A paused animator never finishes, so XCUITest waits out its 60s idle
  timeout before every step: the UI tests launch with `-ui-tests`, which leaves the blur
  off (finishing the animator at its current point instead drops the blur to nothing).
  `ImageRenderer` draws the UIKit blur as a placeholder.
- **The feed holds the clock black** `[test]` (`AppearanceStore.holdsClock`, set by `FeedView`
  on appear, cleared on disappear). With no colour scheme requested, iOS 26 inks the status
  bar from whatever scrolls under it and the clock went white over dark photos; while held,
  System requests the phone's own scheme, which pins it. Released under a pushed event page,
  whose hero photo keeps the white clock it had (2026-09-27).
- **Out of home the feed CARRIES the bar, 1:1** (Jesse, 2026-09-27, Instagram's header).
  `TodayHeader.homeTravel` is the offset clamped to the bar's 58pt: the controls move up by
  it and fade with it, riding up under the status edge, which blurs and pales them on the
  way out as Instagram's header is. It reaches the bar through an `@Observable` box
  (`BarTravel`) that only the bar reads, so the feed's body does not re-run per frame.
  Carried its full height, the bar leaves WITHOUT the slide (`FeedView` sets that state in
  a transaction with animations off): animated, it snapped back to rest as it started
  floating and slid out again over the first post.
- **Past that, the rule is DIRECTION, not distance.** `TodayHeader.chromeHidden(wasHidden:
  floating:anchor:offset:)` is pure and total: inside `hideAfter` (the bar's own height) and
  any rubber-band pull it always shows; a bar carried its full height out of home counts as
  away at once; a floating bar hides after `flipDistance` (12pt) of one-way travel down and
  comes back after 12pt up, and jitter holds the current state. `FeedView` writes each state
  only when it flips.
- **The chrome is REMOVED when hidden, not faded in place, and it has to be** `[prose]` — the
  glass-compositing rule is in `docs/rules/swift-traps.md`. `TodayTopBar` branches on
  `chromeHidden` inside a fixed-height `ZStack` and animates the `.transition`. Note the
  offset expression it keeps: `contentOffset.y` rests at `-contentInsets.top`, so the
  `+ geometry.contentInsets.top` term is what makes 0 mean "at rest" — drop it and the trace
  reads on the wrong schedule.
- **Chrome that has left must not take taps** `[prose]` — `.allowsHitTesting(!chromeHidden)`
  and `.accessibilityHidden(chromeHidden)` sit on the control row.
- **Three controls in 44pt boxes, 16pt in from the screen's edges** (Instagram's, measured
  2026-09-27). `[prose]` A friends mark leads (search until 2026-09-29, when it became a tab),
  the wordmark centres, a notifications bell holds the trailing corner, and the map disc sits
  inboard of it. Friends and the bell are
  **bare ink at home and sit in frosted circles while the bar floats** over the feed
  (`TodayHeader.chromeFloating`: from the moment the bar leaves mid-feed until the feed is
  home again) — a material circle, not Liquid Glass, so it slides and fades with its mark
  (see the glass rule in `docs/rules/swift-traps.md`). A disc **leading** trips
  `TodayHeaderTests.testBrandLockupLeavesTheLeadingHeaderAreaBlank`.
- **The map button is a true circle, 44×44** (Instagram's button size, Jesse 2026-09-27;
  50 before) — the one deliberate exception to this system's 12pt rounded squares.
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
  The one exception is the friends mark: it is Apple's `person.2.fill` itself, because Jesse's
  Reference is that symbol (they differ by ~1px of antialiasing), so there is nothing to trace.

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

- **The Town feed's rules live in `get_town_feed`, not in the app.** `[prose]` They are BP app
  `docs/plans/town-feed/issues/05-eligible.md` (Jesse, 2026-10-08), and they replace the old
  "one-time news, not a standing calendar" rule and `feat/tab-town`'s `townSurfacing`: do not
  adopt that branch. `dedupeRecurring` and `FeedSectioning` are the old posting pipeline, used
  only by DEBUG previews. Two decided rules wait on data: City meetings stay in until people
  can follow the City, and the ZIP check waits until events carry a ZIP or a Place.
- **Admin is an email allowlist, not a security boundary** `[prose]` — `Admin.isAdmin` in
  `DateHelpers.swift`. Self-approved events are an intentional product decision shared with
  the Expo app. **RLS is the real boundary.**
