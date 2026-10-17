-- One interest can't flood the Town feed (BP app docs/plans/town-feed, ticket 32; Jesse,
-- 2026-10-17). On 2026-10-16 the feed held 30 games among 87 Events, 20 of them in the top 40 and
-- eight in a row: each came from a different school, so spacing by host never caught them.
-- An Event's first interest is now spaced out the way a host is: each further item on the same
-- interest counts x 0.7 (`repeatTopic`, the agent's default; tune in the playground). Lemmy's
-- Scaled sort, tried first, scaled every tagged Event down against untagged City meetings and
-- left a run of nine games, so it was dropped.
-- town_feed_place takes the topics and the weight; the old one is dropped once nothing calls it.
-- get_town_feed is 20261017150000_event_interests.sql line for line but for the Event's `tags`,
-- the weight and the call; the columns it returns are the same, so it is replaced in place.

create or replace function private.town_feed_place(
  ids uuid[], kinds text[], hosts text[], topics text[], scores float8[], fresh boolean[],
  max_run int, repeat_host float8, repeat_topic float8, new_spot int)
returns table (id uuid, spot int, spacing float8, topic_spacing float8, moved boolean)
language plpgsql
immutable
set search_path = public
as $$
declare
  n int := coalesce(array_length(ids, 1), 0);
  taken boolean[] := array_fill(false, array[greatest(n, 1)]);
  seen jsonb := '{}';
  seen_topic jsonb := '{}';
  order_ int[] := '{}';
  factor float8[] := array_fill(1::float8, array[greatest(n, 1)]);
  topic_factor float8[] := array_fill(1::float8, array[greatest(n, 1)]);
  t float8;
  best_t float8;
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
      -- Each further item from a host counts less, and each further one on the same interest
      -- (ticket 32); an item with no interest has no topic to repeat.
      s := power(repeat_host, coalesce((seen ->> hosts[i])::int, 0));
      t := power(repeat_topic, coalesce((seen_topic ->> topics[i])::int, 0));
      -- The run rule only steers the pick; it isn't part of the item's points.
      if best is null or scores[i] * s * t * (case when kinds[i] = run_kind then 1e-6 else 1 end) > best_s then
        best := i;
        best_s := scores[i] * s * t * (case when kinds[i] = run_kind then 1e-6 else 1 end);
        best_f := s;
        best_t := t;
      end if;
    end loop;
    taken[best] := true;
    factor[best] := best_f;
    topic_factor[best] := best_t;
    order_ := order_ || best;
    seen := jsonb_set(seen, array[hosts[best]], to_jsonb(coalesce((seen ->> hosts[best])::int, 0) + 1));
    if topics[best] is not null then
      seen_topic := jsonb_set(seen_topic, array[topics[best]],
                              to_jsonb(coalesce((seen_topic ->> topics[best])::int, 0) + 1));
    end if;
  end loop;

  first_new := (select min(j) from generate_series(1, n) j where fresh[order_[j]]);
  if new_spot > 0 and first_new > new_spot then
    order_ := order_[1:new_spot - 1] || order_[first_new] || order_[new_spot:first_new - 1]
              || order_[first_new + 1:n];
  end if;

  return query
    select ids[order_[j]], j, factor[order_[j]], topic_factor[order_[j]],
           coalesce(new_spot > 0 and first_new > new_spot and j = new_spot, false)
    from generate_series(1, n) j;
end;
$$;

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
  saved boolean,
  cancelled boolean,
  friends_going jsonb,
  place_picture jsonb
)
language sql
stable
security invoker
set search_path = public
as $$
  with weights as (
    -- The playground's starting weights (ticket 09). Changing one is a migration.
    select '{"interest":3,"friend":4,"follow":3,"popular":2,"size":1.5,"soonHalf":7,"newHalf":24,"acted":0.4,"notInterested":0.3,"meeting":0.3,"repeatHost":0.5,"repeatTopic":0.7,"maxRun":3,"newSpot":4}'::jsonb as w
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
             || case when e.cancelled_at is not null then '|off' else '' end as series,
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
      -- Called off: out of the feed, unless someone Hearted it (Jesse, 2026-10-15).
      and (e.cancelled_at is null or private.heart_count(e.id) > 0)
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
           tg.tags,
           (select array_agg(x order by x) from unnest(tg.tags) x where x = any(me.interests)) as matched
    from next_up e, town, me,
         -- Every interest the tagger gave the Event (ticket 33); one it hasn't reached yet has
         -- its writer's one.
         lateral (select case when e.interests_tagged_at is not null then e.interests
                              else array[e.category] end as tags) tg
    where e.nth = 1
      and town.today >= coalesce(e.shows_from, e.event_date - 14)
  ),
  counted as (
    -- Going counted once (every account's, from the private helper), the people who saw it
    -- in the feed, from the summary refreshed every 10 minutes, and the caller's friends Going.
    select s.*,
           private.going_count(s.id) as going_n,
           coalesce(st.viewers, 0) as viewers,
           coalesce(fg.friends, 0) as friends_n,
           coalesce(fg.people, '[]'::jsonb) as friends_people
    from shown s
    left join private.feed_item_stats st on st.item_id = s.id
    -- Friends Going (ticket 28): asked once for every shown Event.
    left join private.friends_going(array(select x.id from shown x)) fg on fg.event_id = s.id
  ),
  scored as (
    select c.*,
           (w->>'interest')::float8 * least(coalesce(array_length(c.matched, 1), 0), 2) as interest_pts,
           -- Friends Going (ticket 28): +4 each, at most two counted, as interests are
           -- (Jesse, 2026-10-16).
           (w->>'friend')::float8 * least(c.friends_n, 2) as friend_pts,
           0::float8 as follow_pts,   -- follows: ticket 27
           -- Popularity per view (ticket 20), the playground's formula: Going per person
           -- who saw it, with a floor of 20 so one early Going can't look huge. Nothing
           -- until someone has seen it in the feed: per view needs a view.
           case when c.viewers > 0
                then (w->>'popular')::float8 * least(c.going_n::float8 / greatest(c.viewers, 20) * 10, 3)
                else 0 end as popular_pts,
           -- Where its rate sits among this read's events someone has seen: 'popular' as
           -- the reason needs the top quarter, popular compared with other events (Jesse,
           -- 2026-10-13). An unseen event has no rate, so it takes no rank.
           case when c.viewers > 0
                then cume_dist() over (partition by c.viewers > 0
                                       order by c.going_n::float8 / greatest(c.viewers, 20))
                else 0 end as rate_rank,
           (w->>'size')::float8 * (c.size - 1) as size_pts,
           power(0.5, c.days_away / (w->>'soonHalf')::float8) as soon,
           case when c.going or c.saved then (w->>'acted')::float8 else 1 end as acted
    from counted c, weights
  ),
  totals as (
    select c.*,
           -- Called off and still here (Hearted): never promoted, so it goes last.
           case when c.cancelled_at is null
                then (1 + c.interest_pts + c.friend_pts + c.follow_pts + c.popular_pts + c.size_pts) * c.soon * c.acted
                else 0 end as base,
           -- New: under 2 days old with under 30 viewers and not acted on.
           c.created_at > p_now - interval '2 days' and c.viewers < 30 and not c.going and not c.saved
             and c.cancelled_at is null as fresh,
           -- 'popular' as the reason needs at least 3 people Going and the top quarter by
           -- Going per viewer (Jesse, 2026-10-13); its points count either way.
           (select r.code from (values ('friend', c.friend_pts, 1), ('follow', c.follow_pts, 2),
                                       ('interest', c.interest_pts, 3),
                                       ('popular', case when c.going_n >= 3 and c.rate_rank > 0.75
                                                        then c.popular_pts else 0 end, 4),
                                       ('size', c.size_pts, 5)) r(code, pts, ord)
            where r.pts >= 1 and c.cancelled_at is null
            order by r.pts desc, r.ord limit 1) as lift
    from scored c
  ),
  placed as (
    select p.*
    from (select array_agg(t.id order by t.sort_at, t.title, t.id) as ids,
                 array_agg('event'::text order by t.sort_at, t.title, t.id) as kinds,
                 array_agg(t.host order by t.sort_at, t.title, t.id) as hosts,
                 -- Its first interest, spaced out like a host (ticket 32).
                 array_agg(t.tags[1] order by t.sort_at, t.title, t.id) as topics,
                 array_agg(t.base order by t.sort_at, t.title, t.id) as scores,
                 array_agg(t.fresh order by t.sort_at, t.title, t.id) as fresh
          from totals t) a,
         weights,
         private.town_feed_place(a.ids, a.kinds, a.hosts, a.topics, a.scores, a.fresh,
                                (w->>'maxRun')::int, (w->>'repeatHost')::float8, (w->>'repeatTopic')::float8,
                                (w->>'newSpot')::int) p
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
         case when p.moved then null
              when e.lift = 'interest' then e.matched[1]
              when e.lift = 'friend' then e.friends_people->0->>'name' end,
         case when public.is_admin() then jsonb_build_object(
           'interest', e.interest_pts, 'friend', e.friend_pts, 'follow', e.follow_pts,
           'popular', e.popular_pts, 'viewers', e.viewers, 'size', e.size_pts, 'sizeStep', e.size,
           'daysAway', round(e.days_away::numeric, 2), 'soon', round(e.soon::numeric, 4),
           'acted', e.acted, 'spacing', p.spacing, 'topicSpacing', round(p.topic_spacing::numeric, 4),
           'newSpot', p.moved,
           'total', round((e.base * p.spacing * p.topic_spacing)::numeric, 4),
           'spot', p.spot, 'of', count(*) over ())
         end,
         private.heart_count(e.id),
         exists (select 1 from public.event_likes h where h.event_id = e.id and h.user_id = auth.uid()),
         e.saved,
         e.cancelled_at is not null,
         -- Up to three friends Going, newest Going first: first name and photo (ticket 28).
         e.friends_people,
         public.place_picture(e.place_entry_id)
  from totals e
  join placed p on p.id = e.id
  left join public.clubs c on c.id = e.club_id
  left join labels l on l.series = e.series
  order by p.spot;
$$;

grant execute on function public.get_town_feed(timestamptz) to anon, authenticated;

revoke execute on function private.town_feed_place(uuid[], text[], text[], text[], float8[], boolean[], int, float8, float8, int)
  from public;
grant execute on function private.town_feed_place(uuid[], text[], text[], text[], float8[], boolean[], int, float8, float8, int)
  to anon, authenticated;

drop function if exists private.town_feed_place(uuid[], text[], text[], float8[], boolean[], int, float8, int);
