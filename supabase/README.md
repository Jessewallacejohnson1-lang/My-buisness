# supabase/

The Block Party database: one Supabase project, `lxdgwhvqjqmqliobwjpi`, shared with the
waitlist website.

- `migrations/20260929000000_schema.sql`: the whole live schema in one file, read from
  the database on 2026-09-29. Every table, column, index, function, trigger, policy,
  grant, bucket and scheduled job. Checked by running it on an empty Postgres and
  comparing each of those against live: all match. The 41 older migrations it replaced
  are in git history.
- `functions/`: source of the two live Edge Functions, `moderate-post` (Claude reviews a
  post) and `live-scores` (a game card's live score). Deploy from here with `supabase functions deploy <name>`; never edit only in the
  dashboard.
- `config.toml`: the settings that deploy reads. `live-scores` keeps its login check off.
- `tests/`: fixed stories for the database functions, run in PGlite (Postgres compiled to
  WASM, so no Docker): `npm install && npm test` there. The Town feed's are in
  `town_feed.test.mjs`.

## Changing the schema

A schema change is a new migration file here, committed with the Swift change that needs
it (`supabase migration new <name>`), and applied after Jesse's yes with
`scripts/apply_migration.py <file> --apply`, which refuses a change that would undo another
chat's live work. Never a hand edit in the dashboard, and never the Supabase connector's own
`apply_migration` tool, which skips that check (BP app blocks it with a hook).

## Known gaps

- The live migration history still lists the 34 changes this file replaced.
  `scripts/apply_migration.py` doesn't care; `supabase db push` refuses until
  `supabase migration repair` marks those 34 reverted and `20260929000000` applied.
- `is_admin()` hardcodes one email, so admin can't change without a migration.
- The `bizops_ro` password is set by hand and never committed.
