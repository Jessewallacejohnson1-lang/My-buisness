-- How an Event repeats, said from every door to its page (BP app inside-cards 23). Only the Town feed worked out
-- "Every Sunday" (its `labels`), on its own row, so an Event page opened from the You tab, the bell, a chat, a Town
-- page or a City board's page said nothing. The Event card now carries it, and so do the Town page's and a board's
-- Event rows.

-- How each asked Event's series repeats, as the Town feed words it: its series is its title and host, as
-- private.town_feed keys them, over the feed's window (60 days back from the Town's today). A called-off date says
-- nothing: it isn't happening that week, and the feed counts only the called-off dates someone Hearted.
create function private.series_repeats(p_events uuid[])
returns table (id uuid, recurrence text)
language sql
stable
security invoker
set search_path = ''
as $$
  with asked as (
    select e.id, lower(btrim(e.title)) as title, coalesce(e.club_id::text, e.source_name, e.submitted_by::text, '') as host
    from public.club_events e
    where e.id = any (p_events) and e.cancelled_at is null
  ),
  -- Each series once, its dates read in one pass however many of its weeks were asked.
  series as (
    select a.title, a.host, public.town_feed_series_label(array_agg(x.event_date)) as recurrence
    from (select distinct s.title, s.host from asked s) a
    join public.club_events x
      on lower(btrim(x.title)) = a.title
     and coalesce(x.club_id::text, x.source_name, x.submitted_by::text, '') = a.host
    where x.status = 'approved' and x.kind = 'event' and x.cancelled_at is null
      and (x.submitted_by is not null or x.source_name is not null)
      and x.event_date >= (now() at time zone 'America/Chicago')::date - 60
    group by a.title, a.host
  )
  select a.id, s.recurrence from asked a join series s on s.title = a.title and s.host = a.host
$$;
revoke execute on function private.series_repeats(uuid[]) from public;
grant execute on function private.series_repeats(uuid[]) to anon, authenticated;

-- 20261105211111_fresh_every_open.sql but for the repeat.
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
           -- A photo of what it is, else its place's picture (event-photos 07).
           'place_picture', public.event_picture(e.id),
           -- Who puts it on, its logo first (Jesse, 2026-10-23).
           'host_picture', h.pictures -> jsonb_build_array(e.source_name, c.own_entry_id)::text,
           'description', e.description,
           -- What it is, in one to three words (event-card 05).
           'what', e.what,
           -- Whether it's a real happening, the one meaning of live and "Now" (town-feed 41).
           'live_kind', private.is_live_kind(e.what, e.title, e.draw, e.all_day, e.start_time, e.event_date, e.end_at,
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


revoke execute on function private.event_cards(uuid[]) from public;
grant execute on function private.event_cards(uuid[]) to anon, authenticated;

-- 20261028134707_campus_pages.sql but for the repeat on each Event row.
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
        order by e.event_date, e.start_time
        limit 10
      )
      select jsonb_agg(x order by x ->> 'date', x ->> 'time')
      from (
        select jsonb_build_object('id', y.id, 'title', y.title, 'date', y.event_date, 'time', y.start_time,
                                  'location', y.location, 'recurrence', r.recurrence) as x
        -- Asked once for the list (inside-cards 23).
        from y left join private.series_repeats(array(select y.id from y)) r on r.id = y.id
      ) z), '[]'::jsonb),
    'boards', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', b.id, 'name', b.name,
        'following', exists (select 1 from public.town_follows f where f.follower_id = auth.uid()
                             and f.target_type = 'board' and f.target_id = b.id),
        'next', (select jsonb_build_object('date', e.event_date, 'time', e.start_time)
                 from public.club_events e
                 where e.source_name = b.city_name and e.draw = 1 and e.status = 'approved'
                   and e.cancelled_at is null and e.event_date >= (now() at time zone 'America/Chicago')::date
                   and public.meeting_board(e) = b.id
                 order by e.event_date, e.start_time
                 limit 1)) order by b.name)
      from public.city_boards b
      where b.town = p.town and b.city_name = p.source_name), '[]'::jsonb))
  from public.town_pages p
  where p.town = p_town and p.slug = p_slug
$$;
revoke execute on function public.town_page(text, text) from public;
grant execute on function public.town_page(text, text) to anon, authenticated;

-- 20261027143913_city_pages.sql but for the repeat on each meeting.
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
    join public.club_events e on e.source_name = b.city_name and e.draw = 1
    where b.id = p_board and e.status = 'approved' and e.cancelled_at is null
      and e.event_date >= (now() at time zone 'America/Chicago')::date
      and public.meeting_board(e) = b.id
    order by e.event_date, e.start_time
    limit 20
  )
  select coalesce(jsonb_agg(x order by x ->> 'date', x ->> 'time'), '[]'::jsonb)
  from (
    select jsonb_build_object('id', y.id, 'title', y.title, 'date', y.event_date, 'time', y.start_time,
                              'location', y.location, 'recurrence', r.recurrence) as x
    -- Asked once for the list (inside-cards 23).
    from y left join private.series_repeats(array(select y.id from y)) r on r.id = y.id
  ) z
$$;
revoke execute on function public.board_meetings(uuid) from public;
grant execute on function public.board_meetings(uuid) to anon, authenticated;
