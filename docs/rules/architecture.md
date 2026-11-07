# Architecture

Read this before adding a file, changing a screen, or deciding where a new feature's shape
belongs.

## Project

**Block Party** — a native **SwiftUI + Mapbox** iOS app for the real town of **St. Joseph,
MN**. It began as a port of an Expo / React Native app, retired on 2026-11-02 (Jesse); nothing
is kept in sync with it any more.

> **Something missing?** `docs/archive/GUTTING-LEDGER.md` records every surface that was deleted,
> why, and how to get it back. Open it when something is missing, not as background.

- **Project, scheme, bundle id and deployment target:** `docs/rules/identifiers.md`.
- **Only SPM dependency:** [`mapbox-maps-ios`](https://github.com/mapbox/mapbox-maps-ios).
- **Backend:** one Supabase project (`docs/rules/identifiers.md`), shared with the Android
  port to come.
- **A migration file is made with `supabase migration new <name>`** `[script]`, which stamps the
  version to the second; `apply_migration.py` refuses a new round or future version, and a version
  another worktree already holds (2026-10-25, two chats both took 20261025235000).
- **A migration goes live through `scripts/apply_migration.py <file> --apply`** `[script]`, after
  Jesse's yes. It refuses a branch behind main, a taken version, and a function that is different
  live from main's newest copy: another chat applied a change that isn't on main, and remaking
  the function from the repo would undo it (2026-10-17, the friends lift).

### Other repos

This is the **native iOS / map** codebase and the **spec** the Android app is ported from.

- **Android (Kotlin / Jetpack Compose)** — `~/Documents/block-party-android`. **The port waits
  until iOS is done (Jesse, 2026-11-02): don't port iOS changes to it as you go.** `[prose]`
  When it resumes, read that repo's `CLAUDE.md` first. Server-side logic is never ported:
  Kotlin calls the same Supabase functions; it never re-implements them.

## The shell

`BlockPartyApp` (`@main`) registers fonts, sets the Mapbox token, installs the
unauthorized-response handler, injects `AuthStore.shared`, optionally runs the DEBUG place
seeder, and mounts `RootView` inside `LaunchHost`.

- **The launch** (Jesse, 2026-11-01, reversing 2026-09-18's no splash; BP app
  `references/launch-ball/`): on a fresh process start the Town's round logo bounces off Bp,
  lands as the !'s dot, the ! hops as the Daily tab's does, and Bp! lands on the tab bar's own
  (or zooms through over Welcome). `LaunchScreen.storyboard` is its first frame: BP yellow with
  "Bp" at 90%. The app loads underneath from the first frame and never waits on it; a tap
  skips it, Reduce Motion fades it, UI tests skip it (`-ui-tests`) unless they ask
  (`-launch-play`), and the app shows within 6 s whatever happens. The math is
  `LaunchMotion`, the drawing `LaunchBall`. Back within 10 minutes of iOS shutting the app down
  it doesn't play, and the app opens as you left it (`LeftOff`, BP app backlog 21).
- **Nobody gets past the Welcome without an account** (Jesse, 2026-11-02, BP app onboarding 27;
  sign-in was off from 2026-09-18). `RootView` shows onboarding until `AuthStore.hasAccount`, a
  session that isn't a quiet anonymous one: the Welcome's Continue with email opens Create account,
  its Log in opens Log in (`LoginView.swift`, the same screen), and the account is made before the
  first question. Log in reads Your profile: an account with `onboarded_at` goes straight to the
  tabs, any other to Name. No account once the launch has looked (`AuthStore.booting`), by sign-out
  or a token the server turned down, resets onboarding to a clean Welcome
  (`OnboardingStore.reset`). DEBUG `-skip-onboarding` and `-ui-tests` let screenshot runs and UI
  tests in with no account, where a tap that needs a real account does nothing. A neighbour's code
  opened from the camera is caught above the gate (`RootView`, `WaitingCode`) and held in memory
  until the tabs can open it; opened with no account, its friend request goes by itself. "Come back when you're 13"'s Close deletes the account it made
  (`delete_my_account()`).
- **No more quiet anonymous accounts** (2026-11-02). From 2026-10-09 every install made one
  (`ensureAccount`); phones that still hold one keep `isAnonymous` true and land on the Welcome.
  **Anonymous accounts act but never publish** `[test]`: restrictive `is_real_account()` rules
  stop them posting events, starting clubs, commenting and uploading photos
  (`supabase/migrations/20261009220000_anonymous_accounts.sql`, stories in `supabase/tests/`).
  **Unsigned simulator builds (bp-build's `xc.sh`) can't use the Keychain** (-34018, no
  entitlement): there the session lives in UserDefaults (`Keychain.simulatorKey`), so it
  survives relaunches but not eyes.py's uninstall.
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

`MainTabsView` owns **five** tabs (`Tab`: town/blockParty/friends/search/you), the custom
`BlockPartyTabBar` and the full-screen map cover. **Town** (BP's house, `HouseGlyph`) is the
town feed, **Block Party** (Daily until BP app five-tabs 04; the app icon's Bp!, `DailyMark`, solid picked or
not: Jesse, 2026-10-29) is the personalised paper (town feed ∩ what the neighbour follows), **Friends** (`person.2`) is
neighbours, requests and Groups (`FriendsHomePage`; a page pushed from the Town bar until
2026-11-01), **Search** is BP's traced magnifier (`MagnifierGlyph`, thicker when selected, as
Instagram's is), and **You** mounts `ProfileView`, your own Profile (BP app five-tabs 03).
Business has no slot.

- **Search** (`Features/Search/`, 2026-10-02) is Jesse's Search mockup v7 and its Figma
  frames: a field and filter pills (All, Businesses, Events, Parks: BP app five-tabs 04). With
  nothing typed under All it shows `SearchAtRest`: a row for the part of the day (today's Events
  and the places open now), New in St. Joseph (the week's new Events) and Around town, Instagram's
  Explore grid dealt again each visit. Its Events are the Town feed's cards (`TownFeed.cards`,
  read there when Search opens first), its places Supabase `places`. Its model lives in
  `AppSession` so the places aren't fetched again on every visit. A row's title pushes
  its whole list onto the shell's stack (`SearchShelf`, declared in `SearchPage`). A
  business logo opens `BusinessPage`, an overlay inside the tab, under the tab bar,
  driven by one spring value (`LiveSpring`) so a drag can grab it mid-flight. Logos come
  from Storage through `places.search_logo` (`DECISIONS.md` 2026-10-02, moved 2026-10-08)
  and load through `POILogoCache`, the map pins' cache; restaurant and business
  photos are Block Party's own (`place_photos`), each with its `PhotoCredit`. Groups and
  people have no row or pill (they live on Friends), but typing under All finds the Town's
  Groups (`get_groups`) and neighbours with a real account and a name (`search_neighbors`),
  listed after the places and never saved to Recent.
- **Chat** (`Features/Chat/`, `Backend/ChatAPI.swift`, BP app five-tabs 05): the paper plane at the top
  right of Friends opens Messages, then a chat: text, a photo or an Event, one friend or a group of friends.
  Who is in what is `private.chats` and `private.chat_members`; every write is a function
  (`send_chat_message` and its neighbours) and every read the app makes too. **Strangers:** friends write
  freely; someone else's first message waits in Requests, one text until accepted, and Delete is remembered;
  a direct chat with anyone under 18, or with no birthday, needs a friendship, and what's sent without one is
  `held`, seen only by its sender, who isn't told (Jesse, 2026-11-03). Block, Hide and Leave are in the
  messages' read rule itself. Photos are in the private `chat-photos` bucket, read through links signed for an
  hour. No push yet: a closed app learns nothing until it opens. Delete account (the `delete-account` edge function)
  removes a person's photos, except one a chat report still open names. **Rooms:** a Going chat (five-tabs 06) and a Group chat
  (five-tabs 07) are worked out live from Going and `club_members`, so leaving leaves the chat. Their `chat_members` row
  holds only your read position and your Leave and admits no one: a new kind of room must stay out of `private.in_chat`'s
  member branch and `get_chats`' `others`, or everyone who ever opened it stays in and is listed.
- **The Block Party tab** (`Features/Daily/DailyPage.swift`) shows its page
  when it has something real to show and `BlankTab` otherwise: DEBUG shows a sample
  Spotlight, release keeps the placeholder until the Spotlight read exists. Its spec is
  `docs/plans/daily-tab/SPEC.md` in the BP app folder; sections join one at a time.
- **The bar is five slots built from `Tab.allCases`** `[test]`, pinned by
  `TabBarTests`. The centre Create disc was removed on 2026-09-24. Posting came back on
  2026-11-01 through the Town bar's + (New event, BP app town-plus); there is no compose
  entry in the tab bar or on the map.
- **It is BP's own bar, not Apple's `TabView`, copying Instagram's iOS 26 bar with BP's
  icons** (2026-09-27; Apple's `TabView` was rejected on 2026-09-25, the why is in
  `DECISIONS.md`). One floating glass capsule, the same gap from each side and from the
  physical bottom edge. **Every size, inset, scale and timing is a `TabBarMetric` constant**
  (`TabBar.swift`), capsule-local, with its source in its comment; the slot rule is
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

The entire backend is written by hand over `URLSession` — there is **no `supabase-swift`
dependency**. `[prose]`

- **`Supabase`** (in `SupabaseHTTP.swift`) — the one client for PostgREST (`rest`, `rpc`),
  Storage (`upload`) and edge functions (`invoke`) (BP app codebase-health 16). It holds the
  token, the signed-in check (`userID`), the decoder, the percent-encoding of every query value,
  and the 401 hook (`TokenProviding.handleUnauthorized`). It sends through `Send`: `.live`, the
  test's `FakeServer` (`BlockPartyTests/FakeTokenProvider.swift`), or `.offline`. **Never build a
  Supabase request anywhere else.** `[prose]` `SupabaseHTTP.auth(...)` still hits GoTrue
  (`/auth/v1`) for `AuthStore`.
- **`AuthStore`** (`@MainActor`, singleton `.shared`) — the single auth source: email +
  password, **Keychain-persisted `Session`**, and **coalesced token refresh** (GoTrue rotates
  the refresh token, so concurrent refreshes funnel through one in-flight task). **Always get
  tokens via `validAccessToken()`.** `[prose]`
- **`CommunityAPI`** — the domain API (events, RSVPs, clubs, quests, trails), plus the
  per-user "My activity" reads behind the profile.
- **`ProfileAPI`** — the community-profile layer over **`town_profiles`** (own-row RLS).
  **Community identity lives in `town_profiles`, NOT the wellness app's `profiles` table**
  `[prose]` — the shared Supabase project backs two apps, and `profiles` belongs to the other
  one.
- **`RealtimeClient`** (`@MainActor`) — a hand-written Phoenix-channel client over
  `URLSessionWebSocketTask`. Joins `postgres_changes` on `club_events` with the user's JWT
  (RLS still filters what arrives), heartbeats, and reconnects with capped exponential
  backoff. **One production connection, held by `LiveGames`** (BP app codebase-health-2 08):
  it keeps every game's newest score while a held game is played (the Town feed's list on
  screen, an open Event page from any tab), and hands every change to `MapModel` while the map
  is open, which asks `ClubEventRelevance.matters` whether it is worth a re-read (a new follower
  passes its own days to the same rule). Never open a second `RealtimeClient` on `club_events`.
  Chat has its own (BP app five-tabs 05): `ChatBook` holds one on `chat_messages` and `chat_reads` while
  the app is open and reads again on anything it hears, and an open chat joins a private Broadcast
  channel, `chat:<id>`, for its typing dots. **Realtime sends a DELETE to everyone subscribed, past the
  read rule, with the row's primary key:** a table in the publication never has a key that says anything
  (`chat_reads` has its own id for this reason). A column no client should see isn't granted, since
  Realtime sends what the role may select (`chat_messages.held`).
- **`SupabaseConfig`** — project URL + **publishable key** (safe to ship; RLS is the real
  boundary) and the derived `rest`/`auth`/`storage`/`realtime` URLs.
- Supporting: `Session`, `Reminders`, `Interests`, `TrailServices`,
  `KnownVenues`, `DateHelpers`, `Models`, `LocationPermission` + `UserLocation`.

## Features — one folder per screen, `View` + `Model` (`BlockParty/Features/`)

The house pattern is a `SomethingView` paired with a `SomethingModel` (`@MainActor final
class … ObservableObject`) that owns state and API calls. Top-level folders: `Auth`,
`Chat`, `Components`, `Daily`, `Event`, `Follows`, `Friends`, `Groups`, `Town` (the Town tab),
`Launch`, `Map`, `Notifications`, `Onboarding`, `Profile`, `Search`, `Share`, `You`.

- **The parked utility row (`Civic/Parked/`) was deleted on 2026-10-25** (BP app
  codebase-health 09). `user_utility_prefs` still holds real per-user configuration: a Civic
  tab built later must re-hydrate it rather than start from defaults.
  `docs/archive/GUTTING-LEDGER.md` says how to get the code back.
- **Onboarding is on** (BP app onboarding 24, 2026-10-30): a first launch walks its steps
  (`OnboardingFlow`). **`ONBOARDING.md` is the spec — read it before changing it.** `[prose]`
  Its locked rule: the primary CTA occupies one fixed position for the whole flow and never
  moves between steps (only its title and enabled state change), with the shell owning the
  chrome and footer so step views cannot draw their own button.

### Town feed (`Features/Town/Feed/`)

The Town tab's list of everything coming up in the Town, in an order worked out for each
person (BP app `docs/plans/town-feed`). `TownView` holds `TownBar` and the feed.

- **What is in it and in what order is the database's** `[test]`: `get_town_feed`
  (`supabase/migrations/20261008120000_town_feed.sql`, stories in `supabase/tests/`) applies
  ticket 05. Approved events from their show-from day until they leave (at their end, else 2
  hours after they start, else Town midnight); a series once, at its next date, worded
  "Every 1st & 3rd Monday"; soonest first, the ones you go to last. Android calls the same
  function. **Never filter, re-sort or re-word it in the app** `[prose]`: change the function
  and its tests. News leaves at midnight after its date (`board_items.ends_on`, else the day it is
  about), up to 30 days; with neither, after 7 days. A calendar's closing has a future `published_at`, 7 days
  before its day, so it waits with no feed rule of its own.
- **The feed's body is `private.town_feed`** `[test]` (feed-load, 2026-11-01): `get_town_feed`
  only calls it, and `get_event_of_the_day` asks it for just the day's picks and their hosts'
  Events instead of the whole feed. A change to the feed replaces `private.town_feed`; giving
  `get_town_feed` its own body again leaves Event of the day on the old one (a story checks).
  Both are edited in `supabase/town_feed.sql` and each new migration copies that file `[test]`
  (`migration_numbers.test.mjs`; steps in `supabase/README.md`). `get_event_of_the_day` is not in
  it and repeats the feed's start-time patterns, so a change to `start_minutes` changes it too.
- **`TownFeed` is the app's one module for it** `[test]` (`TownFeedEventsTests`). `MainTabsView`
  holds it, so coming back to Town shows the list it left while it reads again; a failed read
  keeps the list and shows the bar's offline pill; a card goes when its `leaves_at` passes, and
  the feed reads again then and on return to the foreground. Its read is injected: live, DEBUG
  `-town-samples`' sample events, or `-town-offline` (samples kept, every read failing). It
  also records views and opens (ticket 20; `DECISIONS.md` 2026-10-13): `TownFeedColumn`
  reports each card crossing half on screen, the shell's Event page route reports an open
  from the Town tab, and the shell sends a batch every 30 s and on going to the background.
  Its sender is injected too: live, or nowhere for tests, previews and the sample modes.
  The feed counts views; the batch waits in `FeedViews` (`feed.views`). Not interested, Mute,
  Report, their Undo and the Muted list are `FeedHides` (`feed.hides`, `FeedHidesTests`), which
  the screens call directly; the list leaves out whatever it says is hidden (BP app
  codebase-health 30).
- **`RealLifeActions` is the app's one home for Going and Heart** `[test]` (`RealLifeActionsTests`;
  BP app `docs/plans/real-life-actions`, tickets 02 and 03; Save joins it in 04). `MainTabsView`
  holds it beside `TownFeed`, hands it to `TownFeed` (every list the feed takes sets each Event's
  base state, in the same turn) and puts it in the environment over the shell's stack, so the
  card's RSVP and heart and the event page's Join read one entry. **Never keep Going or a
  heart in a screen's own state again** `[prose]`: the page used to, and the card behind it went
  stale; the card's heart reset on every refresh. A tap lays
  the choice over the base until a read agrees; writes run one at a time per Event and are never
  cancelled, so the last tap is what the server ends with; the server's "no" holds 600 ms,
  flips back, then shakes and buzzes only while the screen that asked is open: the Event page
  or the card for Going (its RSVP, rsvp-and-groups 01), the card for Heart. No answer at all (offline, timed out) is no "no": the tap
  stays, is tried again (2, 4, 8, 10 s), and is kept on the phone for its account (up to a day,
  real Events only) until a read
  agrees, so it survives a relaunch; a "no" that comes that late flips back with no shake or
  buzz (town-feed ticket 24). Test runs and sample modes keep nothing (`AuthStore.isTestRun`). The photo's double tap only ever hearts. Whether Join, the card's RSVP
  and the heart show is its `canAct` (an account, or a backend that needs none), not the card's. Writes are
  injected: Supabase, or under DEBUG `-town-samples` nowhere (with `-town-refuse`, every Join refused) and `-town-offline` never answering (taps stay and keep trying),
  so a sample Join never reaches the live database. `RootView` gives the DEBUG preview roots
  outside the shell `RealLifeActions.preview`; a card or event page outside both would crash.
- **When the order changes is ticket 11's** `[test]`: a fresh order only on pull to refresh, or
  on coming back after 30 minutes or more away (a launch counts) while still at the top. Any
  other read keeps the order on screen: cards update in place, ones that went drop out, new ones
  wait for the next fresh order. This keeps the database's last order; it never re-sorts.
  Back within 30 minutes the feed lands where it was (`scrollY`), which a tab switch used to
  lose. The last list is kept on disk (`TownFeedCache`, raw bytes,
  cleared on sign-out), so a relaunch shows it at once, offline too. Overlapping reads keep
  only the newest one's answer.
- `TownFeedColumn` shows its items in the order given. Events only for now; posts, updates
  and news join when they exist.

**No module machinery and no briefing call** (deleted 2026-10-25, BP app codebase-health 09).
`FeedRegistry`, `FeedController`, `FeedModule*`, `FeedRoute` and the `Briefing*` stack are
gone: the Town tab is the top bar over the Town feed, and a load makes no
`rpc/get_today_briefing` call and logs no `briefingOpen`. The server side (`daily_briefings`,
`compose_briefing`, `get_today_briefing`) is still in the database; its hourly
`briefing-reconcile` job was switched off on 2026-10-30. `docs/archive/GUTTING-LEDGER.md`
says how to get the client back.

### Town top bar (`Features/Town/TownBar.swift`)

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
  (`EdgeBlur.layers`, `TownBarTests.testStackedBlursThinInAStraightLine`). Two traps:
  the animator must start on the NEXT run-loop turn after the view lands in a window (SwiftUI
  inserts views with UIKit animations off, and the effect jumps to full), and one blur must
  span the whole height (two stacked views meeting mid-edge drew a seam, each blurring only
  its own side). A paused animator never finishes, so XCUITest waits out its 60s idle
  timeout before every step: the UI tests launch with `-ui-tests`, which leaves the blur
  off (finishing the animator at its current point instead drops the blur to nothing).
  `ImageRenderer` draws the UIKit blur as a placeholder.
- **The feed holds the clock black** `[test]` (`AppearanceStore.holdsClock`, set by `TownView`
  on appear, cleared on disappear). With no colour scheme requested, iOS 26 inks the status
  bar from whatever scrolls under it and the clock went white over dark photos; while held,
  System requests the phone's own scheme, which pins it. Released under a pushed event page,
  whose hero photo keeps the white clock it had (2026-09-27).
- **Out of home the feed CARRIES the bar, 1:1** (Jesse, 2026-09-27, Instagram's header).
  `TownBarRules.barTravel` is the offset clamped to the bar's 58pt: the controls move up by
  it and fade with it, riding up under the status edge, which blurs and pales them on the
  way out as Instagram's header is. It reaches the bar through an `@Observable` box
  (`BarTravel`) that only the bar reads, so the feed's body does not re-run per frame.
  Carried its full height, the bar leaves WITHOUT the slide (`TownView` sets that state in
  a transaction with animations off): animated, it snapped back to rest as it started
  floating and slid out again over the first post.
- **Past that, the rule is DIRECTION, not distance.** `TownBarRules.chromeHidden(wasHidden:
  floating:anchor:offset:)` is pure and total: inside `hideAfter` (the bar's own height) and
  any rubber-band pull it always shows; a bar carried its full height out of home counts as
  away at once; a floating bar hides after `flipDistance` (12pt) of one-way travel down and
  comes back after 12pt up, and jitter holds the current state. `TownView` writes each state
  only when it flips.
- **The chrome is REMOVED when hidden, not faded in place, and it has to be** `[prose]` — the
  glass-compositing rule is in `docs/rules/swift-traps.md`. `TownBar` branches on
  `chromeHidden` inside a fixed-height `ZStack` and animates the `.transition`. Note the
  offset expression it keeps: `contentOffset.y` rests at `-contentInsets.top`, so the
  `+ geometry.contentInsets.top` term is what makes 0 mean "at rest" — drop it and the trace
  reads on the wrong schedule.
- **Chrome that has left must not take taps** `[prose]` — `.allowsHitTesting(!chromeHidden)`
  and `.accessibilityHidden(chromeHidden)` sit on the control row.
- **Three controls in 44pt boxes, 16pt in from the screen's edges** (Instagram's, measured
  2026-09-27). `[prose]` Instagram's + leads and opens New post (`NewPost.swift`, BP app
  post-screen, 2026-11-02; New event from town-plus, 2026-11-01, before it; friends led until it became a tab that day, search before 2026-09-29),
  the wordmark centres, a notifications bell holds the trailing corner, and the map disc sits
  inboard of it. The + and the bell are
  **bare ink at home and sit in frosted circles while the bar floats** over the feed
  (`TownBarRules.chromeFloating`: from the moment the bar leaves mid-feed until the feed is
  home again) — a material circle, not Liquid Glass, so it slides and fades with its mark
  (see the glass rule in `docs/rules/swift-traps.md`). A disc **leading** trips
  `TownBarTests.testBrandLockupLeavesTheLeadingHeaderAreaBlank`.
- **The map button is a true circle, 44×44** (Instagram's button size, Jesse 2026-09-27;
  50 before) — the one deliberate exception to this system's 12pt rounded squares.
- **The map disc is a solid `Hue.brandDisc` circle, exactly #FCE804, carrying
  `Hue.onBrandDisc` ink — no glass, no material, no tint** (2026-09-24). `[test]`
  `TownBarTests.testMapDiscIsExactBrandYellow` pixel-samples the colour. The translucent
  `mapWash` disc before it went mustard over photographs, and a Liquid Glass surface
  composites outside its own view's layer, so it arrived and left out of step with the rest
  of the bar.
- **The bar's glyphs are drawn in-house** (`MapPinGlyph`, and `MagnifierGlyph` / `BellGlyph`
  in `Features/Town/BarGlyphs.swift`) because the SF equivalents are different silhouettes,
  not the same shape at another weight. `MapPinGlyph` is a pin outline and a concentric ring
  as **two subpaths of one `Path`**, so a single stroke renders both at identical weight.
  The + is `PlusGlyph`, in the same file. **The bell carries a dot** while Notifications or the
  hello pill hold something unseen (`TownBar.bellButton`); no number. A new friend
  request puts Instagram's unread dot on the Friends tab, in exact BP yellow (`FriendsBook.dot`,
  BP app docs/plans/friends ticket 03; Jesse, 2026-10-13).

