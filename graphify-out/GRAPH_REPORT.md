# Graph Report - hygge-community-feed  (2026-07-19)

## Corpus Check
- 195 files · ~640,106 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 2238 nodes · 4335 edges · 154 communities (137 shown, 17 thin omitted)
- Extraction: 96% EXTRACTED · 4% INFERRED · 0% AMBIGUOUS · INFERRED: 167 edges (avg confidence: 0.8)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `ac574558`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- Global Constraints
- St. Joe Community Feed Implementation Plan
- .event
- .sections
- CommunityFeedBucketer.swift
- CommunityFeedBucketer
- ClassifiedEvent
- .isFresh
- .minutesOf
- .decode
- BoardRow
- String
- Trail
- Codable
- .monthDateRows
- .rsvpEvent
- ClubStatus
- ClubStatus
- SpeedDialItem
- POI
- DayDetailView
- BentoStatGrid
- MapSheet
- CalendarView
- ProfileView
- ShareCenter
- MainTabsView
- SpotFilter
- Onboarding — Community Profile (name · interests · avatar → Supabase)
- Today Tab Remake — Design Spec
- Living Basemap — design
- .validAccessToken
- Spot
- Session
- Share Reveal Animation — Design Spec
- Save-to-map — design
- AuthStore
- EventCategory
- ShareTargets.swift
- ExploreKit.swift
- SJMapView
- OnboardingView
- CORRECTNESS — full detail
- ButtonStyle
- Today Tab Remake — Implementation Plan
- Image
- TodayInStJoeContent
- MapIntroView.swift
- Global Constraints
- Share Reveal Animation Implementation Plan
- Test harness convention (pure units)
- Daily Almanac v2 — AI day-summary — design
- .timeSpan
- Pop
- InlineAction
- CoreLocation
- Hygge Feature Expansion Implementation Plan
- WeatherBackground — looping video backdrop for the Today weather bar
- Reminders
- TownMenuAction
- View
- Foundation
- DateComponents
- Design
- Community Profile screen — design spec
- Compose "+" speed-dial — design
- Map pin hierarchy — rest dots, awake markers, collision labels
- Upcoming Insights — Personal Spotlight Edition
- .minutesOf
- Interests
- TrailsMapView
- LoginView
- SpringReveal
- CLAUDE.md
- SwiftUI
- SupabaseError
- TrailsListView.swift
- EntriesStatCard
- AroundTownCarousel
- .line
- PlaceFamily
- ProfileAPI
- InsightsData
- VenueAutocompleteField
- ProfileModel
- StaggeredAppear
- FLOW: Live town map (Life360-style)
- .run
- Global Constraints
- Button press "pop" animation — design
- ExploreSearchOverlay
- SafariView
- MoonInfo
- Haptics
- ModerationView
- Product
- FLOW: Activities / Explore (events, clubs, trails)
- FLOW: Community calendar (BeReal-style) + Apple Calendar export
- FLOW: Daily Home / Today tab
- FLOW: First-run: Splash -> Login -> Onboarding wizard -> Map-intro finale
- FLOW: Whole-app product thesis, retention & long-term bets
- Task 1 — Community Feed Bucketer
- Map Intro — onboarding crescendo (design)
- FakeTokenProvider
- GlassShowcaseOverlay
- Masthead
- PlaceDetailView
- REVIEW.md
- FLOW: Profile / identity + global composer (Add)
- TOPIC: Backend/data platform, two-repo sync, scale & long-term foundations
- review_park_photos.py
- Task 2 — Community Feed Event State
- Almanac daily write — design
- Calendar Day-Detail — timeline agenda + staggered entrance (ported from reference)
- InsightsMiniCalendar
- HyggeLogoBadge.swift
- onThisDay
- PinDisplay
- QuickAddSheet
- InterestPickerView
- EditProfileView
- Log
- TOPIC: Codebase architecture, concurrency, testability, tech debt
- .coordinate
- StreakHeroCard
- ViewModifier
- LoadState
- ContinueButton
- OnboardingChrome.swift
- BundleImage.swift
- supabase/ — schema under version control
- Triangle
- ClubView
- HyggeTests
- UIKit
- KnownLocalPhoto
- QuickAddSheet
- 2026-07-16-upcoming-insights-personal-prompt.md
- progress.md
- task-1-brief.md
- task-2-brief.md
- task-3-brief.md
- task-3-report.md
- task-4-brief.md
- InterestCard
- .isAdmin
- StreakHeroCard
- UpcomingInsightsView
- .bottomSheet
- EventRow
- CGFloat
- Date
- Set
- Namespace

## God Nodes (most connected - your core abstractions)
1. `SwiftUI` - 76 edges
2. `CommunityAPI` - 66 edges
3. `Foundation` - 38 edges
4. `AuthStore` - 38 edges
5. `Color` - 38 edges
6. `ActivitiesView` - 33 edges
7. `MapModel` - 33 edges
8. `UpcomingEvent` - 32 edges
9. `SJMapView` - 32 edges
10. `TimelineEvent` - 26 edges

## Surprising Connections (you probably didn't know these)
- `FakeTokenProvider` --inherits--> `TokenProviding`  [EXTRACTED]
  HyggeTests/FakeTokenProvider.swift → Hygge/Backend/TokenProviding.swift
- `OnboardingView` --calls--> `ProfileAPI`  [INFERRED]
  Hygge/Features/Onboarding/OnboardingView.swift → Hygge/Backend/ProfileAPI.swift
- `OnboardingView` --calls--> `Storage`  [INFERRED]
  Hygge/Features/Onboarding/OnboardingView.swift → Hygge/Backend/Storage.swift
- `labeledField()` --calls--> `Group`  [INFERRED]
  Hygge/Features/Add/AddFormView.swift → Hygge/Backend/TownSearch.swift
- `ActivitiesView` --calls--> `ActivitiesModel`  [INFERRED]
  Hygge/Features/Activities/ActivitiesView.swift → Hygge/Features/Activities/ActivitiesModel.swift

