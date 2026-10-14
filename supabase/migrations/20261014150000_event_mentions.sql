-- Every mention of a found event is kept (registry ADR-021), so the two-mention rule for
-- secondhand sources (ADR-001) can count them across mornings (BP app
-- docs/plans/watch-every-place, ticket 03). Written by the SQL that
-- sources/scripts/write_judged.py makes; one row per event, source and page.
-- Read and written with the admin key only: a town group's post never reaches the app.

create table if not exists public.event_mentions (
  event_id    uuid not null references public.club_events(id) on delete cascade,
  source_name text not null,
  source_url  text not null,
  source_uid  text,
  trust       text not null check (trust in ('official', 'squishy')),  -- the registry's words (ADR-001)
  sure        boolean not null,
  first_seen  timestamptz not null default now(),
  last_seen   timestamptz not null default now(),
  primary key (event_id, source_name, source_url)
);

alter table public.event_mentions enable row level security;
-- No policies on purpose: anon/authenticated get nothing. Service role bypasses RLS.
