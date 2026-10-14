# ADR-003 — Supabase migrations are schema truth

**Status:** Accepted
**Date:** 2026-09-22

## Context

The registry's documentation describes a database table. The temptation is to write the
column list into `sources/README.md` so a reader can see the shape without opening the
migrations. Documentation that restates a schema goes stale the first time a column
changes, and then quietly lies.

## Decision

**Supabase migrations are the single source of truth for database schema.** Markdown
never restates column types, constraints, defaults or indexes. Where the shape of a
table matters to a reader, the docs link to the migration instead of copying from it.

## Consequences

- Reading a schema means reading `supabase/migrations/`. There is no faster answer, and
  no wrong one.
- A schema change is a migration. It is not a markdown edit, and it is not a change made
  by hand in the Supabase dashboard.
- The registry docs stay short and stay correct, at the cost of one extra hop for anyone
  who wants the column list.
