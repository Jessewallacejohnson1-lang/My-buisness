-- Importance, 1 to 5, replaces the draw's 1 to 3 on Events (BP app feed-learns 04; Jesse, 2026-11-22 and 2026-11-25):
-- 1 routine business, 2 small, 3 a normal public Event, 4 many people plan for it, 5 the whole Town turns out. Two agents
-- rate each Event on their own and the lower level wins (sources/models/importance.md, importance.py). The guessed values,
-- for Jesse's yes: each step above 1 is 0.75 points, so a 5 is worth what a draw 3 was; the draw maps across 1 to 1, 2 to 3, 3 to 4
-- until the re-rate; one not rated yet counts as 3.
--
-- Everything that read the draw reads importance, each function its newest version but for that, so level 1 is what draw 1
-- was: only its followers see it, and from a City it is a meeting. Nothing reads the draw after this; it is dropped in a
-- migration of its own once a morning has run on the new code.

alter table public.club_events add column importance smallint check (importance between 1 and 5);
update public.club_events set importance = case draw when 1 then 1 when 2 then 3 when 3 then 4 end where draw is not null;

-- 20261105211111_fresh_every_open.sql. A parameter can't be renamed in place, so it is made again; the functions that call it
-- find it by name when they run.
drop function private.is_live_kind(text, text, int, boolean, text, date, timestamptz, boolean);
create function private.is_live_kind(p_what text, p_title text, p_importance int, p_all_day boolean, p_start text,
                                     p_day date, p_end timestamptz, p_game boolean default false)
returns boolean
language sql
stable
set search_path = ''
as $$
  select not coalesce(p_all_day, false)
     and nullif(btrim(p_start), '') is not null
     -- A game between two teams always is: an "Exhibition" game too.
     and (p_game or (coalesce(p_importance, 3) <> 1
          and coalesce(p_what, p_title, '') !~* 'exhibit|\msales?\M|open house|promotion|shopping|\mlaunch\M|meeting|season start'))
     and (p_end is null or p_end <= (p_day + 1)::timestamp at time zone 'America/Chicago' + interval '6 hours')
$$;
revoke execute on function private.is_live_kind(text, text, int, boolean, text, date, timestamptz, boolean) from public;
grant execute on function private.is_live_kind(text, text, int, boolean, text, date, timestamptz, boolean) to anon, authenticated;

-- 20261105211111_fresh_every_open.sql, importance for the draw.
create or replace function public.get_event_of_the_day(p_now timestamptz default now())
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
  asked as (
    select case when exists (select 1 from written) then array(select w.event_id from written w)
                else array(select e.id from public.club_events e, town where e.event_date = town.today) end as ids
  ),
  -- Today's Events as the caller's Town feed has them, in its order: on now or still to come
  -- (the feed lets one go at its leaves_at), not called off.
  feed as (
    select f.*,
           -- Its interests as the feed matches them: the tagger's, else its writer's one.
           case when e.interests_tagged_at is not null then e.interests else array[e.category] end as tags,
           coalesce(e.importance, 3) as importance,
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
  -- The job wrote nothing today: the feed's top Event, never routine business (importance 1). One
  -- you're Going to comes first, since the feed lowers an Event you acted on and Going would
  -- otherwise hand its spot to the next.
  fallback as (
    select p.* from parts p
    where p.importance > 1 and not exists (select 1 from written)
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

-- 20261124161211_closed_events_out_of_the_calendar.sql, importance for the draw.
create or replace function public.get_town_calendar(p_now timestamptz default now())
returns table (card jsonb)
language sql
stable
security invoker
set search_path = public
as $$
  with town as (
    select date_trunc('month', (p_now at time zone 'America/Chicago')::date)::date as first_day
  ),
  me as (
    -- Under 18 from the caller's birthday; signed out or no birthday counts as grown.
    select coalesce(p.interests, '{}'::text[]) as interests,
           p.birthday is null or p.birthday <= (p_now at time zone 'America/Chicago')::date - interval '18 years'
             as adult
    from (select 1) one
    left join public.town_profiles p on p.user_id = auth.uid()
  ),
  muted as (
    select m.host from public.feed_mutes m where m.user_id = auth.uid()
  ),
  -- Not interested keeps out the Event and every date of its series.
  hidden as (
    select lower(btrim(e.title)) || '|' || coalesce(e.club_id::text, e.source_name, e.submitted_by::text, '') as series
    from private.my_not_interested() n
    join public.club_events e on e.id = n.item_id
  ),
  cities as (
    select lower(pg.source_name) as source from public.town_pages pg where pg.slug = 'city'
  ),
  my_pages as (
    select lower(pg.source_name) as source
    from public.town_follows f
    join public.town_pages pg on pg.id = f.target_id
    where f.follower_id = auth.uid() and f.target_type = 'page'
  ),
  my_boards as (
    select b.id
    from public.town_follows f
    join public.city_boards b on b.id = f.target_id
    where f.follower_id = auth.uid() and f.target_type = 'board'
  ),
  picked as (
    select e.id, e.event_date, e.title
    from public.club_events e
    cross join town
    cross join me
    cross join lateral (select coalesce(e.club_id::text, e.source_name, e.submitted_by::text, '') as host,
                               case when e.interests_tagged_at is not null then e.interests
                                    else array[e.category] end as tags,
                               exists (select 1 from public.event_rsvps r where r.event_id = e.id and r.user_id = auth.uid())
                                 or exists (select 1 from public.event_likes l where l.event_id = e.id and l.user_id = auth.uid())
                                 as mine) x
    where e.status = 'approved'
      and e.kind = 'event'
      and e.event_date is not null
      and (e.submitted_by is not null or e.source_name is not null)
      -- Public only: no Group's post, nothing for followers or friends alone.
      and e.club_id is null
      and not coalesce(e.followers_only, false)
      and not coalesce(e.friends_only, false)
      and e.cancelled_at is null
      -- Nobody can sign up any more: only for whoever is Going or Hearted it.
      and (e.signups_closed_by is null or x.mine)
      and e.event_date >= town.first_day
      and e.event_date < (town.first_day + interval '12 months')::date
      -- For college students: only for those who picked College, or are Going or Hearted it.
      and (not ('college' = any(e.interests) and e.interests_tagged_at is not null)
           or 'college' = any(me.interests) or x.mine)
      -- A City meeting: only for those who follow the City or its board, picked Town meetings, or are Going
      -- or Hearted it.
      and (not (coalesce(e.importance = 1, false) and exists (select 1 from cities c where c.source = lower(e.source_name)))
           or ('town_meetings' = any(e.interests) and 'town_meetings' = any(me.interests))
           or exists (select 1 from my_pages p where p.source = lower(e.source_name))
           or exists (select 1 from my_boards b where b.id = public.meeting_board(e))
           or x.mine)
      -- Middle school sports and Knowledge Bowl: only for those who picked Middle school, or are Going or Hearted it.
      and (not ('middle_school' = any(x.tags) and e.interests_tagged_at is not null
                and ('watch_sports' = any(x.tags) or coalesce(e.what, e.title) ~* 'knowledge bowl'))
           or 'middle_school' = any(me.interests) or x.mine)
      and not exists (select 1 from muted m where m.host = x.host)
      and not exists (select 1 from muted m join public.places pl on pl.name = m.host
                      where pl.entry_id = any(e.collab_entry_ids))
      and not exists (select 1 from hidden h where h.series = lower(btrim(e.title)) || '|' || x.host)
      -- Under 18 never sees what its place keeps to 18+ or 21+, nor an age mark from 18 up.
      and (me.adult or not private.adults_only(e.place_entry_id, e.club_id, e.title || ' ' || coalesce(e.description, '')))
      and (me.adult or coalesce((regexp_match(e.ages, '^(?:Ages )?(\d+)(?:\+|–)'))[1]::int, 0) < 18)
  )
  -- The Event card, asked once for all of the rows.
  select ec.card
  from picked p
  join private.event_cards(array(select x.id from picked x)) ec on ec.id = p.id
  order by p.event_date, p.title, p.id
$$;

-- 20261108203849_every_door_carries_the_card.sql, importance for the draw.
create or replace function public.board_meetings(p_board uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  with y as (
    select e.id, e.title, e.event_date, e.start_time, e.location
    from public.city_boards b
    join public.club_events e on e.source_name = b.city_name and e.importance = 1
    where b.id = p_board and e.status = 'approved' and e.cancelled_at is null
      and e.event_date >= (now() at time zone 'America/Chicago')::date
      and public.meeting_board(e) = b.id
    order by e.event_date, e.start_time
    limit 20
  )
  select coalesce(jsonb_agg(x order by x ->> 'date', x ->> 'time'), '[]'::jsonb)
  from (
    select jsonb_build_object('id', y.id, 'title', y.title, 'date', y.event_date, 'time', y.start_time,
                              'location', y.location, 'recurrence', c.card ->> 'recurrence', 'card', c.card) as x
    -- The Event card, asked once for the list (inside-cards 27): the Event page's heart and the rest.
    from y left join private.event_cards(array(select y.id from y)) c on c.id = y.id
  ) z
$$;

-- 20261019150000_city_boards.sql, importance for the draw.
create or replace function public.meeting_board(e public.club_events) returns uuid
language sql stable set search_path = public as $$
  select b.id from public.city_boards b
  where e.importance = 1 and e.source_name = b.city_name
    and exists (select 1 from unnest(b.title_prefixes) p where e.title ilike p || '%')
  order by b.name
  limit 1
$$;

-- 20261124175536_place_ratings.sql, importance for the draw.
create or replace function public.place_facts()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  with today as (select (now() at time zone 'America/Chicago')::date as d),
  titles as (
    select e.place_entry_id, case when e.team_ids is not null then 'Games' else e.title end as title,
           count(*) as dates, max(coalesce(e.importance, 0)) as importance, bool_or(e.event_date >= today.d) as upcoming
    from public.club_events e, today
    where e.status = 'approved' and e.cancelled_at is null and e.event_date > today.d - 365
    group by 1, 2),
  events as (
    select place_entry_id, jsonb_agg(jsonb_build_object('title', title, 'dates', dates, 'importance', importance, 'upcoming', upcoming)
                                     order by importance desc, dates desc, title) as list
    from titles group by 1),
  news as (
    select place_entry_id, jsonb_agg(jsonb_build_object('day', created_at::date, 'title', title) order by created_at desc) as list
    from public.board_items where created_at > now() - interval '90 days' group by 1),
  follows as (
    select target_id, count(distinct follower_id) as n from public.town_follows where target_type = 'place' group by 1)
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', p.id, 'entry_id', p.entry_id, 'place_id', p.place_id, 'google_place_id', p.google_place_id, 'name', p.name,
    'address', p.address, 'family', p.family, 'kind', coalesce(p.category, p.primary_type), 'adults_only', p.adults_only,
    'about', p.about, 'links', p.links, 'events', coalesce(e.list, '[]'), 'news', coalesce(n.list, '[]'),
    'follows', coalesce(f.n, 0), 'love', private.place_love(p.id)) order by p.name), '[]')
  from public.places p
  left join events e on e.place_entry_id = p.entry_id
  left join news n on n.place_entry_id = p.entry_id
  left join follows f on f.target_id = p.id
  where p.closed_at is null;
