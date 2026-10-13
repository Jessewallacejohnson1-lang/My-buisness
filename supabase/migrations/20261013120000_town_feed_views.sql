-- Views recorded, popularity per view (BP app docs/plans/town-feed, ticket 20; plan in
-- assets/build-plans/final-views.md). The app records what the Town feed showed (a card half
-- on screen for 1 second is one view, once per card per feed load) and what was opened; a
-- summary turns views into Going per person who saw it, and the recipe's popularity term
-- switches on. The two jobs that refresh the summary and delete old views are in
-- 20261013120100_feed_jobs.sql (pg_cron, which PGlite doesn't have).

-- What the feed showed and what was opened. Insert-only through the API: the phone sends
-- the event and the action; who and when are set here. Nobody reads a row through the API,
-- their own included. A batch resent after a lost answer can land twice; the summary counts
-- distinct people, so popularity doesn't move (a phone-made id with ignore-duplicates would
-- need a select policy, which this table must not have).
create table public.feed_actions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  item_id uuid not null references public.club_events (id) on delete cascade,
  action text not null check (action in ('view', 'open')),
  at timestamptz not null default now()
);
-- An account's deletion removes its rows through the foreign key: without this it would
-- scan the whole table.
create index feed_actions_user_id_idx on public.feed_actions (user_id);

alter table public.feed_actions enable row level security;
revoke all on public.feed_actions from anon, authenticated;
grant insert (item_id, action) on public.feed_actions to authenticated;
create policy "insert own feed actions" on public.feed_actions
  for insert to authenticated
  with check ((select auth.uid()) = user_id);

-- People who saw each event in the feed, refreshed every 10 minutes (feed_jobs). Counts
-- only, in the private schema the API doesn't expose; get_town_feed reads it as the caller.
create materialized view private.feed_item_stats as
  select item_id, count(distinct user_id)::int as viewers
  from public.feed_actions
  where action = 'view'
  group by item_id;
create unique index feed_item_stats_item_idx on private.feed_item_stats (item_id);
grant select on private.feed_item_stats to anon, authenticated;

-- Views older than 60 days go each night (feed_jobs). Opens stay: they're few.
create or replace function private.feed_clean_up(p_now timestamptz default now())
returns void
language sql
set search_path = ''
as $$
  delete from public.feed_actions where action = 'view' and at < p_now - interval '60 days'
$$;
revoke execute on function private.feed_clean_up(timestamptz) from public, anon, authenticated;

