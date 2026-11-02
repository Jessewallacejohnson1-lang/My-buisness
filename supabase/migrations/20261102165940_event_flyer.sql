-- An Event's own flyer, when the post it came in had no real photo (Jesse, 2026-11-02: Flour & Flower's
-- Pizza night schedule flyer over the bakery's pastry photo). event_picture shows the Event's own photo,
-- then the scene of what it is, then its own flyer, then its place's picture. event_picture is
-- 20261031035522_event_picture_once.sql line for line but for the flyer read.
-- private.event_subject is the place-photos skill's `scenes.py sql`: "holiday collection" is shopping, and
-- a 5K, fun run, marathon, turkey trot or shuffle is running (Snowflake Shuffle 5K read as sports).

alter table public.place_photos drop constraint place_photos_kind_check;
alter table public.place_photos add constraint place_photos_kind_check
  check (kind in ('photo', 'logo', 'scene', 'event', 'flyer'));
-- A flyer names its Event as an Event's photo does, takes no place slot, and is that Event's one live picture
-- (place_photos_one_per_event).
alter table public.place_photos drop constraint place_photos_event_kind;
alter table public.place_photos add constraint place_photos_event_kind
  check ((kind in ('event', 'flyer')) = (event_id is not null));
drop index public.place_photos_one_per_slot;
create unique index place_photos_one_per_slot on public.place_photos (entry_id, status, position)
  where status <> 'retired' and kind not in ('event', 'flyer');

-- The five Pizza nights' flyer, saved as an Event photo before this kind existed.
update public.place_photos set kind = 'flyer'
 where kind = 'event' and description = 'Pizza night schedule for November and December';

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
    (select public.place_picture(e.place_entry_id) from public.club_events e where e.id = p_event))
$$;

create or replace function private.event_subject(p_title text, p_sport text, p_category text)
returns text
language sql
immutable
set search_path = public
as $$
  select case
    when t.x ~ 'hockey' then 'hockey'
    when t.x ~ 'basketball' then 'basketball'
    when t.x ~ 'wrestl|matness' then 'wrestling'
    when t.x ~ 'swim|diving' then 'swimming'
    when t.x ~ 'gymnast' then 'gymnastics'
    when t.x ~ 'volleyball' then 'volleyball'
    when t.x ~ 'football' then 'football'
    when t.x ~ 'cross country' then 'cross-country'
    when t.x ~ 'track and field|track & field' then 'track'
    when t.x ~ '\y5k\y|\y10k\y|fun run|marathon|turkey trot|\yshuffle\y' then 'running'
    when t.x ~ 'soccer' then 'soccer'
    when t.x ~ 'sauna|ice bath|plunge' then 'sauna'
    when t.x ~ 'yoga|pilates|chi kung|qigong|tai chi' then 'yoga'
    when t.x ~ '\ydance|high kick' then 'dance'
    when t.x ~ 'choir|vocal|chorale|singers' then 'choir'
    when t.x ~ '\yband\y|jazz|orchestra|ensemble|\yorgan\y|symphony|informance|drumming' then 'band'
    when t.x ~ 'concert' then 'concert'
    when t.x ~ 'knowledge bowl|math league|robotics' then 'academic'
    when t.x ~ '\yfilm' then 'film'
    when t.x ~ 'powwow|festival|fashion show' then 'festival'
    when t.x ~ 'theat|\yplay\y|musical|mamma mia|mermaid|fall show' then 'theater'
    when t.x ~ 'gallery|exhibit|reception|selected works|bible prints' then 'art-gallery'
    when t.x ~ '\ymass\y|prayer|retreat|adoration|sacred|pilgrimage|contemplative|vespers|spirituality' then 'worship'
    when t.x ~ 'council|board meeting|commission|planning board|authority|monthly meeting|work session' then 'meeting'
    when t.x ~ 'lecture|\ytalk|webinar|speaker|poet|keynote|panel|workshop|training|certificate|class\y' then 'talk'
    when t.x ~ '\ymarkets?\y' then 'market'
    when t.x ~ 'paint|stitch|craft|arrangement|porch pot|art club|wreath' then 'crafts'
    when t.x ~ 'trivia|bingo|raffle|puzzle|board game|game night|game competition|keys for cash' then 'games'
    when t.x ~ 'blood drive' then 'blood-drive'
    when t.x ~ 'hike|tracking|arboretum|conservation|luminary' then 'outdoors'
    when t.x ~ 'black friday|pink friday|days of giving|holiday launch|holiday collection|open house|boo-tique|twinkle' then 'shopping'
    when t.x ~ 'learning commons|popcorn|paws for' then 'library'
    when t.x ~ 'gala|dinner|fare for all|banquet' then 'dinner'
    when t.x ~ 'party|haunted' then 'party'
    else coalesce(jsonb_build_object('watch_sports', 'sports', 'play_sports', 'sports', 'live_music', 'concert', 'art_theater', 'theater', 'faith', 'worship', 'books', 'library', 'health', 'health', 'festivals', 'festival', 'markets', 'market', 'families_kids', 'kids', 'outdoors', 'outdoors', 'dining', 'dinner', 'crafts', 'crafts', 'games', 'games', 'town_meetings', 'meeting', 'campus', 'campus', 'bars', 'bar', 'volunteering', 'volunteer') ->> p_category, 'place')
  end
  from (select lower(coalesce(p_sport, '') || ' ' || coalesce(p_title, '')) as x) t
$$;
