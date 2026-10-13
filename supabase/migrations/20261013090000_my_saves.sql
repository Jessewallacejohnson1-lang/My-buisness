-- Saved in Profile (BP app docs/plans/you-tab, ticket 04): the caller's saved Events from a
-- Town day on, for Profile's Saved list. get_my_going's columns, plus whether the caller is
-- Going, since the Event page opened from Saved reads its Join from the row when the Town feed
-- never read that Event. An Event dated before p_from that is still running (a festival) stays.
-- Only the caller's own saves (event_saves' "own saves select"); the count from private.going_count.
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
  going boolean
)
language sql
stable
security invoker
set search_path = public
as $$
  select e.id, e.title, e.event_date, e.start_time, e.location, e.image_url, e.category,
         c.name as club_name, e.source_name, e.end_at, e.all_day, e.created_at,
         private.going_count(e.id) as going_count,
         exists (select 1 from public.event_rsvps r where r.event_id = e.id and r.user_id = auth.uid()) as going
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
