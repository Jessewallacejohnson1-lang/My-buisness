# Post composer + Activities + Claude moderation — design (v2, Expo stack)

**Date:** 2026-06-24 (revised after discovering v1 targeted the legacy `apps/web` site)
**Status:** Pending approval
**App:** Hygge — St. Joseph, MN community app. **Active codebase: `apps/mobile` (Expo/React Native) + `packages/core` (`@hygge/core`).** The shipping web build is the Expo web export (static SPA, no server).

## Why v2

v1 of this spec/plan was written against `apps/web` — the **legacy, non-shipping** Next.js site. Work there (a Next.js API route, edits to `apps/web/lib/community.ts`) was reverted. This v2 targets the real app: React Native screens in `apps/mobile`, shared queries in `packages/core`, and a **Supabase Edge Function** for moderation (the SPA has no server to host an API route).

## Summary

Turn the **Add an event** tab into a single **Post** composer with a kind picker — **Event · Club · Trail** — each adapting its fields, with the existing optional photo upload. Every submission is screened by Claude (text + image) via a Supabase Edge Function before going live. Reshuffle navigation to **4 calm tabs**, fold the daily Quest into Home, and add an **Activities** tab (replacing Clubs) that browses Clubs + Trails and hosts an admin review queue.

## Decisions (from brainstorming)

| Question | Decision |
|---|---|
| Section name | **Post** ("New post") |
| Photo | **Optional** (reuses existing `uploadEventImage` → `event-images` bucket) |
| Kinds | **Event, Club, Trail** (Notice dropped) |
| "Club" kind | **Reuses the existing `clubs` system** (`submitClub`), not a new table |
| "Trail" kind | **New, lightweight:** `club_events` row with `kind='trail'` (undated) |
| Moderation | Claude reviews text **and image**; **on-brand + safe** |
| Claude flags | **Warn + edit & resubmit** (nothing saved) |
| Check can't run | **Fail-closed → save as `pending`**; admin manual-approve valve |
| Moderation backend | **Supabase Edge Function** `moderate-post` (key = Supabase secret) |
| Navigation | **4 tabs:** Home (+Quest) · Activities · Calendar · Post |
| Quest | Folded into the **bottom of Home**; Quest tab removed |
| Activities tab | Replaces Clubs; groups **Clubs + Trails** + admin review queue |

## Navigation (apps/mobile/src/app/(tabs)/_layout.tsx)

From 5 tabs (index, clubs, calendar, add, quest) → **4**: `index` (Home, now with Quest), `activities` (was `clubs`), `calendar`, `add` (now "Post"). The `quest` route/screen is removed as a tab; its logic moves into a Home section.

## The composer (apps/mobile/src/app/(tabs)/add.tsx → Post)

Reworks the existing screen (which already has a photo square + `uploadEventImage`):
1. **Kind picker first** — three pill toggles: Event · Club · Trail (RN `Pressable`s, moss-tinted when active). Default Event.
2. **Photo square** — the existing optional 150×150 upload (keep as-is; it already uploads to `event-images`).
3. **Title** — always.
4. **Adaptive fields:**
   - **Event** — date, time, location (required) + description → `api.addEvent`.
   - **Club** — host, when (`schedule`), where (`location`), vibe, about (`description`), what-to-expect (`expectations`) — maps to `ClubInput` → `api.submitClub`.
   - **Trail** — location/trailhead (required), length, difficulty (optional) + description → `api.addPost({kind:'trail', …})`.
5. **Submit** → moderation (below) → route to Home (event) or Activities (club/trail).

Uses existing theme tokens (`C`, `F`, `HAIRLINE`), `react-native-svg` icons from `components/icons.tsx`, `expo-haptics`. No emoji. Numbers in `F.mono` with tabular figures.

## Moderation: Supabase Edge Function

- **`supabase/functions/moderate-post/index.ts`** (Deno). Receives `{ kind, title, location?, description?, image_url?, … }`, calls the Anthropic API (text + image-by-URL when present), returns `{ ok: boolean, reason: string }`. `ANTHROPIC_API_KEY` is a **Supabase secret** (`supabase secrets set`).
- Client calls `supabase.functions.invoke('moderate-post', { body })` from the composer.
- **Before writing the function, follow the `claude-api` skill** for the current model id, vision block shape, and message format.
- **Outcomes:** `ok=true` → save approved (live). `ok=false` → show reason, edit & resubmit, nothing saved. invoke throws / non-2xx (key missing, outage) → **fail-closed**: save as `pending`, "waiting for review" confirmation.

## Data model

- **`supabase/migration-posts.sql`** (already revised): `club_events` gets `kind` (`event|trail`, default `event`), `length`, `difficulty`; `event_date`/`start_time` made nullable. Reuses existing `image_url` + `event-images` bucket. **Clubs unchanged** (separate `clubs` table).
- Trails ride on `club_events` with `kind='trail'`, no date.

## packages/core (community.ts + types.ts)

- `types.ts`: add `PostKind = 'event' | 'trail'`; `NewTrailInput`; `Trail` (board row); `image_url`/`status` already present where needed.
- `community.ts` (`createCommunityApi`): 
  - `addPost(input)` — inserts a `kind='trail'` row (status param; default `'approved'`).
  - `getTrails()` — approved trails for Activities.
  - `getPendingPosts()` / `getPendingClubs()` — admin queues (events/trails + clubs).
  - `approvePost(id)` / `rejectPost(id)` and `setClubStatus(id, status)` — admin actions.
  - Event readers (`getTodayEvents`, `getEventsByDate`, `getMonthEventDates`) gain `kind='event'` so trails never leak into the timeline/calendar.
  - `addEvent` gains an optional `status` so the composer can save events as `pending`.
  - Add all new fns to the returned api object.

## Surfacing

- **Home** — timeline (events) unchanged + **Quest section** appended (moved from the Quest tab; reuses `getTodayQuest`/`completeQuest`/count).
- **Calendar** — events only (unchanged once `kind='event'` filter lands).
- **Activities** (was Clubs) — existing Clubs list (join/leave, detail sheet, Start-a-club moves into the Post composer's Club kind) **+ a Trails group** + admin **"Waiting for review"** (pending clubs + pending trails, Approve/Decline). Admin gated by `isAdminEmail`.

## Error handling

- Image upload failure → existing behavior (returns null; post continues photo-less).
- `functions.invoke` failure → fail-closed `pending` path; never blocks the neighbor.
- Admin approve/decline failure → inline error, row stays in queue.

## What the user must do (out-of-band)

1. Run `supabase/migration-posts.sql` in Supabase.
2. Deploy the Edge Function: `supabase functions deploy moderate-post`.
3. Set the secret: `supabase secrets set ANTHROPIC_API_KEY=…`.

## On-brand check

Calm, neighborly, hyper-local; 4 tabs (down from 5) is *more* on-brand. No badges/streaks/feeds. Real counts only. Moss = approved/primary; clay = moderation warning only; sky = brand/focus. Inline svg, no emoji. Dates via `localDate()`.

## Scope note (phasing option)

The heart of the request is the **Post composer + moderation** (+ Activities so trails/clubs have a home). The **Quest→Home** relocation is independent polish. These can ship as one branch or be split (composer+moderation first, nav reshuffle second) if a smaller diff is preferred.

## Definition of done

Verified in the running Expo app (preview/simulator) at phone width: composer for all three kinds with photo; moderation pass/flag/pending paths; Activities shows clubs + trails + admin queue; Quest on Home; timeline/calendar still events-only. Matches `C`/`F` tokens; clears the on-brand bar.
