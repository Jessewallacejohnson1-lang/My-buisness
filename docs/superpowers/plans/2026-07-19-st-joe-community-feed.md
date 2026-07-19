# St. Joe Community Feed Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a calm, real-data, time-bucketed community-events feed to Hygge’s Today tab so a neighbor can find plans for today, this week, fresh additions, and later without engagement-ranking or fabricated activity.

**Architecture:** Keep the existing Today agenda as the `Happening today` bucket and source the three lower buckets from the existing approved `club_events` query. A pure bucketer classifies only future `UpcomingEvent` values by local-date semantics; `HomeModel` owns RSVP state and optimistic writes; a dedicated SwiftUI section renders compact, accessible event cards and a natural end state. No schema, RLS, notification, moderation, or SocialAPI work is part of this slice.

**Tech Stack:** Swift 5, SwiftUI, Foundation, existing hand-rolled Supabase REST client, existing `Reminders`, XcodeBuildMCP simulator verification.

## Global Constraints

- Work only in `/Users/owner/Documents/hygge-community-feed` on branch `feat/st-joe-community-feed`; do not modify the original dirty worktree.
- Use only real approved `club_events` and real RSVP counts; never create fixture data outside the DEBUG-only screenshot path and never fabricate social counts.
- Treat device-local date as authoritative. Do not parse `YYYY-MM-DD` as a UTC instant; input dates belong to `DateHelpers.localDate()` semantics.
- Preserve the existing top agenda as the `Happening today` bucket. The new section must contain, in this order, `This week`, `Fresh from around town`, then `Coming up later`.
- Bucket order is transparent and deterministic: date/time first for event buckets, recent creation time only for the Fresh bucket. Do not add behavioral or engagement ranking.
- Coral (`Hue.accent`) is reserved for Today / the primary RSVP action. Reuse `Hue`, `Radius`, `hyggeCard`, `Motion`, and `SpringReveal` tokens; do not introduce raw colors, shadows, or inline spring constants.
- Make section headings accessibility headings; each event card must expose date, time, place, attendance, and RSVP state to VoiceOver; buttons must remain independent controls with at least 44pt tap areas; support Dynamic Type and Reduce Motion.
- Never use generic stock imagery. Show an image only when `UpcomingEvent.imageUrl` is a real posted image; otherwise use a typographic card.
- Do not revive the historical `FeedCard`, `FeedSection`, or `CommentSheet` from commit `2436d14`; they depend on the abandoned SocialAPI surface and public social metrics that conflict with this feature.
- This repository has no XCTest target. Use the DEBUG-only assertion self-check for the pure bucketing contract, then require a zero-warning build and deterministic simulator screenshot verification.

---

### Task 1: Make time bucketing a pure, checked contract

**Files:**
- Create: `Hygge/Features/Home/CommunityFeed/CommunityFeedBucketer.swift`
- Create: `Hygge/Features/Home/CommunityFeed/CommunityFeedBucketerSelfCheck.swift`

**Interfaces:**
- Consumes: `UpcomingEvent` from `Hygge/Backend/Models.swift` and `DateHelpers.minutesOf(_:)` semantics.
- Produces: `CommunityFeedBucket`, `CommunityFeedSection`, and `CommunityFeedBucketer.sections(for:today:now:)` for the SwiftUI renderer.

- [ ] **Step 1: Write the DEBUG-only failing self-check first**

Create `CommunityFeedBucketerSelfCheck.swift` under `#if DEBUG`. It must construct fixtures with `today = "2026-07-19"` and `now = 2026-07-19T12:00:00Z`, call the not-yet-defined `CommunityFeedBucketer.sections(for:today:now:)`, and assert all of these exact behaviors:

```swift
assert(sections.map(\.bucket) == [.thisWeek, .fresh, .later])
assert(sections[0].events.map(\.id) == ["tomorrow-early", "tomorrow-late", "day-seven"])
assert(sections[1].events.map(\.id) == ["fresh-day-eight"])
assert(sections[2].events.map(\.id) == ["later-day-eight", "later-tie-a", "later-tie-b"])
```

