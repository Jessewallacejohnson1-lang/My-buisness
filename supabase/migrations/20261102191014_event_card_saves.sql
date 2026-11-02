-- The Event card for Saved (BP app codebase-health-2, ticket 02): get_my_saves sends each Event's card, so an
-- Event opened from Saved gets its found link, host picture and game score, as from the Town feed.
--
-- From private.event_cards (20261102174133_event_card_going.sql), as a new last column, `card`, beside the
-- old columns, which builds on phones now still read (expand; ticket 03 drops them). A new column changes
-- what it returns, so it is dropped and made again, with its grants.
--
-- It is 20261028155019_event_photos_my_saves.sql line for line but for that column, read from the card
-- source once for all of the rows, and the old Going count, Going, picture and friends Going taken from
-- the card, so nothing is worked out twice (as get_my_going does).
--
-- Roll back: `drop function public.get_my_saves(date);`, re-run 20261028155019_event_photos_my_saves.sql,
-- then grant execute on it to authenticated.

drop function if exists public.get_my_saves(date);

create function public.get_my_saves(p_from date)
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
  going boolean,
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
    from public.event_saves s
    join public.club_events e on e.id = s.event_id
    left join public.clubs c on c.id = e.club_id
    where s.user_id = auth.uid()
      and e.status = 'approved'
      and e.kind = 'event'
      and (e.event_date >= p_from or e.end_at > now())
      and (e.submitted_by is not null or e.source_name is not null)
  )
  select m.id, m.title, m.event_date, m.start_time, m.location, m.image_url, m.category,
         m.club_name, m.source_name, m.end_at, m.all_day, m.created_at,
         (ec.card->>'going_count')::int as going_count,
         (ec.card->>'going')::boolean as going,
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

grant execute on function public.get_my_saves(date) to authenticated;
