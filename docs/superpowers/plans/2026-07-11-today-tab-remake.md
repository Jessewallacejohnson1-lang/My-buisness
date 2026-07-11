# Today Tab Remake — Implementation Plan

> **For agentic workers:** This plan is executed by a multi-agent Workflow (Opus orchestrator + Sonnet workers) or subagent-driven development. Steps use checkbox (`- [ ]`) syntax for tracking. **This repo has NO XCTest target** — "verify" means *build clean (0 warnings) + confirm in the running simulator via screenshot*, and Supabase branch queries for backend tasks. Follow `superpowers:verification-before-completion` discipline: evidence before claims.

**Goal:** Rebuild the Home ("Today") tab as three zones — a living almanac, today's agenda, and a komoot-1:1 interest feed — backed by real `town_follows` / `event_likes` / `event_comments` tables.

**Architecture:** Reuse the existing weather/photo/reveal stacks; add a hand-rolled social layer over `SupabaseHTTP` (no SDK, matching `@hygge/core`); a new `AlmanacHeader`, an elevated agenda, and a `FeedCard` list with a comment sheet. New Supabase tables + a `get_feed_postings` RPC, applied on a branch first.

**Tech Stack:** SwiftUI (iOS 26.5), Mapbox (untouched here), hand-rolled `URLSession` Supabase client, Supabase Postgres + RLS.

## Global Constraints (verbatim from spec + CLAUDE.md — apply to every task)

- **Builds must be clean: 0 warnings.** Verified = builds clean + screenshot in the sim.
- **Real data only — never seeded/inflated counts.** Every on-screen number traces to a real row; zero/empty states read honestly.
- **Do not hardcode hex/spacing a `Hue`/`Radius`/`HyggeMetrics` token already covers.** System font everywhere (weight carries hierarchy); numbers use mono + `.monospacedDigit()`.
- **Coral (`Hue.accent`) is reserved for live/tappable.** Live-glow = *now* only (`DateHelpers.isLiveNow`, start ≤ now ≤ start+2h).
- **Dates are user-timezone** (`DateHelpers.localDate()` / `nowMinutes()`), never derived from a UTC ISO string.
- **Feed voice is literal komoot:** "Follow", "N followers", "N liked this", "N comments".
- **No mascot** ships. `CompanionSlot` renders nothing (a hook only).
- **No gamification chrome:** no streaks, XP, badges, leaderboards. Momentum = the quest ring + motion only.
- **DerivedData discipline:** resolve `BUILT_PRODUCTS_DIR` via `xcodebuild -showBuildSettings`, never `find|head`; `simctl install` *over* the app, never `uninstall` (preserves `hygge.onboarded`).
- **Shared prod DB:** community-namespaced tables, per-user RLS; migration on a **branch first**, user greenlight before prod merge.

## File Structure

**New**
- `supabase/migrations/<ts>_today_social_layer.sql` — tables + RLS + indexes + `get_feed_postings` RPC + `town_almanac` + seed
- `Hygge/Backend/SocialAPI.swift` — follow / like / comment / feed reads (own struct over `SupabaseHTTP`, constructed like `CommunityAPI`)
- `Hygge/Features/Home/Almanac/AlmanacHeader.swift` — Zone 1 composition
- `Hygge/Features/Home/Almanac/MoonPhase.swift` — pure moon-phase math
- `Hygge/Features/Home/Almanac/OnThisDay.swift` — model + fetch for `town_almanac`
- `Hygge/Features/Home/Feed/FeedSection.swift` — Zone 3 list + interest ordering
- `Hygge/Features/Home/Feed/FeedCard.swift` — the komoot card
- `Hygge/Features/Home/Feed/CommentSheet.swift` — flat comments UI
- `Hygge/Features/Home/CompanionSlot.swift` — empty hook (`EmptyView` today)

