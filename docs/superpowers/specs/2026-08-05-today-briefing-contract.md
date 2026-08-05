# BriefingPayload — the Today tab contract (v1)

Status: **draft, awaiting Phase 1 gate**
Branch: `feat/today-briefing` · worktree `~/Documents/block-party-briefing` · base `integration/block-party`

This is the one artifact the backend lane and the UI lane both work against. Paste
this file plus `fixtures/briefing_sample.json` into a Codex prompt — never
repo-wide context. If a lane needs a field this document doesn't define, that is a
contract change and it comes back here first.

---

## 0. Decisions this document encodes

| Decision | Value |
|---|---|
| Daily touch in v1 | `poll` only. `kind='history'` stays in the schema; on-this-day is a seed change in v2, not a migration. |
| Touch bank | 60 polls, drafted, at `supabase/seed/daily_touches_v1.json`. Jesse edits in the dashboard. |
| Social feed | `TodayFeedView` is **removed** from Today. Happening Soon takes its slot; `CaughtUpFooter` ends the screen. |
| Almanac wiring | `AlmanacSection` gains optional injected inputs and keeps its self-fetch path as fallback. |
| Spotlight source | New `spotlights` table, seeded from the 5 curated places in `BlockParty/Models/Place.swift`. |
| Admin | Supabase dashboard. No admin UI in v1. |
| Home load | One RPC, cache-first. |

---

## 1. Corrections to the v1 plan

These supersede the plan document. Each was verified against the tree at
`integration/block-party`.

**1.1 — There is no `events` table.** Events are `public.club_events` rows with
`kind in ('event','trail')`. `briefing_featured.event_id` references
`club_events(id)`.

**1.2 — The featured picker inherits the `realOnly` invariant.** Every event
display query in the app appends `submitted_by is not null` (`CommunityAPI.swift:50`;
`get_feed_postings` enforces the same). A NULL submitter is seed/fabricated content
and must never surface. The picker and the RPC both filter on it.

**1.3 — The utility-row bug is already fixed.** Shipped in `dad400e`, documented in
`docs/adr/ADR-001-utility-tile-persistence.md`. Phase 3 item 5 is **struck from
scope**. The current line is load-bearing:

```swift
// UtilityRowView.swift:50
var showCustomizeTile: Bool { true }
```

Any briefing layout that hides the Customize tile behind a gesture or a scroll
position reintroduces the defect. Do not touch it.

**1.4 — `utility_snapshots` is struck from scope.** The four tiles are
`weather` (direct Open-Meteo, 15-min TTL), `garbage` and `library` (pure local
computation, no network), `roads` (Supabase `town_status` + a Realtime
subscription). A 6 AM snapshot table would make all four *staler* and would
duplicate `town_status` while breaking the roads live path. The utility row keeps
its own registry, its own loading, and its own cache, and is **not** in the
payload. It stays in the module order as an opaque module.

**1.5 — The almanac is per-user, not per-day.** `daily-almanac` writes a
personalized line to `almanac_daily (user_id, date)`, derived from that user's
RSVPs and 7-day history. `daily_briefings.almanac_md` cannot be that field.
Resolution:

- `almanac.line` — the caller's `almanac_daily` row for `briefing_date`. Null on a
  cache miss; the client then calls the edge function exactly as it does today.
- `almanac.town_line` — `daily_briefings.almanac_md`, town-wide, always present.

The RPC is `security definer` but reads `almanac_daily` **filtered to
`auth.uid()`**, so this does not widen access to other users' lines.

