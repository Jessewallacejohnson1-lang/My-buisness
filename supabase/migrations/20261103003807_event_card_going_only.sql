-- You's Going sends the Event card alone (BP app codebase-health-2, ticket 03): the copied columns beside it
-- go, so a new Event field is one change in private.event_cards and shows here with nothing else to edit.
-- Builds on phones from iOS main ee8e0a53 on read only `card` (CommunityAPI.myGoingRows).
--
-- It is 20261102174133_event_card_going.sql's get_my_going with every column but `card` dropped: the same
-- rows, the same order. The card comes for every row (the card source reads under the same rules), so it is
-- an inner join.
--
-- Roll back: re-run 20261102174133_event_card_going.sql's drop, create and grant of get_my_going.

drop function if exists public.get_my_going(date, date);

create function public.get_my_going(p_from date, p_to date)
returns table (card jsonb)
language sql
stable
security invoker
set search_path = public
as $$
  with mine as (
    select e.id, e.title, e.event_date
    from public.event_rsvps r
    join public.club_events e on e.id = r.event_id
    where r.user_id = auth.uid()
      and e.status = 'approved'
      and e.kind = 'event'
      and e.event_date between p_from and p_to
      and (e.submitted_by is not null or e.source_name is not null)
  )
  -- The Event card, asked once for all of the rows.
  select ec.card
  from mine m
  join private.event_cards(array(select x.id from mine x)) ec on ec.id = m.id
  order by m.event_date, m.title, m.id
$$;

grant execute on function public.get_my_going(date, date) to authenticated;
