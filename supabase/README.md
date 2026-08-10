# supabase/ — schema under version control

Until now, schema / RLS / publication changes were applied ad-hoc to the live
project (`lxdgwhvqjqmqliobwjpi`) and recorded only in prose in `MAP_BUILD_LOG.md`.
That leaves no reproducible way to stand up a second environment, no rollback path,
and no diffable record of the DB's actual shape. This directory fixes the *practice*.

## The rule

Every schema / RLS / publication / storage change gets a numbered `.sql` file
committed here **alongside the Swift change that depends on it**. `MAP_BUILD_LOG.md`
stays the narrative layer; `supabase/migrations/` becomes the durable record.

## Workflow

```bash
# new change
supabase migration new <name>          # creates a timestamped .sql
# write the DDL, then apply it (either is fine):
supabase db push                       # via the CLI
# or via the Supabase MCP: apply_migration(name, query)
```

## Baseline

`20260705000000_baseline_schema.sql` is the full baseline — all 21 `public` tables,
their constraints and indexes, RLS + every policy, the `is_admin()` /
`rls_auto_enable()` helpers, the two SECURITY DEFINER read models
(`get_feed_postings`, `get_event_comments`), the realtime publication, and the three
storage buckets with their policies. It is dated to sort before every other file
here, so `baseline -> 20260706 -> …` replays correctly on an empty project. The
later files are all `add column if not exists`, so they become no-ops on a fresh
replay — that is expected, not a bug.

It was reconstructed by introspecting the live project on 2026-08-04, **not** by
`supabase db pull` (the CLI is not installed). It was verified by building every
table and index into a throwaway schema on the live project and diffing that
against `public`:

- columns (name, type, not-null, default) — **0 differences** across 21 tables
- constraints (PK, unique, FK, check) — **0 differences** except the two
  `town_profiles` checks, which are `NOT VALID` in prod and declared valid in the
  baseline (same expression; a fresh DB starts empty). Documented in the file.
- indexes — **0 differences**

Policies, functions, realtime and storage in that file were transcribed from
`pg_policies` / `pg_proc` / `storage.*` but **were not executed anywhere** — running
them requires a real target, and doing it against prod would have meant dropping and
recreating live policies. Validate them on a Supabase branch or a local stack before
trusting the file for a production restore.

Still not captured: `auth.*` and `storage.objects` internals (Supabase-managed),
row data, and secrets.

### Known: the wellness tables are still live

`public.profiles`, `public.food_logs` and `public.workouts` belong to the retired
Hygge Health product. `pending/20260711_sunset_wellness_app.sql` drops them but has
**not been run** — verified present on 2026-08-04. The baseline records them so it
matches reality; delete that section when you run the sunset.

### Known: `is_admin()` hardcodes an email

Admin is `auth.jwt() ->> 'email' = '<a single hardcoded address>'`, compiled into the
function. Admin cannot be granted or revoked without a schema change, and the address
is committed to git. An `admins` table or a custom JWT claim is the usual fix —
deliberately not changed here, since a baseline records reality rather than improving it.

## functions/ — edge function source

`functions/daily-almanac/` and `functions/moderate-post/` are the source for the
two Edge Functions this app calls at runtime (`BlockParty/Backend/DailyAlmanac.swift`
and `Moderation.swift`). Both are deployed and ACTIVE on the live project.

They previously existed **only** in the Expo repo (`my-business` @ `community-rebuild`),
a branch with no shared git history with this one — so the source for two live
production functions sat outside the repo that depends on them. Copied here on
2026-08-04, verified byte-identical to the deployed versions (`daily-almanac` v5,
`moderate-post` v6) before committing.

```bash
supabase functions deploy daily-almanac --project-ref lxdgwhvqjqmqliobwjpi
supabase secrets set ANTHROPIC_API_KEY=...     # both functions need it
```

`daily-almanac` ships its own checks — run them before any deploy:

```bash
cd supabase/functions/daily-almanac
node --experimental-strip-types prompt-sync.check.mts   # embedded prompt vs prompts/almanac.md
node --experimental-strip-types verify.mts              # format spread + no-repeat rules
```

The prompt lives twice on purpose: readable in `prompts/almanac.md`, base64-embedded
in `index.ts` (Deno deploy ships no side files). `prompt-sync.check.mts` is what stops
those two drifting — it is not optional.

## Two-repo note

Anything that must match the Expo repo (`@hygge/core`) — RLS policies, the
`submitted_by` real-only guard, the admin allowlist — should change in lockstep
there. See the "backend twin" foundation in `REVIEW.md`.

That repo is now dormant (last commit 2026-07-21) and its web app is a different
product line. Treat **this** repo as the source of truth for the shared Supabase
project; pull from the Expo repo only to recover history.

## Edge function source (`functions/`)

Deployed edge-function source is mirrored here — `daily-almanac` (the almanac
writer, which since v9 also logs every decision to `content_decisions` /
`content_candidates`) and `log-agent-event` (Control Room build log). Deploys
happen via the Supabase MCP or `supabase functions deploy <name>`; treat these
files as the source of truth and redeploy from them, never edit only in prod.
