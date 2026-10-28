-- Profile's Saved list sends the friends Going to each saved Event, as get_my_going does (you-tab 07),
-- so the Event page opened from Saved names them in its bar as Town's does (BP app
-- friends-on-event-page). Same helper and rules (private.friends_going, 20261016180000_friends_shape_feed.sql):
-- only friends, only those who show their plans to friends, only findable, only Events not over,
-- newest Going first, three at most. It is 20261019171600_my_going_description.sql's get_my_saves
-- line for line but for that column and one call of the helper for all of the rows; a new column
-- changes the return type, so it is dropped and made again.
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
  friends_going jsonb
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
         private.going_count(m.id) as going_count,
         exists (select 1 from public.event_rsvps r where r.event_id = m.id and r.user_id = auth.uid()) as going,
         m.cancelled_at is not null as cancelled,
         public.place_picture(m.place_entry_id) as place_picture,
         m.description,
         coalesce(fg.people, '[]'::jsonb) as friends_going
  from mine m
  left join private.friends_going(array(select x.id from mine x)) fg on fg.event_id = m.id
  order by m.event_date, m.title, m.id
$$;

grant execute on function public.get_my_saves(date) to authenticated;
