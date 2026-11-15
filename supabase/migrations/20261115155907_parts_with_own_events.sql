-- An Event page's Schedule lists every part, a part that is an Event of its own too (Jesse, 2026-11-15: "yes").
-- WinterWalk's Schedule stopped at "Harp Ensemble at the Monastery": its Tree Lighting and the Great River Chorale's
-- concert point at their own Events (same_as), and this read left those out. On the page they're a line in a list, not a
-- second card. Such a part is never live here: the Town feed reads its card's "Now · ..." through this function and takes
-- only a live part, so the festival's card never says "Now · Tree Lighting" while the Tree Lighting has its own card
-- (supabase/town_feed.sql, unchanged; happening-now 04's story). The cost: that line on the festival's page shows no
-- "Now" either; the Tree Lighting's own card and page do.
-- Copied from 20261115154419_parts_moment_first.sql, the newest version; only the where and live change.
--
-- Roll back: re-run get_event_parts from 20261115154419_parts_moment_first.sql.

create or replace function public.get_event_parts(p_event uuid)
returns table (title text, starts_at timestamptz, ends_at timestamptz, live boolean)
language sql
stable
security invoker
set search_path = ''
as $$
  select ep.title, ep.starts_at, x.ends_at,
         ep.same_as is null
           and x.ends_at - ep.starts_at < interval '12 hours'
           and private.is_live_kind(null, ep.title, null, false, 'part',
                                    (ep.starts_at at time zone 'America/Chicago')::date, x.ends_at)
  from public.event_parts ep
  cross join lateral (select coalesce(ep.ends_at, ep.starts_at + interval '1 hour') as ends_at) x
  where ep.event_id = p_event
  order by ep.starts_at, x.ends_at, ep.title
$$;
