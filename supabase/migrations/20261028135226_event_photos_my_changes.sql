-- public.get_my_changes, as 20261026165558_moved_notices.sql made it, with its card picture from event_picture
-- (event-photos 07: a photo of what the event is, from its place's scenes, else place_picture).
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
  description text,
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
         public.event_picture(t.id), t.description,
         case when t.sport is not null then private.event_game(t.sport, t.team_ids, t.occasion) end,
         t.changed_at, case when t.cancelled_at is null then t.moved_from end, t.label, t.logo
  from told t
  left join public.clubs cl on cl.id = t.club_id
  order by t.changed_at desc, t.id
$$;