-- get_town_feed: 20261012120100_town_feed_private.sql line for line, plus popularity per
-- view, 'popular' as the reason only for the top quarter with 3+ Going, and the new-item
-- spot only under 30 viewers. Same columns, so replaced in place.
create or replace function public.get_town_feed(p_now timestamptz default now())
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
  rsvpd boolean,
  recurrence text,
  leaves_at timestamptz,
  reason text,
  reason_name text,
  score jsonb,
  heart_count int,
  hearted boolean,
  saved boolean
)
language sql
stable
security invoker
set search_path = public
as $$
  with weights as (
    -- The playground's starting weights (ticket 09). Changing one is a migration.
    select '{"interest":3,"friend":4,"follow":3,"popular":2,"size":1.5,"soonHalf":7,"newHalf":24,"acted":0.4,"notInterested":0.3,"meeting":0.3,"repeatHost":0.5,"maxRun":3,"newSpot":4}'::jsonb as w
  ),
  town as (
    select 'America/Chicago'::text as zone,
           (p_now at time zone 'America/Chicago')::date as today
  ),
  me as (
    select coalesce((select p.interests from public.town_profiles p where p.user_id = auth.uid()),
                    '{}'::text[]) as interests
  ),
  real_events as (
    select e.*,
           coalesce(e.club_id::text, e.source_name, e.submitted_by::text, '') as host,
           lower(btrim(e.title)) || '|' || coalesce(e.club_id::text, e.source_name, e.submitted_by::text, '')
             as series,
           -- The free-text start: "7 PM", "7:00 PM", "7pm", "noon", "19:00".
           case
             when e.all_day then null
             when lower(btrim(e.start_time)) = 'noon' then 720
             when lower(btrim(e.start_time)) = 'midnight' then 0
             when m12 is not null and m12[1]::int between 1 and 12 and coalesce(m12[2], '0')::int < 60
               then (m12[1]::int % 12) * 60 + coalesce(m12[2], '0')::int + case when m12[3] = 'p' then 720 else 0 end
             when m24 is not null and m24[1]::int < 24 and m24[2]::int < 60
               then m24[1]::int * 60 + m24[2]::int
           end as start_minutes
    from public.club_events e
    cross join lateral (select
      regexp_match(lower(btrim(e.start_time)), '^(\d{1,2})(?::(\d{2}))?\s*([ap])\.?m\.?$') as m12,
      regexp_match(btrim(e.start_time), '^(\d{1,2}):(\d{2})(?::\d{2})?$') as m24) t
    cross join town
    where e.status = 'approved'
      and e.kind = 'event'
      and e.event_date is not null
      and (e.submitted_by is not null or e.source_name is not null)
      -- The window a series' wording reads, plus anything still running.
      and (e.event_date >= town.today - 60 or e.end_at > p_now)
  ),
  timed as (
    select r.*,
           (r.event_date + make_interval(mins => r.start_minutes)) at time zone town.zone as starts_at,
           coalesce(
             r.end_at,
             (r.event_date + make_interval(mins => r.start_minutes)) at time zone town.zone + interval '2 hours',
             (r.event_date + 1)::timestamp at time zone town.zone
           ) as leaves_at
    from real_events r, town
  ),
  labels as (
    select t.series, public.town_feed_series_label(array_agg(t.event_date)) as recurrence
    from timed t, town
    where t.event_date >= town.today - 60
    group by t.series
  ),
  next_up as (
    select t.*,
           row_number() over (partition by t.series order by t.event_date, t.starts_at nulls first, t.id) as nth,
           exists (select 1 from public.event_rsvps r where r.event_id = t.id and r.user_id = auth.uid())
             as going,
           exists (select 1 from public.event_saves s where s.event_id = t.id and s.user_id = auth.uid())
             as saved
    from timed t
    where t.leaves_at > p_now
  ),
  shown as (
    select e.*,
           coalesce(e.starts_at, e.event_date::timestamp at time zone town.zone) as sort_at,
           e.event_date - town.today as days_off,
           greatest(0, extract(epoch from coalesce(e.starts_at, e.event_date::timestamp at time zone town.zone) - p_now) / 86400)
             as days_away,
           case when e.event_date - e.shows_from >= 50 then 3
                when e.event_date - e.shows_from >= 25 then 2
                else 1 end as size,
           (select array_agg(x order by x) from unnest(array[e.category]) x where x = any(me.interests)) as matched
    from next_up e, town, me
    where e.nth = 1
      and town.today >= coalesce(e.shows_from, e.event_date - 14)
  ),
  counted as (
    -- Going counted once (every account's, from the private helper), and the people who
    -- saw it in the feed, from the summary refreshed every 10 minutes.
    select s.*,
           private.going_count(s.id) as going_n,
           coalesce(st.viewers, 0) as viewers
    from shown s
    left join private.feed_item_stats st on st.item_id = s.id
  ),
  scored as (
    select c.*,
           (w->>'interest')::float8 * least(coalesce(array_length(c.matched, 1), 0), 2) as interest_pts,
           0::float8 as friend_pts,   -- friends Going: ticket 28
           0::float8 as follow_pts,   -- follows: ticket 27
           -- Popularity per view (ticket 20), the playground's formula: Going per person
           -- who saw it, with a floor of 20 so one early Going can't look huge. Nothing
           -- until someone has seen it in the feed: per view needs a view.
           case when c.viewers > 0
                then (w->>'popular')::float8 * least(c.going_n::float8 / greatest(c.viewers, 20) * 10, 3)
                else 0 end as popular_pts,
           -- Where its rate sits among this read's events: 'popular' as the reason needs
           -- the top quarter, popular compared with other events (Jesse, 2026-10-13).
           cume_dist() over (order by c.going_n::float8 / greatest(c.viewers, 20)) as rate_rank,
           (w->>'size')::float8 * (c.size - 1) as size_pts,
           power(0.5, c.days_away / (w->>'soonHalf')::float8) as soon,
           case when c.going or c.saved then (w->>'acted')::float8 else 1 end as acted
    from counted c, weights
  ),
  totals as (
    select c.*,
           (1 + c.interest_pts + c.friend_pts + c.follow_pts + c.popular_pts + c.size_pts) * c.soon * c.acted
             as base,
           -- New: under 2 days old with under 30 viewers and not acted on.
           c.created_at > p_now - interval '2 days' and c.viewers < 30 and not c.going and not c.saved
             as fresh,
           -- 'popular' as the reason needs at least 3 people Going and the top quarter by
           -- Going per viewer (Jesse, 2026-10-13); its points count either way.
           (select r.code from (values ('friend', c.friend_pts, 1), ('follow', c.follow_pts, 2),
                                       ('interest', c.interest_pts, 3),
                                       ('popular', case when c.going_n >= 3 and c.rate_rank > 0.75
                                                        then c.popular_pts else 0 end, 4),
                                       ('size', c.size_pts, 5)) r(code, pts, ord)
            where r.pts >= 1
            order by r.pts desc, r.ord limit 1) as lift
    from scored c
  ),
  placed as (
    select p.*
    from (select array_agg(t.id order by t.sort_at, t.title, t.id) as ids,
                 array_agg('event'::text order by t.sort_at, t.title, t.id) as kinds,
                 array_agg(t.host order by t.sort_at, t.title, t.id) as hosts,
                 array_agg(t.base order by t.sort_at, t.title, t.id) as scores,
                 array_agg(t.fresh order by t.sort_at, t.title, t.id) as fresh
          from totals t) a,
         weights,
         private.town_feed_place(a.ids, a.kinds, a.hosts, a.scores, a.fresh,
                                (w->>'maxRun')::int, (w->>'repeatHost')::float8, (w->>'newSpot')::int) p
  )
  select e.id, e.title, e.event_date, e.start_time, e.location, e.image_url, e.category,
         c.name, e.source_name, e.end_at, e.all_day, e.created_at,
         e.going_n,
         e.going,
         l.recurrence,
         e.leaves_at,
         case when p.moved then 'new'
              else coalesce(e.lift, case when e.days_off <= 0 then 'today' when e.days_off = 1 then 'tomorrow' else 'soon' end)
         end,
         case when e.lift = 'interest' and not p.moved then e.matched[1] end,
         case when public.is_admin() then jsonb_build_object(
           'interest', e.interest_pts, 'friend', e.friend_pts, 'follow', e.follow_pts,
           'popular', e.popular_pts, 'viewers', e.viewers, 'size', e.size_pts, 'sizeStep', e.size,
           'daysAway', round(e.days_away::numeric, 2), 'soon', round(e.soon::numeric, 4),
           'acted', e.acted, 'spacing', p.spacing, 'newSpot', p.moved,
           'total', round((e.base * p.spacing)::numeric, 4),
           'spot', p.spot, 'of', count(*) over ())
         end,
         private.heart_count(e.id),
         exists (select 1 from public.event_likes h where h.event_id = e.id and h.user_id = auth.uid()),
         e.saved
  from totals e
  join placed p on p.id = e.id
  left join public.clubs c on c.id = e.club_id
  left join labels l on l.series = e.series
  order by p.spot;
$$;

grant execute on function public.get_town_feed(timestamptz) to anon, authenticated;

comment on function public.get_town_feed(timestamptz) is
  'The Town feed for the caller, in their order (the ticket 09 recipe), with each event''s hearts and the caller''s save, and popularity per view. Both apps call it; neither re-sorts. BP app docs/plans/town-feed, tickets 05, 18, 19 and 20; real-life-actions, tickets 03 and 04.';
