-- Events for women or men, and a host's Filter (BP app docs/plans/town-feed/issues/52-events-for-women-or-men.md).
-- Jesse, 2026-11-09: "male and female will mainly be in algorithm seeing which genders go. also when people create
-- events they can put it in ... as an option", then yes to the Check-in 1 page (references/gender-lift): a ratio
-- against the town's mix with two pretend Goers, a host's Filter (Gender, Age range), no words on the card.
--
-- 1. public.club_events.for_gender: 'female' or 'male', onboarding's answers; null is everyone. Set by a neighbour's
--    Filter, the morning watch when a page says so (never a game, a kids' group or a shop's sale), and part 4.
-- 2. private.gender_lean(ids): for the caller, how much each Event is for their gender, 0 to 1. A mark for it is 1,
--    a mark for the other 0. Else the Going crowd: once 3 Goers have answered, s = (theirs + 2b) / (answered + 2)
--    against b, the town's share of the caller's gender (one pretend neighbour of each), lean = (s - b) / (1 - b),
--    never below 0. It reads only the caller's own answer and counts, so nobody's gender leaves it.
-- 3. public.apply_judged (20261109035346_age_mark.sql's, copied whole) lands a judged Event's `gender`, and a
--    re-read with none keeps it.
-- 4. The one upcoming Event whose own words say it is for women (Women in Religion, CSB SJU, read 2026-11-09).
-- 5. The Town feed (supabase/town_feed.sql): gender_lean × an interest's points (3), never a reason on the card; a
--    host's own 18+ or 21+ keeps the Event from under-18s as those words do.
--
-- Roll back: re-run 20261109035346_age_mark.sql's apply_judged and 20261108204035_news_heart.sql's Town feed, then
-- `drop function private.gender_lean(uuid[]); alter table public.club_events drop column for_gender`.

-- 1. The mark.
alter table public.club_events add column for_gender text
  constraint club_events_for_gender check (for_gender in ('female', 'male'));
comment on column public.club_events.for_gender is
  'Who it''s for by gender, as its host or its page says: ''female'' or ''male''; null is everyone (town-feed 52).';

-- 2. How much each Event is for the caller's gender.
create function private.gender_lean(p_events uuid[])
returns table (event_id uuid, lean float8)
language sql
stable
security definer
set search_path = ''
as $$
  with me as (
    select p.gender from public.town_profiles p where p.user_id = auth.uid() and p.gender is not null
  ),
  town as (
    select (count(*) filter (where p.gender = me.gender) + 1)::float8 / (count(*) + 2) as b
    from public.town_profiles p cross join me
    where p.gender is not null
  ),
  crowd as (
    select r.event_id, count(*) filter (where p.gender = me.gender) as mine, count(*) as answered
    from public.event_rsvps r
    join public.town_profiles p on p.user_id = r.user_id and p.gender is not null
    cross join me
    where r.event_id = any (p_events)
    group by r.event_id
  )
  select e.id,
         case when e.for_gender is not null then case when e.for_gender = me.gender then 1 else 0 end
              when c.answered >= 3 then greatest(0, ((c.mine + 2 * t.b) / (c.answered + 2) - t.b) / (1 - t.b))
              else 0 end::float8
  from public.club_events e
  cross join me
  cross join town t
  left join crowd c on c.event_id = e.id
  where e.id = any (p_events)
$$;
revoke all on function private.gender_lean(uuid[]) from public;
grant execute on function private.gender_lean(uuid[]) to anon, authenticated;

-- 3. The writer.
create or replace function public.apply_judged(p_events jsonb, p_mentions jsonb, p_upgrades jsonb, p_news jsonb,
                                    p_cancelled jsonb default '[]', p_restored jsonb default '[]')
returns jsonb
language plpgsql
set search_path = ''
as $$
declare
  n_events int; n_mentions int; n_upgrades int; n_news int; n_cancelled int; n_restored int;
  events_added jsonb; news_added jsonb;
begin
  -- 0. Every team a game names (game-card 01), so its card has both before a logo is found.
  insert into public.teams (id, name, short_name)
  select distinct t.id, t.name, coalesce(t.short, t.name)
  from jsonb_to_recordset(p_events) as x(team_ids text[], team_names text[], team_shorts text[])
  cross join lateral unnest(x.team_ids, x.team_names, x.team_shorts) as t(id, name, short)
  where t.id is not null and t.name is not null
  on conflict (id) do nothing;

  -- 1. New found events, and re-reads of ones already listed (same source and uid). Added are the ones
  --    not there before: the statement reads the table as it was before its own insert.
  with given as (
    select a.n, x.*
    from jsonb_array_elements(p_events) with ordinality as a(item, n)
    cross join lateral jsonb_to_record(a.item) as x(status text, title text, event_date date,
      start_time text, end_at timestamptz, all_day boolean, location text, description text,
      source_name text, source_url text, source_uid text, category text, shows_from date,
      place_entry_id text, sport text, team_ids text[], occasion text,
      followers_only boolean, activity_team text, activity_name text, price text, ages text, gender text)
  ), written as (
    insert into public.club_events (status, kind, title, event_date, start_time, end_at, all_day,
      location, description, source_name, source_url, source_uid, category, shows_from, place_entry_id,
      sport, team_ids, occasion, followers_only, activity_team, activity_name, price, ages, for_gender)
    select x.status, 'event', x.title, x.event_date, x.start_time, x.end_at, x.all_day, x.location,
      x.description, x.source_name, x.source_url, x.source_uid, x.category, x.shows_from, x.place_entry_id,
      x.sport, x.team_ids, x.occasion, coalesce(x.followers_only, false), x.activity_team, x.activity_name,
      nullif(x.price, ''), nullif(x.ages, ''), nullif(x.gender, '')
    from given as x
    on conflict on constraint club_events_source_uid_key do update set
      title = excluded.title, event_date = excluded.event_date, start_time = excluded.start_time,
      end_at = excluded.end_at, all_day = excluded.all_day,
      location = coalesce(nullif(excluded.location, ''), club_events.location),
      -- A fuller listing fills a thin About, but never one the describe step or the cleaning wrote (about_written_at):
      -- that one says only what it is and what to expect, so it is shorter on purpose (inside-cards 14).
      description = case when club_events.about_written_at is null
          and length(coalesce(excluded.description, '')) >= length(coalesce(club_events.description, ''))
        then excluded.description else club_events.description end,
      -- What it costs, as words: a re-read with none keeps the one it had (inside-cards 14).
      price = coalesce(nullif(excluded.price, ''), club_events.price),
      -- Who it's for by age: the same, a re-read that doesn't say keeps it (inside-cards 30).
      ages = coalesce(nullif(excluded.ages, ''), club_events.ages),
      -- Who it's for by gender: the same, a re-read that doesn't say keeps it (town-feed 52).
      for_gender = coalesce(excluded.for_gender, club_events.for_gender),
      source_url = excluded.source_url,
      -- coalesce: a writer from before place_entry_id (the cloud routine until this is pushed)
      -- must not wipe a place already set.
      place_entry_id = coalesce(excluded.place_entry_id, club_events.place_entry_id),
      category = coalesce(club_events.category, excluded.category),
      -- Written as read, so a game read wrong once is right the next morning.
      sport = excluded.sport, team_ids = excluded.team_ids, occasion = excluded.occasion,
      -- Once a public page lists it, it stays everyone's; a re-read naming no activity keeps the one it had.
      followers_only = club_events.followers_only and excluded.followers_only,
      activity_team = coalesce(excluded.activity_team, club_events.activity_team),
      activity_name = coalesce(excluded.activity_name, club_events.activity_name),
      -- On its source's list again: not called off.
      cancelled_at = null,
      shows_from = case when club_events.event_date is distinct from excluded.event_date
          or club_events.shows_from is null then excluded.shows_from else club_events.shows_from end,
      -- An admin's approve or decline stands; only a found event the writer left pending is
      -- published by its source. A decline for a misread goes back to Review when the source
      -- changes it (the same rule as read_events.py had).
      status = case when club_events.status = 'pending' and club_events.review_reason is null
          and excluded.status = 'approved' then 'approved'
        when club_events.status = 'rejected'
          and club_events.review_reason is distinct from 'not_event' and club_events.review_reason is not null
          and (club_events.title, club_events.event_date, club_events.start_time, club_events.all_day, club_events.location)
              is distinct from (excluded.title, excluded.event_date, excluded.start_time, excluded.all_day, excluded.location)
        then 'pending' else club_events.status end
    returning 1
  )
  select (select count(*) from written),
    coalesce(jsonb_agg(g.n - 1 order by g.n) filter (where not exists (select 1 from public.club_events e
      where e.source_name = g.source_name and e.source_uid = g.source_uid)), '[]')
  into n_events, events_added
  from given g;

  -- 2. Every mention (ADR-021), counted toward the two-mention rule next time.
  insert into public.event_mentions (event_id, source_name, source_url, source_uid, trust, sure)
  select e.id, x.source_name, x.source_url, x.source_uid, x.trust, x.sure
  from jsonb_to_recordset(p_mentions) as x(event_id uuid, event_source_name text,
    event_source_uid text, source_name text, source_url text, source_uid text, trust text, sure boolean)
  join public.club_events e on e.id = x.event_id
    or (x.event_id is null and e.source_name = x.event_source_name and e.source_uid = x.event_source_uid)
  on conflict (event_id, source_name, source_url) do update set source_uid = excluded.source_uid,
    trust = excluded.trust, sure = excluded.sure, last_seen = now();
  get diagnostics n_mentions = row_count;

  -- 3. Listed events a new mention publishes: pending -> approved, never an admin's call.
  update public.club_events e set status = 'approved'
  from jsonb_array_elements_text(p_upgrades) as x(id)
  where e.id = x.id::uuid and e.status = 'pending' and e.review_reason is null
    and e.club_id is null and e.submitted_by is null;
  get diagnostics n_upgrades = row_count;

  -- 4. News for the town board's store, with its publish time, its interests and the place that
  --    posted it (town-feed 35). The plan left repeats out (write_judged.repeat_of); each is added, or
  --    re-read into the one already there under the same title.
  with given as (
    select a.n, x.*
    from jsonb_array_elements(p_news) with ordinality as a(item, n)
    cross join lateral jsonb_to_record(a.item) as x(title text, blurb text, category text, source_name text,
      source_url text, tier numeric, status text, starts_at timestamptz, ends_on date, shows_from timestamptz, interests text[], place_entry_id text)
  ), judged as (
    select g.*,
      exists (select 1 from public.board_items b where lower(b.title) = lower(g.title) and b.source_name = g.source_name
              and coalesce(b.starts_at, '-infinity'::timestamptz) = coalesce(g.starts_at, '-infinity'::timestamptz)) as listed
    from given g
  ), written as (
    insert into public.board_items (title, blurb, category, source_name, source_url, tier, status,
      starts_at, ends_on, published_at, fetched_at, interests, place_entry_id)
    select x.title, x.blurb, x.category, x.source_name, x.source_url, x.tier, x.status, x.starts_at, x.ends_on,
      case when x.status = 'published' then greatest(now(), x.shows_from) end, now(), x.interests, x.place_entry_id
    from judged as x
    on conflict (lower(title), source_name, coalesce(starts_at, '-infinity'::timestamptz)) do update set
      blurb = excluded.blurb, source_url = excluded.source_url, fetched_at = now(),
      ends_on = coalesce(excluded.ends_on, board_items.ends_on),
      -- The first read's interests stand, as an Event's category does; a writer from before them
      -- (the cloud routine until this is pushed) leaves both as they were.
      interests = coalesce(board_items.interests, excluded.interests),
      place_entry_id = coalesce(excluded.place_entry_id, board_items.place_entry_id),
      status = case when board_items.status = 'staging' and excluded.status = 'published'
        then 'published' else board_items.status end,
      published_at = case when board_items.status = 'staging' and excluded.status = 'published'
        then excluded.published_at else board_items.published_at end
    returning 1
  )
  select (select count(*) from written),
    coalesce(jsonb_agg(n - 1 order by n) filter (where not listed), '[]')
  into n_news, news_added
  from judged;

  -- 5. Found events their schedule dropped: kept and marked cancelled, never deleted; the app
  --    shows the Canceled tag (Jesse, 2026-10-15), so the title stays as written.
  update public.club_events e set cancelled_at = now()
  from jsonb_array_elements_text(p_cancelled) as x(id)
  where e.id = x.id::uuid and e.cancelled_at is null and e.club_id is null and e.submitted_by is null;
  get diagnostics n_cancelled = row_count;

  -- 6. Cancelled events back on their schedule (seen under another source's name; a re-read
  --    by its own source is restored in step 1).
  update public.club_events e set cancelled_at = null
  from jsonb_array_elements_text(p_restored) as x(id)
  where e.id = x.id::uuid and e.cancelled_at is not null;
  get diagnostics n_restored = row_count;

  return jsonb_build_object('events', n_events, 'mentions', n_mentions,
                            'published_by_mention', n_upgrades, 'news', n_news,
                            'cancelled', n_cancelled, 'restored', n_restored,
                            'added', jsonb_build_object('events', events_added, 'news', news_added));
end;
$$;

revoke all on function public.apply_judged(jsonb, jsonb, jsonb, jsonb, jsonb, jsonb) from public, anon, authenticated;
grant execute on function public.apply_judged(jsonb, jsonb, jsonb, jsonb, jsonb, jsonb) to service_role;


-- 4. The Event whose own words say it is for women: "to put on a Women in Religion Event!" (its About, 2026-11-09).
update public.club_events set for_gender = 'female'
  where title = 'Women in Religion' and source_name = 'CSB SJU Campus Events' and event_date >= date '2026-11-09';

-- 5. The Town feed.
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
    -- The recipe's weights (town-feed 36, 41). Changing one is a migration.
    select '{"interest":3,"friend":3,"follow":3,"new":2,"draw":1.5,"soonHalf":7,"newHalf":24,"acted":0.4,"notInterested":0.3,"repeatHost":0.5,"repeatCampus":0.8,"repeatKind":0.8,"seen":0.6,"seenFloor":0.3,"town":1.5,"townMiles":4.5,"meeting":0.3,"liveMax":3,"liveOpens":2,"newsEvery":5}'::jsonb as w
  ),
  town as (
    select 'America/Chicago'::text as zone,
           (p_now at time zone 'America/Chicago')::date as today,
           -- Downtown St. Joseph: everyone counts as St. Joseph until a second town opens (town-feed 41).
           45.5641::float8 as lat, -94.3183::float8 as lng
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
  last_visit as (
    select private.my_last_visit(p_now - interval '30 minutes') as at
  ),
  -- What the caller has seen (town-feed 41), by item and Town day. Not for the Event of the day (p_only),
  -- whose order holds through the day.
  my_seen_rows as materialized (
    select v.item_id, v.day, v.times, v.last_at from private.my_seen(p_now) v where p_only is null
  ),
  -- By series, so seeing one date of a repeating Event is seeing them all; a post goes by its own id.
  my_seen as materialized (
    select lower(btrim(e.title)) || '|' || coalesce(e.club_id::text, e.source_name, e.submitted_by::text, '') as series,
           sum(v.times)::int as times,
           coalesce(sum(v.times) filter (where v.day = town.today), 0)::int as today,
           max(v.last_at) as last_at
    from my_seen_rows v
    join public.club_events e on e.id = v.item_id and e.kind = 'event'
    cross join town
    group by 1
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
           lower(btrim(e.title)) || '|' || coalesce(e.club_id::text, e.source_name, e.submitted_by::text, '') as series,
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
      -- Called off: out of the feed, Hearted or not. Whoever Hearted it or is Going hears it in the bell
      -- (BP app inside-cards 16; until then a Heart kept it here).
      and e.cancelled_at is null
      -- For college students (onboarding 21): only for those who picked College, or are Going or Hearted it.
      and (not ('college' = any(e.interests) and e.interests_tagged_at is not null)
           or (select 'college' = any(me.interests) from me)
           or exists (select 1 from public.event_rsvps r where r.event_id = e.id and r.user_id = auth.uid())
           or exists (select 1 from public.event_likes l where l.event_id = e.id and l.user_id = auth.uid()))
      -- Followers only (a JV game, an away game, a banquet): only for those following its activity
      -- or its school (Jesse, 2026-10-25).
      and (not e.followers_only or fl.followed is not null)
      -- A City meeting reaches only those who follow that City or the meeting's board (town-feed 05, 27),
      -- or are Going to it or Hearted it, which always stay (ticket 05, inside-cards 16).
      and (not mt.is_meeting
           -- Or picked Town meetings, for one the tagger calls a meeting (onboarding 21): the City's
           -- compost site hours are draw 1 too.
           or ('town_meetings' = any(e.interests) and (select 'town_meetings' = any(me.interests) from me))
           or exists (select 1 from my_pages p where p.source = lower(e.source_name))
           or exists (select 1 from my_boards b where b.id = mt.board)
           or exists (select 1 from public.event_rsvps r where r.event_id = e.id and r.user_id = auth.uid())
           or exists (select 1 from public.event_likes l where l.event_id = e.id and l.user_id = auth.uid()))
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
    select t.series, public.town_feed_series_label(array_agg(t.event_date)) as recurrence,
           min(t.event_date) as first_date
    from timed t, town
    where t.event_date >= town.today - 60
    group by t.series
  ),
  next_up as (
    select t.*,
           -- A game played on an earlier day whose final is in gives the series' card to the next game: CSB played
           -- Lake Forest Friday and Saturday, and Friday's final hid Saturday's live game (game-card 24).
           row_number() over (partition by t.series
                              order by t.final_score is not null and t.event_date < (p_now at time zone 'America/Chicago')::date,
                                       t.event_date, t.starts_at nulls first, t.id) as nth,
           exists (select 1 from public.event_rsvps r where r.event_id = t.id and r.user_id = auth.uid())
             as going,
           -- The caller's Heart, which is a save now (inside-cards 16).
           exists (select 1 from public.event_likes l where l.event_id = t.id and l.user_id = auth.uid())
             as hearted
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
           yg.young,
           (select array_agg(x order by x) from unnest(tg.tags) x where x = any(me.interests)) as matched,
           -- The group that posted it, else, for a found Event, the group it was found for: worked out
           -- once here (`shown` is read twice, so kept) for the Group lift and the card's Join.
           coalesce(e.club_id, case when e.submitted_by is null and e.source_name is not null
                                    then private.event_group(e.source_name, e.place_entry_id, e.title) end) as group_id
    from next_up e, town, me,
         -- Every interest the tagger gave the Event (ticket 33); one it hasn't reached yet has
         -- its writer's one.
         lateral (select case when e.interests_tagged_at is not null then e.interests
                              else array[e.category] end as tags) tg,
         -- Middle school sports and Knowledge Bowl (Jesse, 2026-11-05: "junior high sports typically are not gonna
         -- be very popular"), for those who care (`scored`). A school's concerts and shows stay (MEMORY.md).
         lateral (select 'middle_school' = any(tg.tags) and e.interests_tagged_at is not null
                         and ('watch_sports' = any(tg.tags) or coalesce(e.what, e.title) ~* 'knowledge bowl') as young) yg
    where e.nth = 1
      -- After the best (town-feed 23): p_later asks for the Events not yet in, past their show-from day.
      and (town.today >= coalesce(e.shows_from, e.event_date - 14)) <> p_later
      -- Not interested keeps out the item and every week of its series; Mute its host (ticket 21).
      and not exists (select 1 from muted m where m.host = e.host)
      and not exists (select 1 from hidden h where h.series = lower(btrim(e.title)) || '|' || e.host)
      -- Under 18 never sees what its place keeps to 18+ or 21+ (ticket 19).
      -- A host's own 18+ or 21+ (town-feed 52) counts as those words do.
      and (me.adult or not private.adults_only(e.place_entry_id, e.club_id,
                                               e.title || ' ' || coalesce(e.description, '') || ' ' || coalesce(e.ages, '')))
      -- These go before the limit below, or the later list comes up short.
      and (not p_later or not yg.young
           or 'middle_school' = any(me.interests) or e.school_followed is not null or e.going or e.hearted
           or exists (select 1 from private.friends_going(array[e.id])))
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
           -- New (town-feed 36, 38, 41): in the feed, posted or its show-from day come, since the caller's
           -- last visit or in the last 24 hours, whichever reaches further back (least() skips a missing
           -- last visit), its series' first date, and no date of it seen yet. Signed out, a found Event has
           -- no poster and no caller: still New.
           coalesce(greatest(s.created_at, coalesce(s.shows_from, s.event_date - 14)::timestamp at time zone town.zone) > least(lv.at, p_now - interval '24 hours')
                    and not s.going and not s.hearted
                    and coalesce(s.submitted_by <> auth.uid(), true)
                    and s.event_date = lb.first_date
                    and sn.series is null, false) as is_new,
           -- What it takes to be live (town-feed 41): its card says so, as every screen reads "Now".
           coalesce((ec.card->>'live_kind')::boolean, false) as live_kind,
           sn.times as seen_times, sn.today as seen_today, sn.last_at as seen_at,
           (ec.card->>'friends_going_at')::timestamptz as friend_at,
           -- How far from town: its own map point, else its place's (town-feed 41).
           sqrt(power((coalesce(s.lat, pt.lat) - town.lat) * 69, 2)
                + power((coalesce(s.lng, pt.lon) - town.lng) * 69 * cos(radians(town.lat)), 2)) as miles,
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
           coalesce(s.school_followed, fw.name) as followed,
           -- How much it is for the caller's gender, 0 to 1 (town-feed 52): its host's or page's mark, else its
           -- Going crowd against the town's mix. No answer, nothing.
           coalesce(gl.lean, 0) as gender_lean
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
    left join private.gender_lean(array(select x.id from shown x)) gl on gl.event_id = s.id
    left join labels lb on lb.series = s.series
    left join my_seen sn on sn.series = lower(btrim(s.title)) || '|' || s.host
    left join lateral (select pl.lat, pl.lon from public.places pl where pl.entry_id = s.place_entry_id limit 1) pt on true
  ),
  scored as (
    select c.*,
           -- Interests, friends and following count the same and add up (town-feed 41); a second interest
           -- adds nothing.
           (w->>'interest')::float8 * least(coalesce(array_length(c.matched, 1), 0), 1) as interest_pts,
           case when c.friends_n > 0 then (w->>'friend')::float8 else 0 end as friend_pts,
           -- For the caller's gender (town-feed 52): up to an interest's points, and never a reason on the card.
           (w->>'interest')::float8 * c.gender_lean as gender_pts,
           -- Something you follow (school-activities 03, town-feed 37), or a host you've been into (ticket 30),
           -- never routine business (draw 1).
           case when c.followed is not null or (c.tapped_n > 0 and coalesce(c.draw, 2) <> 1)
                then (w->>'follow')::float8 else 0 end as follow_pts,
           case when c.is_new then (w->>'new')::float8 else 0 end as new_pts,
           -- How much it draws a town out, the tagger's 1-3 (ticket 34): everyone's starting point,
           -- 0, 1.5 or 3 points; one not rated yet counts as 2.
           (w->>'draw')::float8 * (coalesce(c.draw, 2) - 1) as draw_pts,
           power(0.5, c.days_away / (w->>'soonHalf')::float8) as soon,
           -- Going sinks it; a Heart doesn't (inside-cards 16): you hearted it to keep it in sight.
           case when c.going then (w->>'acted')::float8 else 1 end as acted,
           -- A City meeting, for those who follow its City or board, sits lower (town-feed 27).
           case when c.is_meeting then (w->>'meeting')::float8 else 1 end as meeting_x,
           -- A host you said Not interested to (ticket 21): × 0.3 for its other Events, with no fade
           -- (town-feed 36). A report hides its item only and lowers nothing (town-feed 22).
           case when exists (select 1 from hidden h where h.lowers and h.host <> '' and h.host = c.host)
                then (w->>'notInterested')::float8 else 1 end as hidden_x,
           case when c.miles <= (w->>'townMiles')::float8 then (w->>'town')::float8 else 1 end as town_x,
           -- Each open you've seen it, down to a floor (town-feed 41). On its own day a real happening counts
           -- only that day's, and a friend's Going since you saw it brings it back: both until you see it again.
           greatest((w->>'seenFloor')::float8, power((w->>'seen')::float8,
             case when c.seen_times is null or c.friend_at > c.seen_at then 0
                  when c.live_kind and c.days_off = 0 then c.seen_today
                  else c.seen_times end)) as seen_x
    from counted c, weights
    -- Only for those who picked Middle school, follow it, have a friend Going, or are Going to it or Hearted it.
    where not c.young
       or 'middle_school' = any(c.matched)
       or c.followed is not null or c.friends_n > 0 or c.going or c.hearted
  ),
  totals as (
    select c.*,
           (1 + c.friend_pts + c.follow_pts + c.interest_pts + c.gender_pts + c.new_pts + c.draw_pts)
             * c.soon * c.acted * c.hidden_x * c.meeting_x * c.town_x * c.seen_x as base,
           -- Which pool it is in, for the Score line: yours or discovery; your own Going in neither.
           case when c.going then null
                else c.friend_pts + c.follow_pts > 0 end as yours,
           -- A real happening on right now, seen on fewer than 2 opens today (town-feed 41).
           p_only is null and not p_later and c.live_kind and c.starts_at <= p_now and p_now < c.leaves_at
             and c.final_score is null and c.hidden_x = 1
             and coalesce(c.seen_today, 0) < (select (w->>'liveOpens')::int from weights) as live_ok,
           -- The reason: something you follow says so first (school-activities 03), then a friend
           -- Going, a host you've been into, New, an interest.
           case when c.followed is not null then 'follow'
                when c.friends_n > 0 then 'friend'
                when c.follow_pts > 0 then 'tapped'
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
           l.leaves_at,
           (select array_agg(x order by x) from unnest(b.interests) x where x = any(me.interests)) as matched
    from public.board_items b
    cross join town
    cross join me
    -- A story stays until midnight after the day its words end, else the day it is about, up to 30 days. With neither,
    -- 7 days (Jesse, 2026-11-06; BP app town-feed 49). write_judged.news_lasts_until says the same for its repeats.
    cross join lateral (
      select case when d.last_day is null then b.published_at + interval '7 days'
                  else least(b.published_at + interval '30 days', (d.last_day + 1)::timestamp at time zone town.zone) end as leaves_at
      from (select coalesce(b.ends_on,
                            case when (b.starts_at at time zone town.zone)::date >= (b.published_at at time zone town.zone)::date
                                 then (b.starts_at at time zone town.zone)::date end) as last_day) d
    ) l
    where p_news and not p_later
      and b.status = 'published'
      and b.category in ('business', 'announcement', 'campus', 'school', 'road')
      and nullif(btrim(b.source_url), '') is not null
      -- Not from a host you muted (ticket 21): a found Event's host is its place's name, as news's is.
      and not exists (select 1 from muted m where m.host = b.source_name)
      -- Nor one you said Not interested to (news-menu).
      and not exists (select 1 from public.news_hides h where h.user_id = auth.uid() and h.item_id = b.id)
      and b.published_at > p_now - interval '30 days' and b.published_at <= p_now
      and l.leaves_at > p_now
      and (me.adult or not private.adults_only(b.place_entry_id, null, b.title || ' ' || coalesce(b.blurb, '')))
  ),
  news_scored as (
    -- A steady mix of News and Events (Jesse, 2026-11-05: "a ratio of news and events"): stories you
    -- haven't seen take every 5th spot (`spots`), your interests first, then town news, then a place's own,
    -- each place's newest before anyone's second, newest first inside each. One you've seen is out of the feed.
    select n.*,
           row_number() over (order by n.rank, n.of_place, n.published_at desc, n.id) as nth
    from (select n.*,
                 case when n.matched is not null then 0 when n.category = 'business' then 2 else 1 end as rank,
                 row_number() over (partition by n.source_name order by n.published_at desc, n.id) as of_place
          from news n
          where not exists (select 1 from public.news_views v where v.item_id = n.id and v.user_id = auth.uid())) n
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
    -- An Event's recipe by age instead of day (town-feed 29): 1, plus following for your own post or one from
    -- someone you follow (friends follow each other), plus New, the whole halving every 24 hours and
    -- sinking as you see it (town-feed 41).
    -- `followed` goes on the row too (daily-tab 23): the Block Party tab's Following shows these posts.
    select p.*,
           (1 + case when p.followed then (w->>'follow')::float8 else 0 end
              + case when not p.mine and p.created_at > least(lv.at, p_now - interval '24 hours')
                          and not exists (select 1 from my_seen_rows v where v.item_id = p.id)
                     then (w->>'new')::float8 else 0 end)
             * power(0.5, extract(epoch from p_now - p.created_at) / 3600 / (w->>'newHalf')::float8)
             * greatest((w->>'seenFloor')::float8, power((w->>'seen')::float8,
                 coalesce((select sum(v.times) from my_seen_rows v where v.item_id = p.id), 0))) as base
    from (select p.*, p.mine or exists (select 1 from my_people mp where mp.id = p.submitted_by) as followed
          from posts p) p, weights, last_visit lv
  ),
  -- Live first (town-feed 41): up to 3, what you're Going to, then most Going, then the draw, your town's
  -- counting more, then the latest to start.
  live_now as (
    select t.id, row_number() over (order by t.going desc, t.going_n desc, coalesce(t.draw, 2) * t.town_x desc,
                                             t.starts_at desc, t.id) as nth
    from totals t
    where t.live_ok
  ),
  pool as (
    -- The campus's Events space as one host's (onboarding 21): Campus lifts them, and CSB and SJU's
    -- dozen calendars can't fill the top of the feed between them.
    select t.id, case when 'campus' = any(t.tags) then 'campus' else t.host end as host, t.base, t.sort_at, t.title,
           coalesce(t.category, t.id::text) as kind, l.nth as live
    from totals t
    left join live_now l on l.id = t.id and l.nth <= (select (w->>'liveMax')::int from weights)
    union all
    -- Posts among the Events, their poster as their host, so a second one from the same neighbour
    -- counts half (the spacing rule below).
    select p.id, p.submitted_by::text, p.base, p.created_at, p.title, p.id::text, null::bigint
    from posts_scored p
  ),
  -- The spacing rules (town-feed 36, 41): each further item from a host counts half, each further one of a kind
  -- counts 0.8. A host's or kind's items are always placed best first, so this is its place among them. Live
  -- cards are placed apart; the Event of the day (p_only) reads only some hosts, so never the kind.
  spaced as (
    select p.*,
           power((select (w->>case when p.host = 'campus' then 'repeatCampus' else 'repeatHost' end)::float8 from weights),
                 row_number() over (partition by p.live is null, p.host order by p.base desc, p.sort_at, p.title, p.id) - 1)
           * case when p_only is null and p.live is null
                  then power((select (w->>'repeatKind')::float8 from weights),
                             row_number() over (partition by p.live is null, p.kind order by p.base desc, p.sort_at, p.title, p.id) - 1)
                  else 1 end
             as spacing
    from pool p
  ),
  ordered as (
    select s.id, s.spacing,
           -- Later Events (town-feed 23) by their start, not their points.
           row_number() over (order by case when p_later then s.sort_at end, s.live nulls last, s.base * s.spacing desc,
                                       s.sort_at, s.title, s.id) as nth
    from spaced s
  ),
  -- Events and posts leave every 5th spot open for News you haven't seen; with none left the next card moves up.
  spots as (
    select x.id, x.spacing, row_number() over (order by x.place, x.id)::int as spot
    from (
      select o.id, o.spacing, o.nth + (o.nth - 1) / ((select (w->>'newsEvery')::int from weights) - 1) as place
      from ordered o
      union all
      -- Only as many as the Events leave spots for, so never two together; the rest wait for a later open. A
      -- town with next to no Events shows what it has.
      select n.id, 1::float8, n.nth * c.every
      from news_scored n
      cross join (select (select (w->>'newsEvery')::int from weights) as every, (select count(*) from ordered) as events) c
      where c.events < c.every - 1 or n.nth <= c.events / (c.every - 1)
    ) x
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
           'interest', e.interest_pts, 'gender', e.gender_pts, 'yours', e.friend_pts + e.follow_pts, 'new', e.new_pts,
           'friend', e.friend_pts,
           'follow', case when e.followed is not null then e.follow_pts else 0 end,
           'tapped', case when e.followed is null then e.follow_pts else 0 end,
           'town', e.town_x, 'seen', e.seen_x, 'live', e.live_ok,
           'popular', 0, 'size', 0, 'sizeStep', 1, 'draw', e.draw_pts,
           'daysAway', round(e.days_away::numeric, 2), 'soon', round(e.soon::numeric, 4),
           'acted', e.acted, 'notInterested', e.hidden_x, 'spacing', p.spacing,
           'newSpot', e.is_new, 'pool', case when e.yours then 'yours' when not e.yours then 'discovery' end,
           'total', round((e.base * p.spacing)::numeric, 4),
           'spot', p.spot, 'of', count(*) over ())
         end,
         -- The Heart is the card's now (inside-cards 16); these two stay for builds that read them here.
         (e.card->>'heart_count')::int,
         e.hearted,
         -- Save is gone (inside-cards 16): builds on phones before it still read their old saves here, until
         -- event_saves is dropped.
         exists (select 1 from public.event_saves s where s.event_id = e.id and s.user_id = auth.uid()),
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
  -- A news item's row: its own columns, nulls and zeros for the rest. Its post's own photo, when the photo step
  -- kept one (town-feed 53), is its image_url, and its shape rides in poster as {"aspect": w / h}, so the card
  -- takes the photo's shape before it loads.
  select n.id, n.title, null::text, np.url, n.source_name, n.published_at,
         null::text, n.leaves_at,
         case when n.matched is not null then 'interest' end, n.matched[1],
         -- Its hearts, every account's, and whether the caller gave one (inside-cards 22), as an Event's card says.
         null::jsonb, private.news_heart_count(n.id),
         exists (select 1 from public.news_likes h where h.item_id = n.id and h.user_id = auth.uid()), false,
         -- The place's logo first, as its Search tile and Instagram's avatars show a place; else its
         -- photo (place_picture).
         private.entry_picture(n.place_entry_id),
         n.blurb, null::uuid, false,
         'news'::text, n.source_url,
         case when np.url is not null then jsonb_build_object('aspect', np.width::float8 / nullif(np.height, 0)) end,
         null::jsonb, s.spot
  from news_scored n
  join spots s on s.id = n.id
  left join public.place_photos np on np.news_id = n.id and np.status = 'live' and np.kind = 'news'
  union all
  -- A post's row (town-feed 29): its words as the title, its Place and photo, its hearts, and who
  -- posted it; nulls and zeros for the rest.
  select p.id, p.title, p.location, p.image_url, null::text, p.created_at,
         null::text, p.created_at + interval '7 days',
         -- From you or someone you follow it says so, with their name, as an Event's row does (daily-tab 23: the
         -- Block Party tab's Following shows these); a stranger's says nothing.
         case when p.followed then 'follow' end, case when p.followed then pp.poster->>'name' end, null::jsonb,
         private.heart_count(p.id),
         exists (select 1 from public.event_likes h where h.event_id = p.id and h.user_id = auth.uid()),
         false, null::jsonb,
         null::text, null::uuid, false,
         'post'::text, null::text,
         -- and the post's own: its photo's shape, which sets the card's before the photo loads, and whether
         -- only friends see it, which its card says.
         pp.poster || jsonb_strip_nulls(jsonb_build_object('aspect', p.image_aspect, 'friends_only', p.friends_only)),
         null::jsonb,
         s.spot
  from posts_scored p
  join spots s on s.id = p.id
  cross join lateral (select private.post_poster(p.submitted_by, p.tagged) as poster) pp
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
