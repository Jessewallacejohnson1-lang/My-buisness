-- BP app backlog 20 (from daily-tab 27 and town-feed 67): the bell's moved and called-off notices for a game you
-- follow say "game vs …" for a co-op too, and a whole school followed hears of its co-op games.
-- 1. A neighbour who follows a whole school is told when a game its activity plays under another team's name moves
--    or is called off (Kennedy's Wrestling 7-12 as the St. Cloud co-op), as the Town feed lifts it (`my_activities`'
--    school rows in supabase/town_feed.sql).
-- 2. The card carries game.mine, your side's team uuid, as the Town feed's does: the app finds your side by it when
--    the followed name isn't a team in the game (ROCORI hockey plays as River Lakes), and says "game vs …" in place
--    of the Event's title.
-- Copied from the live function (20261108033320_heart_replaces_save.sql, checked equal on 2026-11-18); only the
-- follow rows and the card's side are new.
create or replace function public.get_my_changes(p_now timestamptz default now())
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
  -- What the caller follows of the schools: get_town_feed's my_activities and my_schools. Each activity starred
  -- (`ord` 1), then the activities of a whole school followed that play under another team's name (3), named by the
  -- school as a whole school's are (2). `fielder` and `coop`: the teams it plays as.
  my_activities as (
    select m.a, m.label, m.logo, m.ord, coalesce((m.a).fielded_by, (m.a).team_id) as fielder, (m.a).coop as coop
    from (
      select a, t.short_name || ' ' || a.name as label, t.logo_url as logo, 1 as ord
      from public.town_follows f
      join public.team_activities a on a.id = f.target_id
      join public.teams t on t.id = a.team_id
      where f.follower_id = auth.uid() and f.target_type = 'activity'
      union all
      select a, t.short_name, t.logo_url, 3
      from public.town_follows f
      join public.teams t on t.uuid = f.target_id
      join public.team_activities a on a.team_id = t.id
      where f.follower_id = auth.uid() and f.target_type = 'team'
        and (a.fielded_by is not null or a.coop is not null)) m
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
           exists (select 1 from public.event_rsvps r where r.event_id = e.id and r.user_id = auth.uid()) as going,
           -- Hearted (inside-cards 16): told when it's called off, never when it moves.
           exists (select 1 from public.event_likes l where l.event_id = e.id and l.user_id = auth.uid()) as hearted
    from public.club_events e cross join town
    where auth.uid() is not null
      and e.status = 'approved'
      and e.kind = 'event'
      and e.event_date >= town.today
      and coalesce(e.cancelled_at, e.moved_at) is not null
  ),
  told as (
    select (c.ev).*, c.changed_at, c.going, fl.label, fl.logo, fl.side
    from changed c
    -- The activity or school followed that this Event is of: an activity starred first, then the whole school,
    -- then a school whose activity plays in it under another team's name; a school named with the Event's sport or
    -- activity ("Apollo Football"). `side`: the first pick that is a side of the game, the co-op's team when the
    -- co-op plays, else its own (the Town feed's game.mine, daily-tab 27).
    left join lateral (
      select (array_agg(x.label order by x.ord, x.label))[1] as label,
             (array_agg(x.logo order by x.ord, x.label))[1] as logo,
             (array_agg(x.team order by x.ord, x.label) filter (where x.team = any((c.ev).team_ids)))[1] as side
      from (
        select m.label || case when m.ord = 3 then coalesce(' ' || coalesce((c.ev).sport, (c.ev).activity_name), '')
                               else '' end as label,
               m.logo, m.ord,
               case when m.coop = any(array_append(coalesce((c.ev).team_ids, '{}'), (c.ev).activity_team))
                    then m.coop else m.fielder end as team
        from my_activities m
        where ((c.ev).team_ids is not null or (c.ev).activity_team is not null) and public.activity_has_event(m.a, c.ev)
        union all
        select s.label || coalesce(' ' || coalesce((c.ev).sport, (c.ev).activity_name), ''), s.logo, 2, s.id
        from my_schools s
        where s.id = any((c.ev).team_ids) or s.id = (c.ev).activity_team) x
      ) fl on true
    where c.going or (c.hearted and (c.ev).cancelled_at is not null)
       or (fl.label is not null and c.changed_at > p_now - interval '7 days')
  )
  -- The Event card, asked once for all of the rows: its game carries the score, and your side as game.mine.
  select coalesce(case when t.side is not null and jsonb_typeof(ec.card->'game') = 'object'
                       then jsonb_set(ec.card, '{game,mine}',
                                      (select to_jsonb(tm.uuid) from public.teams tm where tm.id = t.side)) end,
                  ec.card),
         t.changed_at, case when t.cancelled_at is null then t.moved_from end, t.label, t.logo
  from told t
  join private.event_cards(array(select x.id from told x)) ec on ec.id = t.id
  order by t.changed_at desc, t.id
$$;
revoke execute on function public.get_my_changes(timestamptz) from public, anon;
grant execute on function public.get_my_changes(timestamptz) to authenticated;