**Modify**
- `Hygge/Backend/Models.swift` — add `FeedPosting`, `EventComment`, `FollowTarget`, `MoonInfo`, `AlmanacFact`; surface `imageUrl` on feed path
- `Hygge/Backend/CommunityAPI.swift` — map `RawEvent.imageUrl` through; add `getRecentPostings` fallback if RPC absent
- `Hygge/Features/Home/HomeView.swift` — new three-zone body
- `Hygge/Features/Home/HomeModel.swift` — load feed + per-user social state; optimistic like/follow/rsvp
- `Hygge/Features/Home/TodayInStJoe.swift` / `AlmanacSection.swift` — retire/absorb into `AlmanacHeader`

**Reuse unchanged:** `WeatherService`, `WeatherBackground`, `DailyAlmanac`, `SpringReveal`, `EventRow`, `PhotoView`/`KnownLocalPhoto`/`VenuePhoto`/`ExploreBlankPhoto`, `Interests`, theme tokens, `Haptics`, `PressableStyle`.

> **Parallelism note for the orchestrator:** the Xcode project uses a **file-system-synchronized group**, so *new* files under `Hygge/` are auto-included with no `project.pbxproj` edit — new-file tasks (MoonPhase, FeedCard, CommentSheet, AlmanacHeader, SocialAPI) can be built in parallel. **Shared-file edits** (`HomeView`, `HomeModel`, `Models.swift`, `CommunityAPI.swift`) must be **serialized** to avoid clobbering. Integrate + build-verify on one worktree.

---

## Task 0: Supabase social migration (branch-first)

**Files:** Create `supabase/migrations/<ts>_today_social_layer.sql`

**Interfaces — Produces (relied on by Task 1):**
- Tables `town_follows(follower_id, target_type, target_id)`, `event_likes(event_id, user_id)`, `event_comments(event_id, user_id, body, created_at)`, `town_almanac(md, fact, source, link)`.
- RPC `get_feed_postings(limit_n int) -> (id, title, event_date, start_time, location, image_url, created_at, club_id, club_name, submitted_by, like_count, comment_count, going_count, follower_count)`.

- [ ] **Step 1: Confirm live schema (read-only).** Via the Supabase MCP, `list_tables` on project `lxdgwhvqjqmqliobwjpi`; confirm `club_events.id`, `club_events.submitted_by`, `club_events.club_id`, `clubs.id`, `town_profiles.id` column types (expected `uuid`). Confirm no existing `town_follows`/`event_likes`/`event_comments` (collision check with the wellness app).

- [ ] **Step 2: Write the migration SQL** (tables + indexes + RLS from spec §5.1/§5.2; `town_almanac`; and the RPC below). Adjust id types to whatever Step 1 found.

```sql
create or replace function public.get_feed_postings(limit_n int default 30)
returns table (
  id uuid, title text, event_date date, start_time text, location text,
  image_url text, created_at timestamptz, club_id uuid, club_name text,
  submitted_by uuid, like_count int, comment_count int, going_count int, follower_count int
) language sql stable security invoker as $$
  select e.id, e.title, e.event_date, e.start_time, e.location,
         e.image_url, e.created_at, e.club_id, c.name as club_name, e.submitted_by,
         coalesce(l.n,0)::int, coalesce(cm.n,0)::int, coalesce(r.n,0)::int,
         coalesce(f.n,0)::int
  from public.club_events e
  left join public.clubs c on c.id = e.club_id
  left join lateral (select count(*) n from public.event_likes    where event_id = e.id) l  on true
  left join lateral (select count(*) n from public.event_comments where event_id = e.id) cm on true
  left join lateral (select count(*) n from public.event_rsvps    where event_id = e.id) r  on true
  left join lateral (select count(*) n from public.town_follows
                     where (target_type='club'    and target_id = e.club_id)
                        or (target_type='profile' and target_id = e.submitted_by)) f on true
  where e.status = 'approved' and e.kind = 'event' and e.submitted_by is not null
  order by e.created_at desc
  limit limit_n;
$$;
```

- [ ] **Step 3: Create a Supabase branch** (`create_branch`) and `apply_migration` to it. **Do not touch prod.**

