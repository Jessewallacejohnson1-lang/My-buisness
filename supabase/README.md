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

## ⚠️ Baseline is incomplete

The files here were **reconstructed from `MAP_BUILD_LOG.md`** and cover only the
changes that log documented (the realtime pipeline, `town_profiles`, the `avatars`
bucket, the board-dedup index). The pre-existing tables (`club_events`, `clubs`,
`club_members`, `trails`, `daily_quests`, `quest_completions`, `board_items`,
`evergreen_pool`, `rsvps`, …) and their RLS are **not yet captured**.

**Next step:** run `supabase db pull` against the live project to generate a true
baseline migration of the full current schema, then treat these hand-written files
as the historical record of what was applied on top of it. Verify each file against
prod before relying on it.

## Two-repo note

Anything that must match the Expo repo (`@hygge/core`) — RLS policies, the
`submitted_by` real-only guard, the admin allowlist — should change in lockstep
there. See the "backend twin" foundation in `REVIEW.md`.
