# supabase/

The Block Party database: one Supabase project, `lxdgwhvqjqmqliobwjpi`, shared with the
waitlist website.

- `migrations/20260929000000_schema.sql`: the whole live schema in one file, read from
  the database on 2026-09-29. Every table, column, index, function, trigger, policy,
  grant, bucket and scheduled job. Checked by running it on an empty Postgres and
  comparing each of those against live: all match. The 41 older migrations it replaced
  are in git history.
- `functions/`: source of the two live Edge Functions, `moderate-post` (Claude reviews a
  post) and `log-agent-event` (Control Room build log). Deploy from here with
  `supabase functions deploy <name>`; never edit only in the dashboard.
- `tests/`: fixed stories for the database functions, run in PGlite (Postgres compiled to
  WASM, so no Docker): `npm install && npm test` there. The Town feed's are in
  `town_feed.test.mjs`.
- `pending/20260711_sunset_wellness_app.sql`: drops the retired Hygge Health tables
  (`profiles`, `food_logs`, `workouts`). Not run. Destructive: back up, then run by hand.

## Changing the schema

A schema change is a new migration file here, committed with the Swift change that needs
it (`supabase migration new <name>`), applied with the Supabase MCP's `apply_migration`
or `supabase db push`. Never a hand edit in the dashboard.

## Known gaps

- The live migration history still lists the 34 changes this file replaced.
  `apply_migration` doesn't care; `supabase db push` refuses until
  `supabase migration repair` marks those 34 reverted and `20260929000000` applied.
- `is_admin()` hardcodes one email, so admin can't change without a migration.
- The `bizops_ro` password is set by hand and never committed.