- [ ] **Step 4: Verify on the branch** (`execute_sql`): (a) `select get_feed_postings(5)` returns rows with sane counts; (b) RLS: as an authenticated role, insert into `event_likes` with `user_id = auth.uid()` succeeds and with a foreign uid is rejected; (c) `event_comments` body length check rejects empty/>500. Capture outputs.

- [ ] **Step 5: Report to the user** the branch results + a diff summary. **Await explicit greenlight before `merge_branch` to prod.** (Blocking gate.)

**Verify:** branch queries succeed; RLS denies cross-user writes; RPC returns real counts. No prod change yet.

---

## Task 1: Social backend (Swift) — models + `SocialAPI`

**Files:** Create `Hygge/Backend/SocialAPI.swift`; Modify `Hygge/Backend/Models.swift`, `Hygge/Backend/CommunityAPI.swift`

**Interfaces — Consumes:** Task 0 tables/RPC. **Produces (relied on by HomeModel + Feed views):**

```swift
enum FollowTargetType: String, Codable { case club, profile }
struct FollowTarget: Hashable { let type: FollowTargetType; let id: String }

struct EventComment: Identifiable, Decodable {
    let id: String; let eventId: String; let authorName: String
    let avatarUrl: String?; let body: String; let createdAt: Date
}

struct FeedPosting: Identifiable {
    let id: String; let title: String; let eventDate: String?; let startTime: String?
    let location: String?; let imageUrl: String?; let createdAt: Date
    let posterName: String; let posterTarget: FollowTarget   // club if present else profile
    var followerCount: Int; var likeCount: Int; var commentCount: Int; var goingCount: Int
    var liked: Bool; var following: Bool; var rsvpd: Bool
}
```

`SocialAPI` (constructed `SocialAPI(auth:)` like `CommunityAPI`, using `SupabaseHTTP.rest`):
```swift
func follow(_ t: FollowTarget) async throws
func unfollow(_ t: FollowTarget) async throws
func isFollowing(_ t: FollowTarget) async throws -> Bool
func likeEvent(_ id: String) async throws
func unlikeEvent(_ id: String) async throws
func hasLiked(_ id: String) async throws -> Bool
func addComment(eventId: String, body: String) async throws -> EventComment   // → Moderation → insert
func comments(eventId: String) async throws -> [EventComment]
func deleteComment(_ id: String) async throws
func getFeedPostings(limit: Int) async throws -> [FeedPosting]                 // calls RPC
func hydrateUserState(_ postings: [FeedPosting]) async throws -> [FeedPosting] // sets liked/following/rsvpd for auth.uid()
```

- [ ] **Step 1:** Add the model structs to `Models.swift` (decoders use the existing `.convertFromSnakeCase` decoder). Map `RawEvent.imageUrl` through the `CommunityAPI` timeline/upcoming mappers so events can surface photos.
- [ ] **Step 2:** Implement `SocialAPI` over `SupabaseHTTP.rest` (POST inserts with `Prefer: return=representation`; DELETE with `follower_id=eq/…`; RPC via `POST /rest/v1/rpc/get_feed_postings`). `addComment` calls the existing `Moderation` edge function first, then inserts. Include an **N+1 fallback** `getFeedPostings` that runs when the RPC 404s (count queries per posting), so the UI works even before prod merge.
- [ ] **Step 3: Verify build** clean (`build_sim`), 0 warnings.
- [ ] **Step 4: Behavior check (DEBUG).** Add a temporary `#if DEBUG` one-shot (button or `.task`) that calls `getFeedPostings(3)` against the branch and `print`s counts; run in sim; confirm real numbers; remove the probe.
- [ ] **Step 5: Commit** `feat(home): social backend — follow/like/comment + feed reads`.

---

## Task 2: `MoonPhase` (pure function)

**Files:** Create `Hygge/Features/Home/Almanac/MoonPhase.swift`

**Interfaces — Produces:** `struct MoonInfo { let phaseName: String; let symbol: String; let illumination: Double }` and `func moonInfo(for date: Date, tz: TimeZone = .current) -> MoonInfo`.

