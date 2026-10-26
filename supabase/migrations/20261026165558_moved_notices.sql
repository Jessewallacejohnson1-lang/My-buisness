-- The moved-or-canceled notice (BP app docs/plans/school-activities, ticket 04): an Event you follow
-- (an activity starred, or its whole school) or are Going to that is canceled, or whose time or place
-- changes, goes into Notifications behind the Town bar's bell. Nothing pops up (Jesse, 2026-10-26:
-- "dont pop up on screen unless pressed just move to notifications"); a real push is ticket 06.
--
-- 1. club_events keeps when it last moved and where from. A trigger sets them for every writer (the
--    morning's apply_judged upsert, an admin's edit), so no writer has to know.
-- 2. get_my_changes: the caller's canceled and moved Events still to come.

alter table public.club_events
  add column if not exists moved_at timestamptz,
  add column if not exists moved_from jsonb;

-- The free-text start as minutes after midnight ("7 PM", "7:00 PM", "7pm", "noon", "19:00"); null when
-- it doesn't read ("TBA"). get_town_feed's own parse, as a function for the trigger.
create or replace function private.start_minutes(p text)
returns int
language sql
immutable
set search_path = ''
as $$
  select case
    when lower(btrim(p)) = 'noon' then 720
    when lower(btrim(p)) = 'midnight' then 0
    when m12 is not null and m12[1]::int between 1 and 12 and coalesce(m12[2], '0')::int < 60
      then (m12[1]::int % 12) * 60 + coalesce(m12[2], '0')::int + case when m12[3] = 'p' then 720 else 0 end
    when m24 is not null and m24[1]::int < 24 and m24[2]::int < 60
      then m24[1]::int * 60 + m24[2]::int
  end
  from (select regexp_match(lower(btrim(p)), '^(\d{1,2})(?::(\d{2}))?\s*([ap])\.?m\.?$') as m12,
               regexp_match(btrim(p), '^(\d{1,2}):(\d{2})(?::\d{2})?$') as m24) t
$$;

-- Two written places are one when, lowered and stripped to letters and digits, one holds the other:
-- "Kennedy" and "Kennedy Community School - Gym" are the same place written longer.
create or replace function private.same_place(a text, b text)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select x = y or position(x in y) > 0 or position(y in x) > 0
  from (select btrim(regexp_replace(lower(a), '[^a-z0-9]+', ' ', 'g')) as x,
               btrim(regexp_replace(lower(b), '[^a-z0-9]+', ' ', 'g')) as y) t
$$;

-- Whether `to` (a date, start and place) is a move from `was`: another day, a start more than 15
-- minutes off, or really another place. A blank start or place on the old side being filled in
-- ("TBA" to "7 PM") is not a move, and neither is an all-day flip on the same day.
create or replace function private.is_move(was jsonb, to_date date, to_start text, to_place text)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select (was->>'event_date')::date is distinct from to_date
      or coalesce(abs(private.start_minutes(was->>'start_time') - private.start_minutes(to_start)) > 15, false)
      or (nullif(btrim(was->>'location'), '') is not null and nullif(btrim(to_place), '') is not null
          and not private.same_place(was->>'location', to_place))
$$;

create or replace function private.note_moved()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  was jsonb := jsonb_build_object('event_date', old.event_date, 'start_time', old.start_time,
                                  'location', old.location);
begin
  -- Only an Event still to come, and only a dated one, can move.
  if old.event_date is null or new.event_date is null
     or greatest(old.event_date, new.event_date) < (now() at time zone 'America/Chicago')::date then
    return new;
  end if;
  if not private.is_move(was, new.event_date, new.start_time, new.location) then
    return new;
  end if;
  -- Back where it first was (a misread fixed the next morning): it never moved, nobody is told.
  if new.moved_from is not null
     and not private.is_move(new.moved_from, new.event_date, new.start_time, new.location) then
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