Fixtures must also include a same-day event, an invalid-date event, and a stale-created day-eight event. They must not appear in any lower feed section. `later-tie-a` must precede `later-tie-b` when both date and time match, proving source-order stability.

- [ ] **Step 2: Run the Debug build and verify the expected RED failure**

Run the configured simulator build after the self-check file exists. Expected result: compilation fails because `CommunityFeedBucketer`, `CommunityFeedBucket`, and `CommunityFeedSection` do not exist yet. Record the missing-symbol failure in the task report.

- [ ] **Step 3: Implement the smallest pure bucketer**

Create these public-to-module types in `CommunityFeedBucketer.swift`:

```swift
enum CommunityFeedBucket: String, CaseIterable, Identifiable {
    case thisWeek
    case fresh
    case later

    var id: Self { self }
    var title: String {
        switch self {
        case .thisWeek: "This week"
        case .fresh: "Fresh from around town"
        case .later: "Coming up later"
        }
    }
}

struct CommunityFeedSection: Identifiable {
    let bucket: CommunityFeedBucket
    let events: [UpcomingEvent]
    var id: CommunityFeedBucket { bucket }
}

enum CommunityFeedBucketer {
    nonisolated static func sections(
        for events: [UpcomingEvent],
        today: String = DateHelpers.localDate(),
        now: Date = Date()
    ) -> [CommunityFeedSection]
}
```

Implement private, `nonisolated` local-date helpers inside the enum. Discard blank or malformed date strings and every event on or before `today`; the existing Home agenda owns those events. Use day offsets from `today` to assign one mutually-exclusive bucket:

```swift
1...7          -> .thisWeek
8...            -> .fresh when createdAt is no older than 7 × 24 × 60 × 60 seconds from now
all remaining   -> .later
```

Sort This Week and Later by event date ascending, `DateHelpers.minutesOf(startTime)` ascending, then original input index. Sort Fresh by parsable ISO-8601 `createdAt` descending, then event date/time, then original input index. Omit empty sections from the returned array and preserve the fixed bucket order.

- [ ] **Step 4: Run the DEBUG self-check and verify GREEN**

Add a temporary DEBUG invocation only in the task-local validation path, or compile a tiny invocation against the new source. Expected result: the self-check assertions all pass and the Debug app target compiles with no warnings.

- [ ] **Step 5: Commit the contract**

```bash
git add Hygge/Features/Home/CommunityFeed/CommunityFeedBucketer.swift \
  Hygge/Features/Home/CommunityFeed/CommunityFeedBucketerSelfCheck.swift
git commit -m "feat(home): add community feed bucketer"
```

### Task 2: Provide future-event RSVP state to the Home feature

**Files:**
- Modify: `Hygge/Backend/Models.swift:64-76`
- Modify: `Hygge/Backend/CommunityAPI.swift:168-182,332-354`
- Modify: `Hygge/Features/Home/HomeModel.swift:9-104`

**Interfaces:**
- Consumes: `CommunityFeedBucketer.sections(for:today:now:)` from Task 1 and existing `CommunityAPI.rsvpEvent(_:)` / `unRsvpEvent(_:)`.
- Produces: `HomeModel.upcoming`, `HomeModel.communityFeedLoaded`, and `HomeModel.toggleUpcomingRsvp(_:_: )` for Task 3.

- [ ] **Step 1: Add the missing domain state without breaking existing callers**

Extend `UpcomingEvent` with defaulted properties so current memberwise construction remains source-compatible:

```swift
var rsvpd: Bool = false
var clubName: String? = nil
var category: EventCategory = .other
```

- [ ] **Step 2: Enrich only the existing upcoming-events reads**

In `CommunityAPI.getUpcomingEvents()`, select `clubs(name)` alongside the existing event fields. Fetch `event_id,user_id` rows for the returned IDs once, calculate both each event’s count and whether `auth.userId` is in that event’s RSVP set, then populate the three new `UpcomingEvent` properties. Preserve `status=approved`, `kind=event`, `event_date=gte.<local today>`, and `Self.realOnly` exactly.