$$;

-- 20261122204701_group_calendar.sql, importance for the draw.
create or replace function public.claim_submit(p_event uuid, p_user uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_photo text := '^https://lxdgwhvqjqmqliobwjpi\.supabase\.co/storage/v1/object/public/event-images/'
                  || p_user::text || '/[0-9a-f-]+\.jpg$';
  -- A post's later photos: <its id>-2.jpg to -10.jpg in the poster's own folder (town-feed 46).
  v_more text := '^https://lxdgwhvqjqmqliobwjpi\.supabase\.co/storage/v1/object/public/event-images/' || p_user::text || '/';
  v_claimed boolean;
begin
  perform pg_advisory_xact_lock(hashtextextended('claim_submit:' || p_user::text, 0));
  if (select count(*) from public.club_events
      where submitted_by = p_user and checked_at > now() - interval '24 hours') >= 10 then
    return false;
  end if;
  with c as (
    update public.club_events e
    set checked_at = now(),
        tagged = (select array_agg(x.id order by x.n)
                  from (select u.id, min(u.n) as n from unnest(e.tagged) with ordinality as u(id, n) group by u.id) x
                  where exists (select 1 from private.friendships f
                                where f.a = least(p_user, x.id) and f.b = greatest(p_user, x.id))),
        at_names = private.checked_at_names(p_user, e.title, e.at_names)
    where e.id = p_event and e.submitted_by = p_user and e.status = 'pending' and e.checked_at is null
      and (
        (e.kind = 'event' and not e.friends_only and e.tagged is null and e.at_names is null)
        or (e.kind = 'post' and e.event_date is null and e.start_time is null and e.end_at is null
            and not e.all_day and (btrim(e.title) <> '' or e.image_url is not null)
            and char_length(e.title) <= 2000 and coalesce(cardinality(e.tagged), 0) <= 20
            and coalesce(jsonb_array_length(e.at_names), 0) <= 20)
      )
      and coalesce(e.category, 'other') = 'other'
      and (e.image_url is null or e.image_url ~ v_photo)
      and (e.more_photos is null
           or (e.kind = 'post' and e.image_url is not null and cardinality(e.more_photos) between 1 and 9
               and (select count(distinct m) from unnest(e.more_photos) m) = cardinality(e.more_photos)
               and not exists (select 1 from unnest(e.more_photos) m where m is null or m !~ (v_more || e.id::text || '-([2-9]|10)\.jpg$'))))
      -- A Group's Event only from someone who may add to it (start-a-group 05).
      and (e.club_id is null or (e.kind = 'event' and private.adds_to_group(e.club_id, p_user)))
      and e.source_name is null and e.source_uid is null and e.source_url is null
      and e.place_entry_id is null and e.team_ids is null and e.activity_team is null
      and e.activity_name is null and e.sport is null and e.occasion is null and e.what is null
      and e.importance is null and e.shows_from is null and coalesce(cardinality(e.interests), 0) = 0 and e.interests_tagged_at is null
      and e.lat is null and e.lng is null and coalesce(e.followers_only, false) = false
      and e.cancelled_at is null and e.moved_at is null and e.moved_from is null
      and e.live_score is null and e.final_score is null and e.scoring_plays is null
      and e.review_reason is null and e.rechecked_at is null
    returning 1
  )
  select exists (select 1 from c) into v_claimed;
  return v_claimed;
end
$$;

-- 20261124172832_closed_events_off_the_town_pages.sql, importance for the draw.
create or replace function public.town_page(p_town text, p_slug text)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'id', p.id, 'name', p.name, 'kind', p.kind, 'picture', p.picture, 'picture_kind', p.picture_kind,
    'picture_credit', p.picture_credit,
    'events', coalesce((
      with y as (
        select e.id, e.title, e.event_date, e.start_time, e.location
        from public.club_events e
        where lower(e.source_name) = lower(p.source_name) and e.status = 'approved' and e.cancelled_at is null
          and not e.followers_only and e.event_date >= (now() at time zone 'America/Chicago')::date
          -- Nobody can sign up any more: only for whoever is Going or Hearted it.
          and (e.signups_closed_by is null
               or exists (select 1 from public.event_rsvps r where r.event_id = e.id and r.user_id = auth.uid())
               or exists (select 1 from public.event_likes l where l.event_id = e.id and l.user_id = auth.uid()))
        order by e.event_date, e.start_time
        limit 10
      )
      select jsonb_agg(x order by x ->> 'date', x ->> 'time')
      from (
        select jsonb_build_object('id', y.id, 'title', y.title, 'date', y.event_date, 'time', y.start_time,
                                  'location', y.location, 'recurrence', c.card ->> 'recurrence', 'card', c.card) as x
        -- The Event card, asked once for the list (inside-cards 27): the Event page's heart and the rest.
        from y left join private.event_cards(array(select y.id from y)) c on c.id = y.id
      ) z), '[]'::jsonb),
    'boards', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', b.id, 'name', b.name,
        'following', exists (select 1 from public.town_follows f where f.follower_id = auth.uid()
                             and f.target_type = 'board' and f.target_id = b.id),
        'next', (select jsonb_build_object('date', e.event_date, 'time', e.start_time)
                 from public.club_events e
                 where e.source_name = b.city_name and e.importance = 1 and e.status = 'approved'
                   and e.cancelled_at is null and e.event_date >= (now() at time zone 'America/Chicago')::date
                   and public.meeting_board(e) = b.id
                 order by e.event_date, e.start_time
                 limit 1)) order by b.name)
      from public.city_boards b
      where b.town = p.town and b.city_name = p.source_name), '[]'::jsonb))
  from public.town_pages p
  where p.town = p_town and p.slug = p_slug
