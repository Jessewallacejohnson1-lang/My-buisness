-- The Town feed and Daily send the Event card alone, beside only what is their own (BP app codebase-health-2,
-- ticket 03): an Event row's copied columns go, so a new Event field is one change in private.event_cards and
-- shows here with nothing else to edit. The answer was 433 KB with the card beside the copies, against 255 KB
-- before the card (2026-11-02).
--
-- An Event row is now its id, `card` and the feed's own: how its series repeats, when it leaves, why it's there
-- (reason and name), the admin's Score, its hearts, whether you saved it, and its group's Join (club_id,
-- in_club). The columns only Events used (event_date, start_time, club_name, end_at, all_day, going_count, rsvpd,
-- cancelled, friends_going, game, what, host_picture) leave the answer, and so does category, which no app reads.
-- The columns news and posts share (title, location, image_url, source_name, created_at, place_picture,
-- description, source_url) stay theirs and are null on an Event row. Daily's Event of the day sends the same,
-- and reads its day, time, all-day and called-off from the club_events row it already joins, and Going from the
-- card.
--
-- Only builds from iOS main <app sha> on read this (CommunityAPI.townFeedLines): earlier ones need an Event row's
-- title, all_day, created_at, going_count, rsvpd and event_date, and fail the whole answer without them. Apply it
-- once Jesse's phone and every open branch run that build.
--
-- All three are 20261102191018_event_card_feed.sql line for line but for those columns.
--
-- Roll back: re-run 20261102191018_event_card_feed.sql (its drops, creates and grants).

drop function if exists private.town_feed(timestamptz, boolean, uuid[], boolean);

create function private.town_feed(p_now timestamptz, p_news boolean, p_only uuid[] default null,
                                             p_later boolean default false)