In `getMyUpcomingRsvps()`, set `rsvpd: true` on its returned `UpcomingEvent` values. Do not add a migration or alter any RLS query.

- [ ] **Step 3: Add independent Home feed state and safe optimistic RSVP handling**

Add these properties to `HomeModel`:

```swift
@Published var upcoming: [UpcomingEvent] = []
@Published var communityFeedLoaded = false
private var upcomingRsvpInFlight: Set<String> = []
```

After the existing Today/quest fetch, independently load `upcoming = try await api.getUpcomingEvents()`. A failure must retain prior values, set `communityFeedLoaded = true`, log the error, and never blank the existing Today agenda.

Implement `toggleUpcomingRsvp(_ api: CommunityAPI, _ event: UpcomingEvent) async` with the same per-ID optimistic-update / success re-assertion / error rollback discipline already used by `toggleRsvp`. Ignore a second tap while an event id is in `upcomingRsvpInFlight`. Do not update the top Today agenda here because Task 1 excludes same-day values from the lower feed.

- [ ] **Step 4: Build the app and check the client contract**

Run a Debug simulator build. Expected result: existing Activities and Profile callers still compile because new `UpcomingEvent` fields are defaulted; no warnings are introduced.

- [ ] **Step 5: Commit the data state**

```bash
git add Hygge/Backend/Models.swift Hygge/Backend/CommunityAPI.swift Hygge/Features/Home/HomeModel.swift
git commit -m "feat(home): load community feed event state"
```

### Task 3: Render the warm lower-bucket feed

**Files:**
- Create: `Hygge/Features/Home/CommunityFeed/CommunityFeedTimelineView.swift`

**Interfaces:**
- Consumes: `CommunityFeedBucketer.sections(for:today:now:)`, `UpcomingEvent`, `Reminders`, `Hue`, `Radius`, `hyggeCard`, `Motion`.
- Produces: `CommunityFeedTimelineView(events:isLoading:onToggleRsvp:onCompose:)` for Task 4.

- [ ] **Step 1: Create a focused SwiftUI renderer**

Declare this interface:

```swift
struct CommunityFeedTimelineView: View {
    let events: [UpcomingEvent]
    let isLoading: Bool
    var onToggleRsvp: (UpcomingEvent) -> Void
    var onCompose: (() -> Void)?
}
```

It must use `CommunityFeedBucketer.sections(for: events)` and render each non-empty section in bucket order. Give each title `.accessibilityAddTraits(.isHeader)`.

- [ ] **Step 2: Implement the card hierarchy and interactions**

Each event card must use a date badge, title, time/place row, low-key `N going` text, a primary `RSVP` / `Going` button, and a separate calendar-save button. The button labels must be independent accessibility elements; do not wrap the card in a button.

Use this exact interaction rule:

```swift
Button(event.rsvpd ? "Going" : "RSVP") {
    Haptics.light()
    onToggleRsvp(event)
}
.buttonStyle(PressableStyle(scale: 0.96))
```

The calendar save button must use existing `Reminders.isScheduled(eventId:)`, `Reminders.requestAuth()`, `Reminders.schedule(eventId:title:date:startTime:)`, and `Reminders.cancel(eventId:)`; its label must toggle between `Save` and `Saved`. Do not show generic imagery. If `imageUrl` resolves successfully, it may appear above the typographic card only in the Fresh section; all other layout must remain useful with no image.

- [ ] **Step 3: Implement honest loading, quiet, and end states**

When `isLoading` is true, show two non-interactive skeleton cards. When no sections have events, show:

```swift
"It’s a quiet day in St. Joe 🌿"
"Here’s what’s coming up when neighbors add plans."
"Post something"
```

The last line triggers `onCompose`. When sections exist, append an unboxed footer:

```swift
"You’re all caught up for now."
"More neighbor plans will appear here."
```

No likes, followers, badges, progress/streak mechanics, or infinite-scroll indicator may appear.