## Import Cycles
- None detected.

## Communities (154 total, 17 thin omitted)

### Community 0 - "Global Constraints"
Cohesion: 0.29
Nodes (6): Global Constraints, St. Joe Community Feed Implementation Plan, Task 1: Make time bucketing a pure, checked contract, Task 2: Provide future-event RSVP state to the Home feature, Task 3: Render the warm lower-bucket feed, Task 4: Integrate Today, add deterministic preview, and verify in the simulator

### Community 1 - "St. Joe Community Feed Implementation Plan"
Cohesion: 0.19
Nodes (12): ClassifiedEvent, CommunityFeedBucket, fresh, later, thisWeek, CommunityFeedBucketer, CommunityFeedSection, Bool (+4 more)

### Community 2 - ".event"
Cohesion: 0.12
Nodes (30): CarouselDots, EventShelfCard, ExploreCategoryTile, ExploreComposeBanner, exploreEventDateline(), ExplorePlaceCard, ExploreSectionHeader, ExploreTownHeader (+22 more)

### Community 3 - ".sections"
Cohesion: 0.06
Nodes (53): Decodable, Attribution, AutocompleteResponse, ConfidentPhoto, DetailsResponse, GooglePlacesService, LatLng, LocalizedText (+45 more)

### Community 4 - "CommunityFeedBucketer.swift"
Cohesion: 0.07
Nodes (39): Almanac, AlmanacReveal, AlmanacSection, Nudge, AttributedString, Bool, CGFloat, Date (+31 more)

### Community 5 - "CommunityFeedBucketer"
Cohesion: 0.36
Nodes (9): Hashable, AgendaEvent, DailyQuest, WeekEvent, Place, PlaceFact, Places, String (+1 more)

### Community 6 - "ClassifiedEvent"
Cohesion: 0.07
Nodes (26): Change, Kind, delete, insert, update, RealtimeClient, Row, Status (+18 more)

### Community 7 - ".isFresh"
Cohesion: 0.06
Nodes (39): AnyClass, AVFoundation, AVPlayer, AVPlayerLayer, AVPlayerLooper, PlayerHostView, PlayerLayerView, Bool (+31 more)

### Community 8 - ".minutesOf"
Cohesion: 0.23
Nodes (15): AgendaRow, ClubInput, ClubRef, CurrentUser, DateRow, MemberRow, NewEventInput, NewTrailInput (+7 more)

### Community 9 - ".decode"
Cohesion: 0.20
Nodes (5): CommunityAPI, Any, Bool, String, TokenProviding

### Community 10 - "BoardRow"
Cohesion: 0.12
Nodes (11): BoardFullRow, BoardRow, BoardSections, IdRow, URL, BoardModel, BoardView, Bool (+3 more)

### Community 11 - "String"
Cohesion: 0.11
Nodes (17): DailyQuest, HomeModel, Bool, CommunityAPI, String, UpcomingEvent, HomeView, AuthStore (+9 more)

### Community 12 - "Trail"
Cohesion: 0.17
Nodes (10): PendingPost, ClubRow, ClubStatus, approved, pending, rejected, Trail, ModerationModel (+2 more)

### Community 13 - "Codable"
Cohesion: 0.14
Nodes (21): EventComment, FeedPosting, FollowTarget, FollowTargetType, club, profile, Date, CommentRPCRow (+13 more)

### Community 14 - ".monthDateRows"
Cohesion: 0.08
Nodes (33): CityParks, Park, CLLocationCoordinate2D, Double, String, Action, openPark, openPlace (+25 more)

### Community 15 - ".rsvpEvent"
Cohesion: 0.08
Nodes (36): UpcomingEvent, ActivitiesView, ClubExploreCard, EventExploreCard, EventGroup, EventInviteCircle, eventTimeKey(), Filter (+28 more)

### Community 16 - "ClubStatus"
Cohesion: 0.09
Nodes (18): CoreText, AttributedString, Bool, Double, Int, Void, TypewriterMode, character (+10 more)

### Community 17 - "ClubStatus"
Cohesion: 0.06
Nodes (34): Build hazard logged, Design tokens added, Dynamic town pill — reverse-geocoded map center (2026-07-06), Filter-chip chrome fix + board de-dup + real-content 5× (2026-07-06, overnight), Final gate (all ✅, screenshot-verified on iPhone 17 sim), Final state, FIX 1 — Map style → light-v11, FIX 2 — Coordinate audit (+26 more)

### Community 18 - "SpeedDialItem"
Cohesion: 0.12
Nodes (15): Alignment, ComposeSpeedDial, SpeedDialAction, compose, invite, SpeedDialAnchor, bottomTrailing, topTrailing (+7 more)

### Community 19 - "POI"
Cohesion: 0.12
Nodes (16): CGSize, Exp, FeatureCollection, POI, Bool, CLLocationCoordinate2D, Double, Hasher (+8 more)

### Community 20 - "DayDetailView"
Cohesion: 0.17
Nodes (13): DayDetailView, DaySlot, EventDescriptionSheet, Bool, Date, DateFormatter, Int, Never (+5 more)

### Community 21 - "BentoStatGrid"
Cohesion: 0.14
Nodes (22): HorizontalEdge, BentoCard, journaled, visited, written, BentoSpec, BentoStatGrid, Rect (+14 more)

### Community 22 - "MapSheet"
Cohesion: 0.20
Nodes (10): MapSheet, SheetDetent, full, medium, peek, SheetMode, places, today (+2 more)

### Community 23 - "CalendarView"
Cohesion: 0.13
Nodes (18): CalendarModel, Calendar, Int, Set, String, AgendaRowCard, CalendarFace, grid (+10 more)

### Community 24 - "ProfileView"
Cohesion: 0.12
Nodes (10): C, AboutHyggeSheet, Expandable, clubs, events, ProfileView, Bool, String (+2 more)

