-- An Event page's Schedule: parts that start together list the shortest first (Jesse, 2026-11-15: "yes"). WinterWalk's
-- 4 PM gave "Chair massages, Golden Hour" (4 to 6) above "Santa's Grand Entrance" (no end, an hour) because ties went by
-- title. A moment (Santa's arrival) now leads the slots that run on beside it; the title still breaks a tie after that.
-- Copied from 20261110193831_event_parts.sql, the only version; only the order by changes. Grants are kept by
-- create or replace.
--
-- Roll back: re-run get_event_parts from 20261110193831_event_parts.sql.

create or replace function public.get_event_parts(p_event uuid)
returns table (title text, starts_at timestamptz, ends_at timestamptz, live boolean)
language sql
stable
security invoker
set search_path = ''
as $$
  select ep.title, ep.starts_at, x.ends_at,
         x.ends_at - ep.starts_at < interval '12 hours'
           and private.is_live_kind(null, ep.title, null, false, 'part',
                                    (ep.starts_at at time zone 'America/Chicago')::date, x.ends_at)
  from public.event_parts ep
  cross join lateral (select coalesce(ep.ends_at, ep.starts_at + interval '1 hour') as ends_at) x
  where ep.event_id = p_event and ep.same_as is null
  order by ep.starts_at, x.ends_at, ep.title
$$;
