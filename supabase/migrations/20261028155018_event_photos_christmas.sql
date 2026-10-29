-- Event photos (BP app docs/plans/event-photos 07, round 2): a photo with Christmas decor is tagged
-- 'christmas' and shows only from November 1 to January 6, whatever the season (Jesse, 2026-10-28:
-- White Peony's Halloween party showed Christmas sweaters). In that window it counts as made for the
-- event's season, so it goes before an any-season photo.

create or replace function private.christmas_time(p_date date)
returns boolean
language sql
immutable
as $$
  select extract(month from p_date) in (11, 12) or (extract(month from p_date) = 1 and extract(day from p_date) <= 6)
$$;

-- public.event_picture, as 20261028134743_event_photos.sql made it, with the Christmas window.
create or replace function public.event_picture(p_event uuid)
returns jsonb
language sql
stable
security invoker
set search_path = public
as $$
  select coalesce(
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
             or ('christmas' = any (s.seasons) and private.christmas_time(e.event_date)))
      order by s.seasons = '{}', md5(e.id::text || s.id::text)
      limit 1),
    (select public.place_picture(e.place_entry_id) from public.club_events e where e.id = p_event))
$$;