### Community 25 - "ShareCenter"
Cohesion: 0.13
Nodes (15): Delegate, MessagesComposer, PhotoSaver, ShareTargetRow, Bool, String, UIImage, UIViewController (+7 more)

### Community 26 - "MainTabsView"
Cohesion: 0.10
Nodes (18): AddKind, AnyTransition, CGFloat, HyggeTabBar, MainTabsView, RootView, AuthStore, Bool (+10 more)

### Community 27 - "SpotFilter"
Cohesion: 0.22
Nodes (11): HaloText, MapPinBadge, POISelectedMarker, PulseRing, SpotFilter, all, campus, downtown (+3 more)

### Community 28 - "Onboarding — Community Profile (name · interests · avatar → Supabase)"
Cohesion: 0.10
Nodes (20): 10. Open questions / tunables, 1. Flow & screens, 2. Interest taxonomy, 3. Imagery (hybrid), 4. Data model (Supabase), 5. Motion & interaction, 6. Accessibility, 7. DEBUG launch args (headless screenshot verification) (+12 more)

### Community 29 - "Today Tab Remake — Design Spec"
Cohesion: 0.11
Nodes (18): 10. Risks & open questions, 1. Goal, 2. Decisions locked (from brainstorming, 2026-07-11), 3. Scope & non-goals, 4. The three zones, 5.1 Tables (draft SQL — confirm types at apply-time), 5.2 RLS (real boundary — mirrors existing app posture), 5.3 Feed read — one round trip (+10 more)

### Community 30 - "Living Basemap — design"
Cohesion: 0.11
Nodes (18): Accessibility & performance, `AtmosphereModel.swift` — `@MainActor ObservableObject`, `AtmosphereWhisper.swift` — the quiet "why", `BasemapPalette.swift` — atmosphere → Mapbox layer colors, Components (one job per file, `Features/Map/Atmosphere/`), Integration in `SJMapView`, Living Basemap — design, Non-goals (YAGNI) (+10 more)

### Community 31 - ".validAccessToken"
Cohesion: 0.15
Nodes (11): DailyAlmanac, Date, String, TimeInterval, Bool, String, Storage, Data (+3 more)

### Community 32 - "Spot"
Cohesion: 0.31
Nodes (6): MapSpots, Spot, Bool, CLLocationCoordinate2D, Hasher, String

### Community 33 - "Session"
Cohesion: 0.16
Nodes (15): Codable, CodingKey, Equatable, AuthUser, CodingKeys, accessToken, expiresAt, refreshToken (+7 more)

### Community 34 - "Share Reveal Animation — Design Spec"
Cohesion: 0.11
Nodes (17): Architecture, Error handling & edge cases, Files, Goals, Integration / rollout ("everywhere"), Motion spec (the 99% copy), Non-goals, Open questions / to resolve in the plan (+9 more)

### Community 35 - "Save-to-map — design"
Cohesion: 0.11
Nodes (17): 10. Risks & mitigations, 1. Goal & principles, 2. Decisions (from brainstorm), 3. Data model — `saved_places`, 4.1 `SavedPlace` value, 4.2 `SavedStore` evolves from ids → places, 4.3 `SavedPlacesAPI`, 4.4 Lifecycle (+9 more)

### Community 36 - "AuthStore"
Cohesion: 0.20
Nodes (7): Error, AuthStore, Bool, Data, String, Task, Void

### Community 37 - "EventCategory"
Cohesion: 0.11
Nodes (16): AddModel, Data, Date, Int, Set, EventCategory, books, faith (+8 more)

### Community 38 - "ShareTargets.swift"
Cohesion: 0.23
Nodes (4): HTTPURLResponse, Data, Int, T

### Community 39 - "ExploreKit.swift"
Cohesion: 0.22
Nodes (13): ExploreBlankPhoto, ExploreCard, exploreCircleIcon(), exploreMetaRow(), MetaItem, SaveBookmarkButton, SavedStore, Bool (+5 more)

### Community 40 - "SJMapView"
Cohesion: 0.19
Nodes (6): SJMapView, CLLocationCoordinate2D, Double, MapboxMap, Viewport, Void

### Community 41 - "OnboardingView"
Cohesion: 0.07
Nodes (29): Interest, Interests, Bool, String, AnyTransition, InlineAction, LoadingBar, Phase (+21 more)

### Community 42 - "CORRECTNESS — full detail"
Cohesion: 0.12
Nodes (16): [10] RollCallSection and QuestSection show a false empty/zero state on every Home-tab revisit, unlike the Today section which has a loading guard, [11] Explore feed silently rebrands network failures as "nothing here yet", [12] Club join/leave has no in-flight guard — out-of-order requests can leave local state opposite the server, [13] Explore feed uses a plain VStack (not lazy) so every card — and every trail's geocode network call — renders/fires eagerly on load, [14] Onboarding/profile hydration is device-session-scoped, not per-user — a second account on the same device permanently skips onboarding and inherits the previous user's local identity mirror, [15] Weekly-repeat event posting has no rollback or idempotency — a mid-loop failure leaves partial events live and a retry duplicates them, [16] VenuePhoto shows a stale (wrong-venue) photo when its inputs change under a reused view identity, [1] A REST-layer 401 (server-revoked/rejected token) never invalidates AuthStore's session or forces re-login (+8 more)

### Community 43 - "ButtonStyle"
Cohesion: 0.13
Nodes (13): ButtonStyle, CoralPillStyle, PeekLineStyle, PlaceRow, SkeletonRow, StatusDot, Bool, Configuration (+5 more)

### Community 44 - "Today Tab Remake — Implementation Plan"
Cohesion: 0.12
Nodes (15): File Structure, Global Constraints (verbatim from spec + CLAUDE.md — apply to every task), Self-Review, Task 0: Supabase social migration (branch-first), Task 10: Prod merge + graphify update, Task 1: Social backend (Swift) — models + `SocialAPI`, Task 2: `MoonPhase` (pure function), Task 3: `OnThisDay` (curated fact) (+7 more)

