-- The bell sends the Event card and only what is its own (BP app codebase-health-2, ticket 03): when it changed,
-- where it moved from, and the activity or school followed that it is of, with its logo. The copied Event columns
-- beside the card go, and so does the old score-less `game`: the card's game carries the score. Builds on phones
-- from iOS main ee8e0a53 on read the Event from `card` (CommunityAPI.changeRows).
--
-- It is 20261102191016_event_card_changes.sql's get_my_changes with those columns dropped: the same rows, the
-- same order. The card comes for every row (the card source reads under the same rules), so it is an inner join.
--
-- Roll back: re-run 20261102191016_event_card_changes.sql.

drop function if exists public.get_my_changes(timestamptz);

create function public.get_my_changes(p_now timestamptz default now())
returns table (
  card jsonb,
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
  -- The Event card, asked once for all of the rows: its game carries the score.
  select ec.card, t.changed_at, case when t.cancelled_at is null then t.moved_from end, t.label, t.logo
  from told t
  join private.event_cards(array(select x.id from told x)) ec on ec.id = t.id
  order by t.changed_at desc, t.id
$$;

revoke execute on function public.get_my_changes(timestamptz) from public, anon;
grant execute on function public.get_my_changes(timestamptz) to authenticated;
