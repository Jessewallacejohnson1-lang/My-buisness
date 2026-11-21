-- The Event calendar in under a second (BP app town-feed 81). Signed out it took 1.1 s in the database for 803
-- cards; the same bodies, changed only in how they run, take 0.57 s (timed in a rolled-back copy, 2026-11-20):
--  - place_picture, event_gender and entry_picture run inside another function. Postgres 17 plans a SQL function
--    again on every such call (0.7 ms each); plpgsql keeps the plan for the session. Bodies unchanged.
--  - event_subject: the same, and its plain-word patterns are checked with like, since its 34 regexes outgrew
--    Postgres's regex cache (32) and were all compiled again on every call. The same subject for all 2,704 Events.
--    Made by sources/scripts/place_photos.py sql.
--  - event_group read all of sources for one name, once per card: an index on the name.

create or replace function private.event_subject(p_title text, p_sport text, p_category text)
returns text
language plpgsql
immutable
set search_path = public
as $$
begin
  return (
  select case
    when t.x like any (array['%hockey%']) then 'hockey'
    when t.x like any (array['%basketball%']) then 'basketball'
    when t.x like any (array['%wrestl%', '%matness%']) then 'wrestling'
    when t.x like any (array['%swim%', '%diving%']) then 'swimming'
    when t.x like any (array['%gymnast%']) then 'gymnastics'
    when t.x like any (array['%volleyball%']) then 'volleyball'
    when t.x like any (array['%football%']) then 'football'
    when t.x like any (array['%cross country%']) then 'cross-country'
    when t.x like any (array['%track and field%', '%track & field%']) then 'track'
    when t.x ~ '\y5k\y|\y10k\y|fun run|marathon|turkey trot|\yshuffle\y' then 'running'
    when t.x like any (array['%soccer%']) then 'soccer'
    when t.x like any (array['%sauna%', '%ice bath%', '%plunge%']) then 'sauna'
    when t.x like any (array['%yoga%', '%pilates%', '%chi kung%', '%qigong%', '%tai chi%']) then 'yoga'
    when t.x ~ '\ydance|high kick|\ykick\y|varsity jazz|jazz (?:and|&) kick' then 'dance'
    when t.x like any (array['%choir%', '%vocal%', '%chorale%', '%singers%']) then 'choir'
    when t.x ~ '\yband\y|jazz|orchestra|ensemble|\yorgan\y|symphony|informance|drumming' then 'band'
    when t.x like any (array['%concert%']) then 'concert'
    when t.x like any (array['%knowledge bowl%', '%math league%', '%robotics%']) then 'academic'
    when t.x ~ '\yfilm' then 'film'
    when t.x like any (array['%powwow%', '%festival%', '%fashion show%']) then 'festival'
    when t.x ~ 'theat|\yplay\y|musical|mamma mia|mermaid|fall show' then 'theater'
    when t.x like any (array['%gallery%', '%exhibit%', '%reception%', '%selected works%', '%bible prints%']) then 'art-gallery'
    when t.x ~ '\ymass\y|prayer|retreat|adoration|sacred|pilgrimage|contemplative|vespers|spirituality' then 'worship'
    when t.x like any (array['%council%', '%board meeting%', '%commission%', '%planning board%', '%authority%', '%monthly meeting%', '%work session%']) then 'meeting'
    when t.x ~ 'lecture|\ytalk|webinar|speaker|poet|keynote|panel|workshop|training|certificate|class\y' then 'talk'
    when t.x ~ '\ymarkets?\y|fare for all' then 'market'
    when t.x like any (array['%paint%', '%stitch%', '%craft%', '%arrangement%', '%porch pot%', '%art club%', '%wreath%']) then 'crafts'
    when t.x like any (array['%trivia%', '%bingo%', '%raffle%', '%puzzle%', '%board game%', '%game night%', '%game competition%', '%keys for cash%']) then 'games'
    when t.x like any (array['%blood drive%']) then 'blood-drive'
    when t.x like any (array['%hike%', '%tracking%', '%arboretum%', '%conservation%', '%luminary%']) then 'outdoors'
    when t.x like any (array['%black friday%', '%pink friday%', '%days of giving%', '%holiday launch%', '%holiday collection%', '%open house%', '%boo-tique%', '%twinkle%']) then 'shopping'
    when t.x like any (array['%learning commons%', '%popcorn%', '%paws for%']) then 'library'
    when t.x like any (array['%gala%', '%dinner%', '%banquet%']) then 'dinner'
    when t.x like any (array['%party%', '%haunted%']) then 'party'
    else coalesce(jsonb_build_object('watch_sports', 'sports', 'play_sports', 'sports', 'live_music', 'concert', 'art_theater', 'theater', 'faith', 'worship', 'books', 'library', 'health', 'health', 'festivals', 'festival', 'markets', 'market', 'families_kids', 'kids', 'outdoors', 'outdoors', 'dining', 'dinner', 'crafts', 'crafts', 'games', 'games', 'town_meetings', 'meeting', 'campus', 'campus', 'bars', 'bar', 'volunteering', 'volunteer') ->> p_category, 'place')
  end
  from (select lower(coalesce(p_sport, '') || ' ' || coalesce(p_title, '')) as x) t
  );
