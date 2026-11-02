-- The Event card (BP app codebase-health-2, ticket 01): everything one Event shows wherever it appears,
-- worked out in one place, so a new Event field is one change here and shows on every tab. The Town
-- feed, You's Going, Saved and the bell each built their own, and on 2026-10-27 the found link reached
-- only the Town feed's.
--
-- private.event_cards takes a list of Event ids, as private.friends_going does, so a read asks once for
-- all of its rows. Its keys are the Town feed's column names, with `going` for the feed's `rsvpd`, and
-- its values are the Town feed's (private.town_feed, 20261102155729_feed_once_per_open.sql): the group
-- that posted it, else the group a found Event was found for; the host picture; the game with its final,
-- live score and plays; the found link. Security invoker: a caller gets a card only for an Event the
-- read rules let them see.
--
-- get_my_going sends it as a new last column, `card`, beside its old columns, which builds on phones
-- now still read (expand; ticket 03 drops them). It is 20261028135225_event_photos_my_going.sql line for
-- line but for that column, read from the card source once for all of the rows, and the old picture,
-- Going count and friends Going taken from the card rather than worked out twice. A new column changes
-- the return type, so it is dropped and made again.

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
           -- The page it was found on, the Event page's link under About (Jesse, 2026-10-27).
           'source_url', e.source_url,
           -- A game between two teams (game-card 01): its teams, host first, its final, live score and plays.
           'game', private.event_game(e.sport, e.team_ids, e.occasion)
                     || jsonb_build_object('final', e.final_score, 'live', e.live_score, 'plays', e.scoring_plays),
           -- Up to three friends Going, newest Going first (town-feed 28).
           'friends_going', coalesce(fg.people, '[]'::jsonb))
  from ev e
  left join public.clubs c on c.id = e.group_id
  left join private.friends_going(p_events) fg on fg.event_id = e.id
  cross join hosts h
$$;
revoke execute on function private.event_cards(uuid[]) from public;
grant execute on function private.event_cards(uuid[]) to anon, authenticated;

drop function if exists public.get_my_going(date, date);

create function public.get_my_going(p_from date, p_to date)
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
  cancelled boolean,
  place_picture jsonb,
  description text,
  friends_going jsonb,
  card jsonb
)
language sql
stable
security invoker
set search_path = public
as $$
  with mine as (
    select e.id, e.title, e.event_date, e.start_time, e.location, e.image_url, e.category,
           c.name as club_name, e.source_name, e.end_at, e.all_day, e.created_at,
           e.cancelled_at, e.place_entry_id, e.description
    from public.event_rsvps r
    join public.club_events e on e.id = r.event_id
    left join public.clubs c on c.id = e.club_id
    where r.user_id = auth.uid()
      and e.status = 'approved'
      and e.kind = 'event'
      and e.event_date between p_from and p_to
      and (e.submitted_by is not null or e.source_name is not null)
  )
  select m.id, m.title, m.event_date, m.start_time, m.location, m.image_url, m.category,
         m.club_name, m.source_name, m.end_at, m.all_day, m.created_at,
         (ec.card->>'going_count')::int as going_count,
         m.cancelled_at is not null as cancelled,
         ec.card->'place_picture' as place_picture,
         m.description,
         ec.card->'friends_going' as friends_going,
         -- The Event card, asked once for all of the rows.
         ec.card
  from mine m
  left join private.event_cards(array(select x.id from mine x)) ec on ec.id = m.id
  order by m.event_date, m.title, m.id
$$;

grant execute on function public.get_my_going(date, date) to authenticated;
