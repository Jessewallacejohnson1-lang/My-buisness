-- The Town feed (BP app docs/plans/town-feed, tickets 05 and 13): what is in it and in
-- what order, worked out here so iOS and Android show the same list. The phone shows
-- the rows in the order given and hides one when its leaves_at passes; it never
-- re-sorts. Events only for now; posts, updates and news join when they exist.

-- Dropped first so this file can be run again as it changes: a function's returned
-- columns can't be changed in place.
drop function if exists public.get_town_feed(timestamptz);

-- How a series repeats, from its dates, in Jesse's words ("Every Tuesday", "Every 1st &
-- 3rd Monday"); null under three dates or with no clear pattern, so the card shows the
-- next date only.
-- A monthly pattern needs every month between the first and last to hold the same weeks;
-- the first month may lack earlier weeks and the last later ones (the window cuts them).
create or replace function public.town_feed_series_label(dates date[])
returns text
language plpgsql
immutable
set search_path = public
as $$
declare
  d date[] := array(select distinct x from unnest(dates) x where x is not null order by 1);
  n int := coalesce(array_length(d, 1), 0);
  gaps int[];
  weekday text;
  weeks int[];
  first_month date;
  last_month date;
  month date;
  held int[];
  full_month boolean := false;
begin
  if n < 3 then
    return null;
  end if;

  gaps := array(select d[i + 1] - d[i] from generate_series(1, n - 1) i);
  weekday := to_char(d[1], 'FMDay');

  -- Days in a row (a weekend festival) are not "every day": no label.
  if 7 = all(gaps) then
    return 'Every ' || weekday;
  elsif 14 = all(gaps) then
    return 'Every other ' || weekday;
  end if;

  if (select count(distinct extract(isodow from x)) from unnest(d) x) <> 1 then
    return null;
  end if;

  weeks := array(select distinct (extract(day from x)::int - 1) / 7 + 1 from unnest(d) x order by 1);
  if array_length(weeks, 1) > 2 then
    return null;
  end if;

  first_month := date_trunc('month', d[1])::date;
  last_month := date_trunc('month', d[n])::date;
  month := first_month;
  while month <= last_month loop
    held := array(
      select distinct (extract(day from x)::int - 1) / 7 + 1 from unnest(d) x
      where date_trunc('month', x)::date = month order by 1);
    if held = weeks then
      full_month := true;
    elsif month = first_month and month = last_month then
      return null;
    elsif month = first_month then
      -- Only weeks before the first date may be missing.
      if exists (select 1 from unnest(weeks) w where w > held[1] and not w = any(held)) then
        return null;
      end if;
    elsif month = last_month then
      -- Only weeks after the last date may be missing.
      if exists (select 1 from unnest(weeks) w
                 where w < held[array_length(held, 1)] and not w = any(held)) then
        return null;
      end if;
    else
      return null;
    end if;
    month := (month + interval '1 month')::date;
  end loop;

  if not full_month then
    return null;
  end if;

  return 'Every ' || (
    select string_agg(w || case w when 1 then 'st' when 2 then 'nd' when 3 then 'rd' else 'th' end,
                      ' & ' order by w)
    from unnest(weeks) w
  ) || ' ' || weekday;
end;
$$;

-- The caller's Town feed at p_now (ticket 05):
-- * approved events that a person posted or a source announced (never seed rows);
-- * from shows_from, or 14 days ahead when unset, until they leave: at end_at; with no
--   end, 2 hours after they start; with no start either, at midnight Town time;
-- * a series (same title, same host) once, at its next date, with how it repeats;
-- * soonest first, the ones you're Going to below the rest.
-- Security invoker: RLS decides what the caller sees, so a signed-out read counts no
-- RSVPs, exactly as the app's own read did before this function.
create or replace function public.get_town_feed(p_now timestamptz default now())
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
  rsvpd boolean,
  recurrence text,
  leaves_at timestamptz
)
language sql
stable
security invoker
set search_path = public
as $$
  with town as (
    select 'America/Chicago'::text as zone,
           (p_now at time zone 'America/Chicago')::date as today
  ),
  real_events as (
    select e.*,
           lower(btrim(e.title)) || '|' || coalesce(e.club_id::text, e.source_name, e.submitted_by::text, '')
             as series,
           -- The free-text start: "7 PM", "7:00 PM", "7pm", "noon", "19:00".
           case
             when e.all_day then null
             when lower(btrim(e.start_time)) = 'noon' then 720
             when lower(btrim(e.start_time)) = 'midnight' then 0
             when m12 is not null and m12[1]::int between 1 and 12 and coalesce(m12[2], '0')::int < 60
               then (m12[1]::int % 12) * 60 + coalesce(m12[2], '0')::int + case when m12[3] = 'p' then 720 else 0 end
             when m24 is not null and m24[1]::int < 24 and m24[2]::int < 60
               then m24[1]::int * 60 + m24[2]::int
           end as start_minutes
    from public.club_events e
    cross join lateral (select
      regexp_match(lower(btrim(e.start_time)), '^(\d{1,2})(?::(\d{2}))?\s*([ap])\.?m\.?$') as m12,
      regexp_match(btrim(e.start_time), '^(\d{1,2}):(\d{2})(?::\d{2})?$') as m24) t
    cross join town
    where e.status = 'approved'
      and e.kind = 'event'
      and e.event_date is not null
      and (e.submitted_by is not null or e.source_name is not null)
      -- The window a series' wording reads, plus anything still running.
      and (e.event_date >= town.today - 60 or e.end_at > p_now)
  ),
  timed as (
    select r.*,
           (r.event_date + make_interval(mins => r.start_minutes)) at time zone town.zone as starts_at,
           coalesce(
             r.end_at,
             (r.event_date + make_interval(mins => r.start_minutes)) at time zone town.zone + interval '2 hours',
             (r.event_date + 1)::timestamp at time zone town.zone
           ) as leaves_at
    from real_events r, town
  ),
  labels as (
    select t.series, public.town_feed_series_label(array_agg(t.event_date)) as recurrence
    from timed t, town
    where t.event_date >= town.today - 60
    group by t.series
  ),
  next_up as (
    select t.*,
           row_number() over (partition by t.series order by t.event_date, t.starts_at nulls first, t.id) as nth,
           exists (select 1 from public.event_rsvps r where r.event_id = t.id and r.user_id = auth.uid())
             as going
    from timed t
    where t.leaves_at > p_now
  )
  select e.id, e.title, e.event_date, e.start_time, e.location, e.image_url, e.category,
         c.name, e.source_name, e.end_at, e.all_day, e.created_at,
         (select count(*)::int from public.event_rsvps r where r.event_id = e.id),
         e.going,
         l.recurrence,
         e.leaves_at
  from next_up e
  cross join town
  left join public.clubs c on c.id = e.club_id
  left join labels l on l.series = e.series
  where e.nth = 1
    and town.today >= coalesce(e.shows_from, e.event_date - 14)
  order by
    e.going,
    coalesce(e.starts_at, e.event_date::timestamp at time zone town.zone),
    e.title,
    e.id;
$$;

grant execute on function public.town_feed_series_label(date[]) to anon, authenticated;
grant execute on function public.get_town_feed(timestamptz) to anon, authenticated;

comment on function public.get_town_feed(timestamptz) is
  'The Town feed for the caller, in order. Both apps call it; neither re-sorts. BP app docs/plans/town-feed, ticket 05.';
