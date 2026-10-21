-- A game stays on the Town feed three hours after its start when it gives no end, not two: a football
-- game runs about three, and at two its card left mid-game (Jesse at game-card 02's Check-in 2: "yes").
-- private.read_finals counts a game over at the same three hours. get_town_feed is
-- 20261021130000_game_finals_reason.sql and read_finals 20261021120100_game_finals_job.sql line for line
-- but for those hours.

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
  place_picture jsonb,
  description text,
  club_id uuid,
  in_club boolean,
  game jsonb
)
language sql
stable
security invoker
set search_path = public
as $$
  with weights as (
    -- The playground's starting weights (ticket 09). Changing one is a migration.
    select '{"interest":3,"friend":4,"follow":3,"popular":2,"size":1.5,"draw":1.5,"tapped":2,"soonHalf":7,"newHalf":24,"acted":0.4,"notInterested":0.3,"meeting":0.3,"repeatHost":0.5,"repeatTopic":0.7,"maxRun":3,"newSpot":4}'::jsonb as w
  ),
  town as (
    select 'America/Chicago'::text as zone,
           (p_now at time zone 'America/Chicago')::date as today
  ),
  me as (
    select coalesce((select p.interests from public.town_profiles p where p.user_id = auth.uid()),
                    '{}'::text[]) as interests
  ),
  -- The caller's own taps in the 90 days before p_now (ticket 30): Going, Heart or Save, each
  -- Event once, read straight from club_events so an older or called-off Event still counts. Only
  -- a club's or a source's Events, never a neighbour's own posting (the card doesn't show who
  -- posted it), and never routine business (draw 1): a heart on a council meeting lifts nothing.
  taps as (
    select coalesce(e.club_id::text, e.source_name) as host, count(*) as n, array_agg(e.id) as ids
    from (select r.event_id from public.event_rsvps r
          where r.user_id = auth.uid() and r.created_at > p_now - interval '90 days'
          union
          select l.event_id from public.event_likes l
          where l.user_id = auth.uid() and l.created_at > p_now - interval '90 days'
          union
          select s.event_id from public.event_saves s
          where s.user_id = auth.uid() and s.created_at > p_now - interval '90 days') t
    join public.club_events e on e.id = t.event_id
    where coalesce(e.club_id::text, e.source_name) is not null and coalesce(e.draw, 2) > 1
    group by 1
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
             -- A game runs about three hours (football), anything else two (game-card 02).
             (r.event_date + make_interval(mins => r.start_minutes)) at time zone town.zone
               + case when r.team_ids is not null then interval '3 hours' else interval '2 hours' end,
             (r.event_date + 1)::timestamp at time zone town.zone
           )
             -- A game whose final is in stays a day past its end (game-card 02).
             + case when r.final_score is not null then interval '1 day' else interval '0' end as leaves_at
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
           coalesce(fg.people, '[]'::jsonb) as friends_people,
           -- How many of the host's other Events the caller tapped (ticket 30).
           coalesce(tp.n - case when s.id = any(tp.ids) then 1 else 0 end, 0) as tapped_n
    from shown s
    left join taps tp on tp.host = coalesce(s.club_id::text, s.source_name)
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
           -- Hosts you've been into (ticket 30): 2 points for one other Event of its host you
           -- tapped, 3 for two or more; never on routine business (draw 1).
           case when c.tapped_n = 0 or coalesce(c.draw, 2) = 1 then 0
                else (w->>'tapped')::float8 * case when c.tapped_n >= 2 then 1.5 else 1 end end as tapped_pts,
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
           -- How much it draws a town out, the tagger's 1-3 (ticket 34): everyone's starting point,
           -- 0, 1.5 or 3 points; one not rated yet counts as 2.
           (w->>'draw')::float8 * (coalesce(c.draw, 2) - 1) as draw_pts,
           power(0.5, c.days_away / (w->>'soonHalf')::float8) as soon,
           case when c.going or c.saved then (w->>'acted')::float8 else 1 end as acted
    from counted c, weights
  ),
  totals as (
    select c.*,
           -- Called off and still here (Hearted): never promoted, so it goes last.
           case when c.cancelled_at is null
                then (1 + c.interest_pts + c.friend_pts + c.follow_pts + c.tapped_pts + c.popular_pts + c.size_pts
                      + c.draw_pts)
                     * c.soon * c.acted
                else 0 end as base,
           -- New: under 2 days old with under 30 viewers and not acted on.
           c.created_at > p_now - interval '2 days' and c.viewers < 30 and not c.going and not c.saved
             and c.cancelled_at is null as fresh,
           -- 'popular' as the reason needs at least 3 people Going and the top quarter by
           -- Going per viewer (Jesse, 2026-10-13); its points count either way.
           (select r.code from (values ('friend', c.friend_pts, 1), ('follow', c.follow_pts, 2),
                                       ('tapped', c.tapped_pts, 3), ('interest', c.interest_pts, 4),
                                       ('popular', case when c.going_n >= 3 and c.rate_rank > 0.75
                                                        then c.popular_pts else 0 end, 5),
                                       ('size', c.size_pts, 6)) r(code, pts, ord)
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
         -- A game whose final is in says so: a day reason ("Happening today") or a friend Going reads
         -- wrong on a game that's over (game-card 02).
         case when e.final_score is not null then 'final'
              when p.moved then 'new'
              else coalesce(e.lift, case when e.days_off <= 0 then 'today' when e.days_off = 1 then 'tomorrow' else 'soon' end)
         end,
         case when e.final_score is not null or p.moved then null
              when e.lift = 'interest' then e.matched[1]
              when e.lift = 'friend' then e.friends_people->0->>'name'
              when e.lift = 'tapped' then coalesce(c.name, e.source_name) end,
         case when public.is_admin() then jsonb_build_object(
           'interest', e.interest_pts, 'friend', e.friend_pts, 'follow', e.follow_pts,
           'popular', e.popular_pts, 'viewers', e.viewers, 'size', e.size_pts, 'sizeStep', e.size,
           'draw', e.draw_pts, 'tapped', e.tapped_pts,
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
         public.place_picture(e.place_entry_id),
         e.description,
         -- The approved group putting it on, and whether the caller is in it (rsvp-and-groups 07).
         case when c.status = 'approved' then c.id end,
         coalesce(c.status = 'approved' and auth.uid() is not null
           and exists (select 1 from public.club_members m where m.club_id = c.id and m.user_id = auth.uid()), false),
         -- A game between two teams (game-card 01): its sport, special night and both teams, host first,
         -- and its final in the same order once it's in (game-card 02).
         private.event_game(e.sport, e.team_ids, e.occasion) || jsonb_build_object('final', e.final_score)
  from totals e
  join placed p on p.id = e.id
  -- The group that posted it, else, for a found Event, the group it was found for.
  left join public.clubs c on c.id = coalesce(e.club_id,
    case when e.submitted_by is null and e.source_name is not null
         then private.event_group(e.source_name, e.place_entry_id, e.title) end)
  left join labels l on l.series = e.series
  order by p.spot;
$$;

grant execute on function public.get_town_feed(timestamptz) to anon, authenticated;

create or replace function private.read_finals(p_now timestamptz default now())
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  g record;
  v_status int;
  v_body text;
  v_final int[];
  v_url text;
  v_file text;
  v_host text;
  n_league int := 0;
  n_files int := 0;
  n_finals int := 0;
  v_refused boolean := false;
  v_today date := (p_now at time zone 'America/Chicago')::date;
begin
  perform extensions.http_set_curlopt('CURLOPT_TIMEOUT', '20');
  for g in
    select e.id, e.event_date, e.team_ids, e.sport, e.source_name, e.source_uid, e.source_url
    from public.club_events e
    cross join lateral (select regexp_match(lower(btrim(e.start_time)), '^(\d{1,2})(?::(\d{2}))?\s*([ap])\.?m\.?$') as m) t
    where e.team_ids is not null and e.final_score is null and e.cancelled_at is null and e.status = 'approved'
      and e.event_date between v_today - 1 and v_today
      and (e.final_checked_at is null or e.final_checked_at < p_now - interval '55 minutes')
      -- Over: its end, else three hours after its start (as the Town feed keeps a game), else the day's end.
      and p_now > coalesce(e.end_at,
            (e.event_date + make_interval(mins => (t.m[1]::int % 12) * 60 + coalesce(t.m[2], '0')::int
                                                  + case when t.m[3] = 'p' then 720 else 0 end))
              at time zone 'America/Chicago' + interval '3 hours',
            (e.event_date + 1)::timestamp at time zone 'America/Chicago')
    order by e.event_date, e.created_at
  loop
    v_final := null;
    v_url := null;
    if g.source_uid like 'mshsl:%' and g.source_url ~ '/group/\d+/' then
      continue when n_league >= 6 or v_refused;
      v_url := format('https://www.mshsl.org/api/team-data/schedule/%s/varsity/%s?start_date=%s&end_date=%s',
                      (regexp_match(g.source_url, '/group/(\d+)/'))[1], (regexp_match(g.source_uid, '^mshsl:(\d+):'))[1],
                      g.event_date, g.event_date + 1);
      if n_league > 0 then perform pg_sleep(5); end if;
      n_league := n_league + 1;
    else
      -- The file for the school and sport, as SIDEARM names them; another sport waits until its file is seen.
      v_file := case g.source_name || '/' || g.sport
        when 'SJU Athletics/Football' then 'csbsju/football'
        when 'SJU Athletics/Soccer' then 'csbsju/msoc'
        when 'CSB Athletics/Soccer' then 'csb/wsoc'
        when 'CSB Athletics/Volleyball' then 'csb/wvball' end;
      v_host := case g.source_name when 'SJU Athletics' then 'john' when 'CSB Athletics' then 'benedict' end;
      continue when v_file is null or n_files >= 1;
      v_url := format('https://sidearmstats.com/%s/game.json?detail=game', v_file);
      n_files := n_files + 1;
    end if;
    v_status := null;
    begin
      select r.status, r.content into v_status, v_body
      from extensions.http(('GET', v_url,
        array[extensions.http_header('User-Agent', 'BlockPartyBot/1.0 (+https://blockpartystjoe.com)')],
        null, null)::extensions.http_request) r;
      if v_status = 200 then
        v_final := case when g.source_uid like 'mshsl:%'
          then private.league_final(v_body::jsonb, g.source_uid, g.event_date, g.team_ids)
          else private.sidearm_final(v_body::jsonb, g.event_date, v_host) end;
      end if;
    exception when others then
      v_final := null;  -- unreachable or not JSON: tried again in an hour
    end;
    update public.club_events set final_checked_at = p_now, final_score = v_final where id = g.id;
    n_finals := n_finals + (v_final is not null)::int;
    -- The league turning us away ends this run's reads there.
    if g.source_uid like 'mshsl:%' and v_status in (403, 429) then v_refused := true; end if;
  end loop;
  return jsonb_build_object('league_reads', n_league, 'files', n_files, 'finals', n_finals, 'refused', v_refused);
end;
$$;