### Community 45 - "Image"
Cohesion: 0.47
Nodes (4): InviteButton, InviteCard, Bool, String

### Community 46 - "TodayInStJoeContent"
Cohesion: 0.18
Nodes (13): BoardItem, Route, board, link, AttributedString, String, URL, TodayInStJoeCard (+5 more)

### Community 47 - "MapIntroView.swift"
Cohesion: 0.21
Nodes (13): IntroPinModel, IntroPulseRing, MapIntroView, PinWithLabel, PortholeMap, Bool, CGFloat, Double (+5 more)

### Community 48 - "Global Constraints"
Cohesion: 0.13
Nodes (14): Community-Profile Onboarding Implementation Plan, Global Constraints, Self-Review, Task 10: Launch hydration from Supabase, Task 11: Full-flow verification + build log, Task 1: Supabase — `town_profiles` table + `avatars` bucket, Task 2: Backend — `TownProfile`, `ProfileAPI`, `Storage.uploadAvatar`, Task 3: Interests taxonomy — 18 categories, sections, name cache (+6 more)

### Community 49 - "Share Reveal Animation Implementation Plan"
Cohesion: 0.13
Nodes (14): Build / screenshot reference (raw fallback), File Structure, Global Constraints, Notes for the implementer, Self-Review (completed during authoring), Share Reveal Animation Implementation Plan, Task 1: `SharePayload` + `ShareCenter` skeleton + overlay window (bare scrim), Task 2: Preview card — centered, spring scale-up (+6 more)

### Community 50 - "Test harness convention (pure units)"
Cohesion: 0.13
Nodes (14): Global Constraints, Living Basemap Implementation Plan, Self-Review, Task 10: Integrate into SJMapView + full simulator verification (`SJMapView.swift`), Task 1: Atmosphere vocabulary (`TownAtmosphere.swift`), Task 2: SolarClock (`SolarClock.swift`), Task 3: SeasonClock (`SeasonClock.swift`), Task 4: WeatherProvider (`WeatherProvider.swift`) (+6 more)

### Community 51 - "Daily Almanac v2 — AI day-summary — design"
Cohesion: 0.13
Nodes (14): 1. `daily_almanac` table (new migration), 2. `daily-almanac` edge function (new, mirrors `moderate-post/index.ts`), 3. Anti-hallucination contract (system prompt), 4. `Hygge/Backend/DailyAlmanac.swift` (new client, mirrors `Moderation.swift`), 5. `AlmanacSection` wiring (edit), Architecture, Components, Daily Almanac v2 — AI day-summary — design (+6 more)

### Community 52 - ".timeSpan"
Cohesion: 0.17
Nodes (12): EventKit, CalendarExport, ExportError, accessDenied, noCalendar, noEvents, saveFailed, Bool (+4 more)

### Community 53 - "Pop"
Cohesion: 0.13
Nodes (15): AppearStagger, Pop, PopIn, CGFloat, Configuration, Content, Double, Int (+7 more)

### Community 54 - "InlineAction"
Cohesion: 0.24
Nodes (8): CaseIterable, AddKind, club, event, trail, AddView, Kind, String

### Community 55 - "CoreLocation"
Cohesion: 0.16
Nodes (9): Blank, CoreLocation, AmenityRow, ParkDetailView, String, CLLocationCoordinate2D, Int, String (+1 more)

### Community 56 - "Hygge Feature Expansion Implementation Plan"
Cohesion: 0.14
Nodes (13): File Structure, Global Constraints, Hygge Feature Expansion Implementation Plan, Self-Review, Task 1: Storage upload (`Storage.swift`), Task 2: Moderation Edge Function (`Moderation.swift`), Task 3: Add form model (`AddModel.swift`), Task 4: Add form UI (`AddFormView.swift` + wire `AddView.swift`) (+5 more)

### Community 57 - "WeatherBackground — looping video backdrop for the Today weather bar"
Cohesion: 0.14
Nodes (13): 1. `WeatherState` — the six states, 2. `WeatherClipCache` (actor), 3. `WeatherVideoController` + `AVPlayerLayer` host, 4. `WeatherBackground` view (the backdrop), 5. `WeatherBar` edits, Architecture, Data flow, Decisions (locked) (+5 more)

### Community 58 - "Reminders"
Cohesion: 0.26
Nodes (5): Reminders, Bool, Date, String, UserNotifications

### Community 59 - "TownMenuAction"
Cohesion: 0.20
Nodes (11): Row, String, Void, TownMenuAction, activities, calendar, compose, invite (+3 more)

### Community 60 - "View"
Cohesion: 0.19
Nodes (7): CardShadow, Radius, Bool, CGFloat, Content, View, View

### Community 61 - "Foundation"
Cohesion: 0.22
Nodes (4): Combine, Foundation, Moderation, BasemapPalette

### Community 62 - "DateComponents"
Cohesion: 0.40
Nodes (5): DateComponents, DateHelpers, Date, Int, String

### Community 63 - "Design"
Cohesion: 0.15
Nodes (12): Accent — coral (the one job: live + tappable), Bans (this project), Color, Design, Iconography, Layout, radii & elevation, Motion, Secondary hues (use sparingly, one job each) (+4 more)

### Community 64 - "Community Profile screen — design spec"
Cohesion: 0.15
Nodes (12): Backend — `CommunityAPI` (3 new methods, PostgREST, RLS-scoped), Community Profile screen — design spec, Components, `EditProfileView` (sheet), Goal, Motion (Emil / house rules), `ProfileModel` (`@MainActor ObservableObject`), `ProfileView` (frosted sheet) (+4 more)

### Community 65 - "Compose "+" speed-dial — design"
Cohesion: 0.15
Nodes (12): 1. `SpeedDial` — one reusable overlay component (`Features/Components/SpeedDial.swift`), 2. Hosting + trigger, 3. Per-surface items (context-tailored), 4. Routing (tap → destination), Addendum (2026-07-13) — all three surfaces anchor TOP-RIGHT, Compose "+" speed-dial — design, Decisions (locked with the user), Design (+4 more)

