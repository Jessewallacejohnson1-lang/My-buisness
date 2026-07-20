# Today Tab Remake — Design Spec

**Date:** 2026-07-11 · **Branch:** `mapbox-map-tab` · **Feature:** Rebuild the Home ("Today") tab as a three-zone screen — a living almanac, today's agenda, and a komoot-style interest feed — backed by a new, real social layer (follow / like / comment).

---

## 1. Goal

Remake the Today tab (`BlockParty/Features/Home/`) into three stacked, scrollable zones:

1. **Almanac** (top) — a living, weather-reactive header: real weather, sun times, moon phase, an AI "read of the day" line, an "On this day in St. Joe" fact, and the daily-quest momentum ring.
2. **Today's Agenda** (middle) — the real `getTodayEvents()` list as a clean timeline.
3. **The Feed** (bottom) — a **1:1 komoot Home-card clone**: account row + Follow, big text-over-photo hero with overlay title + stat line, and an engagement row (like / comment / save / share). Content is recently-posted events, prioritized to the user's onboarding interests. Every count is real, backed by new tables.

The stickiness goal ("Duolingo energy") is delivered through **motion, the living almanac, quest momentum, and tactile social interactions** — **not** a mascot (see §3).

## 2. Decisions locked (from brainstorming, 2026-07-11)

| Decision | Choice |
| --- | --- |
| Layout | Almanac → Agenda → komoot feed (mockup approved) |
| Social layer | **Build it for real** — new `town_follows`, `event_likes`, `event_comments` tables |
| Feed voice | **Literal komoot** — "Follow", "N followers", "N liked this", "N comments" — on real data |
| Almanac richness | **Rich** — weather + sun + AI day-line + moon phase + "on this day" |
| Companion mascot | **None for now** (user dislikes the AI artwork style). Leave a clean insertion hook. |
| Interactivity home | Motion + living almanac + quest ring + tactile Follow/Like/Save (no gamification chrome: no streaks, XP, badges, leaderboards) |

## 3. Scope & non-goals

**In scope:** the three zones; the social backend + RLS; the feed read path; surfacing event `image_url`; local moon-phase math; a small curated "on this day" source; the motion/polish pass.

**Non-goals / deferred:**
- **No mascot / companion character.** A `CompanionSlot` view hook may be stubbed (rendering nothing) so a future illustrated character can drop in without re-plumbing, but no art ships now.
- No push notifications, no email digests, no follower *feed of activity* beyond the Today feed itself.
- No threaded/nested comments — comments are **flat, one level**.
- No changes to the Map, Calendar, Activities, or Onboarding tabs beyond what the shared components require.

## 4. The three zones

### Zone 1 — Almanac (living header)

A single rounded hero card, reusing the existing weather stack.