- [ ] **Step 1:** Implement synodic-age math (reference new moon 2000-01-06 18:14 UTC, synodic month 29.530588853 days); map age → 8 phase names (New, Waxing crescent, First quarter, Waxing gibbous, Full, Waning gibbous, Last quarter, Waning crescent) + SF Symbol (`moon`, `moon.stars`, `moonphase.*` where available) + illumination `(1 - cos(2π·age/period))/2`.
- [ ] **Step 2: Verify against known dates (DEBUG asserts).** 2026-01-03 ≈ Full; 2026-01-18 ≈ New (confirm within ±1 day tolerance). Encode as `#if DEBUG assert(...)` or a `#Preview` that prints. Build clean.
- [ ] **Step 3: Commit** `feat(home): local moon-phase math`.

---

## Task 3: `OnThisDay` (curated fact)

**Files:** Create `Hygge/Features/Home/Almanac/OnThisDay.swift`; content seeded in Task 0's migration.

**Interfaces — Produces:** `struct AlmanacFact { let fact: String; let source: String?; let link: String? }` and `func onThisDay(_ date: Date, auth:) async -> AlmanacFact?` (queries `town_almanac` by `MM-DD`; returns nil when absent).

- [ ] **Step 1:** Seed `town_almanac` in the migration with **real, cited** St. Joe facts (use the St. Joe content-sourcing rules; MN-not-MI). Start with ~8–12 dated entries; absent days return nil.
- [ ] **Step 2:** Implement the fetch (cache once/day). Build clean.
- [ ] **Step 3: Commit** `feat(home): on-this-day almanac facts (curated, cited)`.

---

## Task 4: `AlmanacHeader` (Zone 1)

**Files:** Create `Hygge/Features/Home/Almanac/AlmanacHeader.swift`, `CompanionSlot.swift`; retire hero from `TodayInStJoe.swift`.

**Interfaces — Consumes:** `WeatherService`/`Weather`, `WeatherBackground`, `DailyAlmanac.line`, `MoonInfo`, `AlmanacFact`, quest data from `HomeModel`.

- [ ] **Step 1:** Build the card: weather-reactive backdrop (reuse `WeatherBackground`), temp + H/L + condition (mono), sun row (`↑sunrise ↓sunset`), moon chip, daylight-left, the AI day-line, the on-this-day line (hidden when nil), and the **quest progress ring** (done/target) with a `qbtn` → `HomeModel.completeQuest`. Include `CompanionSlot()` (renders `EmptyView`).
- [ ] **Step 2: Verify** — `build_sim`; screenshot `-open-tab home`; confirm layout, real weather, mono numbers, coral only on the quest CTA/live bits.
- [ ] **Step 3: Commit** `feat(home): living almanac header`.

---

## Task 5: Today's Agenda (Zone 2)

**Files:** Modify `HomeView.swift` (agenda section); evolve `EventRow` if needed.

- [ ] **Step 1:** Render `HomeModel.today` as the agenda (time · title · venue · going · RSVP), live-now stripe/dot via `DateHelpers.isLiveNow`; empty → `TodayCard`.
- [ ] **Step 2: Verify** — build clean; screenshot (populated + a forced-empty state).
- [ ] **Step 3: Commit** `feat(home): today's agenda zone`.

---

## Task 6: `FeedCard` + `FeedSection` (Zone 3)

**Files:** Create `Hygge/Features/Home/Feed/FeedCard.swift`, `FeedSection.swift`

**Interfaces — Consumes:** `FeedPosting`, the photo resolution chain, `Interests.matches`. **Produces:** callbacks `onLike`, `onFollow`, `onSave`, `onComment`, `onOpen` wired by `HomeModel`.

- [ ] **Step 1: `FeedCard`** — account row (avatar + name + "N followers · posted Xh ago" + Follow/Following button), text-over-photo hero (resolution chain: `imageUrl` → `KnownLocalPhoto` → `VenuePhoto` → `ExploreBlankPhoto`; scrim; kicker + title + stat line), engagement meta ("N liked this" · "N comments"), action row (Like/Comment/Save/Share). Literal komoot wording. Coral only on liked/live/CTA.
- [ ] **Step 2: `FeedSection`** — orders `HomeModel.feed`: interest matches first (via `Interests.matches` over title+location+club text), then recency; falls back to soonest-upcoming when sparse. Empty state reads honestly.
- [ ] **Step 3: Verify** — build clean; screenshot the feed (a following card + a not-following card + a blank-photo card).
- [ ] **Step 4: Commit** `feat(home): komoot-style interest feed`.

