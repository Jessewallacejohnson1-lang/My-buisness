-- A place's cover is not a photo of the Event (Jesse, 2026-11-04: "cover photos should never be shown on town feed
-- only photos of the event", BP app town-feed 40). event_picture ends in the place's picture and sent it as a plain
-- photo, so the app couldn't tell. Its answer now carries cover: true there, and only there. event_picture is
-- 20261102165940_event_flyer.sql line for line but for that last read. Builds from before this ignore the new key.

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
       -- The Event's subject, season and gender read once, not once per scene photo of its place (up to 25),
       -- and only when its place has a scene: offset 0 keeps Postgres from pasting them back into the
       -- filter (2026-10-31).
       join lateral (select private.event_subject(e.title, e.sport, e.category) as subject,
                            private.season_of(e.event_date) as season,
                            coalesce(private.event_gender(e.title, e.sport), '') as gender
                      where exists (select 1 from public.place_photos x
                                     where x.entry_id = e.place_entry_id and x.status = 'live' and x.kind = 'scene')
                      offset 0) k on true
       join public.place_photos s on s.entry_id = e.place_entry_id and s.status = 'live' and s.kind = 'scene'
      where e.id = p_event
        and k.subject = any (s.subjects)
        and (s.seasons = '{}' or k.season = any (s.seasons)
             or ('christmas' = any (s.seasons) and private.christmas_fit(e.title, e.event_date)))
        and not ('girls' = any (s.subjects) and k.gender = 'boys')
        and not ('boys' = any (s.subjects) and k.gender = 'girls')
      order by s.seasons = '{}', md5(e.id::text || s.id::text)
      limit 1),
    (select jsonb_build_object('url', f.url, 'kind', 'photo', 'credit', f.credit, 'site', f.source_url,
                               'w', f.width, 'h', f.height,
                               'more', coalesce((select jsonb_agg(jsonb_build_object('url', o.url, 'kind', 'photo',
                                                          'credit', o.credit, 'site', o.source_url,
                                                          'w', o.width, 'h', o.height)
                                                        order by o.position, o.id)
                                                   from public.place_photos o
                                                  where o.entry_id = e.place_entry_id and o.status = 'live'
                                                    and o.kind = 'photo'), '[]'::jsonb))
       from public.club_events e
       join public.place_photos f on f.event_id = e.id and f.status = 'live' and f.kind = 'flyer'
      where e.id = p_event),
    -- The place's own picture says so when it is a photo: the Event's Town card goes white, its page keeps it.
    -- offset 0 keeps Postgres from pasting place_picture back in, once per use.
    (select case when c.picture->>'kind' = 'photo' then c.picture || '{"cover": true}'::jsonb else c.picture end
       from (select public.place_picture(e.place_entry_id) as picture
               from public.club_events e where e.id = p_event offset 0) c))
$$;
