# Upcoming Insights — Personal Spotlight Edition

**Date:** 2026-07-16 · **Status:** approved design, ready for implementation
**Scope:** the Calendar tab's "Upcoming" face (`Hygge/Features/Calendar/Insights/`)

## Problem

The Upcoming face is an Insights dashboard whose **layout & motion** were ported 1:1
from a journaling-app reference (commit `5f909d6`), but whose content is journaling
semantics remapped to bare counts — the bento literally shows the same numbers nested
three ways (This Week / This Month / Upcoming). It reads as stats, not insights.

**Goal:** keep the layout and motion exactly; replace the content with *personal,
real-data town insights* — things you cannot get from staring at a plain calendar.

Grounded in a 53-pattern research pass (event platforms, hyperlocal community apps,
insight-dashboard design, anticipation psychology, calendar-intelligence products).
Key findings applied: anticipation beats retrospection (Van Boven & Ashworth);
day-part copy beats clock times — clock framing makes leisure feel like work
(Tonietto & Malkoc); presence-only social proof with honest absence at zero; every
stat should hand the user a decision (a doorway), not a mirror; design the sparse
case first.

## Decisions (from brainstorm)

1. **Very personal** — driven by onboarding interests + the user's RSVPs.
2. **Popularity = real RSVP counts**, neighborly framing, graceful fallback.
3. **Hero = a swipeable spotlight wheel**: your big event first, then the town's.
4. **No weather** — purely calendar + people data. (Optional future: a January
   "+N min more daylight than yesterday" hero page — pure on-device astronomy,
   no API. Explicitly out of scope for v1.)
5. Layout, card sizes, palette (`InsightsPalette`), and tap-to-expand motion are
   unchanged. Content only.

## Design — slot by slot

### 1 · Hero: the Spotlight wheel

Same 218pt dark-blob card (`StreakHeroCard` visual language), now a horizontally
**paged carousel** (iOS-native paging, page dots at the bottom edge). Each page
keeps the giant countdown numeral with one event as the star:

- **Page 1 — Yours:** soonest RSVP'd event; if none, the **soonest** upcoming
  event matching any picked interest. `3 · Days — Trivia at the Middy · you're going`
- **Page 2 — The town's:** the most-RSVP'd upcoming event (rare annuals like
  Joetown Rocks naturally win). Reason line is count-based social proof when real:
  `5 neighbors are going` — the line is **absent at zero**, never "Be the first!".
  (Names-preferring-follows, e.g. "Anna and 2 neighbors", is a flagged follow-up —
  it needs a new rsvps→town_profiles read; v1 ships count-only.)
- **Page 3 — Next up:** the town's soonest happening, so the wheel always has
  a page.
- Pages **dedupe** (if your event *is* the town's big one, no repeat).
  Signed-out / cold start: pages 2–3 only. `Today` replaces the numeral when the
  event is today (existing hero convention). Empty calendar: single page, `—`,
  "Nothing on the calendar yet".
- Wheel motion: calm and native — paged `ScrollView`/`TabView` snap, no parallax,
  no autoplay. Reduce Motion honored (no springy embellishment).

### 2 · Chart card → "Your Year Ahead"

Big count = upcoming events matching **your** interests; the 12-month bars show
where *your* matches land; the town's totals render as ghost bars behind for
context. Subtitle is a significance sentence naming the real peak:
`August is your fullest month ahead.`
No interests picked → town totals + one quiet `Pick interests to make this yours.`

### 3 · Bento → your 3 interest categories

Each tile is one onboarding interest — title from its `Interest.label`, big
number = upcoming keyword matches: e.g. **Live Music · 3 / Trails · 2 /
Breweries · 4**. Tap-to-expand motion unchanged; expanded sub-stats:

- Sub-stat A: `This week · N`
- Sub-stat B: a **doorway** — `Next · Friday evening` — tapping the expanded tile
  (or the sub-stat) opens that day's detail (`DayDetailView` route the grid face
  already uses).

Selection rules: user picked >3 interests → show the 3 with the most upcoming
matches; <3 picked → fill remaining tiles with the town's most active categories
(marked by their plain names, no pretense they were picked); zero matches renders
an honest `0` with a quiet line, e.g. `A quiet stretch for trails.`

### 4 · Mini month grid

Real current month (existing `InsightsMiniCalendar`): **soft neutral dot** = a day
holding any town happening; **coral dot** = *your* day (RSVP'd or interest-matched).
Caption stays quiet and forward: `Your next full day: Friday.` Never render a
"missed" count — count what happens *for* the user, never the negative space.

### 5 · Copy grammar (applies everywhere)

- Day-parts first, clock times secondary: `Friday evening — live music`, never
  `7:00 PM: Concert`.
- No exclamation points, no imperatives, no "last chance". Neighbor register.
- Compare only to the town's/your own baseline, never user-vs-user.
- **Design the sparse case first**: every zero renders as an honest zero with the
  best sentence in the app. Real data only — 0 reads as 0.
- Countdown framing is reserved for genuinely scarce things (page 1/2 spotlight);
  recurring events are named by their rhythm, not counted down to.

## Data plumbing (no schema changes)

- `CommunityAPI.rsvpCounts(eventIds:)` (currently private, line ~200) becomes
  public/internal.
- `CalendarModel.load` gains two **parallel** reads alongside the existing range
  query: `getMyUpcomingRsvps()` and `rsvpCounts` for the upcoming event ids.
  Signed-out or failed personal reads degrade to town-only content (log, don't
  block the dashboard).
- Interests come synchronously from `Interests` (UserDefaults, already mirrored
  from `town_profiles` by `RootView.hydrateIfNeeded`). Matching is the **existing
  keyword-contains** mechanism over `AgendaEvent.title + location` — the same one
  "Suggested for you" uses. No new matcher.
- `InsightsData.from(...)` stays a **pure function** — new inputs (myRsvps,
  rsvpCounts, selected interests), same testable shape. Unit-test the pure logic
  with the repo's `swiftc -D DEBUG` harness (pin TZ; spotlight ladder, dedupe,
  interest tile selection, sparse cases).
- Immutability: new value-type inputs/outputs; no mutation of model state outside
  `@MainActor` publishes (house pattern).

## Verification

- Build clean, **0 warnings** (watch the MainActor-default gotchas: pure helpers
  `nonisolated`; no `try?` on non-throwing calls).
- Extend `-insights-sample` so every card state screenshots headlessly on a
  signed-out sim: spotlight pages (add `-insights-page <n>`), populated + sparse +
  empty variants, expanded bento tiles.
- Wheel paging + bento expand verified with the frame-montage method (record sim →
  extract frames → contact sheet), per `verifying-animations-frame-montage`.
- Screenshot review: hero pages 1–3, chart with/without interests, all three bento
  tiles expanded, mini grid with both dot kinds, and the empty-calendar state.

## Out of scope (explicitly)

Weather, daylight astronomy, "since you were here" newness lines, RSVP'er names
on social proof, streak-anything, notification hooks, layout changes.