### Community 66 - "Map pin hierarchy — rest dots, awake markers, collision labels"
Cohesion: 0.15
Nodes (12): Acceptance (screenshots), Architecture — style layers + a thin SwiftUI overlay, DEBUG launch args (headless screenshot verification), Hit targets, Map pin hierarchy — rest dots, awake markers, collision labels, Motion (all Reduce-Motion-gated → crossfade only), Pin states (one enum, one resolver), Problem (+4 more)

### Community 67 - "Upcoming Insights — Personal Spotlight Edition"
Cohesion: 0.15
Nodes (12): 1 · Hero: the Spotlight wheel, 2 · Chart card → "Your Year Ahead", 3 · Bento → your 3 interest categories, 4 · Mini month grid, 5 · Copy grammar (applies everywhere), Data plumbing (no schema changes), Decisions (from brainstorm), Design — slot by slot (+4 more)

### Community 68 - ".minutesOf"
Cohesion: 0.15
Nodes (10): categoryChip(), labeledField(), Binding, Bool, String, View, String, InterestImage (+2 more)

### Community 69 - "Interests"
Cohesion: 0.40
Nodes (6): Date, CommunityFeedPreview, FixtureEvent, Int, String, UpcomingEvent

### Community 70 - "TrailsMapView"
Cohesion: 0.15
Nodes (17): DragGesture, openInGoogleMaps(), CGFloat, CGRect, CLLocationCoordinate2D, String, URL, Void (+9 more)

### Community 71 - "LoginView"
Cohesion: 0.22
Nodes (9): SpotCategory, chapel, coffee, college, `default`, downtown, fitness, park (+1 more)

### Community 72 - "SpringReveal"
Cohesion: 0.22
Nodes (10): RevealTiming, SpringReveal, Animation, Bool, CGFloat, Content, Double, Int (+2 more)

### Community 73 - "CLAUDE.md"
Cohesion: 0.17
Nodes (10): Architecture, Backend — hand-rolled, no Supabase SDK (`Hygge/Backend/`), Build, run, verify, Conventions & gotchas, Design system (`Hygge/Theme/`) — ported from the Expo app, Features — one folder per screen, `View` + `Model` (`Hygge/Features/`), First-checkout setup — required or the build fails, graphify (+2 more)

### Community 74 - "SwiftUI"
Cohesion: 0.09
Nodes (15): App, SplashView, View, Void, TodayCard, AvatarStepView, PhotosPickerItem, String (+7 more)

### Community 75 - "SupabaseError"
Cohesion: 0.27
Nodes (8): SupabaseError, SupabaseHTTP, Any, Data, Int, Sendable, String, Void

### Community 76 - "TrailsListView.swift"
Cohesion: 0.29
Nodes (10): CommunityTrailCard, googleMapsURL(), mapPill(), statBadge(), CLLocationCoordinate2D, String, URL, Void (+2 more)

### Community 77 - "EntriesStatCard"
Cohesion: 0.24
Nodes (8): EntriesStatCard, Animation, Bool, CGFloat, Content, Int, String, TapToExpand

### Community 78 - "AroundTownCarousel"
Cohesion: 0.27
Nodes (10): AroundTownCarousel, PlaceCard, PlaceExpandedCard, placeSymbol(), CGFloat, Int, Namespace, Place (+2 more)

### Community 79 - ".line"
Cohesion: 0.24
Nodes (7): DailyGreeting, DayPart, afternoon, evening, morning, Date, UInt64

### Community 80 - "PlaceFamily"
Cohesion: 0.29
Nodes (6): PlaceCategoryMap, PlaceFamily, business, food, Bool, Set

### Community 81 - "ProfileAPI"
Cohesion: 0.13
Nodes (10): ProfileAPI, Bool, Data, String, T, ProfileModel, Bool, Int (+2 more)

### Community 82 - "InsightsData"
Cohesion: 0.26
Nodes (9): Bool, Int, TimelineEvent, Kind, event, open, Double, TimelineSlotView (+1 more)

### Community 83 - "VenueAutocompleteField"
Cohesion: 0.31
Nodes (8): Palette, Bool, Never, String, Task, Void, VenueAutocompleteField, VenueSuggestion

### Community 84 - "ProfileModel"
Cohesion: 0.29
Nodes (6): AnyView, AppInviteCard, SharePayload, Bool, String, V

### Community 85 - "StaggeredAppear"
Cohesion: 0.27
Nodes (7): Motion, StaggeredAppear, Animation, Content, Int, View, View

### Community 86 - "FLOW: Live town map (Life360-style)"
Cohesion: 0.20
Nodes (10): FLOW: Live town map (Life360-style), [friction|impact=high|effort=M] "Recenter" has no user location to recenter to — the map never shows the user's own position, [friction|impact=low|effort=S] "Live now" is signaled two different ways for the identical event, in the same feature, [friction|impact=medium|effort=S] Filter chip opens a native system Menu, breaking the map's own visual language, [friction|impact=medium|effort=S] Offline/error state is handled twice, inconsistently, and the primary UI is a dead end, [improvement|impact=high|effort=M] Pins are binary (live or nothing) — the map looks dead all day until an event's exact start minute, [improvement|impact=medium|effort=S] The map's empty state is a dead blank moment — but the app already has real, on-brand filler content sitting unused, [innovation|impact=low|effort=S] The town pill is Hygge's most dynamic piece of chrome but does nothing when tapped (+2 more)

### Community 87 - ".run"
Cohesion: 0.36
Nodes (5): CustomStringConvertible, PlaceSeeder, Summary, Bool, String

### Community 88 - "Global Constraints"
Cohesion: 0.22
Nodes (8): Global Constraints, Self-Review, Task 1: `WeatherState` — six states, mapping, matched gradients, Task 2: `WeatherClipCache` — download + local cache, Task 3: `WeatherVideoController` + `AVPlayerLayer` host, Task 4: `WeatherBackground` — composed backdrop with lifecycle, Task 5: Wire `WeatherBackground` into `WeatherBar` (state + 30-min cache + swap backdrop), WeatherBackground Implementation Plan

