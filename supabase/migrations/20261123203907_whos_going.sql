-- Who's going (BP app docs/plans/inside-cards, ticket 36; Jesse, 2026-11-23: "shows who else is going to the event", "it wont
-- show minors names unless ur friends with them", then "as luma and attend"). Takes back, for adults, part of town-feed 19's
-- "nobody can read who else is Going" (20261012120100_town_feed_private.sql): event_rsvps itself stays own rows only, and
-- this function is the one way in. Applied live only with Jesse's yes.
--
-- A row comes back only for someone the caller may see; everyone else is in the count alone, with no row, so no name, photo
-- or id of theirs ever leaves the database:
--   - never anyone nameless, anonymous, banned, or blocked either way, nor anyone who keeps their plans to themselves;
--   - a friend, whatever their age;
--   - a neighbour who isn't: both of them 18 or over by birthday (none counts as under 18, private.chat_minor), and the one
--     Going hasn't turned off "Show me to neighbors going".
-- Nothing for an Event that is over, called off, hidden, a Group's the caller can't see, or kept to adults from a minor.

-- On by default, as plans_to_friends. Each neighbour writes their own row.
alter table public.town_profiles add column if not exists plans_to_neighbors boolean not null default true;

-- Four until the caller is Going, as Luma shows four; then the list. Friends first, each half by name: never by when
-- they said so, which nobody needs to know.
create function public.get_event_going(p_event uuid)
returns table (user_id uuid, display_name text, avatar_url text, since timestamptz,
               relation text, mutual_friends int, friends_since timestamptz)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  me uuid := private.need_real();
  v_young boolean := private.chat_minor(me);
  v_going boolean := exists (select 1 from public.event_rsvps r where r.event_id = p_event and r.user_id = me);
begin
  if not exists (select 1 from public.club_events e
                 where e.id = p_event and e.status = 'approved' and e.kind = 'event' and e.cancelled_at is null
                   and coalesce(e.end_at, (e.event_date + 1)::timestamp at time zone 'America/Chicago') > now()
                   and private.sees_group_event(e.id)
                   and not (v_young and private.adults_only(e.place_entry_id, e.club_id,
                                                            e.title || ' ' || coalesce(e.description, '')))) then
    return;
  end if;
  return query
    with named as (
      select p.user_id as id, lower(btrim(p.display_name)) as name, private.relation(me, p.user_id) = 'friends' as friend,
             p.plans_to_neighbors as shown
      from public.event_rsvps r
      join public.town_profiles p on p.user_id = r.user_id
      where r.event_id = p_event and r.user_id <> me and p.plans_to_friends
        and private.findable(p.user_id) and not private.blocked_between(me, p.user_id)
    ), allowed as (
      select n.id, n.name, n.friend from named n
      where n.friend or (n.shown and not v_young and not private.chat_minor(n.id))
      order by n.friend desc, n.name, n.id
      limit case when v_going then 500 else 4 end
    )
    select r.* from allowed a
    cross join lateral private.neighbor_row(me, a.id) r
    order by a.friend desc, a.name, a.id;
end;
$$;
revoke execute on function public.get_event_going(uuid) from public, anon;
grant execute on function public.get_event_going(uuid) to authenticated;
