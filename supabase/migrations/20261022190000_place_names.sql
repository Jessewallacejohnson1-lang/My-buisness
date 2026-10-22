-- A place's name in its own lettering (BP app follows 02, Jesse 2026-10-22: "the name of the place
-- ... in whatever their font is that they use on their website", cut out of its logo when the font
-- can't be had). One white-on-clear picture per registry entry, in the public `places` bucket as
-- `st-joseph/<entry>/name-<hash>.png`; the app tints it white or black, whichever reads on the
-- photo, at the bottom centre of an Event page's and a business page's photo. A place with none
-- shows its page as before. Kept apart from `place_photos`, so the monthly photo refresh never
-- checks a name as a photo. Everyone reads; only the service role writes.

create table if not exists public.place_names (
  entry_id   text primary key,          -- sources.entry_id, as places.entry_id and place_photos
  url        text not null,
  source_url text,                      -- the logo or page the name was cut from
  created_at timestamptz not null default now()
);

alter table public.place_names enable row level security;
drop policy if exists "read place names" on public.place_names;
create policy "read place names" on public.place_names for select to anon, authenticated using (true);
grant select on public.place_names to anon, authenticated;

-- The name over an Event's photo: its place's, when it has one.
create or replace function public.event_place_name(p_event uuid)
returns text
language sql
stable
set search_path = ''
as $$
  select n.url
  from public.club_events e
  join public.place_names n on n.entry_id = e.place_entry_id
  where e.id = p_event
$$;
grant execute on function public.event_place_name(uuid) to anon, authenticated;
