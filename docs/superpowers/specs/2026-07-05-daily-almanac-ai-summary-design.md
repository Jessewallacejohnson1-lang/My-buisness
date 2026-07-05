# Daily Almanac v2 — AI day-summary — design

**Date:** 2026-07-05 · **Branch:** `mapbox-map-tab` · **Status:** awaiting review

## Goal

Turn the Almanac card's copy from a fixed template into **one calm, AI-written line
that summarizes THIS town's real day** — weather + sun **plus** today's real events
and quest — while keeping every brand rule intact:

- **Real data only, never a fake number.** Claude never *sources* facts; it only
  rewords facts the backend hands it. Fed real events, it can honestly say "the
  Farmers Market's on till noon" when that's really on the board.
- **One calm read for the whole town.** Generated once, cached, shared — not
  per-user, not rewritten on every app-open.
- **Graceful fallback.** If anything fails, the card keeps the v1 template nudge
  (already shipped). We never block the card and never invent a reading.

This is v2 of the feature shipped in commit `c3eebe2` (v1 = template nudge from
real sunrise/sunset + weather). v1 stays as the offline fallback.

## Architecture

```
AlmanacSection (client)
  │  renders the v1 template nudge INSTANTLY (unchanged)
  │  .task → DailyAlmanac.line()  ─ upgrades the copy if a line comes back
  ▼
Supabase Edge Function  daily-almanac       ← ANTHROPIC_API_KEY stays server-side
  │  1. gathers CANONICAL facts itself (not from the client):
  │       • open-meteo sun + weather  (America/Chicago, same coords as WeatherService)
  │       • today's approved club_events  (title, start_time, going count)
  │       • today's quest  (title)
  │  2. factsHash = sha256(daily high/low, label, sunset HH:mm, sorted event sigs, quest)
  │  3. SELECT daily_almanac WHERE almanac_date = <today, Chicago>
  │       • row exists AND facts_hash matches → return cached `line`   (no Claude call)
  │       • missing / changed → call Claude (Opus 4.8), validate, UPSERT, return `line`
  ▼
daily_almanac table   (one row per day, town-wide)
```

Gathering facts **server-side** (not trusting client input) is what guarantees the
whole town gets one identical read and bounds Claude calls to "when the day actually
changes."

## Components

### 1. `daily_almanac` table (new migration)

```sql
create table public.daily_almanac (
  almanac_date date primary key,          -- local (America/Chicago) day
  facts_hash   text        not null,      -- sha256 of the canonical fact set
  line         text        not null,      -- the AI-written summary
  updated_at   timestamptz not null default now()
);

alter table public.daily_almanac enable row level security;
-- No policies on purpose: the client never touches this table directly — it calls
-- the edge function, which reads/writes with the service-role key (bypasses RLS).
-- RLS-enabled + zero policies = all client (anon/authenticated) access denied.
```

