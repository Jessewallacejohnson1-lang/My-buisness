-- A game that moves to another arena is a move (BP app docs/plans/watch-every-place, ticket 40; Jesse's
-- yes 2026-11-20). A school game's place id is often the home school, not where it is played, so the
-- same id says nothing about the arena: a Rocori JV hockey game went from Huck Olson Memorial Arena to
-- Ralph Engelstad Arena, Thief River Falls, under rocori-high-school both times and nobody Going was
-- told. For a game (a sport and two teams, as private.event_game) the words decide, by the building:
-- school sites rename the room every week ("Main Gym" to "Gym Center Court"), so room words drop out,
-- and one set of the words left inside the other is the same building. Spots over about 150 m apart
-- are still a move. Every other Event keeps ticket 39's rule.

-- The building words of a place's text: lower case, no room words, no numbers.
create or replace function private.venue_words(p text)
returns text[]
language sql
immutable
set search_path = ''
as $$
  select coalesce(array_agg(distinct w), '{}')
  from regexp_split_to_table(lower(coalesce(p, '')), '[^a-z0-9]+') w
  where w <> '' and w !~ '^[0-9]+$'
    and w not in ('gym', 'gymnasium', 'main', 'court', 'courts', 'center', 'centre', 'aux', 'auxiliary',
                  'east', 'west', 'north', 'south', 'upper', 'lower', 'arena', 'rink', 'the', 'at', 'and')
$$;

-- Two place texts name one building: one's building words all sit in the other's.
create or replace function private.same_venue(a text, b text)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select x <@ y or y <@ x from (select private.venue_words(a) as x, private.venue_words(b) as y) t
$$;

-- Two places, each {location, place_entry_id, lat, lng, game}, are one. Copied from
-- 20261120184915_same_place_spots.sql with the game branch first.
create or replace function private.same_place(a jsonb, b jsonb)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select case
    when coalesce((a->>'game')::boolean, false) or coalesce((b->>'game')::boolean, false) then
      private.same_venue(a->>'location', b->>'location')
      and not coalesce(111320 * sqrt(((a->>'lat')::float8 - (b->>'lat')::float8) ^ 2
            + (((a->>'lng')::float8 - (b->>'lng')::float8) * cos(radians((a->>'lat')::float8))) ^ 2) > 150, false)
    when (a->>'place_entry_id' is null or b->>'place_entry_id' is null)
     and (a->>'lat' is null or b->>'lat' is null) then private.same_place(a->>'location', b->>'location')
    else not coalesce(a->>'place_entry_id' <> b->>'place_entry_id', false)
     and not coalesce(111320 * sqrt(((a->>'lat')::float8 - (b->>'lat')::float8) ^ 2
           + (((a->>'lng')::float8 - (b->>'lng')::float8) * cos(radians((a->>'lat')::float8))) ^ 2) > 150, false)
  end
$$;

-- Copied from 20261120184915_same_place_spots.sql; both sides now say whether the Event is a game.
create or replace function private.note_moved()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  was jsonb := jsonb_build_object('event_date', old.event_date, 'start_time', old.start_time,
                                  'location', old.location, 'place_entry_id', old.place_entry_id,
                                  'lat', old.lat, 'lng', old.lng,
                                  'game', old.sport is not null and cardinality(old.team_ids) = 2);
  now_ jsonb := jsonb_build_object('event_date', new.event_date, 'start_time', new.start_time,
                                   'location', new.location, 'place_entry_id', new.place_entry_id,
                                   'lat', new.lat, 'lng', new.lng,
                                   'game', new.sport is not null and cardinality(new.team_ids) = 2);
begin
  -- Only an Event still to come, and only a dated one, can move.
  if old.event_date is null or new.event_date is null
     or greatest(old.event_date, new.event_date) < (now() at time zone 'America/Chicago')::date then
    return new;
  end if;
  if not private.is_move(was, now_) then
    return new;
  end if;
  -- Back where it first was (a misread fixed the next morning): it never moved, nobody is told.
  if new.moved_from is not null and not private.is_move(new.moved_from, now_) then
    new.moved_at := null;
    new.moved_from := null;
    return new;
  end if;
  -- Moved: from where it first was, so a second move still says it, and a move back is caught.
  new.moved_from := coalesce(new.moved_from, was);
  new.moved_at := now();
  return new;
end;
$$;
