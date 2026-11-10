-- The parts of a long Event (BP app docs/plans/happening-now, ticket 03): an Event that runs 12 hours or longer (an
-- exhibit, a festival, an all-day market) may hold parts at a time its host wrote: an artist talk, a reception, a
-- speaker. Each morning sources/scripts/event_parts.py reads the Event's own page and its host's, two helpers list the
-- parts on their own, and a part is written only where both found it on the same day at the same start, each quoting
-- the host's words with that time. Never a guess. One card per Event: a part never makes a card of its own.
--
-- ends_at empty: the part runs 1 hour (readers apply it). same_as: an Event already listed on the part's day, at its
-- start and place; that Event stays, and the part points at it rather than making a double (Jesse, 2026-11-05).
-- source_line: the host's words the part was read from, for the sample check and the morning report.
-- The app reads an Event's parts through get_event_parts, finished here: the one place their rules live (below). The
-- table itself shows only the parts of an Event the caller may read. The morning job's role `watch` writes an Event's
-- new parts, then takes away its old ones, each morning it reads them.

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
-- Only the parts of an Event the caller may read: club_events' own read rule decides, as the caller (approved, or
-- theirs, or a friend's post they may see).
create policy "read the parts of an Event you can read" on public.event_parts
  for select to anon, authenticated
  using (exists (select 1 from public.club_events e where e.id = event_id));
revoke insert, update, delete, truncate on public.event_parts from anon, authenticated;

grant select, insert, update, delete on public.event_parts to watch;
create policy "watch rows" on public.event_parts to watch using (true) with check (true);

-- An Event's parts as its page lists them (happening-now 06), finished here so the app and the Town feed agree: by
-- start; a part that is an Event of its own (same_as) left out, it has its own card; no stated end, 1 hour. live: a
-- real happening by its title (private.is_live_kind, town-feed 41) running under 12 hours; only a live part says
-- "Now" or counts down. Security invoker: the caller sees only the parts of an Event they may read (the policy above).
create function public.get_event_parts(p_event uuid)
returns table (title text, starts_at timestamptz, ends_at timestamptz, live boolean)
language sql
stable
security invoker
set search_path = ''
as $$
  select ep.title, ep.starts_at, x.ends_at,
         x.ends_at - ep.starts_at < interval '12 hours'
           and private.is_live_kind(null, ep.title, null, false, 'part',
                                    (ep.starts_at at time zone 'America/Chicago')::date, x.ends_at)
  from public.event_parts ep
  cross join lateral (select coalesce(ep.ends_at, ep.starts_at + interval '1 hour') as ends_at) x
  where ep.event_id = p_event and ep.same_as is null
  order by ep.starts_at, ep.title
$$;
revoke execute on function public.get_event_parts(uuid) from public;
grant execute on function public.get_event_parts(uuid) to anon, authenticated;
