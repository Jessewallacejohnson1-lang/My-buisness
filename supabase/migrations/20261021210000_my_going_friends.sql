-- The You tab's Agenda shows the friends Going to each of your plans (you-tab 07), as the Town
-- card does: get_my_going sends them in a new last column from the Town feed's own helper
-- (private.friends_going, 20261016180000_friends_shape_feed.sql): only friends, only those who show
-- their plans to friends, only findable, only Events not over, newest Going first, three at most,
-- first name and own-avatar photo. It is 20261019171600_my_going_description.sql's get_my_going
-- line for line but for that column and one call of the helper for all of the rows; a new column
-- changes the return type, so it is dropped and made again. get_my_saves is unchanged.
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
         private.going_count(m.id) as going_count,
         m.cancelled_at is not null as cancelled,
         public.place_picture(m.place_entry_id) as place_picture,
         m.description,
         -- Up to three friends Going, newest Going first (the Town card's, town-feed 28), asked
         -- once for all of the rows.
         coalesce(fg.people, '[]'::jsonb) as friends_going
  from mine m
  left join private.friends_going(array(select x.id from mine x)) fg on fg.event_id = m.id
  order by m.event_date, m.title, m.id
$$;

grant execute on function public.get_my_going(date, date) to authenticated;
