-- Jesse's three weekly numbers (BP app docs/plans/town-feed, ticket 26): whether the Town feed's
-- order works, so a rule that moves nothing can be switched off and deleted. Admin only.
-- A week runs Monday to Monday, Town time. What exists to count today:
--   shown: an Event a person saw in the Town feed that week (a view, ticket 20), once per person;
--   acted on: one of those they then went Going to or saved that week (shares aren't recorded);
--   bad: Not interested taps that week per 1,000 views (Report, ticket 22, isn't built: it joins
--        here when it is);
--   reach: people who acted on anything that week over people who saw the feed that week (opening
--          the app isn't recorded; a view is the nearest sign).
create or replace function public.weekly_numbers(p_week date default null)
returns table (
  week_start date,
  shown int,
  acted_on int,
  action_rate numeric,
  views int,
  not_interested int,
  bad_rate numeric,
  viewers int,
  actors int,
  reach numeric
)
language sql
stable
security definer
set search_path = ''
as $$
  with week as (
    select d as day,
           d::timestamp at time zone 'America/Chicago' as starts,
           (d + 7)::timestamp at time zone 'America/Chicago' as ends
    from (select date_trunc('week', coalesce(p_week, (now() at time zone 'America/Chicago')::date))::date as d) w
  ),
  acts as (
    select a.user_id, a.item_id, a.action, a.at
    from public.feed_actions a, week
    where a.at >= week.starts and a.at < week.ends
  ),
  -- Each Event a person saw that week, from their first view.
  seen as (
    select user_id, item_id, min(at) as first_at from acts where action = 'view' group by 1, 2
  ),
  -- Going or saved that week, by anyone.
  took as (
    select r.user_id, r.event_id as item_id, r.created_at as at from public.event_rsvps r, week
    where r.created_at >= week.starts and r.created_at < week.ends
    union all
    select s.user_id, s.event_id, s.created_at from public.event_saves s, week
    where s.created_at >= week.starts and s.created_at < week.ends
  ),
  counts as (
    select (select count(*) from seen)::int as shown,
           (select count(*) from seen s
            where exists (select 1 from took t
                          where t.user_id = s.user_id and t.item_id = s.item_id and t.at >= s.first_at))::int as acted_on,
           (select count(*) from acts where action = 'view')::int as views,
           (select count(*) from acts where action = 'not_interested')::int as not_interested,
           (select count(distinct user_id) from seen)::int as viewers,
           (select count(distinct t.user_id) from took t where t.user_id in (select user_id from seen))::int as actors
  )
  select week.day, c.shown, c.acted_on,
         round(c.acted_on::numeric / nullif(c.shown, 0), 4),
         c.views, c.not_interested,
         round(c.not_interested::numeric * 1000 / nullif(c.views, 0), 2),
         c.viewers, c.actors,
         round(c.actors::numeric / nullif(c.viewers, 0), 4)
  from week, counts c
  where public.is_admin()
$$;
revoke execute on function public.weekly_numbers(date) from public, anon;
grant execute on function public.weekly_numbers(date) to authenticated;
