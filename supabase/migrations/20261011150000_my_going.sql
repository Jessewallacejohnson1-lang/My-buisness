-- You tab (BP app docs/plans/you-tab, ticket 01): the caller's Going between two Town days,
-- for the Calendar and the Agenda. The one function iOS and Android both call.
-- * only the caller's own Going: their event_rsvps rows, by auth.uid();
-- * the events the Town feed counts: approved, an event, a person posted it or a source
--   announced it;
-- * every day from p_from to p_to, both ends included, past days too, so the Calendar can
--   show the start of this week;
-- * ordered by day, then title. The app orders a day by start time with the one parser it
--   already has for the free-text start ("7 PM", "noon", "after dark").
-- Security invoker: RLS decides what the caller reads. Signed out, auth.uid() is null and
-- nothing comes back.
create or replace function public.get_my_going(p_from date, p_to date)
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
  going_count int
)
language sql
stable
security invoker
set search_path = public
as $$
  select e.id, e.title, e.event_date, e.start_time, e.location, e.image_url, e.category,
         c.name as club_name, e.source_name, e.end_at, e.all_day, e.created_at,
         (select count(*)::int from public.event_rsvps a where a.event_id = e.id) as going_count
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
