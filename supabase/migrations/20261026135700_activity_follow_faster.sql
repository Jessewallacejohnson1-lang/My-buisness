-- Followed activities (BP app school-activities 03), review: the follow match ran for every Event in the
-- feed's window, times every activity followed (a whole school is about 30), which tripled a signed-in
-- read (live, 2026-10-26: 0.45 s signed out, 1.3 s following Apollo). An Event naming no school now skips it.
-- 20261026132204_activity_follow_lift.sql's get_town_feed line for line but for that.

create or replace function public.get_town_feed(p_now timestamptz default now(), p_news boolean default false)
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
  game jsonb,
  what text,
  kind text,
  source_url text,
  host_picture jsonb
)
language sql
stable
security invoker
set search_path = public
as $$
  with weights as (
    -- The playground's starting weights (ticket 09). Changing one is a migration.
    select '{"interest":3,"friend":4,"follow":3,"popular":2,"size":1.5,"draw":1.5,"tapped":2,"soonHalf":7,"newHalf":24,"acted":0.4,"notInterested":0.3,"meeting":0.3,"repeatHost":0.5,"repeatTopic":0.7,"maxRun":3,"newSpot":4,"news":0.5}'::jsonb as w
  ),
  town as (
    select 'America/Chicago'::text as zone,
           (p_now at time zone 'America/Chicago')::date as today
  ),
  me as (
    -- Under 18 (ticket 19): from the caller's birthday; signed out or no birthday counts as grown.
    select coalesce(p.interests, '{}'::text[]) as interests,
           p.birthday is null or p.birthday <= (p_now at time zone 'America/Chicago')::date - interval '18 years'
             as adult
    from (select 1) one
    left join public.town_profiles p on p.user_id = auth.uid()
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
  -- What the caller said Not interested to (ticket 21): its series and host as real_events keys them,
  -- its interests as shown reads them, and when.
  hidden as (
    select lower(btrim(e.title)) || '|' || coalesce(e.club_id::text, e.source_name, e.submitted_by::text, '') as series,
           coalesce(e.club_id::text, e.source_name, e.submitted_by::text, '') as host,
           case when e.interests_tagged_at is not null then e.interests else array[e.category] end as tags,
           n.at
    from private.my_not_interested() n
    join public.club_events e on e.id = n.item_id
  ),
  -- Hosts the caller muted (ticket 21).
  muted as (
    select m.host from public.feed_mutes m where m.user_id = auth.uid()
  ),
  -- What the caller follows of the schools (school-activities 03): each activity starred, named as
  -- "Cathedral Volleyball (girls)", then every activity of a whole school followed, named by the school.
  -- Read once here, so an Event is matched against a short list.
  my_activities as (
    select a, t.short_name || ' ' || a.name as label, 1 as ord
    from public.town_follows f
    join public.team_activities a on a.id = f.target_id
    join public.teams t on t.id = a.team_id
    where f.follower_id = auth.uid() and f.target_type = 'activity'
    union all
    select a, t.short_name, 2
    from public.town_follows f
    join public.teams t on t.uuid = f.target_id
    join public.team_activities a on a.team_id = t.id
    where f.follower_id = auth.uid() and f.target_type = 'team'
  ),
  my_schools as (
    select t.id, t.short_name as label
    from public.town_follows f
    join public.teams t on t.uuid = f.target_id
    where f.follower_id = auth.uid() and f.target_type = 'team'
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
           end as start_minutes,
           fl.followed
    from public.club_events e
    -- The activity or school you follow that this Event is of, by name; null when none.
    -- Only an Event naming a school can be one's: the rest skip the activity match.
    cross join lateral (select case when e.team_ids is not null or e.activity_team is not null then coalesce(
      (select m.label from my_activities m where public.activity_has_event(m.a, e) order by m.ord limit 1),
      (select s.label from my_schools s where s.id = any(e.team_ids) or s.id = e.activity_team limit 1)) end as followed) fl
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
      -- Followers only (a JV game, an away game, a banquet): only for those following its activity
      -- or its school (Jesse, 2026-10-25).
      and (not e.followers_only or fl.followed is not null)
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
             -- A game whose final is in stays a day past its end (game-card 02); one still being played
             -- (a live score and no final) stays two more hours, so a long game keeps its card (game-card 03).
             + case when r.final_score is not null then interval '1 day'
                    when r.live_score is not null then interval '2 hours' else interval '0' end as leaves_at
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
      -- Not interested keeps out the item and every week of its series; Mute its host (ticket 21).
      and not exists (select 1 from muted m where m.host = e.host)
      and not exists (select 1 from hidden h where h.series = lower(btrim(e.title)) || '|' || e.host)
      -- Under 18 never sees what its place keeps to 18+ or 21+ (ticket 19).
      and (me.adult or not private.adults_only(e.place_entry_id, e.club_id, e.title || ' ' || coalesce(e.description, '')))
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
           -- An activity or school you follow (school-activities 03); people, places and groups: town-feed 27.
           case when c.followed is not null then (w->>'follow')::float8 else 0 end as follow_pts,
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
           case when c.going or c.saved then (w->>'acted')::float8 else 1 end as acted,
           -- Like something you said Not interested to, by host or main interest (ticket 21): × 0.3 the
           -- day you said it, back to × 1 in a straight line over 90 days; the newest one counts.
           coalesce((select min(1 - (1 - (w->>'notInterested')::float8)
                                  * greatest(0, least(1, 1 - extract(epoch from p_now - h.at) / 86400 / 90)))
                     from hidden h
                     where (h.host <> '' and h.host = c.host) or h.tags[1] = c.tags[1]), 1) as hidden_x
    from counted c, weights
  ),
  totals as (
    select c.*,
           -- Called off and still here (Hearted): never promoted, so it goes last.
           case when c.cancelled_at is null
                then (1 + c.interest_pts + c.friend_pts + c.follow_pts + c.tapped_pts + c.popular_pts + c.size_pts
                      + c.draw_pts)
                     * c.soon * c.acted * c.hidden_x
                else 0 end as base,
           -- New: under 2 days old with under 30 viewers and not acted on.
           c.created_at > p_now - interval '2 days' and c.viewers < 30 and not c.going and not c.saved
             and c.cancelled_at is null as fresh,
           -- 'popular' as the reason needs at least 3 people Going and the top quarter by
           -- Going per viewer (Jesse, 2026-10-13); its points count either way.
           -- Something you follow says so first: you asked for it (school-activities 03).
           case when c.followed is not null and c.cancelled_at is null then 'follow' else
           (select r.code from (values ('friend', c.friend_pts, 1), ('follow', c.follow_pts, 2),
                                       ('tapped', c.tapped_pts, 3), ('interest', c.interest_pts, 4),
                                       ('popular', case when c.going_n >= 3 and c.rate_rank > 0.75
                                                        then c.popular_pts else 0 end, 5),
                                       ('size', c.size_pts, 6)) r(code, pts, ord)
            where r.pts >= 1 and c.cancelled_at is null
            order by r.pts desc, r.ord limit 1) end as lift
    from scored c
  ),
  -- Town news (ticket 35): a place's specials, deals and new things, and town news, published in the
  -- last 7 days, never a 511 road alert, only with a post to open. It leaves after 7 days, or at the end
  -- of the day it's about when that day isn't behind its publish day. Only for an app that asks
  -- (p_news): an older one can't read a row without a date.
  news as (
    select b.id, b.title, b.blurb, b.category, b.source_name, b.source_url, b.published_at, b.place_entry_id,
           least(b.published_at + interval '7 days',
                 case when (b.starts_at at time zone town.zone)::date >= (b.published_at at time zone town.zone)::date
                      then ((b.starts_at at time zone town.zone)::date + 1)::timestamp at time zone town.zone end)
             as leaves_at,
           (select array_agg(x order by x) from unnest(b.interests) x where x = any(me.interests)) as matched
    from public.board_items b, town, me
    where p_news
      and b.status = 'published'
      and b.category in ('business', 'announcement', 'campus', 'school')
      and nullif(btrim(b.source_url), '') is not null
      -- Not from a host you muted (ticket 21): a found Event's host is its place's name, as news's is.
      and not exists (select 1 from muted m where m.host = b.source_name)
      and b.published_at > p_now - interval '7 days' and b.published_at <= p_now
      and (me.adult or not private.adults_only(b.place_entry_id, null, b.title || ' ' || coalesce(b.blurb, '')))
  ),
  news_scored as (
    -- Below the Events (Jesse, 2026-10-22: "really tailored to people that care about those things or
    -- like at the bottom of someone's feed"): one sharing an interest with you counts half an Event
    -- with one shared interest, a second adding nothing, and halves each day; the rest go after every
    -- Event (`tail`).
    select n.*,
           (w->>'news')::float8 * (1 + (w->>'interest')::float8)
             * power(0.5, extract(epoch from p_now - n.published_at) / 3600 / (w->>'newHalf')::float8) as base
    from news n, weights
    where n.leaves_at > p_now
  ),
  pool as (
    select t.id, t.host, t.tags[1] as topic, t.base, t.fresh, t.sort_at, t.title from totals t
    union all
    select n.id, n.source_name, n.matched[1], n.base, false, n.published_at, n.title
    from news_scored n where n.matched is not null
  ),
  placed as (
    select p.*
    from (select array_agg(t.id order by t.sort_at, t.title, t.id) as ids,
                 -- One kind for all: never more than 3 Events in a row would lift a news item above
                 -- where its points put it.
                 array_agg('event'::text order by t.sort_at, t.title, t.id) as kinds,
                 array_agg(t.host order by t.sort_at, t.title, t.id) as hosts,
                 -- Its first interest, spaced out like a host (ticket 32).
                 array_agg(t.topic order by t.sort_at, t.title, t.id) as topics,
                 array_agg(t.base order by t.sort_at, t.title, t.id) as scores,
                 array_agg(t.fresh order by t.sort_at, t.title, t.id) as fresh
          from pool t) a,
         weights,
         private.town_feed_place(a.ids, a.kinds, a.hosts, a.topics, a.scores, a.fresh,
                                (w->>'maxRun')::int, (w->>'repeatHost')::float8, (w->>'repeatTopic')::float8,
                                (w->>'newSpot')::int) p
  ),
  -- News that shares none of your interests, after every Event: newest first, one place's posts
  -- spaced out as hosts are.
  tail as (
    select p.*
    from (select array_agg(n.id order by n.published_at desc, n.id) as ids,
                 array_agg('news'::text order by n.published_at desc, n.id) as kinds,
                 array_agg(n.source_name order by n.published_at desc, n.id) as hosts,
                 array_agg(null::text order by n.published_at desc, n.id) as topics,
                 array_agg(n.base order by n.published_at desc, n.id) as scores,
                 array_agg(false order by n.published_at desc, n.id) as fresh
          from news_scored n where n.matched is null) a,
         weights,
         private.town_feed_place(a.ids, a.kinds, a.hosts, a.topics, a.scores, a.fresh,
                                (w->>'maxRun')::int, (w->>'repeatHost')::float8, (w->>'repeatTopic')::float8, 0) p
  ),
  spots as (
    select p.id, p.spot, p.spacing, p.topic_spacing, p.moved from placed p
    union all
    select t.id, t.spot + (select count(*) from placed)::int, t.spacing, t.topic_spacing, t.moved from tail t
  ),
  feed_rows (id, title, event_date, start_time, location, image_url, category, club_name, source_name, end_at, all_day, created_at, going_count, rsvpd, recurrence, leaves_at, reason, reason_name, score, heart_count, hearted, saved, cancelled, friends_going, place_picture, description, club_id, in_club, game, what, kind, source_url, host_picture, spot) as (
  select e.id, e.title, e.event_date, e.start_time, e.location, e.image_url, e.category,
         c.name, e.source_name, e.end_at, e.all_day, e.created_at,
         e.going_n,
         e.going,
         l.recurrence,
         e.leaves_at,
         -- A game whose final is in says so: a day reason ("Happening today") or a friend Going reads
         -- wrong on a game that's over (game-card 02).
         case when e.final_score is not null then 'final'
              when e.lift = 'follow' then 'follow'
              when p.moved then 'new'
              else coalesce(e.lift, case when e.days_off <= 0 then 'today' when e.days_off = 1 then 'tomorrow' else 'soon' end)
         end,
         case when e.final_score is not null then null
              when e.lift = 'follow' then e.followed
              when p.moved then null
              when e.lift = 'interest' then e.matched[1]
              when e.lift = 'friend' then e.friends_people->0->>'name'
              when e.lift = 'tapped' then coalesce(c.name, e.source_name) end,
         case when public.is_admin() then jsonb_build_object(
           'interest', e.interest_pts, 'friend', e.friend_pts, 'follow', e.follow_pts,
           'popular', e.popular_pts, 'viewers', e.viewers, 'size', e.size_pts, 'sizeStep', e.size,
           'draw', e.draw_pts, 'tapped', e.tapped_pts,
           'daysAway', round(e.days_away::numeric, 2), 'soon', round(e.soon::numeric, 4),
           'acted', e.acted, 'notInterested', round(e.hidden_x::numeric, 4), 'spacing', p.spacing, 'topicSpacing', round(p.topic_spacing::numeric, 4),
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
         -- its final in the same order once it's in (game-card 02), its live score while it's on (game-card 03),
         -- and its scoring plays (game-card 05).
         private.event_game(e.sport, e.team_ids, e.occasion) || jsonb_build_object('final', e.final_score,
                                                                                   'live', e.live_score,
                                                                                   'plays', e.scoring_plays),
         -- What it is, in one to three words (event-card 05).
         e.what,
         'event'::text, null::text,
         -- Who puts it on, as a picture beside its name: the registry place that posted it (found
         -- Events) or the group's own place, its logo first (Jesse, 2026-10-23).
         private.host_picture(e.source_name, c.own_entry_id),
         p.spot
  from totals e
  join spots p on p.id = e.id
  -- The group that posted it, else, for a found Event, the group it was found for.
  left join public.clubs c on c.id = coalesce(e.club_id,
    case when e.submitted_by is null and e.source_name is not null
         then private.event_group(e.source_name, e.place_entry_id, e.title) end)
  left join labels l on l.series = e.series
  union all
  -- A news item's row: the Event columns it has, nulls and zeros for the rest.
  select n.id, n.title, null::date, null::text, null::text, null::text, n.category,
         null::text, n.source_name, null::timestamptz, false, n.published_at,
         0, false, null::text, n.leaves_at,
         case when n.matched is not null then 'interest' end, n.matched[1],
         null::jsonb, 0, false, false, false, '[]'::jsonb,
         -- The place's logo first, as its Search tile and Instagram's avatars show a place; else its
         -- photo (place_picture).
         private.entry_picture(n.place_entry_id),
         n.blurb, null::uuid, false, null::jsonb, null::text,
         'news'::text, n.source_url, null::jsonb, s.spot
  from news_scored n
  join spots s on s.id = n.id
  )
  select r.id, r.title, r.event_date, r.start_time, r.location, r.image_url, r.category, r.club_name,
         r.source_name, r.end_at, r.all_day, r.created_at, r.going_count, r.rsvpd, r.recurrence, r.leaves_at,
         r.reason, r.reason_name, r.score, r.heart_count, r.hearted, r.saved, r.cancelled, r.friends_going,
         r.place_picture, r.description, r.club_id, r.in_club, r.game, r.what, r.kind, r.source_url, r.host_picture
  from feed_rows r
  order by r.spot;
$$;

grant execute on function public.get_town_feed(timestamptz, boolean) to anon, authenticated;
