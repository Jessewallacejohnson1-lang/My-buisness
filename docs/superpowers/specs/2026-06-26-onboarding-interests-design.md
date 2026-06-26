# Welcome onboarding (interest-tailored) — design

**Date:** 2026-06-26
**Status:** Approved (design), pending implementation plan
**App:** Hygge — St. Joseph, MN community app. Active codebase: `apps/mobile` (Expo/React Native) + `packages/core`.

## Summary

A calm, one-time **welcome onboarding** that asks a new resident which kinds of community life they're into, then gently surfaces matching **clubs & trails** so newcomers can "find their people" (product job #3). Interests are kept on-device; matching is plain client-side keyword matching against data the app already loads — **no schema changes, no new backend**. The tailoring shows as a quiet **"Suggested for you"** group at the top of the Activities tab.

## Goals

- Help a newcomer immediately find clubs/trails that fit them.
- Stay calm and on-brand: no algorithmic ranked feed, no badges/streaks, real matches only.
- Ship now, testable on the web build (no device, no Supabase setup).

## Non-goals

- No server-side personalization, no profiles table (v1 is on-device).
- No tagging/categorizing of clubs/trails (we keyword-match existing text).
- No notifications (separate follow-up spec).
- No cross-device sync of interests (acceptable for v1; revisit with notifications).

## Decisions (from brainstorming)

| Question | Decision |
|---|---|
| What onboarding tailors | Pick interests → suggest matching clubs/trails |
| Matching mechanism | **Client-side keyword match** on club/trail name/vibe/description (trails auto-match Outdoors) |
| Storage | **AsyncStorage** (device-local): interests array + `onboarded` flag |
| Surface | **"Suggested for you"** group pinned atop the Activities tab |
| Skippable | Yes — "Skip for now" on every step |
| Editable later | Yes — "Edit interests" from the account menu (re-runs the picker) |
| Sequencing | Onboarding first; local RSVP reminders later (separate spec) |

## Interest taxonomy

Nine curated, local interests. Each has a `keywords` list used for matching:

| Interest | Keywords (lowercased substring match) |
|---|---|
| Outdoors & Trails | hike, walk, run, bike, nature, park, river, trail, outdoor |
| Music & Arts | music, art, choir, band, craft, paint, theater, sing, dance |
| Food & Drink | food, coffee, dinner, potluck, bake, brew, market, meal, supper |
| Families & Kids | kid, family, parent, story, playgroup, youth, child, mom, dad |
| Faith & Fellowship | church, faith, prayer, bible, parish, worship, mass, fellowship |
| Sports & Fitness | sport, fitness, yoga, gym, league, ball, swim, workout, pickleball |
| Books & Learning | book, read, class, learn, study, library, lecture, write |
| Service & Volunteering | volunteer, service, give, clean, donate, help, charity, drive |
| Games & Social | game, cards, trivia, social, meetup, hang, club, board |

Trails (`kind='trail'`) always count toward **Outdoors & Trails** regardless of text.

## Architecture

### New: interests module (`apps/mobile/src/lib/interests.ts`)
- `INTERESTS: { id: string; label: string; keywords: string[] }[]` — the taxonomy above.
- `getInterests(): Promise<string[]>` / `setInterests(ids: string[]): Promise<void>` — read/write `hygge.interests` in AsyncStorage.
- `isOnboarded(): Promise<boolean>` / `setOnboarded(): Promise<void>` — read/write `hygge.onboarded`.
- `matches(text: string, interestIds: string[]): boolean` and a `scoreMatch`/`filterSuggested(items, interestIds, isTrail)` helper used by the suggestion surface.

### New: onboarding route (`apps/mobile/src/app/onboarding.tsx`)
- A stack screen (sibling of `index`/`login`/`(tabs)` in the root `_layout`), `headerShown:false`.
- Steps (single screen, local step state — not multiple routes):
  1. **Hello** — warm one-liner intro (Spectral display), "Get started" / "Skip for now".
  2. **Interests** — the nine interest chips, multi-select (moss tint when selected); "Continue".
  3. **Suggestions** — "A few to check out" listing matched clubs/trails (reuses the Activities card visual); "Take me in" → tabs. If nothing matches, show a calm line ("More neighbors are joining — check back soon") and the button.
- On finish or skip: `setInterests(...)` (if any), `setOnboarded()`, `router.replace('/(tabs)')`.

### Auth-gate integration (`apps/mobile/src/app/_layout.tsx` → `RootNav`)
- Current gate: signed-out + in tabs → `/login`; signed-in + outside tabs → `/(tabs)`.
- Add: when `session` exists and `!onboarded`, route to `/onboarding` (instead of/along the existing signed-in path). Read the onboarded flag once on session change into local state; treat `'(tabs)'` and `'onboarding'` both as "inside" so the gate doesn't fight the onboarding screen. Skipping/finishing sets the flag and proceeds to tabs.

### Suggestion surface (`apps/mobile/src/app/(tabs)/activities.tsx`)
- On load, read `getInterests()`. Compute `suggested = filterSuggested([...clubs, ...trails], interests)`.
- Render a **"Suggested for you"** section at the very top **only when `suggested.length > 0`**, using the existing club/trail card components. The existing Clubs and Trails groups render unchanged below it.
- Admin "Waiting for review" (if present) stays above everything, as today.

### Account menu (`apps/mobile/src/components/AccountMenu.tsx`)
- Add an **"Edit interests"** item that routes to `/onboarding` (which, when already onboarded, opens straight to the interests step). Re-saving updates AsyncStorage.

## Data flow

1. First signed-in launch → gate sees `!onboarded` → `/onboarding`.
2. User picks interests → stored in AsyncStorage → `onboarded=true` → tabs.
3. Activities reads interests → keyword-matches loaded clubs/trails → shows "Suggested for you".
4. "Edit interests" (account menu) re-opens the picker; saving updates suggestions next time Activities loads.

## Error handling

- AsyncStorage read failure → treat as "no interests / not onboarded" (fail toward showing onboarding once; never crash). Write failure → still proceed into the app (don't trap the user); suggestions simply won't tailor.
- Empty interests or zero matches → "Suggested for you" is omitted entirely (no empty section, no filler).

## On-brand check

- Calm, neighborly, hyper-local; serves "find your people." No badges/streaks/feeds/follower-counts, no notification spam.
- "Suggested for you" shows **only real matches** — never seeded or padded. Honest emptiness over fake social proof.
- Surfaces use `C`/`F`/`HAIRLINE` tokens; moss = selected/primary; inline `react-native-svg` icons, no emoji; any numbers in `F.mono`.

## Definition of done

Verified in the running app (web at phone width): first run shows onboarding; picking interests stores them and lands in tabs; Activities shows a "Suggested for you" group matching those interests (and hides it when none match); "Skip for now" works; "Edit interests" from the account menu re-opens the picker and updates suggestions. Typecheck clean + `expo export` bundles. Clears the on-brand bar.
