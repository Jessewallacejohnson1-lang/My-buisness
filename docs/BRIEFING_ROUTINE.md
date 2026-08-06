# The 6 AM briefing routine

The daily job that composes and publishes `daily_briefings`. Phase 2 of the Today
tab briefing build. Contract: `docs/superpowers/specs/2026-08-05-today-briefing-contract.md`.

**Host: pg_cron, hourly.** The scheduled-agent path was abandoned once it proved
unreachable: cloud agents cannot read local env vars, there is no Supabase MCP
connector, and compose/publish are service_role only — so any external runner
needs a full-access service-role key stored somewhere. pg_cron needs none of
that; it runs as the job owner inside Postgres.

Job: `briefing-reconcile`, `0 * * * *`, calling `run_briefing_reconcile()`.

**Hourly and idempotent**, not one 6 AM fire:
  · DST-proof — "6 AM Central" moves between 11:00 and 12:00 UTC; an hourly
    reconcile never has to know.
  · Self-healing — a missed hour costs an hour, not a whole day.
  · Cheap — two index lookups when there is nothing to do, which is most hours.

It guarantees: **today is published, tomorrow is drafted.** Tomorrow staying a
draft is deliberate — it preserves the dashboard edit window, and means the day
is re-composed against a fresher calendar on the morning it goes live.

The town line comes from `evergreen_pool` (15 written, true town facts), rotated
deterministically by date — no AI call, no outbound request. The line each
neighbour actually reads is still their personalized one from `almanac_daily`,
generated per user by the daily-almanac edge function.

Weather is left null. The utility row and the almanac card both fetch live
weather through WeatherService's 15-minute cache, which is fresher all day than
a snapshot taken once at 6 AM.

---

## What the database already decides

| Function | Role | Callable by |
|---|---|---|
| `briefings_pending(p_from, p_days)` | Which dates still need work. Returns `missing` or `draft` rows only. | `service_role` |
| `compose_briefing(p_date, p_almanac_md, p_weather, …)` | Featured picker, touch picker, spotlight rotation, fallback copy. Idempotent. | `service_role` |
| `publish_briefing(p_date)` | Flips `draft` → `published`. Refuses a day with no touch **and** no featured content. | `service_role` |
| `pick_touch(p_date)` / `season_of(p_date)` | Season-aware touch selection. | `service_role` |

`compose_briefing` returns a summary the agent should read, not discard:

```json
{ "briefing_date": "2026-08-06", "featured_mode": "near", "featured_count": 1,
  "touch_id": "…", "touch_season": "summer", "spotlight_id": "…",
  "bank_remaining_in_season": 7, "bank_low": true, "status": "draft" }
```

### The rules it encodes

- **Featured** — up to 3 approved events with a non-null `submitted_by`, `kind='event'`,
  inside 14 days, soonest first, more-RSVPs first as the tiebreak. Yesterday's rank-1
  sorts last so a thin calendar rotates instead of repeating a lead.
  `featured_mode` reports which branch ran:
  - `near` — events inside the window
  - `next_up` — nothing near, so the single next real event however far out
  - `evergreen` — genuinely nothing, so `featured_fallback` carries the slot
- **Touch** — oldest unused poll whose `season` is the current season or `any`,
  preferring in-season copy so seasonal prompts are spent in their season. Claimed
  by stamping `used_on`.
- **Spotlight** — least recently shown active row, recorded on
  `daily_briefings.spotlight_id`. The read model returns what was composed rather
  than re-deriving it.

---

## What each run does

`run_briefing_reconcile()` — service_role only, called hourly by pg_cron.

1. Resolve the town date: `(now() at time zone 'America/Chicago')::date`. Never
   the server's UTC date — after ~7pm local, UTC has already rolled over.
2. **Today must be published.**
   - No row at all (cold start, or many missed runs) → compose it, then publish.
   - Row exists but is a draft (the normal case — yesterday's run drafted it) →
     publish it.
   - Already published → nothing.
3. **Tomorrow gets drafted**, if it does not exist yet. Never published: that
   preserves the dashboard edit window and lets the day re-compose against a
   fresher calendar on the morning it goes live.
4. Return a summary including `bank_remaining_in_season`. It lands in
   `cron.job_run_details`.

Every step is idempotent, so running it 24 times a day is safe and the 23 runs
with nothing to do are two index lookups each.

### Watching it

```sql
select runid, status, return_message, start_time
from cron.job_run_details
where jobid = (select jobid from cron.job where jobname = 'briefing-reconcile')
order by start_time desc limit 12;
```

When `bank_remaining_in_season` drops below 10, more polls need writing. Do NOT
auto-generate them — the bank is edited copy, and the point of the module is that
a person wrote it.

### Things that must not happen

- **Never fabricate an event, a vote, or a count.** `DESIGN.md` bans seeded or
  inflated data in any surface, and the featured picker only ever selects rows that
  already exist and are approved.
- **Never publish a day with nothing in it.** `publish_briefing` already refuses,
  and the client renders `status: "none"` calmly. An empty published briefing is
  worse than no briefing.
- **Never write `almanac_md` you cannot stand behind.** The routine draws it from
  `evergreen_pool`, whose lines are already verified true. If you add rows there,
  hold them to the same bar — it is town-wide copy with no per-day review.

---

## Verifying a run

```sql
select briefing_date, status, published_at,
       (select count(*) from briefing_featured f where f.briefing_date = db.briefing_date) as featured,
       (select prompt from daily_touches t where t.used_on = db.briefing_date) as touch,
       (select slug from spotlights s where s.id = db.spotlight_id) as spotlight
from daily_briefings db
order by briefing_date desc limit 7;
```

And the payload the app will actually receive:

```sql
select jsonb_pretty(public.get_today_briefing(null, 'America/Chicago'));
```

## Re-running a day by hand

`compose_briefing` is idempotent. Re-running refreshes the almanac copy and
re-picks featured events, but **keeps** the touch and spotlight already claimed for
that date, so a manual re-run does not burn extra bank. To force a different touch,
clear it first:

```sql
update daily_touches set used_on = null where used_on = '<date>';
```