- **Reuse:** `WeatherService` (`WeatherBar.swift`) for temp / high / low / condition / **sunrise / sunset**; `WeatherBackground` gradients + looping MP4 backdrops for the weather-reactive sky; `DailyAlmanac.line(auth:)` for the AI "read of the day" sentence.
- **Net-new — moon phase:** computed **locally** from the date (synodic-month math; no API/key). Renders a phase glyph + name (e.g. "Waxing gibbous") and, optionally, illumination %.
- **Net-new — "On this day in St. Joe":** a small **curated** source (see §6.4). Real, cited facts only (per the St. Joe content-sourcing rule). When no fact exists for today, the line is **hidden** (graceful) — never fabricated.
- **Quest momentum:** the existing `getTodayQuest()` + completion count, presented as a **progress ring** (done/target within the day's quest) with a satisfying spring-pop + haptic on completion. **No streak counter.**
- **Motion:** temp count-up on load; sun-arc position by time of day; sky transitions with weather state; honors Reduce Motion.

Replaces the current `TodayInStJoeCard` hero as the top element. The board/"Today in St. Joe" curated items either fold into the feed or are retired from Home (decision in plan; leaning: retire from Home, the feed supersedes it).

### Zone 2 — Today's Agenda

- **Data:** `getTodayEvents()` → `[TimelineEvent]` (already loaded by `HomeModel.today`).
- **UI:** a clean timeline (time · title · venue · going count · RSVP), reusing/evolving `EventRow`. **Live-now** events get the coral stripe + dot (`DateHelpers.isLiveNow`, `start ≤ now ≤ start+2h`).
- **Empty state:** the warm "A clear day in St. Joe" card (existing `TodayCard`).

### Zone 3 — The Feed (komoot 1:1)

A vertical list of `FeedCard`s. Each card, top → bottom, mirrors the komoot Home card exactly:

1. **Account row:** avatar + display name + **"N followers · posted Xh ago"** + a **Follow / Following** button (real `town_follows`). The account is the **club** (`club_id`) that posted, else the **submitter's town_profile** (`submitted_by`).
2. **Text-over-photo hero:** full-bleed event photo via the existing resolution chain (`RawEvent.image_url` → `KnownLocalPhoto` → `VenuePhoto`/Google Places → `ExploreBlankPhoto`), a bottom scrim, and overlay text: **kicker** (interest/category label) + **title** (event title) + **stat line** ("Sat 2:00p · Millstream Park · 8 going"). A heart button sits top-right (komoot parity).
3. **Engagement meta:** **"N liked this"** (real `event_likes`) · **"N comments"** (real `event_comments`) — literal komoot wording.
4. **Action row:** Like (heart) · Comment (opens `CommentSheet`) · Save · Share. Real, tactile, haptic.

**Ordering / tailoring:** fetch recent approved postings (`created_at desc`, `submitted_by IS NOT NULL`), then **prioritize interest matches** to the top using the existing free-text `Interests.matches()` primitive over each posting's `title` + `location` (+ club `vibe`/`schedule` when it's a club post). **Fallback:** when recent postings are sparse, blend in soonest-upcoming events so the feed is never empty.

**Comments:** flat list in a `CommentSheet`. New comments pass through the existing **Claude Moderation edge function** before insert (same discipline as event submission). Author can delete their own; admins can delete any.

## 5. New backend — the social layer

> ⚠️ **MIGRATION GATE.** These tables live in the **shared** Supabase project `lxdgwhvqjqmqliobwjpi`, which also backs the wellness app. **No SQL is applied to prod until the user explicitly greenlights it.** Before applying: (a) run `list_tables` to confirm `club_events` / `town_profiles` id column types, (b) apply on a **branch** first via the Supabase MCP, verify, then merge. Table names are community-namespaced to avoid collision with the wellness app.

### 5.1 Tables (draft SQL — confirm types at apply-time)

```sql
-- Follows: a user follows a club or a community member (town_profile)
create table if not exists public.town_follows (
  id           uuid primary key default gen_random_uuid(),
  follower_id  uuid not null references auth.users(id) on delete cascade,
  target_type  text not null check (target_type in ('club','profile')),
  target_id    uuid not null,
  created_at   timestamptz not null default now(),
  unique (follower_id, target_type, target_id)
);
create index on public.town_follows (target_type, target_id);
create index on public.town_follows (follower_id);

-- Likes on an event/posting (club_events row)
create table if not exists public.event_likes (
  id          uuid primary key default gen_random_uuid(),
  event_id    uuid not null references public.club_events(id) on delete cascade,
  user_id     uuid not null references auth.users(id) on delete cascade,
  created_at  timestamptz not null default now(),
  unique (event_id, user_id)
);
create index on public.event_likes (event_id);

-- Flat comments ("notes") on an event/posting
create table if not exists public.event_comments (
  id          uuid primary key default gen_random_uuid(),
  event_id    uuid not null references public.club_events(id) on delete cascade,
  user_id     uuid not null references auth.users(id) on delete cascade,
  body        text not null check (char_length(body) between 1 and 500),
  created_at  timestamptz not null default now()
);
create index on public.event_comments (event_id, created_at);
```

### 5.2 RLS (real boundary — mirrors existing app posture)

