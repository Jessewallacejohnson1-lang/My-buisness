-- The Town feed in each neighbour's own order (BP app docs/plans/town-feed, ticket 18):
-- the recipe Jesse settled in the playground (ticket 09), its score() and rank() line for
-- line. Same eligibility, series and leave rules as 20261008120000_town_feed.sql; each row
-- now also says why it's there, and for the admin the points behind its place.
-- Friends, follows, popularity, Not interested, Mute and City meetings read zero or stay
-- out until their own tickets bring the data.

drop function if exists public.get_town_feed(timestamptz);

-- Places scored items one at a time (the playground's rank()): each pick is the best
-- score left after x repeat_host per item already placed from the same host, and never
-- a (max_run + 1)th of one kind in a row while another kind is left. Then the best-placed
-- fresh item moves up to spot new_spot if it sits lower. Inputs are parallel arrays in
-- the caller's order, which breaks ties. Returns each item's 1-based spot and the
-- spacing factor its pick was made at.
-- ponytail: O(n^2) picks; fine for the few hundred items a Town has, a heap past that.
create or replace function public.town_feed_place(
  ids uuid[], kinds text[], hosts text[], scores float8[], fresh boolean[],
  max_run int, repeat_host float8, new_spot int)
returns table (id uuid, spot int, spacing float8, moved boolean)
language plpgsql
immutable
set search_path = public
as $$
declare
  n int := coalesce(array_length(ids, 1), 0);
  taken boolean[] := array_fill(false, array[greatest(n, 1)]);
  seen jsonb := '{}';
  order_ int[] := '{}';
  factor float8[] := array_fill(1::float8, array[greatest(n, 1)]);
  run_kind text;
  best int;
  best_s float8;
  best_f float8;
  s float8;
  k int;
  i int;
  first_new int;
begin
  for k in 1..n loop
    run_kind := null;
    if k > max_run and (select count(distinct kinds[order_[j]]) from generate_series(k - max_run, k - 1) j) = 1 then
      run_kind := kinds[order_[k - 1]];
    end if;
    best := null;
    best_s := null;
    for i in 1..n loop
      continue when taken[i];
      s := power(repeat_host, coalesce((seen ->> hosts[i])::int, 0));
      if kinds[i] = run_kind then s := s * 1e-6; end if;
      if best is null or scores[i] * s > best_s then
        best := i;
        best_s := scores[i] * s;
        best_f := s;
      end if;
    end loop;
    taken[best] := true;
    factor[best] := best_f;
    order_ := order_ || best;
    seen := jsonb_set(seen, array[hosts[best]], to_jsonb(coalesce((seen ->> hosts[best])::int, 0) + 1));
  end loop;

  first_new := (select min(j) from generate_series(1, n) j where fresh[order_[j]]);
  if new_spot > 0 and first_new > new_spot then
    order_ := order_[1:new_spot - 1] || order_[first_new] || order_[new_spot:first_new - 1]
              || order_[first_new + 1:n];
  end if;

  return query
    select ids[order_[j]], j, factor[order_[j]], new_spot > 0 and first_new > new_spot and j = new_spot
    from generate_series(1, n) j;
end;
$$;

-- The caller's Town feed at p_now, in their order:
-- * what's in it is unchanged (ticket 05): approved events a person posted or a source
--   announced, from shows_from (or 14 days ahead) until they leave, a series once at its
--   next date;
-- * score = (1 + interest x min(matches, 2) + friend x friends going + follow + popular
--   x min(action rate x 10, 3) + size x (size - 1)) x 0.5^(days away / soonHalf) x acted
--   when you're Going or saved it; then placed by town_feed_place;
-- * matches: the event's interests among the caller's picked ones (town_profiles.
--   interests). An event's interests are its one category until events carry more;
-- * size from how early the event starts showing: shows_from 50+ days ahead is big (3),
--   25+ medium (2), else small (1);
-- * reason: 'new' for the item moved to the new-item spot; else the biggest lift when it's
--   worth a point or more, in the playground's order (friend, follow, interest, popular,
--   size); else the day (today, tomorrow, soon). reason_name is the matched interest;
-- * score: every term behind the place, for the admin only; null for everyone else.
-- Security invoker: RLS decides what the caller sees, so a signed-out read counts no
-- RSVPs and has no picks or own state: the Town's biggest, soonest things first.
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
  score jsonb
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
  scored as (
    select s.*,
           (w->>'interest')::float8 * least(coalesce(array_length(s.matched, 1), 0), 2) as interest_pts,
           0::float8 as friend_pts,   -- friends Going: ticket 28
           0::float8 as follow_pts,   -- follows: ticket 27
           0::float8 as popular_pts,  -- popularity per view: ticket 20
           (w->>'size')::float8 * (s.size - 1) as size_pts,
           power(0.5, s.days_away / (w->>'soonHalf')::float8) as soon,
           case when s.going or s.saved then (w->>'acted')::float8 else 1 end as acted
    from shown s, weights
  ),
  totals as (
    select c.*,
           (1 + c.interest_pts + c.friend_pts + c.follow_pts + c.popular_pts + c.size_pts) * c.soon * c.acted
             as base,
           -- New: under 2 days old with under 30 views (views read 0 until they're
           -- recorded, ticket 20) and not acted on.
           c.created_at > p_now - interval '2 days' and not c.going and not c.saved as fresh,
           (select r.code from (values ('friend', c.friend_pts, 1), ('follow', c.follow_pts, 2),
                                       ('interest', c.interest_pts, 3), ('popular', c.popular_pts, 4),
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
         public.town_feed_place(a.ids, a.kinds, a.hosts, a.scores, a.fresh,
                                (w->>'maxRun')::int, (w->>'repeatHost')::float8, (w->>'newSpot')::int) p
  )
  select e.id, e.title, e.event_date, e.start_time, e.location, e.image_url, e.category,
         c.name, e.source_name, e.end_at, e.all_day, e.created_at,
         (select count(*)::int from public.event_rsvps r where r.event_id = e.id),
         e.going,
         l.recurrence,
         e.leaves_at,
         case when p.moved then 'new'
              else coalesce(e.lift, case when e.days_off <= 0 then 'today' when e.days_off = 1 then 'tomorrow' else 'soon' end)
         end,
         case when e.lift = 'interest' and not p.moved then e.matched[1] end,
         case when public.is_admin() then jsonb_build_object(
           'interest', e.interest_pts, 'friend', e.friend_pts, 'follow', e.follow_pts,
           'popular', e.popular_pts, 'size', e.size_pts, 'sizeStep', e.size,
           'daysAway', round(e.days_away::numeric, 2), 'soon', round(e.soon::numeric, 4),
           'acted', e.acted, 'spacing', p.spacing, 'newSpot', p.moved,
           'total', round((e.base * p.spacing)::numeric, 4),
           'spot', p.spot, 'of', count(*) over ())
         end
  from totals e
  join placed p on p.id = e.id
  left join public.clubs c on c.id = e.club_id
  left join labels l on l.series = e.series
  order by p.spot;
$$;

grant execute on function public.town_feed_place(uuid[], text[], text[], float8[], boolean[], int, float8, int)
  to anon, authenticated;
grant execute on function public.get_town_feed(timestamptz) to anon, authenticated;

comment on function public.get_town_feed(timestamptz) is
  'The Town feed for the caller, in their order (the ticket 09 recipe). Both apps call it; neither re-sorts. BP app docs/plans/town-feed, tickets 05 and 18.';