- [ ] **Step 4: Use existing motion and accessibility rules**

Use `Motion.snappy` only for RSVP-state changes and let `SpringReveal` be applied by the parent to the whole section, never to individual scrolling rows. Respect `accessibilityReduceMotion`; do not add keyframes or a new spring token. Avoid fixed text heights and include date, time, place, attendance, and RSVP state in each card’s combined accessibility label/value.

- [ ] **Step 5: Build and commit the renderer**

```bash
git add Hygge/Features/Home/CommunityFeed/CommunityFeedTimelineView.swift
git commit -m "feat(home): render time-bucketed community feed"
```

### Task 4: Integrate Today, add deterministic preview, and verify in the simulator

**Files:**
- Create: `Hygge/Features/Home/CommunityFeed/CommunityFeedPreview.swift`
- Modify: `Hygge/Features/Home/HomeView.swift:22-108`
- Modify: `Hygge/Features/Home/HomeModel.swift:21-66`

**Interfaces:**
- Consumes: `CommunityFeedTimelineView` from Task 3 and `CommunityFeedBucketerSelfCheck.run()` from Task 1.
- Produces: production Home integration plus DEBUG-only `-community-feed-preview` and `-community-feed-self-check` launch arguments.

- [ ] **Step 1: Add DEBUG-only deterministic fixtures**

In `CommunityFeedPreview.swift`, provide a `#if DEBUG` fixture set with an empty Today state and future events that render all three lower sections: three This Week items, one Fresh item, and two Later items. Fixture image URLs must be `nil`. Include a `TimelineEvent` fixture only when a preview needs to demonstrate the top RSVP state; never include the fixture path in release builds.

- [ ] **Step 2: Centralize Home loading for preview and production**

Add a private `loadHome()` async helper to `HomeView`. In DEBUG, if `ProcessInfo.processInfo.arguments` contains `-community-feed-self-check`, run `CommunityFeedBucketerSelfCheck.run()`. If arguments contain `-community-feed-preview`, call a DEBUG-only `HomeModel.loadCommunityFeedPreview()` and skip network fetches. Otherwise call the existing `model.load(api)`.

Make both the initial `.task` and `.refreshable` call `await loadHome()`. Preserve the existing collapse/reveal and almanac replay behavior.

- [ ] **Step 3: Place the feed without disturbing the page hierarchy**

Rename the existing top header from `Today` to `Happening today`; retain its existing `EventRow` RSVP behavior. Insert:

```swift
CommunityFeedTimelineView(
    events: model.upcoming,
    isLoading: model.loading && !model.communityFeedLoaded,
    onToggleRsvp: { event in Task { await model.toggleUpcomingRsvp(api, event) } },
    onCompose: onCompose
)
.padding(.horizontal, 18)
.springReveal(4, revealed: revealed, animated: revealAnimated)
```

immediately after `todaySection` and before `AroundTownCarousel`. Shift the carousel’s reveal index from `4` to `5`. The new feed must be shown even when Today is empty.

- [ ] **Step 4: Build and run the exact worktree binary**

Use XcodeBuildMCP, after confirming the session defaults point at `/Users/owner/Documents/hygge-community-feed/Hygge.xcodeproj`, the `Hygge` scheme, and the `Hygge-Shots` simulator. Build and run with:

```text
-community-feed-self-check -community-feed-preview
```

Capture a screenshot and inspect: all headings are ordered `Happening today → This week → Fresh from around town → Coming up later`; no fixtures leak into release code; the RSVP and Save controls are distinct and visible; the footer is visible; no clipping or tab-bar overlap occurs.

- [ ] **Step 5: Update graph, commit, and record verification**

Run `graphify update .` from the worktree, then commit:

```bash
git add Hygge/Features/Home/HomeView.swift \
  Hygge/Features/Home/HomeModel.swift \
  Hygge/Features/Home/CommunityFeed/CommunityFeedPreview.swift \
  graphify-out
git commit -m "feat(home): integrate St. Joe community feed"
```

Record the build and screenshot result in the task report before review.

