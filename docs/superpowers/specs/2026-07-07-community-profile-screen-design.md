# Community Profile screen — design spec

**Date:** 2026-07-07 · **Branch:** `mapbox-map-tab`

## Goal
A profile screen where a neighbor can see everything the app knows about them, in
one calm place. Layout copies a Revolut profile reference ~95% (avatar → name →
two feature cards → grouped list rows), but rendered in Block Party's **warm frosted
glass** — real iOS 26 translucency over the light canvas, coral accent — not the
reference's dark theme. Decided with the user:
- **Look:** warm frosted glass (see-through, on-brand), not dark.
- **Entry point:** the already-present (decorative) person glass button in Home's
  top-right Masthead → opens the profile as a frosted sheet.
- **Contents:** identity + **real** activity (no fabricated counts).

## Real data only
`town_profiles` is intentionally thin: `displayName`, `avatarUrl`, `interests[]`,
`onboardedAt`. Auth gives `email` + `userId` + `Admin.isAdmin`. Activity aggregates
did **not** exist per-user, so we add three queries (below). If a number can't be
made real, the row is omitted — never seeded.

## Components

### Backend — `CommunityAPI` (3 new methods, PostgREST, RLS-scoped)
- `getMyUpcomingRsvps() -> [UpcomingEvent]` — `event_rsvps` by `user_id` → those
  `club_events` with `event_date >= today`, approved, ordered; reuse `rsvpCounts`.
- `getMyClubs() -> [ClubView]` — `getApprovedClubs().filter(\.joined)`.
- `getMyQuestCount() -> Int` — count `quest_completions` by `user_id`.

### `ProfileModel` (`@MainActor ObservableObject`)
Owns display state. `load()` runs `ProfileAPI.getMyProfile()` + the 3 activity
queries concurrently (`async let`). Derives:
- name: `TownProfile.displayName ?? Interests.displayName ?? firstNameFromEmail(email) ?? email`
- since: `onboardedAt` ISO → "Neighbor since <Month YYYY>"
- `isAdmin`, interest labels via `Interests.all`.
`save(name:image:interests:)` mirrors `OnboardingView.finishData` (upload avatar →
`ProfileAPI.upsert` → mirror to `Interests`/UserDefaults) then reloads.

### `ProfileView` (frosted sheet)
- Presented `.sheet` from `HomeView` with `.presentationBackground(.ultraThinMaterial)`
  + `.presentationDragIndicator(.visible)` — the "see-through" hero.
- Overlay top bar: frosted **X** (dismiss, like `PlaceDetailView.closeButton`) +
  soft-coral **Edit** pill.
- Header: avatar (AsyncImage; blank person-slot when nil, coral edit badge), name
  (`display(26)`), "Saint Joseph, MN · Neighbor since …", admin "Town organizer"
  pill, interest chips (coral-soft pills).
- Two feature cards (glass panels): **Going to** (N upcoming RSVPs, coral) ·
  **Invite a neighbor** (share sheet).
- Grouped glass card "Around town": Events you're going to (N, expandable list) ·
  Clubs you've joined (N, expandable) · Quests completed (N).
- Grouped glass card "Settings": Edit profile · Notifications (opens iOS Settings) ·
  About Block Party · Account (email shown).
- Destructive: **Sign out** (`clay700`, confirmationDialog → `auth.signOut()`).

### `EditProfileView` (sheet)
Avatar well + PhotosPicker (reuse `AvatarStepView` pattern), name field, "Edit
interests" (reuse `InterestPickerView` grid via `Set<String>`), Save (`ContinueButton`).

## Motion (Emil / house rules)
- Section cascade: `.springReveal(index:revealed:)` (0.05 stagger, 0.48 spring,
  0.28 bounce) driven by `@State revealed` flipped in `.onAppear` — same as Home.
- Rows/cards: `PressableStyle` (0.97). Expand/collapse: `spring(0.42, 0.86)` +
  chevron rotation. Haptics: `.light` taps, `.selection` nav, `.success/.error` save.
- Reduce Motion inherited from `SpringReveal`; content visible by default (no
  visibility gated on a transition that won't fire headless).

## Tokens (reuse, no new hexes)
`Hue.paper/canvas/accent/accentSoft/ink/ink2/ink3/hairline/clay700`, `Radius.*`,
`CardShadow`, `.ultraThinMaterial` (the app's one frosted primitive), `Font.*`
system helpers + `.monospacedDigit()` for all counts.

## Wiring
`Masthead` gains `onProfile: (() -> Void)?` on the `person` glass circle;
`HomeView` holds `@State showProfile` and presents `ProfileView` (inherits
`AuthStore` env). New files live in `BlockParty/Features/Profile/` (auto-joins the
target via the Xcode synchronized group).

## Verify
Build clean (0 warnings) + screenshot loop in the iPhone 17 sim (a signed-in
account with a `town_profiles` row), plus the empty/loading states.