drop trigger if exists club_events_moved on public.club_events;
create trigger club_events_moved
  before update of event_date, start_time, location on public.club_events
  for each row execute function private.note_moved();

-- The caller's canceled and moved Events still to come, newest change first: every one they're
-- Going to, and each one of an activity or school they follow changed in the last 7 days (a new
-- phone doesn't open on a pile of old news). `followed` names what they follow ("Kennedy
-- Volleyball"), with its school's logo; null for one they're only Going to.
create or replace function public.get_my_changes(p_now timestamptz default now())
returns table (
  id uuid,
  title text,
  event_date date,
  start_time text,
  location text,
  image_url text,
  category text,
  club_name text,
  source_name text,
  end_at timestamptz,
  all_day boolean,
  created_at timestamptz,
  going_count int,
  going boolean,
  cancelled boolean,
  place_picture jsonb,
  game jsonb,
  changed_at timestamptz,
  moved_from jsonb,
  followed text,
  followed_logo text
)
language sql
stable
security invoker
set search_path = public
as $$
  with town as (
    select (p_now at time zone 'America/Chicago')::date as today
  ),
  -- What the caller follows of the schools: get_town_feed's my_activities and my_schools.
  my_activities as (
    select a, t.short_name || ' ' || a.name as label, t.logo_url as logo, 1 as ord
    from public.town_follows f
    join public.team_activities a on a.id = f.target_id
    join public.teams t on t.id = a.team_id
    where f.follower_id = auth.uid() and f.target_type = 'activity'
  ),
  my_schools as (
    select t.id, t.short_name as label, t.logo_url as logo
    from public.town_follows f
    join public.teams t on t.uuid = f.target_id
    where f.follower_id = auth.uid() and f.target_type = 'team'
  ),
  -- Each whole row as `ev`, since activity_has_event takes a club_events row.
  changed as (
    select e as ev, coalesce(e.cancelled_at, e.moved_at) as changed_at,
           exists (select 1 from public.event_rsvps r where r.event_id = e.id and r.user_id = auth.uid()) as going
    from public.club_events e cross join town
    where auth.uid() is not null
      and e.status = 'approved'
      and e.kind = 'event'
      and e.event_date >= town.today
      and coalesce(e.cancelled_at, e.moved_at) is not null
  ),
  told as (
    select (c.ev).*, c.changed_at, c.going, fl.label, fl.logo
    from changed c
    -- The activity or school followed that this Event is of: an activity starred first, then the
    -- whole school, named with the Event's sport or activity ("Apollo Football").
    left join lateral (
      select * from (
        select m.label, m.logo, m.ord from my_activities m
        where ((c.ev).team_ids is not null or (c.ev).activity_team is not null) and public.activity_has_event(m.a, c.ev)
        union all
        select s.label || coalesce(' ' || coalesce((c.ev).sport, (c.ev).activity_name), ''), s.logo, 2 from my_schools s
        where s.id = any((c.ev).team_ids) or s.id = (c.ev).activity_team) x
      order by x.ord limit 1) fl on true
    where c.going or (fl.label is not null and c.changed_at > p_now - interval '7 days')
  )
  select t.id, t.title, t.event_date, t.start_time, t.location, t.image_url, t.category,
         cl.name, t.source_name, t.end_at, t.all_day, t.created_at,
         private.going_count(t.id), t.going, t.cancelled_at is not null,
         public.place_picture(t.place_entry_id),
         case when t.sport is not null then private.event_game(t.sport, t.team_ids, t.occasion) end,
         t.changed_at, case when t.cancelled_at is null then t.moved_from end, t.label, t.logo
  from told t
  left join public.clubs cl on cl.id = t.club_id
  order by t.changed_at desc, t.id
$$;

revoke execute on function public.get_my_changes(timestamptz) from public, anon;
grant execute on function public.get_my_changes(timestamptz) to authenticated;