### Community 89 - "Button press "pop" animation — design"
Cohesion: 0.22
Nodes (8): 1. Upgrade `PressableStyle` in place, 2. Adopt on `.plain` holdouts that are real controls, Button press "pop" animation — design, Decisions (locked with the user), Design, Final implementation, Problem, Verification findings

### Community 90 - "ExploreSearchOverlay"
Cohesion: 0.26
Nodes (5): ShareCenter, Any, UIImage, UIViewController, UIWindow

### Community 91 - "SafariView"
Cohesion: 0.12
Nodes (14): ExploreSearchOverlay, Animation, Bool, Double, String, Suggestion, Void, SafariLink (+6 more)

### Community 92 - "MoonInfo"
Cohesion: 0.33
Nodes (7): MoonInfo, MoonPhaseSelfCheck, phase(), Date, Double, String, TimeZone

### Community 94 - "ModerationView"
Cohesion: 0.31
Nodes (4): ModerationView, Int, String, Void

### Community 95 - "Product"
Cohesion: 0.22
Nodes (8): Accessibility & Inclusion, Anti-references, Brand Personality, Design Principles, Product, Product Purpose, Register, Users

### Community 96 - "FLOW: Activities / Explore (events, clubs, trails)"
Cohesion: 0.22
Nodes (9): FLOW: Activities / Explore (events, clubs, trails), [friction|impact=high|effort=M] Explore cards are dead-ends — no detail view, and a full detail screen already exists unused, [friction|impact=high|effort=M] Explore events have no RSVP action — the model doesn't even carry RSVP state, [friction|impact=medium|effort=S] The time-frame filter — one of the two primary levers — is hidden in a small overflow menu, [improvement|impact=medium|effort=M] Club cards show a static schedule string, never the real next meeting date, [improvement|impact=medium|effort=M] Recurring-event grouping collapses a whole series behind one date with no way to see the others, [improvement|impact=medium|effort=S] Explore has no live-now indicator, even though the app already defines one, [innovation|impact=medium|effort=M] No data-driven 'this weekend' shelf to spark discovery beyond the flat feed (+1 more)

### Community 97 - "FLOW: Community calendar (BeReal-style) + Apple Calendar export"
Cohesion: 0.22
Nodes (9): FLOW: Community calendar (BeReal-style) + Apple Calendar export, [friction|impact=high|effort=M] RSVP exists in the data model and on Home, but is missing from the Calendar tab entirely, [friction|impact=high|effort=S] Tapping an empty day is a dead end instead of an invitation to fill it, [friction|impact=high|effort=S] The Calendar tab has zero "add" affordance — even though its own empty state invites it, [friction|impact=medium|effort=S] "Add to your calendar" can silently create duplicate Apple Calendar entries, [friction|impact=medium|effort=S] Calendar export is bulk-per-day only, not per-event, [improvement|impact=medium|effort=S] Grid is the default face; Agenda answers the daily-habit question faster, [innovation|impact=high|effort=M] Posting an event is a full form up front; borrow Partiful/Luma's progressive-disclosure quick-add (+1 more)

### Community 98 - "FLOW: Daily Home / Today tab"
Cohesion: 0.22
Nodes (9): FLOW: Daily Home / Today tab, [friction|impact=high|effort=M] Two un-reconciled 'today' feeds compete for the same three seconds, [friction|impact=high|effort=S] Dead search icon in the masthead — a tappable-looking button that does nothing, [friction|impact=medium|effort=M] A quiet week stacks five separate 'nothing happening' messages, [friction|impact=medium|effort=M] Almanac, Roll Call, and Quest are three identically-dressed cards that blur together, [improvement|impact=medium|effort=M] AroundTownCarousel is a static, date-blind detour inside a live daily feed, [innovation|impact=high|effort=L] Unify weather + almanac + curated highlight into one true 'Now' card, [innovation|impact=medium|effort=M] Replace three parallel daily 'asks' with one rotating invite slot (+1 more)

### Community 99 - "FLOW: First-run: Splash -> Login -> Onboarding wizard -> Map-intro finale"
Cohesion: 0.22
Nodes (9): FLOW: First-run: Splash -> Login -> Onboarding wizard -> Map-intro finale, [friction|impact=high|effort=M] Sign-up funnels through an email-confirmation round trip with zero preview of the town first, [friction|impact=high|effort=M] The map never asks for or uses real location — "Recenter" recenters to nothing, [friction|impact=high|effort=S] "Explore the map" doesn't open the map, [friction|impact=high|effort=S] No "forgot password" path anywhere, [friction|impact=medium|effort=S] "Skip for now" on Welcome skips the map finale too, [improvement|impact=medium|effort=S] The login screen is a blank form right after a bold coral splash, [innovation|impact=medium|effort=M] Interest picking is pure form-fill with no live payoff until the very end (+1 more)

### Community 100 - "FLOW: Whole-app product thesis, retention & long-term bets"
Cohesion: 0.22
Nodes (9): FLOW: Whole-app product thesis, retention & long-term bets, [friction|impact=high|effort=M] No in-app moderation queue — content growth is capped at one person checking Supabase by hand, [friction|impact=high|effort=S] The daily quest — the app's one built-in daily loop — has no authoring UI, [friction|impact=medium|effort=S] Home leads with two competing "read of today" cards, [improvement|impact=high|effort=M] Going/joined counts are anonymous numbers in a town where everyone plausibly knows each other, [innovation|impact=medium|effort=M] No low-stakes way to post a one-line neighbor update short of a full Event/Club/Trail form, [longterm|impact=high|effort=L] No re-engagement surface exists once the app is backgrounded — a foundational push gap, [longterm|impact=high|effort=L] Real civic recurring content currently depends on one manual research-and-SQL pass, not an ongoing pipeline (+1 more)