**1.6 — `evergreen_pool` is not fallback copy, and `town_almanac` is empty.**
Verified against production. `evergreen_pool` holds 15 active rows and its shape is
`(id, line, active)` — the content is *town history facts* ("St. Joseph was first
settled in 1854…"), used as the almanac generator's fallback lines. It is the wrong
voice for a "nothing on today" slot and has no title or deeplink. `town_almanac`
(`md`, `fact`, `source`, `link`) is the right shape for a v2 on-this-day bank but
currently has **0 rows** — it is a table, not a bank.

Resolution: the 0-event copy lives on `daily_briefings` as three nullable columns
(`fallback_title`, `fallback_body`, `fallback_deeplink`), written by the 6 AM
routine only on a 0-event day. No sixth table, and the payload shape is unchanged.

**1.6b — The empty case is the common case at launch, not an edge case.**
Production right now: **2** approved upcoming events with a non-null submitter, 10
real events all-time, and **4** users. Consequences the lanes must design for, not
defend against:

- `featured` will hold 1–2 entries far more often than 3. The single-event hero
  variant and the `featured_fallback` slot are the *primary* renderings — build and
  review them first, not last.
- A poll's `total_votes` will be 0–4. This is why invariant §7.2 requires showing
  the true count: a 1-of-1 poll rendering as "100%" with no denominator is the
  fabricated-confidence failure `DESIGN.md` bans.

**1.6c — `almanac_daily` column names.** The columns are `body_text` and
`format_used`, not `line`/`format`. The RPC aliases them into the payload's
`almanac.line` / `almanac.format`.

**1.7 — Phase 4's motion numbers are superseded.** See §6.

---

## 2. The payload

One JSON object. Every module key is **nullable** — a failure in one module must
not take the briefing down. This mirrors the existing rule that a feed outage
leaves the rest of Today intact (`HomeModel.swift:97`).

Keys are `snake_case`. The client decodes with `SupabaseCoding.decoder`
(`.convertFromSnakeCase` + dual-ISO date strategy), so **no `CodingKeys` are
written** — that matches the whole model layer, which has none.

```jsonc
{
  "briefing_date": "2026-08-05",        // date, town-anchored. NOT NULL
  "tz": "America/Chicago",              // text. NOT NULL
  "status": "published",                // 'published' | 'none'. NOT NULL
                                        // 'none' = the routine has not published a
                                        // briefing for this date. Every module is
                                        // null, featured is [], caught_up still
                                        // renders. The RPC never raises and never
                                        // returns a draft.
  "published_at": "2026-08-05T06:00:00-05:00",  // timestamptz | null

  "almanac": {                          // object | null
    "line": "…",                        // string | null  — caller's almanac_daily row
    "format": "field_note",             // string | null
    "source": "personal",               // 'personal' | 'town' | null
    "town_line": "…"                    // string — daily_briefings.almanac_md
  },

  "weather": {                          // object | null
    "condition": "clear",
    "temp_f": 91, "feels_like_f": 96, "high_f": 92, "low_f": 68,
    "sunrise": "06:07", "sunset": "20:36",
    "observed_at": "2026-08-05T05:58:00-05:00"
  },

  "featured": [                         // array, 0–3, ordered by rank ascending
    {
      "rank": 1,                        // 1–3
      "id": "uuid",                     // club_events.id
      "title": "…",
      "event_date": "2026-08-05",       // 'YYYY-MM-DD' string, never a Date
      "start_time": "7pm",              // free text — the column is text
      "location": "…",                  // string | null
      "image_url": "…",                 // string | null
      "club_name": "…",                 // string | null
      "category": "music_arts",         // EventCategory raw value
      "going_count": 14,
      "going_avatars": ["…"],           // 0–3 URLs, facepile
      "like_count": 6,
      "comment_count": 2,
      "rsvpd": false, "saved": false, "liked": false   // caller's own state
    }
  ],

  "featured_fallback": {                // object | null — present iff featured is []
    "kind": "evergreen",
    "title": "…", "body": "…",
    "deeplink": "activities"
  },

  "touch": {                            // object | null
    "id": "uuid",
    "kind": "poll",                     // 'poll' | 'history'
    "prompt": "…",                      // ≤ 53 chars in the v1 bank
    "options": ["…","…","…","…"],       // exactly 4 in the v1 bank; ≤ 35 chars each
    "body": null,                       // history only; null for polls
    "vote_counts": [11, 4, 2, 6],       // parallel to options. REAL counts only
    "total_votes": 23,
    "my_vote": null                     // Int index | null
  },

  "spotlight": {                        // object | null
    "id": "uuid", "slug": "wobegon-trail",
    "title": "…", "blurb": "…",
    "image_url": "…",                   // string | null
    "place_id": null                    // uuid | null → places(id)
  },

  "caught_up": {                        // object. NOT NULL
    "next_briefing_at": "2026-08-06T06:00:00-05:00",
    "label": "New briefing at 6 AM"
  }
}
```

### Fixtures

| File | State it pins |
|---|---|
| `fixtures/briefing_sample.json` | 3 featured events, poll unvoted |
| `fixtures/briefing_one_event.json` | 1 featured event → hero variant |
| `fixtures/briefing_zero_events.json` | 0 events → `featured_fallback` |
| `fixtures/briefing_voted.json` | poll with `my_vote` set |
| `fixtures/briefing_none.json` | `status: "none"` — no briefing published for the date |
| `fixtures/briefing_degraded.json` | published, but every optional module null |

Fixture invariants, enforced by the Phase 3 test that loads them:

- top-level keys are exactly the 11 in the contract, in every fixture
- `vote_counts` is index-aligned to `options` and sums to `total_votes`
- `featured` ranks are `1…n` with no gaps
- `featured_fallback` is non-null **iff** `featured` is empty **and**
  `status == "published"`
- `caught_up` is never null

Variants derive from the base via `python3 fixtures/make_variants.py`. Edit the
base, re-run, never hand-edit a variant.

---

## 3. Schema (Phase 1)

New migration files only. `supabase/migrations/*` is applied history and is never
edited retroactively.

```sql
create table public.daily_briefings (
    briefing_date date primary key,
    almanac_md    text not null,
    weather       jsonb,
    status        text not null default 'draft' check (status in ('draft','published')),
    published_at  timestamptz,
    created_at    timestamptz not null default now(),
    -- The 0-event slot copy. Written by the 6 AM routine only when the featured
    -- picker returns nothing. See correction 1.6 — evergreen_pool is town history
    -- facts and is the wrong voice for this.
    fallback_title    text,
    fallback_body     text,
    fallback_deeplink text
);

create table public.briefing_featured (
    briefing_date date not null references public.daily_briefings (briefing_date) on delete cascade,
    event_id      uuid not null references public.club_events (id) on delete cascade,
    rank          int  not null check (rank between 1 and 3),
    primary key (briefing_date, rank),
    unique (briefing_date, event_id)
);

create table public.daily_touches (
    id      uuid primary key default gen_random_uuid(),
    kind    text not null check (kind in ('poll','history')),
    prompt  text not null,
    options jsonb,                      -- poll only; array of text
    body    text,                       -- history only
    used_on date unique,                -- null = still in the bank
    created_at timestamptz not null default now(),
    check ((kind = 'poll' and options is not null)
        or (kind = 'history' and body is not null))
);

create table public.touch_votes (
    touch_id   uuid not null references public.daily_touches (id) on delete cascade,
    user_id    uuid not null references auth.users (id) on delete cascade,
    option_idx int  not null check (option_idx >= 0),
    created_at timestamptz not null default now(),
    primary key (touch_id, user_id)
);

create table public.spotlights (
    id         uuid primary key default gen_random_uuid(),
    slug       text unique not null,
    title      text not null,
    blurb      text not null,
    image_url  text,
    place_id   uuid references public.places (id) on delete set null,
    active     boolean not null default true,
    last_shown date
);
```

`touch_votes` primary key `(touch_id, user_id)` is what enforces one vote per
touch — do not also add a unique index.

### RLS

Follow the newer, perf-correct idiom already in the tree — wrap `auth.uid()` in a
subquery (`baseline_schema.sql:607`):

- `daily_briefings`, `briefing_featured`, `daily_touches`, `spotlights` — SELECT to
  `authenticated`. `daily_briefings` additionally `using (status = 'published')`.
  **No write policies** — the 6 AM routine writes with the service-role key, same
  as `town_status`.
- `touch_votes` — own-row SELECT and INSERT: `using ((select auth.uid()) = user_id)`
  / `with check ((select auth.uid()) = user_id)`. **No UPDATE, no DELETE** — a vote
  is final in v1.

Write-path consequence, documented three times in the tree (`SocialAPI.swift:110`):
a table with no UPDATE policy must be written with
`Prefer: resolution=ignore-duplicates`. `merge-duplicates` emits
`ON CONFLICT DO UPDATE` and returns 42501. The vote insert uses
`ignore-duplicates`.

---

## 4. The RPC

```sql
create or replace function public.get_today_briefing(
    p_date date default null,
    p_tz   text default 'America/Chicago'
) returns jsonb
language sql
stable security definer
set search_path to 'public', 'pg_temp'
as $$ … $$;

revoke all on function public.get_today_briefing(date, text) from public, anon;
grant execute on function public.get_today_briefing(date, text) to authenticated;
```

The `revoke … from public, anon` then `grant … to authenticated` pair is not
optional — the anon key ships in the binary, and a `security definer` function is
otherwise callable by `anon`.

Rules:

- `p_date` null → `(now() at time zone p_tz)::date`. Never `current_date`; UTC
  rollover drops today's events after ~7pm local (`baseline_schema.sql:669`).
- Returns `jsonb`, not `returns table` — the payload is nested. `get_feed_postings`
  uses `returns table` because its rows are flat; this one is not.
- Reads `almanac_daily` filtered to `auth.uid()`.
- Featured join filters `status = 'approved'` **and** `submitted_by is not null`.
- Caller-state fields (`rsvpd`, `saved`, `liked`, `my_vote`) resolve against
  `auth.uid()` inside the function.
- Returns a well-formed payload with null modules rather than raising, in every
  case except an unpublished/missing briefing row.

Swift call site follows the two existing RPCs verbatim
(`SocialAPI.swift:256`):

```swift
let (data, _) = try await SupabaseHTTP.rest("rpc/get_today_briefing", method: "POST",
                                            accessToken: t,
                                            body: try jsonBody(["p_tz": Town.timeZone.identifier]))
```

---

## 5. Module registry (Phase 3)

Copy the shape of `UtilityTileRegistry` — it is the house precedent and it already
proves a new module can ship without touching a UI file
(`docs/UTILITY_ROW.md:50`).

- `BriefingModuleID`: a string-backed `RawRepresentable`, **not** a closed enum.
  Same reason as `UtilityTileID` — a payload from a newer server version must decode
  and drop unknown ids rather than fail.
- Order is one array literal. v1:
  `[.almanac, .utility, .happeningSoon, .dailyTouch, .spotlight, .caughtUp]`
- `.utility` renders `UtilityRowView()` unchanged and ignores the payload.
- `HomeView`'s body becomes the registry loop. `TodayTopBar` stays outside the
  `ScrollView`, unchanged. The trailing `Color.clear.frame(height: 96)` tab-bar
  spacer stays.

`BriefingModel` follows the house pattern — `@MainActor final class … ObservableObject`
owning state and API calls. Cache-first: persist the last payload to disk, render it
immediately, refresh in the background. New UserDefaults keys use a `briefing.*`
prefix. **Never rename or reuse a `hygge.*` or `utility.*` key** — the bundle id
`Jesse.Hygge`, keychain account `hygge.session`, and those defaults keys are frozen.

Dead code this replaces, safe to delete: `TodayFeedView` and its card stack,
`AroundTownCarousel` (already zero references), `TodayLoadingCard` (already unused),
and the vestigial `HomeModel` members `today`, `weekGoing`, `quest`, `questCount`,
`questDone`, `upcoming`, `communityFeedLoaded`, `feedFailed`, `toggleRsvp`,
`toggleUpcomingRsvp`, `completeQuest` — all verified to have zero call sites outside
`HomeModel.swift`.

---

## 6. Feel (Phase 4) — corrected

The plan's raw spring values are **superseded**. House rule: named springs live in
`BlockParty/Theme/Motion.swift` and nowhere else; views must not carry inline magic
springs. A spec that introduces `response 0.4 / damping 0.85` at a call site
violates it, and `Motion.tileEntrance` is already `spring(response: 0.40,
dampingFraction: 0.90)`.

| Plan said | Ship instead | Why |
|---|---|---|
| entrance: rise 8pt, stagger 40 ms, spring 0.4/0.85 | `.springReveal(index:revealed:)` at indices 0…5 | The Today signature entrance. `AlmanacSection` already uses index 0; modules continue the same ladder. `RevealTiming`: stagger 0.05, rise 22, duration 0.48, bounce 0.28, startScale 0.94. |
| poll row scale 1.0→1.02→1.0, spring 0.35/0.8 | `Motion.select` (0.32/0.72) | Existing token, semantically "selection pop". |
| bar fill 300 ms ease-out | `.easeOut(duration: 0.3)` inline | Ease curves at call sites have precedent (the header hairline). Only *springs* are token-only. |
| haptic `.light` / `.success` | `Haptics.light()` / `Haptics.success()` | The raw-generator calls in `FeedEventCard.swift:389` are a documented deviation, not the convention. `Haptics` no-ops under Low Power Mode. |
| RSVP press animation | `FeedEventCardJoinButton` unchanged | 44×44, `Radius.button` rounded square, press scale 0.88, spring 0.25/0.6, plus→check morph 0.18, square ring burst. |

**Gate correction.** Phase 4's gate cannot assert spring values — SwiftUI
`Animation` is opaque and has no runtime accessors. This is already established in
`BlockPartyTests/UtilityRowMotionTests.swift:78`. The enforceable assertion is *"the
view reads `Motion.<token>`"* plus numeric layout/timing constants. Feel is verified
by screen recording against this table, not by unit test.

---

## 7. Invariants every lane obeys

Extracted from `CLAUDE.md` and `DESIGN.md`. `CLAUDE.md` is authoritative;
`AGENTS.md` is a stale pre-rebrand clone.

1. **Never attach a pan-competing gesture to a scrollable cell.** A whole-card
   `LongPressGesture(minimumDuration: 0)`, a `.gesture(DragGesture)`, or a plain
   non-simultaneous `.gesture(TapGesture)` claims the touch on press-down and
   out-competes the enclosing `ScrollView`. **This is the single highest risk in the
   poll card** — tappable option rows inside a scroll view. Do press feedback via a
   `ButtonStyle`'s `isPressed`; attach card-level gestures with
   `.simultaneousGesture`. Verify scrolling on a real device.
2. **Real data only. No fabricated or seeded counts, in any surface.** Poll results
   show true `vote_counts`. Do not seed votes, do not floor a percentage, do not
   round a 1-vote poll to something that reads better. Show the count, not only the
   percentage.
3. **Monochrome chrome.** `ink #111111` · `paper #FAFAF7` · `surface #FFFFFF` ·
   `inkSecondary #6E6E6E` · `hairline #E7E7E4` · `fill #F1F1EF`. No accent of any
   kind — `Hue.accent` exists in code but `DESIGN.md` and the brand skill both say
   build monochrome until the hue is chosen. Emphasis is weight, value, or
   fill-vs-outline, never hue. Poll bars are value contrast, not color.
4. **Never nest cards.** `DailyTouchCard` is a card; its option rows are not.
5. **`inkSecondary` on `fill` is 4.51:1** — no margin over the 4.5 floor. Never add
   opacity to secondary text on a filled surface. Relevant to every poll option row
   that sits on a fill.
6. **Numbers are always `.monospacedDigit()`** at the call site. Vote counts,
   percentages, temperatures, times.
7. **Radii:** `button 12` (a rounded square, never a pill), `tile 16`, `card 20`,
   `bento 22`. Always `.continuous`. One elevation: `CardShadow` = black 6%, r10, y4.
8. **Reduce Motion is mandatory** and degrades to a crossfade or an instant final
   state. Reveals enhance already-visible content — **never gate visibility on an
   animation that won't fire in a headless render.** This binds the `CaughtUpFooter`
   checkmark draw-on directly.
9. **Dates:** `DateHelpers.localDate()` / `nowMinutes()` for "today" (pinned to
   `TimeZone.current`); never derive today from a UTC ISO string. Town-fixed math
   uses `Town.calendar` (America/Chicago). Date display strings come from
   `TodayHeader.eyebrow(for:)` — the app's single definition, already under test.
10. **MainActor by default.** Mark pure helpers `nonisolated` or they trip the
    0-warning bar. Resolve MainActor defaults inside the function body, never in a
    default argument.
11. **Design tokens are mandatory.** No raw hex, no hardcoded spacing a token
    covers. `.accentColor`, `.orange`, `.red`, `.blue`, `.green` are banned at call
    sites.
12. **Verified = builds clean with 0 warnings + confirmed in the simulator via
    screenshots.**
    `xcodebuild test -project BlockParty.xcodeproj -scheme BlockParty -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO`

---

## 8. Phase gates

Hard stop at each. Jesse verifies on simulator before the next phase starts.

- **Phase 1** — `select public.get_today_briefing('2026-08-05','America/Chicago')`
  in the SQL editor returns a payload whose shape matches
  `fixtures/briefing_sample.json` key-for-key. Anon-key write attempts against all
  five new tables fail.
- **Phase 2** — the routine runs 3 consecutive fake days and produces a complete
  payload each time, including one forced 0-event day that emits
  `featured_fallback`. Touch bank decrements and never repeats.
- **Phase 3** — every module renders from each of the five fixtures with the
  network off. No layout jump when real data lands. Scrolling verified on a
  physical device with the poll card on screen (invariant 1).
- **Phase 4** — screen recording reviewed against the §6 table. Token-identity
  tests pass. 120 fps, no dropped frames on module entrance.
- **Phase 5** — one real day end to end: the 6 AM routine publishes, the app shows
  it, a vote lands in `touch_votes`.