```sql
alter table public.town_follows   enable row level security;
alter table public.event_likes    enable row level security;
alter table public.event_comments enable row level security;

-- Counts must be readable by any authenticated user
create policy read_follows  on public.town_follows   for select to authenticated using (true);
create policy read_likes    on public.event_likes    for select to authenticated using (true);
create policy read_comments on public.event_comments for select to authenticated using (true);

-- Users manage only their own rows
create policy write_own_follow  on public.town_follows   for insert to authenticated with check (follower_id = auth.uid());
create policy del_own_follow     on public.town_follows   for delete to authenticated using (follower_id = auth.uid());
create policy write_own_like     on public.event_likes    for insert to authenticated with check (user_id = auth.uid());
create policy del_own_like       on public.event_likes    for delete to authenticated using (user_id = auth.uid());
create policy write_own_comment  on public.event_comments for insert to authenticated with check (user_id = auth.uid());
create policy del_own_comment    on public.event_comments for delete to authenticated using (user_id = auth.uid());
-- (Admin comment deletion handled via the existing admin allowlist path / service role, not a broad policy.)
```

### 5.3 Feed read — one round trip

To avoid N+1 count queries per card, add a Postgres **RPC** (or view) that returns recent postings joined to their poster, photo, and counts:

```sql
-- Returns recent approved postings with poster info + like/comment/going/follower counts.
-- Draft; exact column list confirmed at apply-time.
create or replace function public.get_feed_postings(limit_n int default 30)
returns table (
  id uuid, title text, event_date date, start_time text, location text,
  image_url text, created_at timestamptz,
  club_id uuid, club_name text, submitted_by uuid,
  like_count int, comment_count int, going_count int, follower_count int
) language sql stable as $$
  -- select from club_events e
  -- left join clubs c on c.id = e.club_id
  -- left join lateral (counts…) …
  -- where e.status = 'approved' and e.submitted_by is not null and e.kind = 'event'
  -- order by e.created_at desc limit limit_n
$$;
```

Per-user state (did *I* like / follow / RSVP) is fetched in a second small query keyed by `auth.uid()` and merged client-side, so the RPC stays user-agnostic and cacheable. **Fallback:** if the RPC isn't present yet, the client uses the existing N+1 pattern (as `getApprovedClubs` already does for member counts).

### 5.4 CommunityAPI additions (`BlockParty/Backend/CommunityAPI.swift`)

- `follow(_ target: FollowTarget)` / `unfollow(_:)` / `isFollowing(_:) -> Bool` / `followerCount(_:) -> Int` / `myFollowing() -> [FollowTarget]`
- `likeEvent(_ id:)` / `unlikeEvent(_ id:)` / `likeCount(_ id:) -> Int` / `hasLiked(_ id:) -> Bool`
- `addComment(eventId:_ body:)` (→ Moderation → insert) / `comments(eventId:) -> [EventComment]` / `deleteComment(_ id:)`
- `getFeedPostings(limit:) -> [FeedPosting]` (RPC, with N+1 fallback)

New models (`BlockParty/Backend/Models.swift`): `FollowTarget { type, id }`, `EventComment { id, eventId, author, avatarUrl?, body, createdAt }`, `FeedPosting { …event fields…, imageUrl?, poster (club|profile), followerCount, likeCount, commentCount, goingCount, liked, following, rsvpd }`.

## 6. Data plumbing changes

1. **Surface event photos:** map `RawEvent.imageUrl` through to the feed model (`CommunityAPI.swift:148-153`, `:164-168` currently drop it). Feed hero uses it as the first source in the resolution chain.
2. **Recent-postings query / RPC** (§5.3) — new; distinct from the existing start-time-ordered reads.
3. **Interest tailoring:** reuse `Interests.matches()` (`Interests.swift:121`) over `title + location (+ club text)`. Note the known substring over-match caveat; acceptable for prioritization (not a hard filter).
4. **"On this day" source (§4):** a small curated table `town_almanac (md text primary key, fact text not null, source text, link text)` keyed `MM-DD`, seeded with a handful of **real, cited** St. Joe facts; read once/day, cached; **absent day → line hidden.** (Alternatively fold the fact into the existing `daily-almanac` edge function; curated table preferred for citation control.)

