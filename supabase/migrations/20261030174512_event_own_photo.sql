-- An Event's own photo (BP app docs/plans/event-photos 09; Jesse, 2026-10-30: "for each event when the event is
-- found ... they should all have a photo of event. dont worry about games for now"). The morning job and the
-- social watch look at the pictures each new Event came with (its post, its campus listing, its own page) and,
-- when none is a real photo of it, at its place's other recent posts (sources/scripts/event_photos.py); the one a
-- model picks is saved as a place_photos row of kind 'event' tied to that Event, credited like a place photo and
-- taken down on request (status 'retired'). An Event card shows it before any scene. Search and the map read
-- kind 'photo' only, and place_picture 'photo' and 'logo', so an Event's photo never becomes a place's cover.
-- club_events.photo_checked_at: when the job looked, found or not, so each Event is looked at once (as described_at).

alter table public.place_photos drop constraint if exists place_photos_kind_check;
alter table public.place_photos add constraint place_photos_kind_check check (kind in ('photo', 'logo', 'scene', 'event'));
alter table public.place_photos add column if not exists event_id uuid references public.club_events (id) on delete cascade;
alter table public.place_photos drop constraint if exists place_photos_event_kind;
alter table public.place_photos add constraint place_photos_event_kind check ((kind = 'event') = (event_id is not null));

-- A place's slots are its photos, logos and scenes; an Event's photo takes none, and an Event has one live photo.
drop index if exists public.place_photos_one_per_slot;
create unique index place_photos_one_per_slot on public.place_photos (entry_id, status, position)
  where status <> 'retired' and kind <> 'event';
create unique index if not exists place_photos_one_per_event on public.place_photos (event_id) where status = 'live';

alter table public.club_events add column if not exists photo_checked_at timestamptz;

-- public.event_picture, as 20261029140851_event_photos_christmas_fit.sql made it, with the Event's own photo first.
create or replace function public.event_picture(p_event uuid)
returns jsonb
language sql
stable
security invoker
set search_path = public
as $$
  select coalesce(
    (select jsonb_build_object('url', p.url, 'kind', 'photo', 'credit', p.credit, 'site', p.source_url,
                               'w', p.width, 'h', p.height,
                               'more', coalesce((select jsonb_agg(jsonb_build_object('url', o.url, 'kind', 'photo',
                                                          'credit', o.credit, 'site', o.source_url,
                                                          'w', o.width, 'h', o.height)
                                                        order by o.position, o.id)
                                                   from public.place_photos o
                                                  where o.entry_id = e.place_entry_id and o.status = 'live'
                                                    and o.kind = 'photo'), '[]'::jsonb))
       from public.club_events e
       join public.place_photos p on p.event_id = e.id and p.status = 'live' and p.kind = 'event'
      where e.id = p_event),
    (select jsonb_build_object('url', s.url, 'kind', 'photo', 'credit', s.credit, 'site', s.source_url,
                               'w', s.width, 'h', s.height,
                               'more', coalesce((select jsonb_agg(jsonb_build_object('url', o.url, 'kind', 'photo',
                                                          'credit', o.credit, 'site', o.source_url,
                                                          'w', o.width, 'h', o.height)
                                                        order by o.position, o.id)
                                                   from public.place_photos o
                                                  where o.entry_id = s.entry_id and o.status = 'live'
                                                    and o.kind = 'photo'), '[]'::jsonb))
       from public.club_events e
       join public.place_photos s on s.entry_id = e.place_entry_id and s.status = 'live' and s.kind = 'scene'
      where e.id = p_event
        and private.event_subject(e.title, e.sport, e.category) = any (s.subjects)
        and (s.seasons = '{}' or private.season_of(e.event_date) = any (s.seasons)
             or ('christmas' = any (s.seasons) and private.christmas_fit(e.title, e.event_date)))
        and not ('girls' = any (s.subjects) and coalesce(private.event_gender(e.title, e.sport), '') = 'boys')
        and not ('boys' = any (s.subjects) and coalesce(private.event_gender(e.title, e.sport), '') = 'girls')
      order by s.seasons = '{}', md5(e.id::text || s.id::text)
      limit 1),
    (select public.place_picture(e.place_entry_id) from public.club_events e where e.id = p_event))
$$;
