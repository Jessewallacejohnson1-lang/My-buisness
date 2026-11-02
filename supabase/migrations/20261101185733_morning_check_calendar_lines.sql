-- Two more lines for the 8:00 check from the group calendar review (Jesse, 2026-11-01: "yes i agree to all"):
--   - a calendar read this morning with nothing on it for 2 weeks (River Runners' weekly runs stop at the end of
--     December until the club adds the new year), which no failed read would show;
--   - a meeting the group's page promises (its rule, behind the top line "Sundays at 7:30 AM · The Local Blend")
--     that its calendar doesn't have in the coming week at that time and place: the club moved or skipped it,
--     and the top line, typed by hand, may need changing.
-- Otherwise line for line 20261101184308_morning_check_calendars.sql's morning_problems.

create or replace function private.morning_problems(p_now timestamptz default now())
returns setof text
language plpgsql
stable
set search_path = ''
as $$
declare
  v_today date := (p_now at time zone 'America/Chicago')::date;
  v_report text;
  v_line text;
  v_pages int;
  v_failed int;
  v_events int;
  v_n int;
begin
  -- The morning run: its report row (smooth-mornings 10), any step it says failed, its numbers.
  select r.report into v_report from public.morning_reports r where r.day = v_today;
  if v_report is null then
    return next 'No morning report today: the morning run didn''t finish.';
  else
    for v_line in select left(m[1], 200) from regexp_matches(v_report, '^\[morning\] (.+ failed: .*)$', 'gn') m loop
      return next 'A morning step failed: ' || v_line;
    end loop;
    v_pages := (regexp_match(v_report, '^- Pages: (\d+) fetched', 'n'))[1]::int;
    v_failed := (regexp_match(v_report, '^- Failed today: (\d+)', 'n'))[1]::int;
    v_events := (regexp_match(v_report, '^- Events: (\d+) new', 'n'))[1]::int;
    if v_pages is null or v_failed is null or v_events is null then
      return next 'The morning report has no Pages, Failed today or Events line, so it couldn''t be checked.';
    end if;
    if v_events = 0 then
      return next 'The morning run added 0 Events.';
    end if;
    -- More than 1 in 10 pages (Jesse, 2026-10-31). Oct 31: 2 of 242.
    if v_failed * 10 > v_pages then
      return next format('%s of %s pages failed this morning.', v_failed, v_pages);
    end if;
  end if;

  -- A neighbour's post waiting for Jesse's approval over a day.
  for v_line in
    select format('A neighbour''s post has waited over a day for your approval: "%s" (since %s).',
                  e.title, to_char(e.created_at at time zone 'America/Chicago', 'Mon FMDD'))
    from public.club_events e
    where e.submitted_by is not null and e.status = 'pending' and e.created_at < p_now - interval '24 hours'
    order by e.created_at
  loop
    return next v_line;
  end loop;

  -- Live scores refused or failing (ticket 05 makes a refusal fail the run). pg_cron's rare startup timeout is noise.
  for v_line, v_n in
    select split_part(d.return_message, E'\n', 1), count(*)::int
    from cron.job_run_details d
    join cron.job j on j.jobid = d.jobid
    where j.jobname = 'live-scores' and d.status = 'failed' and d.start_time > p_now - interval '24 hours'
      and d.return_message is distinct from 'job startup timeout'
    group by 1
    order by max(d.start_time) desc
  loop
    return next format('Live scores failed %s %s since yesterday: %s', v_n,
                       case when v_n = 1 then 'time' else 'times' end, left(v_line, 200));
  end loop;

  -- A game the live-scores job listened to for 30 minutes with no score saved (SIDEARM moved its files on Oct 29
  -- and nothing failed). Which games and when it listens are private.live_games' (start minus 15 minutes, one
  -- game per file a day), worked out the same way here because a game with its final in drops out of that one.
  for v_line in
    with games as (
      select e.title, e.live_score, private.sidearm_file(e.source_name, e.sport) as file, e.event_date,
             (e.event_date + make_interval(mins => (t.m[1]::int % 12) * 60 + coalesce(t.m[2], '0')::int
                                                   + case when t.m[3] = 'p' then 720 else 0 end))
               at time zone 'America/Chicago' as starts_at
      from public.club_events e
      cross join lateral (select regexp_match(lower(btrim(e.start_time)), '^(\d{1,2})(?::(\d{2}))?\s*([ap])\.?m\.?$') as m) t
      where e.team_ids is not null and e.cancelled_at is null and e.status = 'approved'
        and e.event_date between v_today - 1 and v_today and t.m is not null
    )
    select format('Live scores heard nothing from %s (%s).', g.title,
                  to_char(g.starts_at at time zone 'America/Chicago', 'Dy FMHH12:MI AM'))
    from games g
    where g.file is not null and g.live_score is null
      and g.starts_at + interval '15 minutes' > p_now - interval '24 hours'
      and g.starts_at + interval '15 minutes' <= p_now
      and (select count(*) from games o where o.file = g.file and o.event_date = g.event_date) = 1
    order by g.starts_at
  loop
    return next v_line;
  end loop;

  -- A group's calendar not read in over a day: its Coming up still shows the last copy.
  for v_line in
    select format('The %s calendar hasn''t been read since %s.', c.name,
                  coalesce(to_char(c.calendar_read_at at time zone 'America/Chicago', 'Mon FMDD'), 'it was added'))
    from public.clubs c
    where c.calendar_id is not null and c.status = 'approved'
      and (c.calendar_read_at is null or c.calendar_read_at < p_now - interval '26 hours')
    order by c.name
  loop
    return next v_line;
  end loop;

  -- A calendar read this morning with nothing on it for the next 2 weeks.
  for v_line in
    select format('The %s calendar has nothing on it for the next 2 weeks.', c.name)
    from public.clubs c
    where c.calendar_id is not null and c.status = 'approved' and c.calendar_read_at >= p_now - interval '26 hours'
      and not exists (select 1 from jsonb_array_elements(coalesce(c.calendar, '[]'::jsonb)) m
                      where m ->> 'day' between to_char(v_today, 'YYYY-MM-DD') and to_char(v_today + 13, 'YYYY-MM-DD'))
    order by c.name
  loop
    return next v_line;
  end loop;

  -- The first meeting in the coming week that a group's page promises and its fresh calendar doesn't have at
  -- that time and place.
  for v_line in
    select distinct on (c.name)
           format('%s: the page says %s, but its calendar has no %s on %s%s. Check the page''s top line.',
                  c.name, concat_ws(' · ', c.schedule, c.location), r ->> 'what',
                  to_char((r ->> 'day')::date, 'Dy Mon FMDD'),
                  coalesce(' at ' || to_char(('2000-01-01 ' || (r ->> 'time'))::timestamp, 'FMHH12:MI AM'), ''))
    from public.clubs c
    cross join lateral jsonb_array_elements(public.group_meetings(c.meets, v_today, 10)) r
    where c.calendar_id is not null and c.status = 'approved' and c.calendar_read_at >= p_now - interval '26 hours'
      and (r ->> 'day')::date <= v_today + 7
      and not exists (select 1 from jsonb_array_elements(coalesce(c.calendar, '[]'::jsonb)) m
                      where m ->> 'day' = r ->> 'day'
                        and (r ->> 'time' is null or m ->> 'time' = r ->> 'time')
                        and (coalesce(r ->> 'where', c.location) is null
                             or m ->> 'where' = coalesce(r ->> 'where', c.location)))
    order by c.name, r ->> 'day', r ->> 'time'
  loop
    return next v_line;
  end loop;
end;
$$;

revoke execute on function private.morning_problems(timestamptz) from public;
