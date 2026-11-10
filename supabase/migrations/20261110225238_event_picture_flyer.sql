-- One flyer with many Events (BP app town-feed 59; Jesse, 2026-11-10: "if each event could have a different cover photo,
-- and then you could swipe and then see the full list of things ... if you can't find a photo, then it just defaults to
-- the flyer"). An Event may now keep its own photo and its flyer together, so its page opens on the photo and swipes to
-- the flyer. event_picture is 20261105193756_whole_flyer.sql line for line, wrapped: when the Event has a live flyer
-- and the picture is something else, it adds "flyer" (the flyer as a whole picture); when that flyer also lists an
-- Event with another title, "lineup": true, so the page can say what it is part of. Builds from before this ignore both.

-- One live picture per Event per kind: its own photo and its flyer side by side, never two of either.
drop index if exists public.place_photos_one_per_event;
create unique index place_photos_one_per_event on public.place_photos (event_id, kind) where status = 'live';
-- The lineup read matches a flyer's address.
create index if not exists place_photos_flyer_url on public.place_photos (url) where kind = 'flyer' and status = 'live';

create or replace function public.event_picture(p_event uuid)
returns jsonb
language sql
stable
security invoker
set search_path = public
as $$
  select x.pic
         || case when f.url is not null and x.pic->>'url' is distinct from f.url
                 then jsonb_build_object('flyer', jsonb_build_object('url', f.url, 'kind', 'photo', 'credit', f.credit,
                                                                     'site', f.source_url, 'w', f.width, 'h', f.height,
                                                                     'whole', true))
                 else '{}'::jsonb end
         || case when f.url is not null and exists (
                   select 1 from public.place_photos o
                     join public.club_events oe on oe.id = o.event_id
                    where o.url = f.url and o.kind = 'flyer' and o.status = 'live' and o.event_id <> p_event
                      and lower(oe.title) <> lower(f.title))
                 then '{"lineup": true}'::jsonb
                 else '{}'::jsonb end
  from (
      select coalesce(
        (select case when p.whole then '{"whole": true}'::jsonb else '{}'::jsonb end
                || jsonb_build_object('url', p.url, 'kind', 'photo', 'credit', p.credit, 'site', p.source_url,
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
        (select case when s.whole then '{"whole": true}'::jsonb else '{}'::jsonb end
                || jsonb_build_object('url', s.url, 'kind', 'photo', 'credit', s.credit, 'site', s.source_url,
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
        -- A flyer is always whole.
        (select '{"whole": true}'::jsonb
                || jsonb_build_object('url', f.url, 'kind', 'photo', 'credit', f.credit, 'site', f.source_url,
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
  ) x(pic)
  left join lateral (select fl.url, fl.credit, fl.source_url, fl.width, fl.height, e.title
                       from public.place_photos fl
                       join public.club_events e on e.id = fl.event_id
                      where fl.event_id = p_event and fl.status = 'live' and fl.kind = 'flyer'
                      limit 1) f on true
$$;
