-- An Event whose title names no subject but whose About or place says exhibit, art show or gallery is an exhibit
-- (art-gallery), not its category's theater (BP app event-photos 26): "Bréagán", in the Alice R. Rogers and Target
-- Galleries, was theater, so with no photo of its own it could show another show's scene. The words are
-- place_photos.EXHIBIT, the dig's is_exhibit too. The subject function is `place_photos.py sql` (its self-test reads
-- this file); it takes two more arguments, so the three-argument one goes first. event_picture is
-- 20261110231708_lineup_counts_approved.sql line for line but for passing the About and the place.

drop function private.event_subject(text, text, text);

create or replace function private.event_subject(p_title text, p_sport text, p_category text,
                                                 p_about text default null, p_place text default null)
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
    when t.x ~ '\ydance|high kick|\ykick\y|varsity jazz|jazz (?:and|&) kick' then 'dance'
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
    when t.x ~ '\ymarkets?\y|fare for all' then 'market'
    when t.x ~ 'paint|stitch|craft|arrangement|porch pot|art club|wreath' then 'crafts'
    when t.x ~ 'trivia|bingo|raffle|puzzle|board game|game night|game competition|keys for cash' then 'games'
    when t.x ~ 'blood drive' then 'blood-drive'
    when t.x ~ 'hike|tracking|arboretum|conservation|luminary' then 'outdoors'
    when t.x ~ 'black friday|pink friday|days of giving|holiday launch|holiday collection|open house|boo-tique|twinkle' then 'shopping'
    when t.x ~ 'learning commons|popcorn|paws for' then 'library'
    when t.x ~ 'gala|dinner|banquet' then 'dinner'
    when t.x ~ 'party|haunted' then 'party'
    when lower(coalesce(p_about, '') || ' ' || coalesce(p_place, '')) ~ '\yexhibit|\yart show|\ygaller(?:y|ies)\y' then 'art-gallery'
    else coalesce(jsonb_build_object('watch_sports', 'sports', 'play_sports', 'sports', 'live_music', 'concert', 'art_theater', 'theater', 'faith', 'worship', 'books', 'library', 'health', 'health', 'festivals', 'festival', 'markets', 'market', 'families_kids', 'kids', 'outdoors', 'outdoors', 'dining', 'dinner', 'crafts', 'crafts', 'games', 'games', 'town_meetings', 'meeting', 'campus', 'campus', 'bars', 'bar', 'volunteering', 'volunteer') ->> p_category, 'place')
  end
  from (select lower(coalesce(p_sport, '') || ' ' || coalesce(p_title, '')) as x) t
$$;

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
                      and oe.status = 'approved'
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
           join lateral (select private.event_subject(e.title, e.sport, e.category, e.description, e.location) as subject,
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