## 7. Files

**New**
- `Features/Home/Almanac/AlmanacHeader.swift` — Zone 1 (composes weather + sun + moon + on-this-day + quest ring)
- `Features/Home/Almanac/MoonPhase.swift` — local moon-phase math + glyph
- `Features/Home/Feed/FeedSection.swift`, `FeedCard.swift`, `CommentSheet.swift` — Zone 3
- `Features/Home/CompanionSlot.swift` — empty hook (renders nothing now)
- `Backend/SocialAPI.swift` (or extend `CommunityAPI.swift`) — follow/like/comment/feed
- SQL migration file under `supabase/migrations/` (gated)

**Modify**
- `Features/Home/HomeView.swift` — new three-zone body
- `Features/Home/HomeModel.swift` — load feed + per-user social state; optimistic like/follow/rsvp
- `Backend/CommunityAPI.swift`, `Backend/Models.swift` — per §5.4/§5
- Possibly `Features/Home/TodayInStJoe.swift` / `AlmanacSection.swift` — refactor/retire into `AlmanacHeader`

**Reuse unchanged:** `WeatherService`, `WeatherBackground`, `DailyAlmanac`, `SpringReveal`, `EventRow` (agenda), `PhotoView`/`KnownLocalPhoto`/`VenuePhoto`/`ExploreBlankPhoto`, `Interests`, theme tokens.

## 8. Build order (phases)

1. **Backend** — confirm schema (`list_tables`), write migration, **get greenlight**, apply on branch → verify → merge; add `CommunityAPI` social methods + models + feed read (with N+1 fallback so UI can build before the RPC lands).
2. **Zone 1 + Zone 2** — `AlmanacHeader` (reuse weather; add moon + on-this-day + quest ring) and the elevated agenda. Lowest risk; verify by screenshot.
3. **Zone 3** — `FeedCard` (account row + text-over-photo hero + engagement), `CommentSheet`, Follow/Like/Save wiring, interest ordering.
4. **Motion & polish** — `emil-design-eng` micro-interactions, spring reveals, haptics, count-ups; animation-montage verification.

Each phase: **builds clean (0 warnings) + confirmed in the simulator via screenshots** (the repo's definition of "verified"; use the DEBUG launch args and the DerivedData-path discipline from `CLAUDE.md`).

## 9. Verification

- Build: `build_sim` / `xcodebuild` clean, **zero warnings**.
- Screenshots via booted sim (`-open-tab home` default; add debug args as needed), resolving `BUILT_PRODUCTS_DIR` (not `find|head`) and installing **over** the app.
- Motion: record the sim + extract a frame montage for the entrance + like/follow/quest interactions.
- Real-data check: every count on screen traces to a real row; empty/zero states read honestly.

## 10. Risks & open questions

- **Shared prod DB.** Biggest risk. Mitigated by the migration gate, branch-first, community-namespaced tables, and per-user RLS. Confirm the wellness app has no name collision on `town_follows`/`event_likes`/`event_comments`.
- **"No feeds" brand rule.** This feature deliberately introduces a feed with follows/likes/comments — a conscious, user-authorized evolution of the Home tab. `CLAUDE.md`'s brand bar should be updated to reflect the new stance once shipped.
- **Interest matching is thin for events** (title + location only). Acceptable as soft prioritization; a real category/tag column on `club_events` is the future upgrade (out of scope).
- **"On this day" content** is a curation lift; ship with a small seed and grow it; hide when absent.
- **Comment moderation** relies on the existing edge function; confirm it accepts arbitrary short text, not just event bodies.
- **Photo coverage.** Many events lack `image_url`; the resolution chain falls back to bundled/Places/blank — feed heroes must look intentional even at the blank end.
```