returns table (
  id uuid,
  title text,
  location text,
  image_url text,
  source_name text,
  created_at timestamptz,
  recurrence text,
  leaves_at timestamptz,
  reason text,
  reason_name text,
  score jsonb,
  heart_count int,
  hearted boolean,
  saved boolean,
  place_picture jsonb,
  description text,
  club_id uuid,
  in_club boolean,
  kind text,
  source_url text,
  -- A post's neighbour: name, photo and the friends they tagged (town-feed 29); null for the rest.
  poster jsonb,
  -- The Event card (codebase-health-2 02); null for news and posts. An Event's title, place, picture, words and
  -- link are its card's: those columns are news' and posts' only (codebase-health-2 03).
  card jsonb
)
language sql
stable
security invoker
set search_path = public
as $$
  with weights as (
    -- The simple recipe's weights (town-feed 36). Changing one is a migration.
    select '{"yours":3,"interest":3,"new":2,"draw":1.5,"soonHalf":7,"newHalf":24,"acted":0.4,"notInterested":0.3,"repeatHost":0.5,"repeatCampus":0.8,"news":0.5,"meeting":0.3}'::jsonb as w
  ),
  town as (
    select 'America/Chicago'::text as zone,
           (p_now at time zone 'America/Chicago')::date as today
  ),
  -- p_only (feed-load): only these Events and every other Event of their hosts, each host as the spacing
  -- rule keys it (`pool` below: the campus as one, else who puts it on). An Event's points and its
  -- series read only its own host's Events, so these come out exactly as in the whole feed, in the same
  -- order among themselves; only the admin's Score spot and count are the whole feed's. Null: everything.
  only_hosts as (
    select array_agg(distinct case when 'campus' = any(case when e.interests_tagged_at is not null then e.interests
                                                            else array[e.category] end) then 'campus'
                                   else coalesce(e.club_id::text, e.source_name, e.submitted_by::text, '') end) as hosts
    from public.club_events e
    where e.id = any(p_only)
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
  my_taps as (
    select e.id, e.event_date, coalesce(e.club_id::text, e.source_name) as host, e.team_ids, e.sport
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
  ),
  -- A school's or a club's own Events: a game you tapped isn't one of them (town-feed 39).
  taps as (
    select t.host, count(*) as n, array_agg(t.id) as ids
    from my_taps t
    where t.team_ids is null or t.sport is null
    group by 1
  ),
  -- A game's host is its team (town-feed 39): each team in a game you tapped, by its sport ("Girls Swim"
  -- and "Girls Swimming and Diving" are one), and the days of those games. Days, not games: a school lists
  -- its varsity, JV and C games of a day as a row each, and a game between two schools can be on both
  -- their calendars.
  team_taps as materialized (
    select k.team, coalesce(private.sport_gender(t.sport), '') || ' ' || private.sport_base(t.sport) as sport,
           array_agg(distinct t.event_date) as days
    from my_taps t
    cross join unnest(t.team_ids) as k(team)
    where t.sport is not null
    group by 1, 2
  ),
  -- What the caller said Not interested to (ticket 21): its series and host as real_events keys them.
  hidden as (
    select lower(btrim(e.title)) || '|' || coalesce(e.club_id::text, e.source_name, e.submitted_by::text, '') as series,
           coalesce(e.club_id::text, e.source_name, e.submitted_by::text, '') as host,
           n.lowers  -- town-feed 22: false for a report
    from private.my_not_interested() n
    join public.club_events e on e.id = n.item_id
  ),
  -- The caller's last visit (town-feed 36): their newest view at least 30 minutes before p_now, so
  -- the visit they're on doesn't count. None yet (a first open, signed out): New reaches back the last
  -- 24 hours only (town-feed 38, `counted`).
  my_views as materialized (
    select v.item_id from private.my_views() v
  ),
  last_visit as (
    select private.my_last_visit(p_now - interval '30 minutes') as at
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
  -- The rest of what the caller follows (town-feed 37): people (named through the private helper, as
  -- profiles read only their own row), Places, and the Groups they're in, which count as follows.
  my_people as (
    select p.id, p.name from private.my_followed_people() p
  ),
  my_places as (
    select pl.name, pl.entry_id
    from public.town_follows f
    join public.places pl on pl.id = f.target_id
    where f.follower_id = auth.uid() and f.target_type = 'place'
  ),
  my_groups as (
    select c.id, c.name
    from public.club_members m
    join public.clubs c on c.id = m.club_id
    where m.user_id = auth.uid() and c.status = 'approved'
  ),
  -- The Town's pages and the City's boards the caller follows (follows 04, town-feed 27): a page by the
  -- name its Events carry, as `town_page` lists them.
  my_pages as (
    select pg.name, lower(pg.source_name) as source
    from public.town_follows f
    join public.town_pages pg on pg.id = f.target_id
    where f.follower_id = auth.uid() and f.target_type = 'page'
  ),
  my_boards as (
    select b.id, b.name
    from public.town_follows f
    join public.city_boards b on b.id = f.target_id
    where f.follower_id = auth.uid() and f.target_type = 'board'
  ),
  -- Each City's name on its Events: a draw 1 Event of one is a meeting (follows 03).
  cities as (
    select lower(pg.source_name) as source from public.town_pages pg where pg.slug = 'city'
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
           fl.followed as school_followed,
           mt.is_meeting,
           mt.board as meeting_board
    from public.club_events e
    -- The activity or school you follow that this Event is of, by name; null when none.
    -- Only an Event naming a school can be one's: the rest skip the activity match.
    cross join lateral (select case when e.team_ids is not null or e.activity_team is not null then coalesce(
      (select m.label from my_activities m where public.activity_has_event(m.a, e) order by m.ord limit 1),
      (select s.label from my_schools s where s.id = any(e.team_ids) or s.id = e.activity_team limit 1)) end as followed) fl
    cross join lateral (select
      regexp_match(lower(btrim(e.start_time)), '^(\d{1,2})(?::(\d{2}))?\s*([ap])\.?m\.?$') as m12,
      regexp_match(btrim(e.start_time), '^(\d{1,2}):(\d{2})(?::\d{2})?$') as m24
      -- Read once per Event: without offset 0 Postgres pastes both reads into each of the start's
      -- eleven uses, about 0.2 s a feed (2026-10-31).
      offset 0) t
    -- A City meeting, and the board it belongs to (null for one that matches no board).
    cross join lateral (select m.is_meeting, case when m.is_meeting then public.meeting_board(e) end as board
                        from (select coalesce(e.draw = 1, false)
                                     and exists (select 1 from cities c where c.source = lower(e.source_name))
                                     as is_meeting) m) mt
    cross join town
    where e.status = 'approved'
      and e.kind = 'event'
      -- Only the hosts asked for (p_only), first, so nothing else is worked out for the rest.
      and (p_only is null
           or case when 'campus' = any(case when e.interests_tagged_at is not null then e.interests
                                            else array[e.category] end) then 'campus'
                   else coalesce(e.club_id::text, e.source_name, e.submitted_by::text, '') end
              = any((select h.hosts from only_hosts h)::text[]))
      and e.event_date is not null
      and (e.submitted_by is not null or e.source_name is not null)
      -- The window a series' wording reads, plus anything still running.
      and (e.event_date >= town.today - 60 or e.end_at > p_now)
      -- Called off: out of the feed, unless someone Hearted it (Jesse, 2026-10-15).
      and (e.cancelled_at is null or private.heart_count(e.id) > 0)
      -- For college students (onboarding 21): only for those who picked College, or are Going or saved it.
      and (not ('college' = any(e.interests) and e.interests_tagged_at is not null)
           or (select 'college' = any(me.interests) from me)
           or exists (select 1 from public.event_rsvps r where r.event_id = e.id and r.user_id = auth.uid())
           or exists (select 1 from public.event_saves s where s.event_id = e.id and s.user_id = auth.uid()))
      -- Followers only (a JV game, an away game, a banquet): only for those following its activity
      -- or its school (Jesse, 2026-10-25).
      and (not e.followers_only or fl.followed is not null)
      -- A City meeting reaches only those who follow that City or the meeting's board (town-feed 05, 27),
      -- or are Going to it or saved it, which always stay (ticket 05).
      and (not mt.is_meeting
           -- Or picked Town meetings, for one the tagger calls a meeting (onboarding 21): the City's
           -- compost site hours are draw 1 too.
           or ('town_meetings' = any(e.interests) and (select 'town_meetings' = any(me.interests) from me))
           or exists (select 1 from my_pages p where p.source = lower(e.source_name))
           or exists (select 1 from my_boards b where b.id = mt.board)
           or exists (select 1 from public.event_rsvps r where r.event_id = e.id and r.user_id = auth.uid())
           or exists (select 1 from public.event_saves s where s.event_id = e.id and s.user_id = auth.uid()))
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
           tg.tags,
           (select array_agg(x order by x) from unnest(tg.tags) x where x = any(me.interests)) as matched,
           -- The group that posted it, else, for a found Event, the group it was found for: worked out
           -- once here (`shown` is read twice, so kept) for the Group lift and the card's Join.
           coalesce(e.club_id, case when e.submitted_by is null and e.source_name is not null
                                    then private.event_group(e.source_name, e.place_entry_id, e.title) end) as group_id
    from next_up e, town, me,
         -- Every interest the tagger gave the Event (ticket 33); one it hasn't reached yet has
         -- its writer's one.
         lateral (select case when e.interests_tagged_at is not null then e.interests
                              else array[e.category] end as tags) tg
    where e.nth = 1
      -- After the best (town-feed 23): p_later asks for the Events not yet in, past their show-from day.
      and (town.today >= coalesce(e.shows_from, e.event_date - 14)) <> p_later
      -- Not interested keeps out the item and every week of its series; Mute its host (ticket 21).
      and not exists (select 1 from muted m where m.host = e.host)
      and not exists (select 1 from hidden h where h.series = lower(btrim(e.title)) || '|' || e.host)
      -- Under 18 never sees what its place keeps to 18+ or 21+ (ticket 19).
      and (me.adult or not private.adults_only(e.place_entry_id, e.club_id, e.title || ' ' || coalesce(e.description, '')))
    -- Later Events come 20 at a time, soonest first, so the per-Event reads below run for those only.
    order by case when p_later then 1 end, sort_at
    limit case when p_later then 20 end
  ),
  counted as (
    -- The Event card (codebase-health-2 02), and from it Going counted once (every account's) and the
    -- caller's friends Going.
    select s.*,
           ec.card,
           (ec.card->>'going_count')::int as going_n,
           -- New (town-feed 36, 38): in the feed, posted or its show-from day come, since the caller's
           -- last visit or in the last 24 hours, whichever reaches further back (least() skips a missing
           -- last visit), and not yet seen by them. Signed out, a found Event has no poster and no caller:
           -- still New.
           coalesce(greatest(s.created_at, coalesce(s.shows_from, s.event_date - 14)::timestamp at time zone town.zone) > least(lv.at, p_now - interval '24 hours')
                    and s.cancelled_at is null and not s.going and not s.saved
                    and coalesce(s.submitted_by <> auth.uid(), true)
                    and not exists (select 1 from my_views v where v.item_id = s.id), false) as is_new,
           coalesce(jsonb_array_length(ec.card->'friends_going'), 0) as friends_n,
           coalesce(ec.card->'friends_going', '[]'::jsonb) as friends_people,
           -- How many of the host's other Events the caller tapped (ticket 30). A game counts the other
           -- days the caller tapped a game of one of its teams in its sport, and only from two: one
           -- game can't say which side you're on, your own team is in each one you tap (town-feed 39).
           coalesce(case when s.team_ids is null or s.sport is null
                         then tp.n - case when s.id = any(tp.ids) then 1 else 0 end
                         when tt.days >= 2 then tt.days end, 0) as tapped_n,
           -- The team, as "Saint John's Soccer"; no teams row leaves the host's name.
           tt.name as tapped_team,
           -- What the caller follows that this Event is of, by name: an activity or school first, then
           -- a meeting's board, the neighbour who posted it, the Place it's at, a page (the City,
           -- Joetown), a Group they're in (town-feed 37, 27).
           coalesce(s.school_followed, fw.name) as followed
    from shown s
    left join taps tp on tp.host = coalesce(s.club_id::text, s.source_name)
    -- The game's team you've tapped on the most other days, its host team first on a tie (town-feed 39).
    left join lateral (
      select cardinality(array_remove(x.days, s.event_date)) as days, tm.short_name || ' ' || s.sport as name
      from team_taps x
      left join public.teams tm on tm.id = x.team
      where x.team = any(s.team_ids)
        and x.sport = coalesce(private.sport_gender(s.sport), '') || ' ' || private.sport_base(s.sport)
      order by 1 desc, array_position(s.team_ids, x.team)
      limit 1) tt on s.sport is not null
    left join lateral (
      select x.name from (
        -- A meeting's board first (town-feed 27).
        select b.name, 0 as ord from my_boards b where b.id = s.meeting_board
        union all
        -- Only a neighbour's own posting names them: a Group's Event never says who posted it.
        select p.name, 1 from my_people p where p.id = s.submitted_by and s.club_id is null
        union all
        select pl.name, 2 from my_places pl where pl.entry_id = s.place_entry_id
        union all
        -- A page by the name its Events carry: the City, Joetown (town-feed 27).
        select pg.name, 3 from my_pages pg where pg.source = lower(s.source_name)
        union all
        select g.name, 4 from my_groups g where g.id = s.group_id
      ) x
      order by x.ord, x.name limit 1) fw
      -- Never your own posting, as New never is.
      on s.school_followed is null and s.submitted_by is distinct from auth.uid()
    cross join last_visit lv
    cross join town
    -- The Event card, friends Going (ticket 28) with it: asked once for every shown Event.
    left join private.event_cards(array(select x.id from shown x)) ec on ec.id = s.id
  ),
  scored as (
    select c.*,
           (w->>'interest')::float8 * least(coalesce(array_length(c.matched, 1), 0), 2) as interest_pts,
           -- Yours (town-feed 36): a friend Going (ticket 28), something you follow (school-activities 03,
           -- town-feed 37), or a host you've been into (ticket 30), never routine business
           -- (draw 1). Counts once, whichever it is.
           case when c.friends_n > 0 or c.followed is not null or (c.tapped_n > 0 and coalesce(c.draw, 2) <> 1)
                then (w->>'yours')::float8 else 0 end as yours_pts,
           case when c.is_new then (w->>'new')::float8 else 0 end as new_pts,
           -- How much it draws a town out, the tagger's 1-3 (ticket 34): everyone's starting point,
           -- 0, 1.5 or 3 points; one not rated yet counts as 2.
           (w->>'draw')::float8 * (coalesce(c.draw, 2) - 1) as draw_pts,
           power(0.5, c.days_away / (w->>'soonHalf')::float8) as soon,
           case when c.going or c.saved then (w->>'acted')::float8 else 1 end as acted,
           -- A City meeting, for those who follow its City or board, sits lower (town-feed 27).
           case when c.is_meeting then (w->>'meeting')::float8 else 1 end as meeting_x,
           -- A host you said Not interested to (ticket 21): × 0.3 for its other Events, with no fade
           -- (town-feed 36). A report hides its item only and lowers nothing (town-feed 22).
           case when exists (select 1 from hidden h where h.lowers and h.host <> '' and h.host = c.host)
                then (w->>'notInterested')::float8 else 1 end as hidden_x
    from counted c, weights
  ),
  totals as (
    select c.*,
           -- Called off and still here (Hearted): never promoted, so it goes last.
           case when c.cancelled_at is null
                then (1 + c.yours_pts + c.interest_pts + c.new_pts + c.draw_pts) * c.soon * c.acted * c.hidden_x * c.meeting_x
                else 0 end as base,
           -- Which pool it is in, for the Score line: yours or discovery; your own Going and saves,
           -- and a called-off one, in neither.
           case when c.going or c.saved or c.cancelled_at is not null then null
                else c.yours_pts > 0 end as yours,
           -- The reason: something you follow says so first (school-activities 03), then a friend
           -- Going, a host you've been into, New, an interest.
           case when c.cancelled_at is not null then null
                when c.followed is not null then 'follow'
                when c.friends_n > 0 then 'friend'
                when c.yours_pts > 0 then 'tapped'
                when c.is_new then 'new'
                when c.interest_pts > 0 then 'interest' end as lift
    from scored c
  ),
  -- Town news (ticket 35): a place's specials, deals and new things, and town news, published in the
  -- last 7 days, road work and closures too, only with a post to open. It leaves after 7 days, or at the end
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
    where p_news and not p_later
      and b.status = 'published'
      and b.category in ('business', 'announcement', 'campus', 'school', 'road')
      and nullif(btrim(b.source_url), '') is not null
      -- Not from a host you muted (ticket 21): a found Event's host is its place's name, as news's is.
      and not exists (select 1 from muted m where m.host = b.source_name)
      -- Nor one you said Not interested to (news-menu).
      and not exists (select 1 from public.news_hides h where h.user_id = auth.uid() and h.item_id = b.id)
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
  -- A neighbour's post (town-feed 29, BP app references/post-screen): their own words, maybe a photo and a
  -- Place, from the last 7 days, once the instant check said yes. Only for an app that asks (p_news), as
  -- news: an older app can't read a row without a date. A Friends-only post reaches only the poster and
  -- their friends: the read rule on club_events keeps it from everyone else, here too (security invoker).
  posts as (
    select e.id, e.title, e.location, e.image_url, e.image_aspect, e.friends_only, e.created_at, e.submitted_by, e.tagged,
           e.submitted_by = auth.uid() as mine
    from public.club_events e
    where p_news and not p_later
      and e.kind = 'post' and e.status = 'approved'
      and e.created_at > p_now - interval '7 days' and e.created_at <= p_now
      -- Yours, or a real, named neighbour's, neither of you blocking the other.
      and private.shows_poster(e.submitted_by)
      and not exists (select 1 from muted m where m.host = e.submitted_by::text)
      -- Not interested or a report keeps out that post alone, by its id: photo-only posts share an
      -- empty title, so the series key would hide them all.
      and not exists (select 1 from private.my_not_interested() n where n.item_id = e.id)
  ),
  posts_scored as (
    -- An Event's recipe by age instead of day (town-feed 29): 1, plus Yours for your own post or one from
    -- someone you follow (friends follow each other), plus New, the whole halving every 24 hours.
    select p.*,
           (1 + case when p.mine or exists (select 1 from my_people mp where mp.id = p.submitted_by)
                     then (w->>'yours')::float8 else 0 end
              + case when not p.mine and p.created_at > least(lv.at, p_now - interval '24 hours')
                          and not exists (select 1 from my_views v where v.item_id = p.id)
                     then (w->>'new')::float8 else 0 end)
             * power(0.5, extract(epoch from p_now - p.created_at) / 3600 / (w->>'newHalf')::float8) as base
    from posts p, weights, last_visit lv
  ),
  pool as (
    -- The campus's Events space as one host's (onboarding 21): Campus lifts them, and CSB and SJU's
    -- dozen calendars can't fill the top of the feed between them.
    select t.id, case when 'campus' = any(t.tags) then 'campus' else t.host end, t.base, t.sort_at, t.title, 0 as part
    from totals t
    union all
    select n.id, n.source_name, n.base, n.published_at, n.title, 0
    from news_scored n where n.matched is not null
    union all
    -- News that shares none of your interests, after every Event: newest first (its points halve
    -- each day).
    select n.id, n.source_name, n.base, n.published_at, n.title, 1
    from news_scored n where n.matched is null
    union all
    -- Posts among the Events, their poster as their host, so a second one from the same neighbour
    -- counts half (the spacing rule below).
    select p.id, p.submitted_by::text, p.base, p.created_at, p.title, 0
    from posts_scored p
  ),
  -- The one spacing rule (town-feed 36): each further item from a host counts half. A host's items
  -- are always placed best first, so this is its place among them.
  spaced as (
    select p.*,
           power((select (w->>case when p.host = 'campus' then 'repeatCampus' else 'repeatHost' end)::float8 from weights),
                 row_number() over (partition by p.part, p.host order by p.base desc, p.sort_at, p.title, p.id) - 1)
             as spacing
    from pool p
  ),
  spots as (
    select s.id, s.spacing,
           -- Later Events (town-feed 23) by their start, not their points.
           row_number() over (order by case when p_later then s.sort_at end, s.part, s.base * s.spacing desc, s.sort_at,
                                       s.title, s.id)::int as spot
    from spaced s
  ),
  feed_rows (id, title, location, image_url, source_name, created_at, recurrence, leaves_at, reason, reason_name, score, heart_count, hearted, saved, place_picture, description, club_id, in_club, kind, source_url, poster, card, spot) as (
  -- An Event's title, place, picture, words and link are its card's (codebase-health-2 03).
  select e.id, null::text, null::text, null::text, null::text, null::timestamptz,
         l.recurrence,
         e.leaves_at,
         -- A game whose final is in says so: a day reason ("Happening today") or a friend Going reads
         -- wrong on a game that's over (game-card 02).
         case when e.final_score is not null then 'final'
              when e.lift = 'follow' then 'follow'
              else coalesce(e.lift, case when e.days_off <= 0 then 'today' when e.days_off = 1 then 'tomorrow' else 'soon' end)
         end,
         case when e.final_score is not null then null
              when e.lift = 'follow' then e.followed
              when e.lift = 'interest' then e.matched[1]
              when e.lift = 'friend' then e.friends_people->0->>'name'
              when e.lift = 'tapped' then coalesce(e.tapped_team, c.name, e.source_name) end,
         -- The Score line (ticket 18): the keys the shipped app reads stay, the dropped parts at 0.
         case when public.is_admin() then jsonb_build_object(
           'interest', e.interest_pts, 'yours', e.yours_pts, 'new', e.new_pts,
           -- Yours goes to the reason the card names: what you follow, then a friend Going.
           'friend', case when e.followed is null and e.friends_n > 0 then e.yours_pts else 0 end,
           'follow', case when e.followed is not null then e.yours_pts else 0 end,
           'tapped', case when e.friends_n = 0 and e.followed is null then e.yours_pts else 0 end,
           'popular', 0, 'size', 0, 'sizeStep', 1, 'draw', e.draw_pts,
           'daysAway', round(e.days_away::numeric, 2), 'soon', round(e.soon::numeric, 4),
           'acted', e.acted, 'notInterested', e.hidden_x, 'spacing', p.spacing,
           'newSpot', e.is_new, 'pool', case when e.yours then 'yours' when not e.yours then 'discovery' end,
           'total', round((e.base * p.spacing)::numeric, 4),
           'spot', p.spot, 'of', count(*) over ())
         end,
         private.heart_count(e.id),
         exists (select 1 from public.event_likes h where h.event_id = e.id and h.user_id = auth.uid()),
         e.saved,
         null::jsonb, null::text,
         -- The approved group putting it on, and whether the caller is in it (rsvp-and-groups 07).
         case when c.status = 'approved' then c.id end,
         coalesce(c.status = 'approved' and auth.uid() is not null
           and exists (select 1 from public.club_members m where m.club_id = c.id and m.user_id = auth.uid()), false),
         'event'::text, null::text,
         null::jsonb,
         -- The Event card (codebase-health-2 02): its game, host picture, friends Going, link and the rest.
         e.card,
         p.spot
  from totals e
  join spots p on p.id = e.id
  -- The group that posted it, else, for a found Event, the group it was found for.
  left join public.clubs c on c.id = e.group_id
  left join labels l on l.series = e.series
  union all
  -- A news item's row: its own columns, nulls and zeros for the rest.
  select n.id, n.title, null::text, null::text, n.source_name, n.published_at,
         null::text, n.leaves_at,
         case when n.matched is not null then 'interest' end, n.matched[1],
         null::jsonb, 0, false, false,
         -- The place's logo first, as its Search tile and Instagram's avatars show a place; else its
         -- photo (place_picture).
         private.entry_picture(n.place_entry_id),
         n.blurb, null::uuid, false,
         'news'::text, n.source_url, null::jsonb, null::jsonb, s.spot
  from news_scored n
  join spots s on s.id = n.id
  union all
  -- A post's row (town-feed 29): its words as the title, its Place and photo, its hearts, and who
  -- posted it; nulls and zeros for the rest.
  select p.id, p.title, p.location, p.image_url, null::text, p.created_at,
         null::text, p.created_at + interval '7 days',
         null::text, null::text, null::jsonb,
         private.heart_count(p.id),
         exists (select 1 from public.event_likes h where h.event_id = p.id and h.user_id = auth.uid()),
         false, null::jsonb,
         null::text, null::uuid, false,
         'post'::text, null::text,
         -- and the post's own: its photo's shape, which sets the card's before the photo loads, and whether
         -- only friends see it, which its card says.
         private.post_poster(p.submitted_by, p.tagged)
           || jsonb_strip_nulls(jsonb_build_object('aspect', p.image_aspect, 'friends_only', p.friends_only)),
         null::jsonb,
         s.spot
  from posts_scored p
  join spots s on s.id = p.id
  )
  select r.id, r.title, r.location, r.image_url, r.source_name, r.created_at, r.recurrence, r.leaves_at,
         r.reason, r.reason_name, r.score, r.heart_count, r.hearted, r.saved, r.place_picture, r.description,
         r.club_id, r.in_club, r.kind, r.source_url, r.poster, r.card
  from feed_rows r
  order by r.spot;
$$;
revoke execute on function private.town_feed(timestamptz, boolean, uuid[], boolean) from public;
grant execute on function private.town_feed(timestamptz, boolean, uuid[], boolean) to anon, authenticated;

-- The Town feed, as every app reads it: the body is private.town_feed's.
drop function if exists public.get_town_feed(timestamptz, boolean, boolean);

create function public.get_town_feed(p_now timestamptz default now(), p_news boolean default false,
                                      p_later boolean default false)
returns table (
  id uuid,
  title text,
  location text,
  image_url text,
  source_name text,
  created_at timestamptz,
  recurrence text,
  leaves_at timestamptz,
  reason text,
  reason_name text,
  score jsonb,
  heart_count int,
  hearted boolean,
  saved boolean,
  place_picture jsonb,
  description text,
  club_id uuid,
  in_club boolean,
  kind text,
  source_url text,
  -- A post's neighbour: name, photo and the friends they tagged (town-feed 29); null for the rest.
  poster jsonb,
  -- The Event card (codebase-health-2 02); null for news and posts. An Event's title, place, picture, words and
  -- link are its card's: those columns are news' and posts' only (codebase-health-2 03).
  card jsonb
)
language sql
stable
security invoker
set search_path = public
as $$
  select * from private.town_feed(p_now, p_news, null, p_later);
$$;
grant execute on function public.get_town_feed(timestamptz, boolean, boolean) to anon, authenticated;

-- Event of the day reads only the slice of the feed it needs (above).
drop function if exists public.get_event_of_the_day(timestamptz);

create function public.get_event_of_the_day(p_now timestamptz default now())
returns table (
  id uuid,
  recurrence text,
  leaves_at timestamptz,
  reason text,
  reason_name text,
  score jsonb,
  heart_count int,
  hearted boolean,
  saved boolean,
  club_id uuid,
  in_club boolean,
  -- The Event card (codebase-health-2 02), alone with the feed's own (03).
  card jsonb
)
language sql
stable
security invoker
set search_path = public
as $$
  with town as (
    select 'st-joseph-mn'::text as town, (p_now at time zone 'America/Chicago')::date as today
  ),
  written as (
    select s.event_id, s.rank from public.daily_standouts s, town
    where s.town = town.town and s.day = town.today
  ),
  -- What it reads of the Town feed (feed-load): the morning's picks, else (none written) every Event
  -- that day, each with the rest of its host's Events, which is all the feed's order among them reads.
  -- The admin's Score line carries the whole feed's spot and count, so the admin reads it all.
  asked as (
    select case when public.is_admin() then null
                when exists (select 1 from written) then array(select w.event_id from written w)
                else array(select e.id from public.club_events e, town where e.event_date = town.today) end as ids
  ),
  -- Today's Events as the caller's Town feed has them, in its order: on now or still to come
  -- (the feed lets one go at its leaves_at), not called off.
  feed as (
    select f.*,
           -- Its interests as the feed matches them: the tagger's, else its writer's one.
           case when e.interests_tagged_at is not null then e.interests else array[e.category] end as tags,
           coalesce(e.draw, 2) as draw,
           -- The hour it starts, read as the feed reads "7 PM", "7:30 pm", "noon", "19:00": the
           -- same patterns as private.town_feed's start_minutes; change both together.
           case
             when e.all_day then null
             when lower(btrim(e.start_time)) = 'noon' then 12
             when m12 is not null and m12[1]::int between 1 and 12 then m12[1]::int % 12 + case when m12[3] = 'p' then 12 else 0 end
             when m24 is not null and m24[1]::int < 24 then m24[1]::int
           end as hour
    from private.town_feed(p_now, false, (select a.ids from asked a)) with ordinality f
    join public.club_events e on e.id = f.id
    cross join town
    cross join lateral (select
      regexp_match(lower(btrim(e.start_time)), '^(\d{1,2})(?::(\d{2}))?\s*([ap])\.?m\.?$') as m12,
      regexp_match(btrim(e.start_time), '^(\d{1,2}):(\d{2})(?::\d{2})?$') as m24) t
    -- Its day, time and called-off are its own row's; the feed's Event rows send them only in the card (03).
    where f.kind = 'event' and e.event_date = town.today and e.cancelled_at is null
      -- Never one only its followers see (school-activities 03).
      and not e.followers_only
      -- Standing things that repeat (weekly trivia) never go here, picked or not (daily-tab 14).
      and f.recurrence is null
  ),
  parts as (
    -- Morning before noon (all day or untimed counts as morning), afternoon to 5 PM, evening.
    select f.*, case when f.hour is null or f.hour < 12 then 1 when f.hour < 17 then 2 else 3 end as part
    from feed f
  ),
  me as (
    select coalesce((select p.interests from public.town_profiles p where p.user_id = auth.uid()),
                    '{}'::text[]) as interests
  ),
  standouts as (
    select p.*, w.rank,
           cardinality(array(select unnest(p.tags) intersect select unnest(me.interests))) as fit
    from parts p
    join written w on w.event_id = p.id
    cross join me
  ),
  -- Each part's standout sharing the most of your interests, else its top-ranked one. Going
  -- doesn't move it: the pick reads interests and rank only.
  mine as (
    select distinct on (s.part) s.* from standouts s order by s.part, s.fit desc, s.rank
  ),
  -- The job wrote nothing today: the feed's top Event, never routine business (draw 1). One
  -- you're Going to comes first, since the feed lowers an Event you acted on and Going would
  -- otherwise hand its spot to the next.
  fallback as (
    select p.* from parts p
    where p.draw > 1 and not exists (select 1 from written)
    order by coalesce((p.card->>'going')::boolean, false) desc, p.ordinality
    limit 1
  ),
  picked as (
    select m.id, m.part, m.ordinality from mine m
    union all
    select f.id, f.part, f.ordinality from fallback f
  )
  select f.id, f.recurrence, f.leaves_at, f.reason, f.reason_name, f.score, f.heart_count, f.hearted, f.saved,
         f.club_id, f.in_club, f.card
  from picked k
  join feed f on f.id = k.id
  order by k.part, k.ordinality;
$$;
grant execute on function public.get_event_of_the_day(timestamptz) to anon, authenticated;
