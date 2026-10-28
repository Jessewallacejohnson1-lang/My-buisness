-- public.get_my_saves, as 20261028135304_my_saves_friends.sql made it, with its card picture from event_picture
-- (event-photos 07: a photo of what the event is, from its place's scenes, else place_picture).
create or replace function public.get_my_saves(p_from date)
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
         public.event_picture(m.id) as place_picture,
         m.description,
         coalesce(fg.people, '[]'::jsonb) as friends_going
  from mine m
  left join private.friends_going(array(select x.id from mine x)) fg on fg.event_id = m.id
  order by m.event_date, m.title, m.id
$$;
