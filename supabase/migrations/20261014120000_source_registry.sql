-- The source registry's runtime table (BP app docs/plans/watch-every-place, ticket 02; registry
-- ADR-002/003). Registry columns are overwritten from sources/*.md on every run.py --write;
-- runtime columns (last_*) are written only by run.py --write, so a run knows what changed
-- since the last one. Read and written with the admin key only: no policies for app users.

create table if not exists public.sources (
  id              uuid primary key default gen_random_uuid(),
  entry_id        text not null,              -- permanent slug from the md
  url             text not null,
  town            text not null,
  name            text not null,
  status          text not null check (status in ('proposed','active','paused','retired')),
  kind            text,
  method          text not null check (method in ('fetch','search_snippet','submission','api')),
  trust           text check (trust in ('official','squishy')),
  place_id        text,                       -- only Google field ever stored
  extra           jsonb not null default '{}',-- open schema: unknown md keys land here
  last_checked_at timestamptz,
  last_changed_at timestamptz,
  last_hash       text,
  last_error      text,
  unique (entry_id, url)
);

create index if not exists sources_town_status on public.sources (town, status);

alter table public.sources enable row level security;
-- No policies on purpose: anon/authenticated get nothing. Service role bypasses RLS.
