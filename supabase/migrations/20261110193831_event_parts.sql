-- The parts of a long Event (BP app docs/plans/happening-now, ticket 03): an Event that runs 12 hours or longer (an
-- exhibit, a festival, an all-day market) may hold parts at a time its host wrote: an artist talk, a reception, a
-- speaker. Each morning sources/scripts/event_parts.py reads the Event's own page and its host's, two helpers list the
-- parts on their own, and a part is written only where both found it on the same day at the same start, each quoting
-- the host's words with that time. Never a guess. One card per Event: a part never makes a card of its own.
--
-- ends_at empty: the part runs 1 hour (readers apply it). same_as: an Event already listed on the part's day, at its
-- start and place; that Event stays, and the part points at it rather than making a double (Jesse, 2026-11-05).
-- source_line: the host's words the part was read from, for the sample check and the morning report.
-- The app only reads; the morning job's role `watch` replaces an Event's parts each morning it reads them.

create table public.event_parts (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.club_events (id) on delete cascade,
  title text not null check (btrim(title) <> ''),
  starts_at timestamptz not null,
  ends_at timestamptz check (ends_at > starts_at),
  source_url text not null,
  source_line text not null check (btrim(source_line) <> ''),
  same_as uuid references public.club_events (id) on delete set null,
  found_at timestamptz not null default now(),
  unique (event_id, starts_at, title)
);

create index event_parts_starts_at on public.event_parts (starts_at);

comment on table public.event_parts is
  'Parts at a stated time of an Event running 12 hours or longer (happening-now 03). ends_at empty = 1 hour. Only the morning job writes.';

alter table public.event_parts enable row level security;
create policy "Anyone reads the parts" on public.event_parts
  for select to anon, authenticated using (true);
revoke insert, update, delete, truncate on public.event_parts from anon, authenticated;

grant select, insert, delete on public.event_parts to watch;
create policy "watch rows" on public.event_parts to watch using (true) with check (true);
