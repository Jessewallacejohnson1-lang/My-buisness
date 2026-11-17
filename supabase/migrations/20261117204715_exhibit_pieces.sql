-- Swipe through an exhibit's work (BP app event-photos 25; Jesse, 2026-11-17: "port the photos in, so viewers can swipe
-- through them", "like an Instagram carousel", then "yes" at Check-in 1). An Event may hold several live photos of its
-- own, each at its own position: the first leads its card, and an exhibit's page swipes through the rest, then its
-- flyer. Only the dig keeps more than one, and only for an exhibit; every other Event keeps one (inside-cards 15).
-- event_picture is 20261110231708_lineup_counts_approved.sql line for line, but: its own photo is the first by position,
-- and "pieces" (at most 9) carries the others in order. The own photo's id rides along inside as "own" and is taken
-- off before it returns. Builds from before this ignore "pieces".

-- One live photo per Event per position; one live flyer, News photo or anything else per Event, as before.
drop index if exists public.place_photos_one_per_event;
create unique index place_photos_one_per_event on public.place_photos (event_id, kind)
  where status = 'live' and kind <> 'event';
create unique index place_photos_one_per_piece on public.place_photos (event_id, position)
  where status = 'live' and kind = 'event';

create or replace function public.event_picture(p_event uuid)
returns jsonb
language sql
stable
security invoker
set search_path = public
as $$
  select (x.pic - 'own')
         -- An exhibit's other pieces, after the one leading its card (event-photos 25).
         || case when x.pic->>'own' is not null then coalesce((
                   select jsonb_build_object('pieces', jsonb_agg(jsonb_build_object('url', q.url, 'kind', 'photo',
                                                                 'credit', q.credit, 'site', q.source_url,
                                                                 'w', q.width, 'h', q.height)
                                                               order by q.position, q.id))
                     from (select q.* from public.place_photos q
                            where q.event_id = p_event and q.status = 'live' and q.kind = 'event'
                              and q.id <> (x.pic->>'own')::bigint
                            order by q.position, q.id
                            limit 9) q
                   having count(*) > 0), '{}'::jsonb)
                 else '{}'::jsonb end
         || case when f.url is not null and x.pic->>'url' is distinct from f.url
                 then jsonb_build_object('flyer', jsonb_build_object('url', f.url, 'kind', 'photo', 'credit', f.credit,
                                                                     'site', f.source_url, 'w', f.width, 'h', f.height,
                                                                     'whole', true))
                 else '{}'::jsonb end
         || case when f.url is not null and exists (
                   select 1 from public.place_photos o
                     join public.club_events oe on oe.id = o.event_id
                    where o.url = f.url and o.kind = 'flyer' and o.status = 'live' and o.event_id <> p_event
                      and oe.status = 'approved'
                      and lower(oe.title) <> lower(f.title))
                 then '{"lineup": true}'::jsonb
                 else '{}'::jsonb end
  from (
      select coalesce(
        (select case when p.whole then '{"whole": true}'::jsonb else '{}'::jsonb end
                || jsonb_build_object('own', p.id, 'url', p.url, 'kind', 'photo', 'credit', p.credit, 'site', p.source_url,
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
          where e.id = p_event
          -- The first of its set leads (event-photos 25).
          order by p.position, p.id
          limit 1),
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

