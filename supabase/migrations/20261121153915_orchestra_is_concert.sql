-- An orchestra or symphony is concert, not band: a jazz band photo showed on Cathedral's Orchestra Concert (BP app event-photos 27).

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
    when t.x ~ '\yband\y|jazz|ensemble|\yorgan\y|informance|drumming' then 'band'
    when t.x like any (array['%concert%', '%orchestra%', '%symphony%']) then 'concert'
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