One row per day. Not in the `supabase_realtime` publication (the card fetches on
appear; live updates aren't needed). Not a per-user table. The client reads the line
*through the function*, never via PostgREST.

### 2. `daily-almanac` edge function (new, mirrors `moderate-post/index.ts`)

Contract:

```
POST /functions/v1/daily-almanac      (anon apikey + Bearer JWT, like Moderation)
  → 200 { "line": "<summary>" }        on success (cached or freshly generated)
  → 200 { "line": null }               fail-open: client keeps the template
```

Behaviour:

1. **Gather facts** (server-side, canonical):
   - Weather: `GET api.open-meteo.com/v1/forecast?...&daily=temperature_2m_max,
     temperature_2m_min,sunrise,sunset&timezone=America/Chicago` — same coords as
     `WeatherService`. Derive label from `weather_code` (reuse the WMO mapping).
   - Today (Chicago local date): `SELECT title, start_time, going_count FROM
     club_events WHERE event_date = <today> AND status = 'approved'` (exact columns
     confirmed via `list_tables` at build time; mirrors `getTodayEvents`).
   - Today's quest title (mirrors `getTodayQuest`).
   - Uses the Supabase service-role key (server-side) for these reads.
2. **factsHash** = `sha256` over a canonical string built from the **daily high/low**
   (stable across the day — avoids rewriting the line every time the current temp
   ticks), weather `label`, `sunset` as `HH:mm`, the sorted list of `title@start_time`
   event signatures, and the quest title.
3. **Cache check**: `SELECT * FROM daily_almanac WHERE almanac_date = <today>`.
   Hash matches → return `line`. Else continue.
4. **Generate** with Claude:
   - `model: "claude-opus-4-8"`, `max_tokens: 200`, no `thinking` (omitted → runs
     without thinking on Opus 4.8), no sampling params (Opus 4.8 rejects them).
   - System prompt (the anti-hallucination contract, see below).
   - User content = the exact facts as plain text.
   - Parse the JSON `{ "line": "..." }` from the response text (regex-extract, like
     `moderate-post`). Validate: non-empty, ≤ ~200 chars, single/×2 sentences.
5. **UPSERT** `{ almanac_date, facts_hash, line, updated_at: now() }` and return `line`.
6. **Fail-open** on any error (no key, open-meteo down, Claude 5xx, bad JSON,
   validation fail) → `{ "line": null }`. Never throw to the client.

### 3. Anti-hallucination contract (system prompt)

```
You write ONE calm line for the "Daily Almanac" card in Hygge, a warm, quiet,
hyper-local app for the real town of St. Joseph, Minnesota.

Use ONLY the facts provided below. Never invent a number, a time, a temperature,
an event, or a place — if a fact isn't given, don't mention it. Every number you
write must come verbatim from the facts.

Voice: a neighbor, not a brand. Warm, calm, hyper-local. No hype, no emoji, no
exclamation. At most two short sentences. Read out the day and turn it into one
low-bar nudge to step outside. If real events are listed, you may point at one.

Respond with ONLY a JSON object: {"line": "<the line>"}. No preamble, no reasoning.
```

The final-answer-only instruction matters on Opus 4.8 with thinking off (it can
otherwise leak reasoning into the visible response).

### 4. `Hygge/Backend/DailyAlmanac.swift` (new client, mirrors `Moderation.swift`)

```swift
struct DailyAlmanac {
    let auth: AuthStore
    /// The shared town summary for today, or nil to fall back to the template.
    func line() async -> String?   // POST /functions/v1/daily-almanac; nil on any failure
}
```

Same transport as `Moderation`: `SupabaseConfig.url + functions/v1/daily-almanac`,
`apikey` + `Bearer`, decode `{ line }`. Client-side 30-min cache (like
`WeatherService`) so re-opening the tab doesn't re-hit the function.

### 5. `AlmanacSection` wiring (edit)

- Keep the v1 template render exactly as-is — it shows **instantly**.
- Add `.task` (or extend the existing one): `if let line = await DailyAlmanac(auth:).line()`
  swap the hero/detail for the AI line (a gentle change; no layout jump).
- **"Every number is mono" for AI copy:** render the returned line by regex-splitting
  numeric runs (`\d[\d:.,]*°?` — matches `8:58`, `84°`, `20`, `noon` stays sans) and
  rendering those spans in Geist Mono `.monoMedium`, prose in DM Sans — so the AI line
  is stylistically identical to the template. Falls back to plain sans if the regex
  finds nothing.
- `AlmanacSection` needs `AuthStore` (for the function call) — inject via
  `@EnvironmentObject` like `HomeView` already does.

## Model & cost

`claude-opus-4-8`. Cached by fact-hash and generated a handful of times per day
town-wide → a fraction of a cent/day even at Opus-tier. Latency isn't user-blocking:
the template shows first, the AI line upgrades it when it lands.

## Deployment (via Supabase MCP, then verify)

1. `list_tables` — confirm `club_events` / quest column names for the fact queries.
2. `apply_migration` — create `daily_almanac` + RLS.
3. `deploy_edge_function` — deploy `daily-almanac` (reuses the project's existing
   `ANTHROPIC_API_KEY` secret, same as `moderate-post`).
4. `get_advisors` (security + performance) — confirm no new RLS/policy warnings.
5. Also write the function + migration source into the **Expo repo**
   (`~/Documents/my-business/supabase/functions/daily-almanac/` + a migration file)
   so the shared backend keeps source-of-truth, alongside `moderate-post`.
6. Verify end-to-end: build the app, launch the Today tab, screenshot the card
   showing the AI line; confirm the `daily_almanac` row was written (`execute_sql`).

## Verification / done

- Migration applied; `get_advisors` clean.
- Edge function deployed; a manual invoke returns `{ line }` and writes one row.
- App builds clean (0 warnings); Today-tab screenshot shows the AI line with mono
  numbers; killing the function (or offline) still shows the template (fallback).
- Source committed to both repos.

## Scope boundaries (non-goals)

- No per-user personalization, no notifications, no new user-facing settings.
- No scheduled/cron regeneration — generation is lazy (on first request after the
  day's facts change). No backfill.
- No realtime subscription for the card.
- v1 template stays; this only *upgrades* the copy when the function answers.

## Rollback

- Client: the fallback is automatic — if `daily-almanac` is removed/erroring, the
  card shows the template. To hard-disable, revert the `AlmanacSection` `.task` edit.
- Backend: `drop table public.daily_almanac;` + delete the edge function. No other
  table or app depends on it.
```