### Other surfaces

- **Town menu** — deleted on 2026-10-25 (`TownMenuView`, `GlassShowcaseOverlay`,
  `-open-menu`); only that flag reached it. Its appearance switch went with it: a saved
  System / Light / Dark choice still applies (`AppearanceStore`), and nothing sets one now.
- **You** (`Features/Profile/`, `Features/You/`) — the fifth tab is your own Profile
  (`ProfileView`, BP app five-tabs 03): identity and settings, **no fabricated counts**
  `[prose]`, over your three weeks of Going on a Lapse-style Calendar with the picked day's
  Agenda (`YouPage`), read by `get_my_going` and kept in the shell (`YouModel`) like the
  Town feed (BP app `docs/plans/you-tab`). Its Saved row pushes the saved Events (`SavedPage`), read by
  `get_my_saves` and kept in the shell (`YouModel.saves()`), with this session's saves laid
  over it from `RealLifeActions` (BP app `docs/plans/you-tab`, ticket 04). `EditProfileView` writes
  **server-first** (upload avatar → `ProfileAPI.upsert`) and surfaces a real save failure
  instead of a false success.
- **Your profile is one model** (`ProfileModel`, BP app codebase-health-2 09) `[test]`: your
  name, photo, Interests and onboarded date. `RootView` makes it (it reads while onboarding is
  up), hands it to `AppSession` and puts it in the environment at the root, so the You tab, the
  tab bar's photo, New post, Your code, Edit interests and the name sheet all read one copy and
  a save shows everywhere at once. One read per account; reads asked together share a request,
  and one that an account change or a save overtook never lands. **Only it writes the phone's
  copy** (`Interests`' keys) `[prose]`: never make a second `ProfileModel` or write those keys
  elsewhere.
- **Onboarding hands its answers to Your profile** (BP app codebase-health-2 10) `[test]`:
  `OnboardingStore` keeps them on the phone; its finish here calls `ProfileModel.finished`
  (the stamp first, which the tabs wait up to 2.5 s for, then name and photo, then Contacts'
  requests), and each account's arrival calls `ProfileModel.arrived` (the read, then the stamp a
  finish never got, a reinstall's skip, and waiting answers). `RootView` only shows what they say:
  the Done island while `welcoming`, the tabs once `answersLanded`, and the shell reads the Town
  feed again on each of `lateLandings`.
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
  adopt that branch. Two decided rules wait on data: City meetings stay in until people
  can follow the City, and the ZIP check waits until events carry a ZIP or a Place.
- **Admin is an email allowlist, not a security boundary** `[prose]` — `Admin.isAdmin` in
  `DateHelpers.swift`. Self-approved events are an intentional product decision. **RLS is the real
  boundary.**
