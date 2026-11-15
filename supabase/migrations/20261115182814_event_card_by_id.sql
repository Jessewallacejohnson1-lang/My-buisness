-- One Event's card by its id (BP app inside-cards 29): the bell's "Your event is live" row and its pill open your own
-- just-posted Event with its heart, count and map spot, as every other door does, before the Town feed's window holds it.
-- Your own approved Event only: the door never opens anyone else's, so the read shows nothing the Town feed wouldn't.
-- The shape is get_my_going's (one row, `card`), so the app reads it with the same decoder.

create function public.get_event_card(p_event uuid)
returns table (card jsonb)
language sql
stable
security invoker
set search_path = public
as $$
  select ec.card
  from public.club_events e
  join private.event_cards(array[e.id]) ec on ec.id = e.id
  where e.id = p_event
    and e.submitted_by = auth.uid()
    and e.status = 'approved'
    and e.kind = 'event'
$$;

revoke execute on function public.get_event_card(uuid) from public, anon;
grant execute on function public.get_event_card(uuid) to authenticated;