### Community 101 - "Task 1 — Community Feed Bucketer"
Cohesion: 0.22
Nodes (8): Concerns, Files changed, GREEN, RED, Reviewer follow-up — Fresh ordering coverage, Reviewer follow-up — Fresh same-date time ordering, Self-review, Task 1 — Community Feed Bucketer

### Community 102 - "Map Intro — onboarding crescendo (design)"
Cohesion: 0.25
Nodes (7): Choreography (all gated by `accessibilityReduceMotion`, like PulseRing/SkeletonBar), Composition (top → bottom, mirrors the reference), Decisions (locked with user), Files, Goal, Map Intro — onboarding crescendo (design), Verify

### Community 103 - "FakeTokenProvider"
Cohesion: 0.32
Nodes (4): Hygge, FakeTokenProvider, String, XCTest

### Community 104 - "GlassShowcaseOverlay"
Cohesion: 0.25
Nodes (6): GlassShowcaseOverlay, Animation, Bool, CGFloat, Content, Void

### Community 105 - "Masthead"
Cohesion: 0.29
Nodes (5): Masthead, Bool, Double, String, Void

### Community 106 - "PlaceDetailView"
Cohesion: 0.32
Nodes (4): PlaceDetailView, Bool, Place, String

### Community 107 - "REVIEW.md"
Cohesion: 0.25
Nodes (7): ARCHITECTURE — full detail, Execution tracker, Hygge — Full App Review (multi-agent audit), Part 1 — Correctness (16 bugs)  — 11/16 done (Batch 1: builds clean + launch verified), Part 2 — UX quick-wins  — 5.5/6 done, Part 3 — Long-term foundations  — 2.5/4 done, UX & INNOVATION — full detail

### Community 108 - "FLOW: Profile / identity + global composer (Add)"
Cohesion: 0.25
Nodes (8): FLOW: Profile / identity + global composer (Add), [friction|impact=high|effort=S] The "+" composer is invisible on the two screens most tied to posting, [friction|impact=medium|effort=S] Profile lists your plans and clubs but gives you no way to undo them, [friction|impact=medium|effort=S] Trail and Club location fields skip the curated-venue autocomplete Events get, [improvement|impact=low|effort=M] "Quests completed" is a bare number with nowhere to go, [innovation|impact=medium|effort=M] Composing an event/club/trail is a bare form with no sense of "this will go live in town", [innovation|impact=medium|effort=S] The kind-chooser treats Event, Club, and Trail as equally likely first taps, [longterm|impact=high|effort=L] Community identity is never actually shown to the community

### Community 109 - "TOPIC: Backend/data platform, two-repo sync, scale & long-term foundations"
Cohesion: 0.25
Nodes (8): [priority=high|effort=M] Close the client-side status-authorization gap before content volume grows, [priority=high|effort=S] Bring the Postgres schema under version control, [priority=high|effort=S] Give the two-repo "backend twin" a real sync mechanism, not a comment, [priority=low|effort=S] Harden Codable decoding against a single bad row blanking an entire screen, [priority=medium|effort=M] Add a minimal last-good-snapshot cache for the core screens, [priority=medium|effort=M] Model recurring events as a recurrence, not N duplicate rows, [priority=medium|effort=S] Add a server-side kill switch and minimal ops visibility — no analytics SDK, TOPIC: Backend/data platform, two-repo sync, scale & long-term foundations

### Community 110 - "review_park_photos.py"
Cohesion: 0.46
Nodes (7): dist(), gdetails(), gsearch(), names_align(), read(), resolve_google(), scenic()

### Community 111 - "Task 2 — Community Feed Event State"
Cohesion: 0.25
Nodes (7): Changes, Concerns, Re-review follow-up — multi-load ordering and override cleanup, Reviewer-resolution follow-up — RSVP/load concurrency, Self-review, Task 2 — Community Feed Event State, Verification

### Community 112 - "Almanac daily write — design"
Cohesion: 0.29
Nodes (6): Almanac daily write — design, Architecture, Decisions (approved), Intent, Timing (Emil framework — a rare, first-open delight), Verification

### Community 113 - "Calendar Day-Detail — timeline agenda + staggered entrance (ported from reference)"
Cohesion: 0.29
Nodes (6): Adaptation to Hygge (decisions), Animation — FINAL tuned values (frame-matched to the reference), Calendar Day-Detail — timeline agenda + staggered entrance (ported from reference), Final build (v2 — full 1:1 timeline), Verify — workflow + two gotchas (both cost real iterations here), What the reference shows

### Community 114 - "InsightsMiniCalendar"
Cohesion: 0.38
Nodes (4): InsightsMiniCalendar, CGFloat, Int, String

### Community 115 - "HyggeLogoBadge.swift"
Cohesion: 0.38
Nodes (4): BrandBadgeModifier, HyggeLogoBadge, Content, View

### Community 116 - "onThisDay"
Cohesion: 0.43
Nodes (6): AlmanacFact, onThisDay(), OnThisDayCache, Date, String, TimeZone

### Community 117 - "PinDisplay"
Cohesion: 0.29
Nodes (5): PinDisplay, live, rest, saved, Bool

### Community 119 - "InterestPickerView"
Cohesion: 0.33
Nodes (5): InterestPickerView, Bool, Set, String, Void

### Community 120 - "EditProfileView"
Cohesion: 0.29
Nodes (6): EditProfileView, Bool, PhotosPickerItem, Set, String, UIImage

### Community 121 - "Log"
Cohesion: 0.38
Nodes (3): Log, String, OSLog

