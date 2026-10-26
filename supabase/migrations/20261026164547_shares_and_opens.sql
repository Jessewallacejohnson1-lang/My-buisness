-- Shares and app opens for Jesse's weekly numbers (BP app docs/plans/town-feed, ticket 26
-- follow-up): an Event shared from the app is one more feed action, and each person's first open
-- of the app each Town day is one row. weekly_numbers then counts a share as acting on an Event,
-- and reach as people who acted over people who opened the app.

alter table public.feed_actions drop constraint feed_actions_action_check;
alter table public.feed_actions add constraint feed_actions_action_check
  check (action in ('view', 'open', 'not_interested', 'share'));

-- One row per person per Town day they opened the app. Nobody reads or writes it through the API
-- but record_open, which adds today's row once.
create table public.app_opens (
  user_id uuid not null references auth.users (id) on delete cascade,
  day date not null,
  primary key (user_id, day)
);
alter table public.app_opens enable row level security;
revoke all on public.app_opens from anon, authenticated;

create or replace function public.record_open()
returns void
language sql
security definer
set search_path = ''
as $$
  insert into public.app_opens (user_id, day)
  select auth.uid(), (now() at time zone 'America/Chicago')::date
  where auth.uid() is not null
  on conflict do nothing
$$;
revoke execute on function public.record_open() from public, anon;
grant execute on function public.record_open() to authenticated;

-- 20261026161000_weekly_numbers.sql but for shares and opens: acted on now counts a share, and reach
-- is over people who opened the app that week (a feed view counts as an open, so a week from before
-- opens were recorded, or an app too old to send them, still reads). It returns two more columns,
-- so it is dropped and made again.
drop function public.weekly_numbers(date);
create function public.weekly_numbers(p_week date default null)
returns table (
  week_start date,
  shown int,
  acted_on int,
  action_rate numeric,
  views int,
  not_interested int,
  bad_rate numeric,
  openers int,
  actors int,
  reach numeric,
  shares int,
  viewers int
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
  -- Going, saved or shared that week, by anyone.
  took as (
    select r.user_id, r.event_id as item_id, r.created_at as at from public.event_rsvps r, week
    where r.created_at >= week.starts and r.created_at < week.ends
    union all
    select s.user_id, s.event_id, s.created_at from public.event_saves s, week
    where s.created_at >= week.starts and s.created_at < week.ends
    union all
    select user_id, item_id, at from acts where action = 'share'
  ),
  opened as (
    select o.user_id from public.app_opens o, week where o.day >= week.day and o.day < week.day + 7
    union
    select user_id from seen
  ),
  counts as (
    select (select count(*) from seen)::int as shown,
           (select count(*) from seen s
            where exists (select 1 from took t
                          where t.user_id = s.user_id and t.item_id = s.item_id and t.at >= s.first_at))::int as acted_on,
           (select count(*) from acts where action = 'view')::int as views,
           (select count(*) from acts where action = 'not_interested')::int as not_interested,
           (select count(*) from opened)::int as openers,
           (select count(distinct t.user_id) from took t where t.user_id in (select user_id from opened))::int as actors,
           (select count(*) from acts where action = 'share')::int as shares,
           (select count(distinct user_id) from seen)::int as viewers
  )
  select week.day, c.shown, c.acted_on,
         round(c.acted_on::numeric / nullif(c.shown, 0), 4),
         c.views, c.not_interested,
         round(c.not_interested::numeric * 1000 / nullif(c.views, 0), 2),
         c.openers, c.actors,
         round(c.actors::numeric / nullif(c.openers, 0), 4),
         c.shares, c.viewers
  from week, counts c
  where public.is_admin()
$$;
revoke execute on function public.weekly_numbers(date) from public, anon;
grant execute on function public.weekly_numbers(date) to authenticated;
