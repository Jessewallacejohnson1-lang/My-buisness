# Post composer + Board + Claude moderation — design

**Date:** 2026-06-24
**Status:** Approved (design), pending implementation plan
**App:** Hygge — St. Joseph, MN community app (`/community`)

## Summary

Replace the single-purpose **Add Event** form with an Instagram-style **Post**
composer that supports four kinds of community post — **Event, Club, Trail,
Notice** — each with an optional uploaded photo and kind-specific fields. Every
submission is reviewed by the Claude API (text **and** image) before it can go
live. A new **Board** tab surfaces the undated kinds (Club / Trail / Notice) and
hosts an admin-only "Waiting for review" queue as a manual safety valve.

This serves the product's #1 job — getting neighbors together IRL — by lowering
the bar to share anything local (a group to join, a trail to walk, a heads-up),
not just dated events, while keeping the timeline a calm "what's happening today."

## Goals

- One friendly composer for any community post, modeled on making an Instagram post.
- Optional photo on every post, stored in Supabase Storage.
- Claude moderation gate (on-brand + safe, image included) before a post goes live.
- Keep the daily timeline and calendar purely dated **events** — unchanged feel.
- Give undated posts (Club / Trail / Notice) a calm home: the **Board** tab.
- Never let a post be permanently stuck: admin can manually approve.

## Non-goals

- No public moderation/voting, reporting, or comment threads.
- No per-user profiles, follower counts, feeds, badges, or streaks (off-brand).
- No second storage system (Supabase only; not Vercel Blob).
- No editing/deleting of already-live posts in this iteration (future work).

## Decisions (from brainstorming)

| Question | Decision |
|---|---|
| Section name | **Post** ("New post"); tab label "Post" |
| Photo | **Optional** on every kind |
| Kinds | **Event, Club, Trail, Notice** |
| Extra fields | **Real columns**, not folded into description |
| Non-event home | **New "Board" tab** (5 tabs total) |
| Image storage | **Supabase Storage** (`post-images` bucket) |
| Moderation scope | On-brand + safe; **reviews the image too** (Claude vision) |
| Claude flags post | **Warn + edit & resubmit** (not saved) |
| Check can't run | **Fail-closed** → save as `pending`; **admin manual approve** valve |

## Navigation

Tab bar goes 4 → 5: **Home · Calendar · Post · Board · Quest**.
`Tab` type adds `'board'`; `'add'` tab id becomes `'post'`. This is the calm
ceiling — no further tabs should be added later.

## The composer (`PostTab`, replaces `AddEventTab`)

Top-to-bottom, Instagram-style:

1. **Kind picker first** — four quiet pill toggles: Event · Club · Trail · Notice.
   Selecting one reveals only that kind's fields. Default: Event.
2. **Image square** — large 1:1 tap-to-upload area, optional for all kinds.
   Shows preview thumbnail with a remove ✕ once chosen. Uploads to Supabase
   Storage on file-select; keeps the returned public URL in form state.
3. **Title** — always shown, required.
4. **Adaptive fields by kind:**
   - **Event** — `event_date`, `start_time`, `location` (all required) + `description` (optional).
   - **Club** — `cadence` (optional, e.g. "Thursdays 6pm"), `location` (optional) + `description` (optional).
   - **Trail** — `location`/trailhead (required), `length` (optional), `difficulty` (optional) + `description` (optional).
   - **Notice** — `description` (required); `location` (optional). No date.
5. **Submit** → moderation (below) → on pass route to Home (event) or Board (others);
   on pending route to Board with the "waiting for review" note.

Reuse existing `labelStyle` / `fieldStyle` / `.hygge-field` form styling and the
moss primary button. All numbers (dates, length) render `font-mono tabular-nums`.

## Data model

### `club_events` (reused as the posts table — no new table)

New / changed columns via `supabase/migration-posts.sql`:

- `kind text not null default 'event'` — one of `event | club | trail | notice`.
  Add a `check (kind in ('event','club','trail','notice'))` constraint.
- `image_url text` — public URL of the uploaded photo (nullable).
- `cadence text` — Club only (nullable).
- `length text` — Trail only (nullable).
- `difficulty text` — Trail only (nullable).
- `event_date date` and `start_time` made **nullable** (only Event requires them).

`status` (`pending | approved | rejected`) already exists and is reused:
moderation pass → `approved`; check-can't-run → `pending`; admin decline → `rejected`.

