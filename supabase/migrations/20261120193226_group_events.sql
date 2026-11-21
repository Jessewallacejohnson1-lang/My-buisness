-- A Group page's found Events (BP app rsvp-and-groups 10): the Events the morning job or the social watch found for
-- the Group (private.event_group: its own page, or its name at its place), next three from today, as cards. The Group
-- page lays them among its meetings, one row a day, and a tap opens the Event page. The cards are the ones the Town
-- feed would show (approved, not called off, not a friends-only post); the shape is get_my_going's (one `card` per
-- row), so the app reads it with the same decoder. Signed out reads it too, as get_groups.

create function public.get_group_events(p_group uuid)
returns table (card jsonb)
language sql
stable
security invoker
set search_path = public
as $$
  with found as (
    select e.id, e.event_date
    from public.club_events e
    where e.status = 'approved'
      and e.kind = 'event'
      and e.cancelled_at is null
      and not coalesce(e.friends_only, false)
      and e.source_name is not null
      and e.event_date >= (now() at time zone 'America/Chicago')::date
      -- event_group (security definer: neighbours can't read sources) runs once per upcoming found Event, a few
      -- hundred to two thousand rows: cheap for a page open.
      and private.event_group(e.source_name, e.place_entry_id, e.title) = p_group
    order by e.event_date, e.id
    limit 3
  )
  select ec.card
  from found f
  join private.event_cards(array(select id from found)) ec on ec.id = f.id
  order by f.event_date, f.id
$$;

revoke execute on function public.get_group_events(uuid) from public;
grant execute on function public.get_group_events(uuid) to anon, authenticated;
