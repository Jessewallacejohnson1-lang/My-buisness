-- Event photos (BP app docs/plans/event-photos, tickets 06 and 07): an event card shows a photo of
-- what the event is, at its own place, fitting the season. A pool photo is a place_photos row of
-- kind 'scene' with a description, the subjects it shows and the seasons it fits (empty: any).
-- Search and the map read kind 'photo' only, so a scene never becomes a business cover, and
-- place_picture reads 'photo' and 'logo' only. With no scene rows this changes nothing: every
-- card falls back to place_picture as before.

alter table public.place_photos drop constraint if exists place_photos_kind_check;
alter table public.place_photos add constraint place_photos_kind_check check (kind in ('photo', 'logo', 'scene'));
alter table public.place_photos
  add column if not exists description text,
  add column if not exists subjects text[] not null default '{}',
  add column if not exists seasons text[] not null default '{}';

-- What an event is, from its sport and title, else its category: the same list as the
-- place-photos skill's scenes.py (SUBJECTS), which writes this function.
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
    when t.x ~ 'black friday|pink friday|days of giving|holiday launch|open house|boo-tique|twinkle' then 'shopping'
    when t.x ~ 'learning commons|popcorn|paws for' then 'library'
    when t.x ~ 'gala|dinner|fare for all|banquet' then 'dinner'
    when t.x ~ 'party|haunted' then 'party'
    else coalesce(jsonb_build_object('watch_sports', 'sports', 'play_sports', 'sports', 'live_music', 'concert', 'art_theater', 'theater', 'faith', 'worship', 'books', 'library', 'health', 'health', 'festivals', 'festival', 'markets', 'market', 'families_kids', 'kids', 'outdoors', 'outdoors', 'dining', 'dinner', 'crafts', 'crafts', 'games', 'games', 'town_meetings', 'meeting', 'campus', 'campus', 'bars', 'bar', 'volunteering', 'volunteer') ->> p_category, 'place')
  end
  from (select lower(coalesce(p_sport, '') || ' ' || coalesce(p_title, '')) as x) t
$$;

-- Minnesota's seasons by month: December to February is winter.
create or replace function private.season_of(p_date date)
returns text
language sql
immutable
as $$
  select (array['winter', 'spring', 'summer', 'fall'])[(extract(month from p_date)::int % 12) / 3 + 1]
$$;

-- An event card's picture: of its place's live scenes showing the event's subject, one made for its
-- season before one that fits any season; several take turns by event. None: place_picture. Same
-- shape as place_picture, its "more" being the place's photos, for the Event page.
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
        and (s.seasons = '{}' or private.season_of(e.event_date) = any (s.seasons))
      order by s.seasons = '{}', md5(e.id::text || s.id::text)
      limit 1),
    (select public.place_picture(e.place_entry_id) from public.club_events e where e.id = p_event))
$$;

grant execute on function public.event_picture(uuid) to anon, authenticated;