### Storage: `post-images` bucket

- New **public** Supabase Storage bucket `post-images`.
- RLS: signed-in users may `insert` objects under their own `auth.uid()` path
  prefix; public `select` (read). No update/delete by clients in this iteration.
- Path convention: `post-images/{auth.uid()}/{timestamp}-{filename}`.

## Surfacing

- **Home (timeline) & Calendar** — filter to `kind = 'event'` AND a non-null
  `event_date` AND `status = 'approved'`. Behavior/appearance unchanged.
- **Board (new `BoardTab`)** — `status = 'approved'` AND `kind in (club, trail,
  notice)`, grouped by kind (Clubs, Trails, Notices). Reuses the event-card
  visual; photo on top when `image_url` present; shows kind-specific fields
  (cadence / length+difficulty / location) instead of date.
- **Admin "Waiting for review"** — at the top of Board, only when
  `isAdminEmail(user.email)`: lists `status = 'pending'` posts with photo +
  **Approve** / **Decline**. Empty state hidden when queue is empty.

## Claude moderation

### Server route `app/api/moderate-post/route.ts`

- POST handler; uses the already-installed `@anthropic-ai/sdk` with
  `ANTHROPIC_API_KEY` (server-side only — the browser SDK is unsafe).
- Request body: the post fields (kind, title, fields, description) and, if a
  photo was uploaded, its public URL (fetched and passed to Claude as an image
  block for vision review).
- Prompt asks Claude to judge: (a) a real St. Joseph community post of its kind,
  not spam/ad/abusive/inappropriate; (b) the image (if any) is appropriate;
  (c) reads neighborly / on-brand. Returns strict JSON `{ ok: boolean,
  reason: string }` (reason shown to the user when `ok=false`).
- **Before writing this route, follow the `claude-api` skill** (model id,
  message shape, vision blocks, structured output).

### Client flow on submit

1. POST fields (+ image URL) to `/api/moderate-post`.
2. **`ok = true`** → `addPost(...)` with `status='approved'`; route to Home/Board; `haptic('success')`.
3. **`ok = false`** → show `reason` inline (clay text); do **not** insert; user edits & resubmits.
4. **Route throws / non-200 / key missing** (fail-closed) → `addPost(...)` with
   `status='pending'`; show calm "Your post is waiting for review" confirmation;
   route to Board.

## Lib changes (`lib/community.ts`)

- Generalize `NewEventInput` → `NewPostInput` (adds `kind`, `image_url`,
  `cadence`, `length`, `difficulty`; `event_date`/`start_time` optional).
- `addEvent` → `addPost(input, status)` (status defaults to `'approved'`).
- New: `uploadPostImage(file)` → Supabase Storage upload, returns public URL.
- New: `getBoardPosts()` (approved club/trail/notice), `getPendingPosts()`
  (admin), `approvePost(id)`, `rejectPost(id)`.
- `getTodayEvents` / `getEventsByDate` / `getMonthEventDates` add
  `kind = 'event'` + non-null-date filters.

## Error handling

- Image upload failure → inline error, photo cleared, rest of form preserved.
- Moderation route failure → fail-closed `pending` path (above), never blocks the
  neighbor from submitting.
- Admin approve/decline failure → inline error, row stays in queue.
- Missing `ANTHROPIC_API_KEY` → route returns a non-200 the client treats as
  fail-closed; surfaced once to admin via the pending queue filling up.

## What the user must do (out-of-band)

1. Paste the key into `ANTHROPIC_API_KEY` in `.env.local`.
2. Run `supabase/migration-posts.sql` in the Supabase SQL editor.
3. Create the public `post-images` Storage bucket + RLS policies (SQL provided
   with the migration).

## On-brand check

- Calm, neighborly, hyper-local; no badges/streaks/feeds/follower-counts.
- Real counts only (RSVP/going counts unchanged; no seeded numbers).
- Moss = approved/primary, clay = the moderation warning only, sky = focus.
- Inline `<svg>` icons only; no emoji. Numbers in `font-mono tabular-nums`.
- Dates via `localDate()` from `lib/db.ts`, never `toISOString()`.

## Definition of done

Verified in the running app via preview tools at ~390px: composer for all four
kinds, optional photo upload to Storage, moderation pass/flag/pending paths,
Board rendering + admin queue, timeline/calendar still events-only. Matches design
tokens; clears the on-brand bar.