### Community 122 - "TOPIC: Codebase architecture, concurrency, testability, tech debt"
Cohesion: 0.29
Nodes (7): [priority=high|effort=M] Give AuthStore/CommunityAPI a protocol seam so features are unit-testable without the network, [priority=high|effort=S] Add a single, brand-safe error/observability hook instead of the current silent-swallow-everywhere pattern, [priority=high|effort=S] Stand up a minimal XCTest target and start with DateHelpers + RealtimeClient reducer, [priority=low|effort=S] Fold the growing .shared singleton pattern into the same DI pass as AuthStore/CommunityAPI, [priority=medium|effort=M] Unify the five ad-hoc LoadState shapes into one shared type, [priority=medium|effort=S] Break up the two largest Views (ActivitiesView, CalendarView) before they grow further, TOPIC: Codebase architecture, concurrency, testability, tech debt

### Community 123 - ".coordinate"
Cohesion: 0.67
Nodes (4): KnownVenues, CLLocationCoordinate2D, String, Venue

### Community 124 - "StreakHeroCard"
Cohesion: 0.33
Nodes (6): ActivityCoralPanel, ActivityTile, CGFloat, Photo, String, Trailing

### Community 126 - "LoadState"
Cohesion: 0.33
Nodes (6): LoadState, empty, error, loaded, loading, offline

### Community 127 - "ContinueButton"
Cohesion: 0.53
Nodes (5): ContinueButton, NameStepView, Bool, String, Void

### Community 128 - "OnboardingChrome.swift"
Cohesion: 0.47
Nodes (5): OnboardingBackButton, OnboardingProgressBar, OnboardingTopBar, Int, Void

### Community 130 - "supabase/ — schema under version control"
Cohesion: 0.33
Nodes (5): ⚠️ Baseline is incomplete, supabase/ — schema under version control, The rule, Two-repo note, Workflow

### Community 131 - "Triangle"
Cohesion: 0.40
Nodes (4): Concern, Delivered, Task 4 — Community Feed Integration, Verification

### Community 132 - "ClubView"
Cohesion: 0.31
Nodes (4): ClubView, ActivitiesModel, Set, String

### Community 133 - "HyggeTests"
Cohesion: 0.40
Nodes (4): Adding the target (one time, ~15 seconds in Xcode), HyggeTests, Next (per REVIEW.md), What's covered (Phase 1)

### Community 134 - "UIKit"
Cohesion: 0.31
Nodes (5): Photo, PhotoView, String, UIImage, UIKit

### Community 136 - "QuickAddSheet"
Cohesion: 0.33
Nodes (4): QuickAddSheet, Binding, Bool, String

### Community 144 - "InterestCard"
Cohesion: 0.29
Nodes (5): InterestCard, PressableCardStyle, Bool, Configuration, Void

### Community 145 - ".isAdmin"
Cohesion: 0.33
Nodes (3): Admin, firstNameFromEmail(), Bool

### Community 146 - "StreakHeroCard"
Cohesion: 0.40
Nodes (4): StreakHeroCard, CGFloat, Double, String

### Community 147 - "UpcomingInsightsView"
Cohesion: 0.40
Nodes (3): Content, String, UpcomingInsightsView

### Community 149 - "EventRow"
Cohesion: 0.50
Nodes (3): EventRow, String, Void

## Knowledge Gaps
- **556 isolated node(s):** `home`, `activities`, `calendar`, `map`, `EventKit` (+551 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **17 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `AuthStore` connect `AuthStore` to `Session`, `CommunityFeedBucketer.swift`, `ClassifiedEvent`, `QuickAddSheet`, `.decode`, `BoardRow`, `SJMapView`, `Codable`, `.monthDateRows`, `.rsvpEvent`, `ProfileAPI`, `CalendarView`, `onThisDay`, `.run`, `Foundation`, `ModerationView`, `.validAccessToken`?**
  _High betweenness centrality (0.077) - this node is a cross-community bridge._
- **Why does `SwiftUI` connect `SwiftUI` to `OnboardingChrome.swift`, `.event`, `.sections`, `CommunityFeedBucketer.swift`, `UIKit`, `.isFresh`, `QuickAddSheet`, `BoardRow`, `String`, `.monthDateRows`, `.rsvpEvent`, `ClubStatus`, `InterestCard`, `SpeedDialItem`, `StreakHeroCard`, `DayDetailView`, `BentoStatGrid`, `UpcomingInsightsView`, `CalendarView`, `EventRow`, `POI`, `MainTabsView`, `SpotFilter`, `ProfileView`, `.bottomSheet`, `ShareCenter`, `Spot`, `EventCategory`, `ExploreKit.swift`, `OnboardingView`, `ButtonStyle`, `Image`, `TodayInStJoeContent`, `MapIntroView.swift`, `InlineAction`, `CoreLocation`, `TownMenuAction`, `View`, `.minutesOf`, `TrailsMapView`, `SpringReveal`, `TrailsListView.swift`, `EntriesStatCard`, `AroundTownCarousel`, `PlaceFamily`, `ProfileAPI`, `VenueAutocompleteField`, `ProfileModel`, `StaggeredAppear`, `SafariView`, `ModerationView`, `GlassShowcaseOverlay`, `Masthead`, `PlaceDetailView`, `InsightsMiniCalendar`, `HyggeLogoBadge.swift`, `InterestPickerView`, `StreakHeroCard`, `ContinueButton`?**
  _High betweenness centrality (0.069) - this node is a cross-community bridge._
- **Why does `CommunityAPI` connect `.decode` to `ClubView`, `ShareTargets.swift`, `ClassifiedEvent`, `QuickAddSheet`, `BoardRow`, `Trail`, `.rsvpEvent`, `ProfileAPI`, `CalendarView`, `ModerationView`?**
  _High betweenness centrality (0.044) - this node is a cross-community bridge._
- **What connects `home`, `activities`, `calendar` to the rest of the system?**
  _556 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `.event` be split into smaller, more focused modules?**
  _Cohesion score 0.11742424242424243 - nodes in this community are weakly interconnected._
- **Should `.sections` be split into smaller, more focused modules?**
  _Cohesion score 0.060534822215692036 - nodes in this community are weakly interconnected._
- **Should `CommunityFeedBucketer.swift` be split into smaller, more focused modules?**
  _Cohesion score 0.06810035842293907 - nodes in this community are weakly interconnected._