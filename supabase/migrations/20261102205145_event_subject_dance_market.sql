-- private.event_subject is the place-photos skill's `scenes.py sql` (iOS sources/scripts/place_photos.py
-- SUBJECTS), BP app event-photos 13 (Jesse, 2026-11-02): a dance team's "Varsity Jazz", "Junior Varsity
-- Jazz", "Jazz and Kick" and "Conference Kick" meets are dance, not band or theater (they showed a jazz band
-- and a play); Fare for All, which sells food boxes, is a market, not a dinner (it showed a sit-down meal).

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
    else coalesce(jsonb_build_object('watch_sports', 'sports', 'play_sports', 'sports', 'live_music', 'concert', 'art_theater', 'theater', 'faith', 'worship', 'books', 'library', 'health', 'health', 'festivals', 'festival', 'markets', 'market', 'families_kids', 'kids', 'outdoors', 'outdoors', 'dining', 'dinner', 'crafts', 'crafts', 'games', 'games', 'town_meetings', 'meeting', 'campus', 'campus', 'bars', 'bar', 'volunteering', 'volunteer') ->> p_category, 'place')
  end
  from (select lower(coalesce(p_sport, '') || ' ' || coalesce(p_title, '')) as x) t
$$;
