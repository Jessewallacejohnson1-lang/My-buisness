-- Same place in other words is not a move (BP app docs/plans/watch-every-place, ticket 39; Jesse's yes
-- 2026-11-20). A re-read Facebook Event writes its host's place text every time, and the words alone
-- marked 6 of 7 such Events moved though they stayed put. A new place is now a new place_entry_id, or
-- a spot (lat, lng) over about 150 m off; the words decide only when neither row has a place or a spot.

-- Two places, each {location, place_entry_id, lat, lng}, are one.
create or replace function private.same_place(a jsonb, b jsonb)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select case
    when coalesce(a->>'place_entry_id', b->>'place_entry_id', a->>'lat', b->>'lat') is null then private.same_place(a->>'location', b->>'location')
    else not coalesce(a->>'place_entry_id' <> b->>'place_entry_id', false)
     and not coalesce(111320 * sqrt(((a->>'lat')::float8 - (b->>'lat')::float8) ^ 2
           + (((a->>'lng')::float8 - (b->>'lng')::float8) * cos(radians((a->>'lat')::float8))) ^ 2) > 150, false)
  end
$$;

-- is_move now takes the new side whole, as `was` is.
drop function if exists private.is_move(jsonb, date, text, text);
create or replace function private.is_move(was jsonb, now_ jsonb)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select (was->>'event_date')::date is distinct from (now_->>'event_date')::date
      or coalesce(abs(private.start_minutes(was->>'start_time') - private.start_minutes(now_->>'start_time')) > 15, false)
      or (nullif(btrim(was->>'location'), '') is not null and nullif(btrim(now_->>'location'), '') is not null
          and not private.same_place(was, now_))
$$;

create or replace function private.note_moved()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  was jsonb := jsonb_build_object('event_date', old.event_date, 'start_time', old.start_time,
                                  'location', old.location, 'place_entry_id', old.place_entry_id,
                                  'lat', old.lat, 'lng', old.lng);
  now_ jsonb := jsonb_build_object('event_date', new.event_date, 'start_time', new.start_time,
                                   'location', new.location, 'place_entry_id', new.place_entry_id,
                                   'lat', new.lat, 'lng', new.lng);
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

-- The 6 false marks (ticket 39's table). The Magic of Motown (498853ef) really moved and keeps its
-- mark. Only Santa Knows has neither a place nor a spot, so the rule still reads it as moved: cleared by id.
update public.club_events set moved_at = null, moved_from = null
where id in ('faaa2c51-0851-48f9-84f9-5bff9931b085',  -- Young Adult Praise Night
             'cd887295-7f4f-4285-8a5b-20b644de63cd',  -- AMCofA Big Sing
             '4accb9a9-f15e-4453-bf73-370f0eccb926',  -- Pumpkin Pie Giveaway
             'efc451e3-20ed-467d-9dce-87da2ee3b3cc',  -- Only Santa Knows Mystery Tour
             'f48edfa8-1e3b-4510-9be3-a880898cf829',  -- Market at the Meadow
             '16030009-1e82-456c-9057-a4ca4995e5c7')  -- Wreath Workshop
  and moved_at is not null;
