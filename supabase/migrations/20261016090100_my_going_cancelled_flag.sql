-- Your Going and your saves say which Events are called off (BP app docs/plans/watch-every-place,
-- ticket 12). The app leaves a cancelled Event out of the Agenda, the Calendar and Saved, and
-- tells the people Going once, when they next open it (Jesse, 2026-10-15), so the read still
-- returns cancelled Going: that is how the app finds whom to tell. Both functions are
-- 20261012120000_my_going_private.sql and 20261013090000_my_saves.sql line for line but for the
-- new last column, `cancelled`. A new column changes the return type, so each is dropped and
-- made again.
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
  cancelled boolean
)
language sql
stable
security invoker
set search_path = public
as $$
  select e.id, e.title, e.event_date, e.start_time, e.location, e.image_url, e.category,
         c.name as club_name, e.source_name, e.end_at, e.all_day, e.created_at,
         private.going_count(e.id) as going_count,
         e.cancelled_at is not null as cancelled
  from public.event_rsvps r
  join public.club_events e on e.id = r.event_id
  left join public.clubs c on c.id = e.club_id
  where r.user_id = auth.uid()
    and e.status = 'approved'
    and e.kind = 'event'
    and e.event_date between p_from and p_to
    and (e.submitted_by is not null or e.source_name is not null)
  order by e.event_date, e.title, e.id
$$;

grant execute on function public.get_my_going(date, date) to authenticated;

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
  cancelled boolean
)
language sql
stable
security invoker
set search_path = public
as $$
  select e.id, e.title, e.event_date, e.start_time, e.location, e.image_url, e.category,
         c.name as club_name, e.source_name, e.end_at, e.all_day, e.created_at,
         private.going_count(e.id) as going_count,
         exists (select 1 from public.event_rsvps r where r.event_id = e.id and r.user_id = auth.uid()) as going,
         e.cancelled_at is not null as cancelled
  from public.event_saves s
  join public.club_events e on e.id = s.event_id
  left join public.clubs c on c.id = e.club_id
  where s.user_id = auth.uid()
    and e.status = 'approved'
    and e.kind = 'event'
    and (e.event_date >= p_from or e.end_at > now())
    and (e.submitted_by is not null or e.source_name is not null)
  order by e.event_date, e.title, e.id
$$;

grant execute on function public.get_my_saves(date) to authenticated;