$$;

-- 20261110225556_business_collab.sql, importance for the draw.
create or replace function private.event_cards(p_events uuid[])
returns table (id uuid, card jsonb)
language sql
stable
security invoker
set search_path = ''
as $$
  -- The group that posted it, else, for a found Event, the group it was found for: worked out once per
  -- Event (kept, as the Town feed's `shown` is), never once per group the join tries.
  with ev as materialized (
    select e.*,
           coalesce(e.club_id, case when e.submitted_by is null and e.source_name is not null
                                    then private.event_group(e.source_name, e.place_entry_id, e.title) end) as group_id
    from public.club_events e
    where e.id = any (p_events)
  ),
  -- Each host's picture once, and all of them before any Event's picture. The host picture is read as
  -- its owner and the Event picture as the caller, so asking for both on every row makes Postgres 18 plan
  -- their shared place_picture again each time: 124 ms against 46 for 200 Events (PGlite, 2026-11-02).
  hosts as materialized (
    select jsonb_object_agg(k.host, private.host_picture(k.source_name, k.own_entry_id)) as pictures
    from (select distinct jsonb_build_array(e.source_name, c.own_entry_id)::text as host, e.source_name, c.own_entry_id
          from ev e
          left join public.clubs c on c.id = e.group_id) k
  )
  select e.id,
         jsonb_build_object(
           'id', e.id,
           'title', e.title,
           'event_date', e.event_date,
           'start_time', e.start_time,
           'location', e.location,
           'image_url', e.image_url,
           'category', e.category,
           'club_name', c.name,
           'source_name', e.source_name,
           'end_at', e.end_at,
           'all_day', e.all_day,
           'created_at', e.created_at,
           'going_count', private.going_count(e.id),
           'going', exists (select 1 from public.event_rsvps r where r.event_id = e.id and r.user_id = auth.uid()),
           'cancelled', e.cancelled_at is not null,
           -- The Heart, which is a save now (inside-cards 16): every account's, and whether the caller gave one. Every
           -- door to the Event page knows it, so a heart shows the same from the feed, the bell, Going and Liked.
           'heart_count', private.heart_count(e.id),
           'hearted', exists (select 1 from public.event_likes l where l.event_id = e.id and l.user_id = auth.uid()),
           -- A photo of what it is, else its place's picture (event-photos 07).
           'place_picture', public.event_picture(e.id),
           -- Who puts it on, its logo first (Jesse, 2026-10-23).
           'host_picture', h.pictures -> jsonb_build_array(e.source_name, c.own_entry_id)::text,
           -- The businesses it was made with, in order (town-feed 58): each place's id, name and picture.
           'collabs', (select coalesce(jsonb_agg(jsonb_build_object('id', pl.id, 'entry_id', pl.entry_id, 'name', pl.name,
                                                                    'picture', public.place_picture(pl.entry_id)) order by k.n), '[]'::jsonb)
                       from unnest(e.collab_entry_ids) with ordinality k(entry, n)
                       join public.places pl on pl.entry_id = k.entry
                       -- Never its host again, whoever set the list: the stack would show one logo twice.
                       where pl.name is distinct from e.source_name),
           'description', e.description,
           -- What it costs, as words (inside-cards 14): the Event page's price line, absent when unknown.
           'price', e.price,
           -- Who it's for by age as a source said it, "21+" or "Ages 6–14" (inside-cards 30): the Event page's price
           -- line and the Town card's time line show it like a LEGO box's "18+", nothing when unknown.
           'ages', e.ages,
           -- Where it is on the map, or at no one place (Online, a bare town, several places): what its page's Map and
           -- a held card's View on Map do, known with the card, offline too (inside-cards 19, review).
           'lat', e.lat,
           'lng', e.lng,
           'no_place', e.no_place,
           -- What it is, in one to three words (event-card 05).
           'what', e.what,
           -- Whether it's a real happening, the one meaning of live and "Now" (town-feed 41).
           'live_kind', private.is_live_kind(e.what, e.title, e.importance, e.all_day, e.start_time, e.event_date, e.end_at,
                                             e.sport is not null and e.team_ids is not null),
           -- The newest of those friends' Going, which brings a seen card back (town-feed 41).
           'friends_going_at', fg.last_at,
           -- The page it was found on, the Event page's link under About (Jesse, 2026-10-27).
           'source_url', e.source_url,
           -- A game between two teams (game-card 01): its teams, host first, its final, live score and plays.
           'game', private.event_game(e.sport, e.team_ids, e.occasion)
                     || jsonb_build_object('final', e.final_score, 'live', e.live_score, 'plays', e.scoring_plays),
           -- Up to three friends Going, newest Going first (town-feed 28).
           'friends_going', coalesce(fg.people, '[]'::jsonb),
           -- How its series repeats ("Every Sunday"), the Event page's day row from every door (inside-cards 23).
           'recurrence', sr.recurrence)
  from ev e
  left join public.clubs c on c.id = e.group_id
  left join private.friends_going(p_events) fg on fg.event_id = e.id
  left join private.series_repeats(p_events) sr on sr.id = e.id
  cross join hosts h
$$;

-- supabase/town_feed.sql: the score's points, routine, live order, the top five and the Score line.
-- The same creator never twice in a row (BP app town-feed 66, Jesse 2026-11-13). Takes the Town feed's cards in their
-- order, each as its creator (a number per creator) and its lane (0 live and the top five on top, 1 Events and posts, 2 News), and gives
-- back the order to show them in, as places in that list. Every spot keeps its lane, so live stays on top and News keeps
-- its spots. Each spot takes the first card of its lane not yet placed whose creator isn't the one above, so a card
-- moves down only past the next creator's card. A pair still touching after that (one creator all that's left at the
-- bottom, or a story's spot after its own place's Event) trades one of its two cards with the nearest card of the same
-- lane, within 20 spots, that sits between two others there: the shortest move first, below first. The first pass
-- doesn't look ahead to a story's spot, so now and then it leaves more touching than the order it was given; that order
-- gets the same trades too, and the one with fewer touching wins (the first pass's on a tie). One creator with more than
-- half a lane still touches: no card is left out.
create or replace function private.never_two_in_a_row(p_who int[], p_lane int[])
returns int[]
language plpgsql
immutable strict
set search_path = ''
as $$
declare
  n int := coalesce(array_length(p_who, 1), 0);
  used boolean[] := array_fill(false, array[n]);
  pick int[] := array_fill(0, array[n]);
  -- Per lane, where its cards not yet placed start.
  first_of int[] := array[1, 1, 1];
  lane int;
  prev int;
  j int;
  take int;
  spare int;
  m int;
  held int;
  greedy int[];
  best int[];
  fewest int;
  touching int;
begin
  for pos in 1..n loop
    lane := p_lane[pos];
    take := null;
    spare := null;
    j := first_of[lane + 1];
    while j <= n loop
      if not used[j] and p_lane[j] = lane then
        spare := coalesce(spare, j);
        if prev is null or p_who[j] <> prev then
          take := j;
          exit;
        end if;
      end if;
      j := j + 1;
    end loop;
    -- Every spot has a card of its lane left: a lane has as many cards as spots.
    take := coalesce(take, spare);
    used[take] := true;
    pick[pos] := take;
    prev := p_who[take];
    while first_of[lane + 1] <= n and (used[first_of[lane + 1]] or p_lane[first_of[lane + 1]] <> lane) loop
      first_of[lane + 1] := first_of[lane + 1] + 1;
    end loop;
  end loop;

  greedy := pick;
  for round in 1..2 loop
    pick := case when round = 1 then greedy else array(select generate_series(1, n)) end;
    -- 20 spots each way: twice the longest move on the live feed (10, 2026-11-13), and a feed one creator fills stays
    -- quick. Each check is plain arithmetic, no query.
    for k in 2..n loop
      continue when p_who[pick[k]] <> p_who[pick[k - 1]];
      <<pair>>
      for d in 1..20 loop
        foreach j in array array[k, k - 1] loop
          foreach m in array array[j + d, j - d] loop
            -- Only a card of the same lane from someone else can go there.
            continue when m < 1 or m > n or p_lane[m] <> p_lane[j] or p_who[pick[m]] = p_who[pick[j]];
            held := pick[m];
            pick[m] := pick[j];
            pick[j] := held;
            exit pair when (m = 1 or p_who[pick[m]] <> p_who[pick[m - 1]])
                       and (m = n or p_who[pick[m]] <> p_who[pick[m + 1]])
                       and (j = 1 or p_who[pick[j]] <> p_who[pick[j - 1]])
                       and (j = n or p_who[pick[j]] <> p_who[pick[j + 1]]);
            pick[j] := pick[m];
            pick[m] := held;
          end loop;
        end loop;
      end loop;
    end loop;
    touching := 0;
    for k in 2..n loop
      if p_who[pick[k]] = p_who[pick[k - 1]] then
        touching := touching + 1;
      end if;
    end loop;
    if fewest is null or touching < fewest then
      best := pick;
      fewest := touching;
    end if;
  end loop;
  return best;
end;
$$;
revoke execute on function private.never_two_in_a_row(int[], int[]) from public;
grant execute on function private.never_two_in_a_row(int[], int[]) to anon, authenticated;

drop function if exists private.town_feed(timestamptz, boolean, uuid[], boolean);
drop function if exists private.town_feed(timestamptz, boolean, uuid[], boolean, int, uuid[]);

-- p_top_seed (town-feed 73): the open's roll, which the app makes new after an hour or more away. With one, the feed
-- starts with the top five (`top_pick`), the same five for every read with that roll; none (an older app, the Block
-- Party tab, Later Events), no top. p_last_top: the last roll's first cards (live ones, then its top's first), none
-- of which leads the next one.
create function private.town_feed(p_now timestamptz, p_news boolean, p_only uuid[] default null,
                                             p_later boolean default false, p_top_seed int default null,
                                             p_last_top uuid[] default null)
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
    select '{"interest":3,"friend":3,"follow":3,"new":2,"importance":0.75,"soonHalf":7,"newHalf":24,"acted":0.4,"notInterested":0.3,"repeatHost":0.5,"repeatCampus":0.8,"repeatKind":0.8,"seen":0.6,"seenFloor":0,"town":1.5,"townMiles":4.5,"meeting":0.3,"liveMax":3,"liveHours":12,"newsEvery":5,"top":5,"topFrom":8,"topMine":4,"topYours":2,"topDays":7,"topSoonHalf":14,"topRepeat":0.5,"noAbout":0.5,"noPlace":0.5,"aboutMin":30}'::jsonb as w
  ),
  town as (
    select 'America/Chicago'::text as zone,
           (p_now at time zone 'America/Chicago')::date as today,
           -- Downtown St. Joseph: everyone counts as St. Joseph until a second town opens (town-feed 41).
           45.5641::float8 as lat, -94.3183::float8 as lng,
           -- The town's own teams, whose games a Sports pick follows (BP app onboarding 48). A new town needs its own.
           array['saint-benedict', 'saint-johns', 'kennedy', 'st-johns-prep']::text[] as own_teams
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
  -- posted it), and never routine business (importance 1): a heart on a council meeting lifts nothing.
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
    where coalesce(e.club_id::text, e.source_name) is not null and coalesce(e.importance, 3) > 1
  ),
  -- The kinds of Events the caller went Going to in those 90 days (town-feed 73): their tagger's interests, not where
  -- they were (a campus or a school says where, not what). They make the top five's Events of that kind yours.
  my_kinds as (
    select coalesce(array_agg(distinct k), '{}'::text[]) as kinds
    from public.event_rsvps r
    join public.club_events e on e.id = r.event_id
    cross join lateral unnest(case when e.interests_tagged_at is not null then e.interests
                                   else array[e.category] end) as k
    where r.user_id = auth.uid() and r.created_at > p_now - interval '90 days' and coalesce(e.importance, 3) > 1
      and k not in ('campus', 'college', 'high_school', 'middle_school')
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
  -- "Cathedral Volleyball (girls)" (`ord` 1), then the activities of a whole school followed that play under
  -- another team's name (a co-op, another school's team), named by the school (`ord` 3). The school's other
  -- activities need no row: their Events name the school, which `my_schools` matches with the same label (2).
  -- Read once, each name through sport_base once (town-feed 67): `real_events` asks activity_has_event only
  -- about an activity whose team the Event names and whose name could be the Event's. Asked about every
  -- activity of a followed school for every Event (45 x 1,421), it took 16 s and the feed timed out.
  my_activities as materialized (
    select m.a, m.label, m.ord, coalesce((m.a).fielded_by, (m.a).team_id) as fielder, (m.a).coop as coop,
           private.sport_base((m.a).name) as base, private.sport_gender((m.a).name) as gender
    from (
      select a, t.short_name || ' ' || a.name as label, 1 as ord
      from public.town_follows f
      join public.team_activities a on a.id = f.target_id
      join public.teams t on t.id = a.team_id
      where f.follower_id = auth.uid() and f.target_type = 'activity'
      union all
      select a, t.short_name, 3
      from public.town_follows f
      join public.teams t on t.uuid = f.target_id
      join public.team_activities a on a.team_id = t.id
      where f.follower_id = auth.uid() and f.target_type = 'team'
        and (a.fielded_by is not null or a.coop is not null)) m
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
  -- Each City's name on its Events: an importance 1 Event of one is a meeting (follows 03).
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
           fl.team as school_team,
           mt.is_meeting,
           mt.board as meeting_board
    from public.club_events e
    -- The teams the Event names and its sport or activity name, through sport_base once (`offset 0` as below)
    -- and only for a caller who follows something of the schools: most don't, and no name is read for them.
    cross join lateral (select x.n, array_append(coalesce(e.team_ids, '{}'), e.activity_team) as teams,
                               case when f.follows then private.sport_base(x.n) end as base,
                               case when f.follows then private.sport_gender(x.n) end as gender
                        from (select coalesce(e.sport, e.activity_name) as n) x,
                             (select exists (select 1 from my_activities) as follows) f
                        offset 0) v
    -- The activity or school you follow that this Event is of, by name; null when none. One pick: an
    -- activity you starred, then a school you follow that the Event names, then a school you follow whose
    -- activity plays in it under another team's name; by label within each, so a card keeps its name.
    -- Only an Event naming a school can be one's: the rest skip the activity match. The inner `case` keeps
    -- the order: activity_has_event's team rule and activity_may_have first, both cheap, then the function.
    -- With it, the side of the game it plays as (daily-tab 27): the co-op's when the co-op plays, else its own; the
    -- first pick that is a side, as a school can be named only as the Event's `activity_team` (ROCORI's calendar lists
    -- the River Lakes co-op's games).
    cross join lateral (select case when e.team_ids is not null or e.activity_team is not null then
      (select array[(array_agg(x.label order by x.ord, x.label))[1],
                    (array_agg(x.team order by x.ord, x.label) filter (where x.team = any(e.team_ids)))[1]]
       from (select m.label, m.ord,
                    case when m.coop = any(v.teams) then m.coop else m.fielder end as team
             from my_activities m
             where case when (m.fielder = any(v.teams) or m.coop = any(v.teams))
                         and private.activity_may_have(m.base, m.gender, v.n, v.base, v.gender, e.sport is null)
                        then public.activity_has_event(m.a, e) end
             union all
             select s.label, 2, s.id from my_schools s where s.id = any(v.teams)) x
      ) end as pick
                        offset 0) fp
    cross join lateral (select fp.pick[1] as followed, fp.pick[2] as team) fl
    cross join lateral (select
      regexp_match(lower(btrim(e.start_time)), '^(\d{1,2})(?::(\d{2}))?\s*([ap])\.?m\.?$') as m12,
      regexp_match(btrim(e.start_time), '^(\d{1,2}):(\d{2})(?::\d{2})?$') as m24
      -- Read once per Event: without offset 0 Postgres pastes both reads into each of the start's
      -- eleven uses, about 0.2 s a feed (2026-10-31).
      offset 0) t
    -- A City meeting, and the board it belongs to (null for one that matches no board).
    cross join lateral (select m.is_meeting, case when m.is_meeting then public.meeting_board(e) end as board
                        from (select coalesce(e.importance = 1, false)
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
      -- Nobody can sign up any more (signups_closed_by; BP app watch-every-place 49): out of the feed and its later list,
      -- except for whoever is Going or Hearted it.
      and (e.signups_closed_by is null
           or exists (select 1 from public.event_rsvps r where r.event_id = e.id and r.user_id = auth.uid())
           or exists (select 1 from public.event_likes l where l.event_id = e.id and l.user_id = auth.uid()))
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
           -- Or picked Town meetings, for one the tagger calls a meeting (onboarding 21).
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
                    when r.live_score is not null then interval '2 hours' else interval '0' end as leaves_at,
           -- How long it runs, start to end, for what can lead as live (town-feed 56).
           coalesce(r.end_at - (r.event_date + make_interval(mins => r.start_minutes)) at time zone town.zone,
                    case when r.team_ids is not null then interval '3 hours' else interval '2 hours' end) as runs_for
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
      -- Nor one a business you muted made with its host (town-feed 58): a place's mute is its name.
      and not exists (select 1 from muted m join public.places pl on pl.name = m.host
                      where pl.entry_id = any(e.collab_entry_ids))
      and not exists (select 1 from hidden h where h.series = lower(btrim(e.title)) || '|' || e.host)
      -- Under 18 never sees what its place keeps to 18+ or 21+ (ticket 19).
      and (me.adult or not private.adults_only(e.place_entry_id, e.club_id, e.title || ' ' || coalesce(e.description, '')))
      -- Nor an Event whose age mark starts at 18 or older: a host's Filter can say 19+ or Ages 18–30 (town-feed 52).
      and (me.adult or coalesce((regexp_match(e.ages, '^(?:Ages )?(\d+)(?:\+|–)'))[1]::int, 0) < 18)
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
           -- A game's side the caller follows, as game.mine (daily-tab 27): the app's Following row says "vs" the
           -- other side and shows this one's logo.
           coalesce(case when s.school_team is not null and jsonb_typeof(ec.card->'game') = 'object'
                         then jsonb_set(ec.card, '{game,mine}',
                                        (select to_jsonb(t.uuid) from public.teams t where t.id = s.school_team)) end,
                    ec.card) as card,
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
           coalesce(gl.lean, 0) as gender_lean,
           -- The part of a long Event on now, else its next (happening-now 04): an artist talk at 3 PM.
           prt.title as part_title, prt.starts_at as part_start, prt.ends_at as part_end
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
        -- A business it was made with (town-feed 58): following either one lifts it, once.
        select pl.name, 2 from my_places pl where pl.entry_id = any(s.collab_entry_ids)
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
    -- Read as the Event page reads them (get_event_parts): only a live part, a real happening by its title under 12
    -- hours (town-feed 41); one that is an Event of its own (same_as) has its own card; no stated end, 1 hour.
    left join lateral (
      select p.title, p.starts_at, p.ends_at
      from public.get_event_parts(s.id) p
      where p.live and p.ends_at > p_now
      order by p.starts_at, p.title
      limit 1) prt on true
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
           -- never routine business (importance 1). A Sports pick follows the town's own teams' games (BP app onboarding
           -- 48, Jesse 2026-11-19: "yes add fix"); their followers-only games stay followers only.
           case when c.followed is not null
                     or (coalesce(c.importance, 3) <> 1
                         and (c.tapped_n > 0
                              or ('watch_sports' = any(c.matched) and c.team_ids && (select t.own_teams from town t))))
                then (w->>'follow')::float8 else 0 end as follow_pts,
           case when c.is_new then (w->>'new')::float8 else 0 end as new_pts,
           -- Importance, the two agents' 1 to 5 (feed-learns 04): everyone's starting point, 0 to 3 points; one not
           -- rated yet counts as 3.
           (w->>'importance')::float8 * (coalesce(c.importance, 3) - 1) as importance_pts,
           power(0.5, c.days_away / (w->>'soonHalf')::float8) as soon,
           -- Going sinks it; a Heart doesn't (inside-cards 16): you hearted it to keep it in sight.
           case when c.going then (w->>'acted')::float8 else 1 end as acted,
           -- A City meeting, for those who follow its City or board, sits lower (town-feed 27).
           case when c.is_meeting then (w->>'meeting')::float8 else 1 end as meeting_x,
           -- What it is and where (town-feed 78; Jesse, 2026-11-19: "things don't have information ... are lower in the
           -- feed"): no About to speak of, × 0.5; no place, × 0.5. A game's card says what it is.
           case when c.team_ids is null and length(btrim(coalesce(c.description, ''))) < (w->>'aboutMin')::int
                then (w->>'noAbout')::float8 else 1 end
             * case when nullif(btrim(c.location), '') is null and c.place_entry_id is null
                    then (w->>'noPlace')::float8 else 1 end as facts_x,
           -- A host you said Not interested to (ticket 21): × 0.3 for its other Events, with no fade
           -- (town-feed 36). A report hides its item only and lowers nothing (town-feed 22).
           case when exists (select 1 from hidden h where h.lowers and h.host <> '' and h.host = c.host)
                then (w->>'notInterested')::float8 else 1 end as hidden_x,
           case when c.miles <= (w->>'townMiles')::float8 then (w->>'town')::float8 else 1 end as town_x,
           -- Each open you've seen it, with no floor (town-feed 41, 55). On its own day a real happening counts
           -- only that day's, and a friend's Going since you saw it brings it back: both until you see it again.
           greatest((w->>'seenFloor')::float8, power((w->>'seen')::float8,
             case when c.seen_times is null or c.friend_at > c.seen_at then 0
                  when c.live_kind and c.days_off = 0 then c.seen_today
                  else c.seen_times end)) as seen_x
    from counted c, weights
    -- Only for those who picked Middle school, follow it, have a friend Going, or are Going to it or Hearted it.
    where (not c.young
       or 'middle_school' = any(c.matched)
       or c.followed is not null or c.friends_n > 0 or c.going or c.hearted)
      -- Routine business (importance 1: a church's own round, a club's meeting) reaches only those who follow its place,
      -- host or page, have a friend Going, or are Going or Hearted it; its page still lists it (town-feed 78). A City
      -- meeting has its own rule above.
      and (coalesce(c.importance, 3) <> 1 or c.is_meeting
           or c.followed is not null or c.friends_n > 0 or c.going or c.hearted)
  ),
  totals as (
    select c.*,
           (1 + c.friend_pts + c.follow_pts + c.interest_pts + c.gender_pts + c.new_pts + c.importance_pts)
             * c.soon * c.acted * c.hidden_x * c.meeting_x * c.town_x * c.seen_x * c.facts_x as base,
           -- Which pool it is in, for the Score line: yours or discovery; your own Going in neither.
           case when c.going then null
                else c.friend_pts + c.follow_pts > 0 end as yours,
           -- A real happening on right now that runs under 12 hours (town-feed 41, 56): it stays on top while it's on,
           -- however often you've seen it.
           p_only is null and not p_later and c.live_kind and c.starts_at <= p_now and p_now < c.leaves_at
             and c.final_score is null and c.hidden_x = 1
             and c.runs_for < make_interval(hours => (select (w->>'liveHours')::int from weights))
           -- Or a part of it is on (happening-now 04): the Event's card is live while its artist talk is.
           or coalesce(p_only is null and not p_later and c.part_start <= p_now and p_now < c.part_end
                       and c.final_score is null and c.hidden_x = 1
                       and c.part_end - c.part_start < make_interval(hours => (select (w->>'liveHours')::int from weights)),
                       false) as live_ok,
           -- The same, starting within the hour (happening-now 02): it takes the top after what's on now.
           p_only is null and not p_later and c.live_kind and p_now < c.starts_at and c.starts_at <= p_now + interval '1 hour'
             and c.final_score is null and c.hidden_x = 1
             and c.runs_for < make_interval(hours => (select (w->>'liveHours')::int from weights))
           or coalesce(p_only is null and not p_later and p_now < c.part_start and c.part_start <= p_now + interval '1 hour'
                       and c.final_score is null and c.hidden_x = 1
                       and c.part_end - c.part_start < make_interval(hours => (select (w->>'liveHours')::int from weights)),
                       false) as soon_ok,
           -- The reason: something you follow says so first (school-activities 03), then a friend
           -- Going, a host you've been into, New, an interest. A Sports pick's own-team game says its interest.
           case when c.followed is not null then 'follow'
                when c.friends_n > 0 then 'friend'
                when c.tapped_n > 0 and coalesce(c.importance, 3) <> 1 then 'tapped'
                when c.is_new then 'new'
                when c.interest_pts > 0 then 'interest' end as lift
    from scored c
  ),
  -- Town news (ticket 35): a place's specials, deals and new things, and town news, published in the
  -- last 7 days, road work and closures too, only with a post to open. It leaves after 7 days, or at the end
  -- of the day it's about when that day isn't behind its publish day. Only for an app that asks
  -- (p_news): an older one can't read a row without a date.
  news as (
    -- Its time is when the place posted it, when the social watch knew (town-feed 70; Jesse, 2026-11-16: it leaves 7
    -- days after the post and sorts newest post first), else when it went up. A story held back to go up later (a
    -- closing that waits for its day) counts from that day, so it never reads old on its first day.
    select b.id, b.title, b.blurb, b.category, b.source_name, b.source_url, a.at as published_at, b.place_entry_id,
           l.leaves_at,
           (select array_agg(x order by x) from unnest(b.interests) x where x = any(me.interests)) as matched
    from public.board_items b
    cross join town
    cross join me
    -- A story stays until midnight after the day its words end, else the day it is about, up to 30 days. With neither,
    -- 7 days (Jesse, 2026-11-06; BP app town-feed 49). write_judged.news_lasts_until says the same for its repeats.
    cross join lateral (
      select case when b.published_at > b.created_at + interval '1 hour' then b.published_at
                  else least(b.posted_at, b.published_at) end as at
    ) a
    cross join lateral (
      select case when d.last_day is null then a.at + interval '7 days'
                  else least(a.at + interval '30 days', (d.last_day + 1)::timestamp at time zone town.zone) end as leaves_at
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
    select e.id, e.title, e.location, e.image_url, e.image_aspect, e.more_photos, e.friends_only, e.created_at,
           e.submitted_by, e.tagged, e.at_names, e.submitted_by = auth.uid() as mine
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
  -- Live first (town-feed 41, 56): up to 3, what you're Going to, then the most yours (interests, friends Going,
  -- following, gender, your town), then most Going, then importance, then the latest to start. Then what starts
  -- within the hour, soonest first, then the same (happening-now 02).
  live_now as (
    select t.id, row_number() over (order by t.live_ok desc, case when not t.live_ok then case when p_now < t.part_start then t.part_start else t.starts_at end end,
                                             t.going desc,
                                             (1 + t.friend_pts + t.follow_pts + t.interest_pts + t.gender_pts) * t.town_x desc,
                                             t.going_n desc, coalesce(t.importance, 3) desc, t.starts_at desc, t.id) as nth
    from totals t
    where t.live_ok or t.soon_ok
  ),
  -- The top five (town-feed 73; Jesse, 2026-11-17: "feel like there's big events going on", "make it personable", "mixed
  -- up a little bit too. Each time"). Real happenings from today to 7 days ahead, not on top as live already. Big first:
  -- importance, a friend Going and the Going count, each a doubling; yours (an interest, or a kind you went Going to) two
  -- steps more (town-feed 76; Jesse, 2026-11-17: "doesn't necessarily have to be a big event. just meant for that
  -- person"), so what you like comes before what's big; soonest a little; one that repeats (a weekly class, bingo night) counts half, as no big night out.
  -- Going, seen, Not interested and a meeting sink it as they sink the rest.
  top_pool as (
    select t.id, x.mine,
           lower(btrim(coalesce(nullif(t.card->>'club_name', ''), nullif(t.card->>'source_name', ''), t.host))) as creator,
           power(2, coalesce(t.importance, 3) + case when x.mine then (w->>'topYours')::float8 else 0 end + case when t.friends_n > 0 then 1 else 0 end
                    + coalesce(t.going_n, 0)::float8 / (coalesce(t.going_n, 0) + 10))
             * power(0.5, t.days_away / (w->>'topSoonHalf')::float8)
             * t.acted * t.hidden_x * t.meeting_x * t.town_x * t.seen_x * t.facts_x
             * case when lb.recurrence is not null then (w->>'topRepeat')::float8 else 1 end as weight
    from totals t
    left join labels lb on lb.series = t.series
    cross join weights
    cross join town
    cross join lateral (select t.matched is not null or t.tags && (select k.kinds from my_kinds k) as mine) x
    where p_top_seed is not null and p_only is null and not p_later
      and t.live_kind and t.final_score is null
      and t.event_date <= town.today + (w->>'topDays')::int
      and not exists (select 1 from live_now l where l.id = t.id and l.nth <= (w->>'liveMax')::int)
  ),
  -- The best 8 yours and the best 8 not yours (town-feed 76: when the best 8 were all yours, the spot yours can't take
  -- stood empty), one per creator, each mixed up a little by the roll: its weight moves up to a quarter either way, so
  -- Events about as good trade places from roll to roll, and one twice as good (big, or yours) always stays ahead of
  -- one that isn't. The same roll mixes the same.
  top_best as (
    select b.*, b.weight * (0.75 + 0.5 * ('x' || substr(md5(b.id::text || ':' || p_top_seed), 1, 8))::bit(32)::bigint
                                      / 4294967296.0) as key
    from (select c.*, row_number() over (partition by c.mine order by c.weight desc, c.id) as nth
          from (select p.*, row_number() over (partition by p.creator order by p.weight desc, p.id) as of_creator
                from top_pool p) c
          where c.of_creator = 1 and c.weight > 0) b
    where b.nth <= (select (w->>'topFrom')::int from weights)
  ),
  -- Five of them, the highest after the mix, at most 4 yours, so one spot is the town's biggest (town-feed 76); the
  -- last roll's first goes to the back.
  top_pick as (
    select y.id, row_number() over (order by coalesce(y.id = any(p_last_top), false), y.key desc, y.id) as top
    from (select y.* from (select b.*, row_number() over (partition by b.mine order by b.key desc, b.id) as of_mine
                           from top_best b) y
          where not y.mine or y.of_mine <= (select (w->>'topMine')::int from weights)
          order by y.key desc, y.id
          limit (select (w->>'top')::int from weights)) y
  ),
  pool as (
    -- The campus's Events space as one host's (onboarding 21): Campus lifts them, and CSB and SJU's
    -- dozen calendars can't fill the top of the feed between them.
    select t.id, case when 'campus' = any(t.tags) then 'campus' else t.host end as host, t.base, t.sort_at, t.title,
           coalesce(t.category, t.id::text) as kind, l.nth as live, tp.top,
           -- Who the card says made it (town-feed 66): its group, else its source, else the neighbour who posted it.
           lower(btrim(coalesce(nullif(t.card->>'club_name', ''), nullif(t.card->>'source_name', ''), t.host))) as creator
    from totals t
    left join live_now l on l.id = t.id and l.nth <= (select (w->>'liveMax')::int from weights)
    left join top_pick tp on tp.id = t.id
    union all
    -- Posts among the Events, their poster as their host, so a second one from the same neighbour
    -- counts half (the spacing rule below).
    select p.id, p.submitted_by::text, p.base, p.created_at, p.title, p.id::text, null::bigint, null::bigint,
           p.submitted_by::text
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
    select s.id, s.spacing, s.live, s.top, s.creator,
           -- Later Events (town-feed 23) by their start, not their points. Live, then the top five (town-feed 73).
           row_number() over (order by case when p_later then s.sort_at end, s.live nulls last, s.top nulls last,
                                       s.base * s.spacing desc,
                                       s.sort_at, s.title, s.id) as nth
    from spaced s
  ),
  first_cards as (
    select (select (w->>'newsEvery')::int from weights) as every, (select count(*) from ordered) as events,
           -- With no roll, none: live cards count toward the 5th spot, as they always have.
           case when exists (select 1 from ordered o where o.top is not null)
                then (select count(*) from ordered o where o.live is not null or o.top is not null) else 0 end as k
  ),
  -- Events and posts leave every 5th spot open for News you haven't seen; with none left the next card moves up. Live
  -- cards and the top five (`k` of them, town-feed 73) come first with no News between them, and the count starts
  -- after them. They share the live lane, so the creator rule below never moves one out of the top.
  spots as (
    select x.id, x.spacing, x.lane, x.creator, row_number() over (order by x.place, x.id)::int as spot
    from (
      select o.id, o.spacing, case when o.live is null and o.top is null then 1 else 0 end as lane, o.creator,
             case when o.nth <= c.k then o.nth
                  else o.nth + (o.nth - c.k - 1) / (c.every - 1) end as place
      from ordered o
      cross join first_cards c
      union all
      -- Only as many as the Events leave spots for, so never two together; the rest wait for a later open. A
      -- town with next to no Events shows what it has.
      select n.id, 1::float8, 2, lower(btrim(n.source_name)), c.k + n.nth * c.every
      from news_scored n
      cross join first_cards c
      where c.events - c.k < c.every - 1 or n.nth <= (c.events - c.k) / (c.every - 1)
    ) x
  ),
  -- The same creator never twice in a row (town-feed 66, Jesse 2026-11-13): the Town feed only. The Block Party tab
  -- (p_only) may show one twice, and Later Events (p_later) keep their date order.
  in_a_row as (
    select array_agg(s.id order by s.spot) as ids,
           private.never_two_in_a_row(array_agg(s.who order by s.spot), array_agg(s.lane order by s.spot)) as pick
    from (select s.id, s.spot, s.lane, dense_rank() over (order by coalesce(s.creator, s.id::text))::int as who
          from spots s) s
    where p_only is null and not p_later
  ),
  placed as (
    select s.id, s.spacing, coalesce(r.spot, s.spot) as spot
    from spots s
    left join (select a.ids[k.pick] as id, k.spot::int as spot
               from in_a_row a, unnest(a.pick) with ordinality k(pick, spot)) r on r.id = s.id
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
           -- A Sports pick's own-team game counts as a follow (onboarding 48), never as tapped.
           'follow', case when e.followed is null and e.tapped_n > 0 and coalesce(e.importance, 3) <> 1 then 0 else e.follow_pts end,
           'tapped', case when e.followed is null and e.tapped_n > 0 and coalesce(e.importance, 3) <> 1 then e.follow_pts else 0 end,
           'town', e.town_x, 'seen', e.seen_x, 'facts', e.facts_x, 'live', e.live_ok,
           'popular', 0, 'size', 0, 'sizeStep', 1, 'importance', e.importance_pts,
           'daysAway', round(e.days_away::numeric, 2), 'soon', round(e.soon::numeric, 4),
           'acted', e.acted, 'notInterested', e.hidden_x, 'spacing', p.spacing,
           'newSpot', e.is_new, 'pool', case when e.yours then 'yours' when not e.yours then 'discovery' end,
           'total', round((e.base * p.spacing)::numeric, 4),
           -- The top five's (town-feed 73): its place among them, and its weight there.
           'top', tk.top, 'topWeight', round(tw.weight::numeric, 4),
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
         -- The Event card (codebase-health-2 02): its game, host picture, friends Going, link and the rest. With a part
         -- on now or still to come, that part (happening-now 04), for its time line: "Now · Artist talk".
         case when e.part_title is null then e.card
              else e.card || jsonb_build_object('part', jsonb_build_object(
                'title', e.part_title, 'starts_at', e.part_start, 'ends_at', e.part_end, 'live', true)) end,
         p.spot
  from totals e
  join placed p on p.id = e.id
  left join top_pick tk on tk.id = e.id
  left join top_pool tw on tw.id = e.id
  -- The group that posted it, else, for a found Event, the group it was found for.
  left join public.clubs c on c.id = e.group_id
  left join labels l on l.series = e.series
  union all
  -- A news item's row: its own columns, nulls and zeros for the rest. Its post's own photo, when the photo step
  -- kept one (town-feed 53), is its image_url, and its shape rides in poster as {"aspect": w / h}, so the card
  -- takes the photo's shape before it loads; with "flyer" when it is the post's own graphic and "photos" when the
  -- post has several (private.news_photo, town-feed 77).
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
         np.poster,
         null::jsonb, s.spot
  from news_scored n
  join placed s on s.id = n.id
  left join lateral private.news_photo(n.id) np on true
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
         -- and the post's own: its photo's shape, which sets the card's before the photo loads, its photos after the
         -- first in the poster's order (town-feed 46), whether only friends see it, which its card says, and the
         -- @names in its words still good for you (town-feed 60).
         pp.poster || jsonb_strip_nulls(jsonb_build_object('aspect', p.image_aspect, 'more_photos', p.more_photos,
                                                           'friends_only', p.friends_only,
                                                           'at_names', private.post_at_names(p.at_names),
                                                           -- Its comments as its sheet lists them (backlog 38).
                                                           'comments', private.comment_count(p.id))),
         null::jsonb,
         s.spot
  from posts_scored p
  join placed s on s.id = p.id
  cross join lateral (select private.post_poster(p.submitted_by, p.tagged) as poster) pp
  )
  select r.id, r.title, r.location, r.image_url, r.source_name, r.created_at, r.recurrence, r.leaves_at,
         r.reason, r.reason_name, r.score, r.heart_count, r.hearted, r.saved, r.place_picture, r.description,
         r.club_id, r.in_club, r.kind, r.source_url, r.poster, r.card
  from feed_rows r
  order by r.spot;
$$;
revoke execute on function private.town_feed(timestamptz, boolean, uuid[], boolean, int, uuid[]) from public;
grant execute on function private.town_feed(timestamptz, boolean, uuid[], boolean, int, uuid[]) to anon, authenticated;

-- The Town feed, as every app reads it: the body is private.town_feed's.
drop function if exists public.get_town_feed(timestamptz, boolean, boolean);
drop function if exists public.get_town_feed(timestamptz, boolean, boolean, int, uuid[]);

-- p_top_seed and p_last_top: the open's roll and the last roll's first cards (town-feed 73); an app that sends neither
-- gets the feed as before.
create function public.get_town_feed(p_now timestamptz default now(), p_news boolean default false,
                                      p_later boolean default false, p_top_seed int default null,
                                      p_last_top uuid[] default null)
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
  select * from private.town_feed(p_now, p_news, null, p_later, p_top_seed, p_last_top);
$$;
grant execute on function public.get_town_feed(timestamptz, boolean, boolean, int, uuid[]) to anon, authenticated;