end
$$;

CREATE OR REPLACE FUNCTION public.place_picture(p_entry_id text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public'
AS $function$
begin
  return (

  select coalesce(
    (select jsonb_build_object('url', p.url, 'kind', 'photo', 'credit', p.credit, 'site', p.source_url,
                               'w', p.width, 'h', p.height,
                               'more', coalesce((select jsonb_agg(jsonb_build_object('url', o.url, 'kind', 'photo',
                                                          'credit', o.credit, 'site', o.source_url,
                                                          'w', o.width, 'h', o.height)
                                                        order by o.position, o.id)
                                                   from public.place_photos o
                                                  where o.entry_id = p.entry_id and o.status = 'live'
                                                    and o.kind = 'photo' and o.id <> p.id), '[]'::jsonb))
       from public.place_photos p
      where p.entry_id = p_entry_id and p.status = 'live' and p.kind = 'photo'
      order by p.position, p.id limit 1),
    (select jsonb_build_object('url', p.url, 'kind', 'logo', 'hue', p.hue)
       from public.place_photos p
      where p.entry_id = p_entry_id and p.status = 'live' and p.kind = 'logo'
      order by p.position limit 1),
    (select jsonb_build_object('url', pl.search_logo->>'url', 'kind', 'logo',
              'hue', case when coalesce((pl.search_logo->>'chroma')::boolean, true)
                          then (pl.search_logo->>'hue')::numeric end)
       from public.places pl
      where pl.entry_id = p_entry_id and pl.search_logo->>'url' is not null
      order by pl.name limit 1))
  );
end
$function$;

CREATE OR REPLACE FUNCTION private.event_gender(p_title text, p_sport text)
 RETURNS text
 LANGUAGE plpgsql
 IMMUTABLE
AS $function$
begin
  return (

  select case
    when x ~ '\y(girls|women|womens|women''s|lady|ladies)\y' then 'girls'
    when x ~ '\y(boys|men|mens|men''s)\y' then 'boys'
    when x ~ '\y(csb|bennies|blazers)\y|\ys(ain)?t\.? benedict' and x !~ '\y(sju|johnnies)\y' then 'girls'
    when x ~ '\y(sju|johnnies)\y' and x !~ '\y(csb|bennies|blazers)\y|\ys(ain)?t\.? benedict' then 'boys'
  end
  from (select lower(coalesce(p_sport, '') || ' ' || coalesce(p_title, '')) as x) t
  );
end
$function$;

CREATE OR REPLACE FUNCTION private.entry_picture(p_entry text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  return (

  select coalesce(
    (select jsonb_build_object('url', ph.url, 'kind', 'logo', 'hue', ph.hue)
       from public.place_photos ph
      where ph.entry_id = p_entry and ph.status = 'live' and ph.kind = 'logo'
      order by ph.position limit 1),
    (select jsonb_build_object('url', pl.search_logo->>'url', 'kind', 'logo',
              'hue', case when coalesce((pl.search_logo->>'chroma')::boolean, true)
                          then (pl.search_logo->>'hue')::numeric end)
       from public.places pl
      where pl.entry_id = p_entry and pl.search_logo->>'url' is not null
      order by pl.name limit 1),
    public.place_picture(p_entry))
  );
end
$function$;

create index if not exists sources_name on public.sources (name);