---

## Task 7: `CommentSheet` + wiring

**Files:** Create `Hygge/Features/Home/Feed/CommentSheet.swift`; wire in `FeedCard`/`HomeModel`.

- [ ] **Step 1:** Flat comment list (author + avatar + body + relative time), a composer (→ `SocialAPI.addComment` through Moderation), own-comment delete, honest empty state.
- [ ] **Step 2: Verify** — build clean; screenshot the sheet (with comments + empty + composer focused).
- [ ] **Step 3: Commit** `feat(home): flat comment sheet w/ moderation`.

---

## Task 8: `HomeModel` + `HomeView` integration

**Files:** Modify `HomeModel.swift`, `HomeView.swift`

- [ ] **Step 1: `HomeModel`** — load `feed` via `SocialAPI.getFeedPostings` + `hydrateUserState`; add optimistic `toggleLike`, `toggleFollow` (reconcile-by-id + rollback on error, mirroring the existing `toggleRsvp` pattern). Keep quest + agenda loads.
- [ ] **Step 2: `HomeView`** — new body: `Masthead → AlmanacHeader → Agenda → FeedSection`, each `.springReveal(index)`; retire `TodayInStJoeCard`/`AroundTownCarousel`/`RollCall` from Home (or fold as decided). Preserve pull-to-refresh + profile sheet.
- [ ] **Step 3: Verify** — build clean; full-scroll screenshots; exercise like/follow/RSVP and confirm optimistic + persisted (re-open tab).
- [ ] **Step 4: Commit** `feat(home): three-zone Today tab integration`.

---

## Task 9: Motion & polish (emil pass)

**Files:** touch the new views.

- [ ] **Step 1:** Apply `emil-design-eng` micro-interactions: temp count-up on load, like heart-burst + `Haptics`, Follow spring fill, quest-ring fill + completion pop, `PressableStyle` on all tappables, honor Reduce Motion. No new gamification.
- [ ] **Step 2: Verify** — build clean; record the sim + extract a **frame montage** (per the animations-montage memory) for entrance + like + follow + quest; confirm springy, not janky.
- [ ] **Step 3: Commit** `feat(home): motion + micro-interaction polish`.

---

## Task 10: Prod merge + graphify update

- [ ] **Step 1:** With user greenlight, `merge_branch` the Supabase migration to prod; smoke-test the live feed in the sim.
- [ ] **Step 2:** `graphify update .` to refresh the knowledge graph. Update `CLAUDE.md`'s brand bar to record the deliberate "Home has a feed now" evolution. Continue `MAP_BUILD_LOG.md`? (Home, not map — use a `HOME_BUILD_LOG.md` or a spec addendum instead.)
- [ ] **Step 3: Commit** `chore(home): prod merge + graph refresh + brand-bar note`.

---

## Self-Review

- **Spec coverage:** §4 zones → Tasks 4/5/6/7/8; §5 social layer → Tasks 0/1; §6 plumbing → Tasks 1/2/3; §9 verification baked into every task; §10 risks → Task 0 gate + Task 10. ✅
- **Placeholder scan:** SQL/moon-math/model structs/signatures are concrete; view bodies are structured (not line-by-line) by design — workers implement against tokens + the approved mockup. No "TBD".
- **Type consistency:** `FeedPosting`/`EventComment`/`FollowTarget`/`MoonInfo`/`AlmanacFact` names match across Tasks 1–8; `get_feed_postings` column list matches Task 1's decoder.
- **Known softness:** interest match is thin for events (title+location) — soft ordering, not a filter (accepted). Photo coverage varies — blank-photo state must look intentional (Task 6 covers it).
