-- A flyer shows whole on the Event page and the Block Party tab's cards, over a blurred copy of itself (Jesse,
-- 2026-11-03 and 2026-11-05, BP app event-photos 16). Kind `flyer` says so already, but the deep dive kept its flyers as
-- `event` or `scene`, and re-kinding them would let a scene beat an own photo, and a scene names no Event. So a flag.
-- event_picture is 20261104200634_event_picture_says_cover.sql line for line but for the flag. Absent on every other
-- picture, as `cover` is; builds from before this ignore the new key. Rows are marked by the picture's address.

alter table public.place_photos add column whole boolean not null default false;

update public.place_photos set whole = true
 where url in (
  'https://lxdgwhvqjqmqliobwjpi.supabase.co/storage/v1/object/public/places/st-joseph/events/event-band-light-blue-cathedral-school-band-concert-title-graphic-with-14456d4a91.webp',
  'https://lxdgwhvqjqmqliobwjpi.supabase.co/storage/v1/object/public/places/st-joseph/events/event-band-the-abbey-s-own-picture-for-this-vocalist-and-organist-b9ac5d3768.webp',
  'https://lxdgwhvqjqmqliobwjpi.supabase.co/storage/v1/object/public/places/st-joseph/events/event-crafts-green-and-gold-holiday-arrangement-party-title-graphic-with-202189d5a4.webp',
  'https://lxdgwhvqjqmqliobwjpi.supabase.co/storage/v1/object/public/places/st-joseph/events/event-dinner-navy-and-gold-cathedral-school-winter-gala-title-graphic-68fad8ca66.webp',
  'https://lxdgwhvqjqmqliobwjpi.supabase.co/storage/v1/object/public/places/st-joseph/events/event-dinner-the-bakery-s-pizza-night-schedule-graphic-listing-every-fe3d3fe48d.webp',
  'https://lxdgwhvqjqmqliobwjpi.supabase.co/storage/v1/object/public/places/st-joseph/events/event-shopping-a-teacher-and-students-in-blue-school-shirts-with-a-gold-5857be8e15.webp',
  'https://lxdgwhvqjqmqliobwjpi.supabase.co/storage/v1/object/public/places/st-joseph/events/event-shopping-w-r-s-holiday-events-graphic-over-a-stocking-hung-mantel-2934abf065.webp',
  'https://lxdgwhvqjqmqliobwjpi.supabase.co/storage/v1/object/public/places/st-joseph/saint-johns-abbey/scene-band-abbey-concert-graphic-for-a-past-choir-and-organ-concert-1ba30aaa92.webp',
  'https://lxdgwhvqjqmqliobwjpi.supabase.co/storage/v1/object/public/places/st-joseph/saint-johns-abbey/scene-band-abbey-concert-graphic-for-a-past-trumpet-and-organ-concert-8d97b8f839.webp'
 );

create or replace function public.event_picture(p_event uuid)
returns jsonb
language sql
stable
security invoker
set search_path = public
as $$
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
$$;
