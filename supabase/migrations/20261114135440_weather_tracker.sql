-- The weather tracker and school closings (BP app docs/plans/school-activities, tickets 07 and 08; Jesse, 2026-11-13:
-- "i agree to all", "bp should have a weather tracker in backend"; 2026-11-14: "i agree").
--
-- Last winter Block Party would have heard of 5 of District 742's 6 weather calls about 10:40 AM, after school started,
-- from the districts' Facebook and Instagram. Every one of the 8 school-day changes came with a National Weather Service
-- winter alert out at least 18 hours before the call. So the edge function `weather` (supabase/functions/weather),
-- woken every 15 minutes, reads each town's alerts once an hour, and while a winter alert is out reads WJON's closings
-- list every 15 minutes from 7 to 10 PM and 5 AM to noon; otherwise once at 6:15 AM. Each list read comes here
-- (public.apply_school_closings): a closing writes News for the town's own schools and calls off that day's Events by
-- District 742's own rule. The alerts stay in the backend; the app never shows them (Jesse, 2026-11-14).

-- 1. What the tracker knows per town: its forecast zone, the alerts last read, when it last read them and the list,
--    and its last failure (the 8:00 email names it).
create table private.weather (
  town text primary key,
  zone text not null,
  alerts jsonb not null default '[]',
  alerts_read_at timestamptz,
  list_read_at timestamptz,
  error text,
  error_at timestamptz
);
insert into private.weather (town, zone) values ('st-joseph-mn', 'MNZ049');

-- 2. Each district's closing as the list last said it, per school day: closed, out early, late, or e-learning.
create table private.school_closings (
  day date not null,
  district text not null,
  kind text not null check (kind in ('closed', 'early', 'late', 'elearning')),
  words text not null,
  url text not null,
  news_id uuid references public.board_items (id) on delete set null,
  read_at timestamptz not null default now(),
  primary key (day, district)
);

-- 3. An Event a closing called off names the district. Its own source re-reading it that day (apply_judged writes
--    cancelled_at = null for an Event still on its list) leaves it called off; only the closing taking it back, which
--    clears called_off_by in the same write, brings it back.
alter table public.club_events add column called_off_by text;

create function private.keep_called_off()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if old.called_off_by is not null and new.called_off_by is not distinct from old.called_off_by
     and new.cancelled_at is null then
    new.cancelled_at := old.cancelled_at;
  end if;
  return new;
end;
$$;

create trigger club_events_keep_called_off
  before update of cancelled_at on public.club_events
  for each row execute function private.keep_called_off();

-- 4. The edge function's three calls. Service role only.
create function public.weather_state(p_town text)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select to_jsonb(w) - 'town' from private.weather w where w.town = p_town;
$$;

-- What a run did: alerts read (p_alerts), the list read (p_list_read), or a failure (p_error).
create function public.save_weather(p_town text, p_alerts jsonb default null, p_list_read boolean default false,
                                    p_error text default null, p_now timestamptz default now())
returns void
language sql
security definer
set search_path = ''
as $$
  update private.weather set
    alerts = coalesce(p_alerts, alerts),
    alerts_read_at = case when p_alerts is not null then p_now else alerts_read_at end,
    list_read_at = case when p_list_read then p_now else list_read_at end,
    error = coalesce(left(p_error, 300), error),
    error_at = case when p_error is not null then p_now else error_at end
  where town = p_town;
$$;

-- One day's list as last read, whole: p_closings holds every district the list names for p_day, each
-- {district, kind, words, title, teams, sources, news}. A district no longer on it, or on it with another kind, has
-- its News archived and its Events brought back first. Then each closing's News (only a district with `news`: the
-- town's own schools, Jesse) and its call-offs: closed calls off all that day's Events of the district's schools and
-- teams, home and away, all-day ones too; out early those from noon on; late and e-learning none (Jesse, 2026-11-13).
-- Only found Events are called off, never a neighbour's own (as apply_judged's step 5).
create function public.apply_school_closings(p_day date, p_url text, p_closings jsonb, p_now timestamptz default now())
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  c jsonb;
  prev private.school_closings;
  v_news uuid;
  n_off int := 0;
  n_back int := 0;
  n_news int := 0;
  n int;
begin
  for prev in
    select s.* from private.school_closings s
    where s.day = p_day
      and not exists (select 1 from jsonb_array_elements(p_closings) x
                      where x ->> 'district' = s.district and x ->> 'kind' = s.kind)
  loop
    update public.board_items set status = 'archived' where id = prev.news_id and status = 'published';
    update public.club_events set called_off_by = null, cancelled_at = null
    where called_off_by = prev.district and event_date = p_day;
    get diagnostics n = row_count;
    n_back := n_back + n;
    delete from private.school_closings where day = p_day and district = prev.district;
  end loop;

  for c in select * from jsonb_array_elements(p_closings) loop
    v_news := (select s.news_id from private.school_closings s where s.day = p_day and s.district = c ->> 'district');
    if v_news is null and c -> 'news' is not null and jsonb_typeof(c -> 'news') = 'object' then
      insert into public.board_items (title, blurb, category, source_name, source_url, tier, status, starts_at, ends_on,
                                      published_at, fetched_at, place_entry_id)
      values (c ->> 'title', to_char(p_day, 'FMDay, Mon FMDD'), 'school', c -> 'news' ->> 'source_name', p_url, 1,
              'published', p_day::timestamp at time zone 'America/Chicago', p_day, p_now, p_now,
              c -> 'news' ->> 'place_entry_id')
      on conflict (lower(title), source_name, coalesce(starts_at, '-infinity'::timestamptz)) do update set
        status = 'published', source_url = excluded.source_url, fetched_at = excluded.fetched_at
      returning id into v_news;
      n_news := n_news + 1;
    end if;
    insert into private.school_closings (day, district, kind, words, url, news_id, read_at)
    values (p_day, c ->> 'district', c ->> 'kind', c ->> 'words', p_url, v_news, p_now)
    on conflict (day, district) do update set words = excluded.words, url = excluded.url, read_at = excluded.read_at;

    update public.club_events e set cancelled_at = p_now, called_off_by = c ->> 'district'
    where e.event_date = p_day and e.cancelled_at is null and e.club_id is null and e.submitted_by is null
      and (e.source_name in (select jsonb_array_elements_text(c -> 'sources'))
           or e.team_ids && array(select jsonb_array_elements_text(c -> 'teams')))
      and (c ->> 'kind' = 'closed'
           or (c ->> 'kind' = 'early' and private.start_minutes(e.start_time) >= 720));
    get diagnostics n = row_count;
    n_off := n_off + n;
  end loop;

  return jsonb_build_object('closings', jsonb_array_length(p_closings), 'news', n_news,
                            'called_off', n_off, 'brought_back', n_back);
end;
$$;

revoke execute on function public.weather_state(text) from public, anon, authenticated;
revoke execute on function public.save_weather(text, jsonb, boolean, text, timestamptz) from public, anon, authenticated;
revoke execute on function public.apply_school_closings(date, text, jsonb, timestamptz) from public, anon, authenticated;

-- 5. Every 15 minutes, wake the edge function. It answers at once and reads in the background, so this waits 3 seconds
--    at most; the pacing is the function's, from private.weather.
create function private.wake_weather()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_status int;
  v_body text;
begin
  perform extensions.http_set_curlopt('CURLOPT_TIMEOUT', '3');
  select r.status, r.content into v_status, v_body
  from extensions.http(('POST', 'https://lxdgwhvqjqmqliobwjpi.supabase.co/functions/v1/weather',
    array[extensions.http_header('User-Agent', 'BlockPartyBot/1.0 (+https://blockpartystjoe.com)')],
    'application/json', '{}')::extensions.http_request) r;
  if v_status not between 200 and 299 then
    raise exception 'weather answered %: %', v_status, left(v_body, 200);
  end if;
end;
$$;

revoke execute on function private.wake_weather() from public;

select cron.schedule('weather', '*/15 * * * *', $$select private.wake_weather()$$);

-- 6. The 8:00 email names a failing tracker: its runs failing, the weather not read in 3 hours, or its last failure in
--    the past day. Otherwise line for line 20261106201753_reports_in_the_morning_email.sql's morning_problems.

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
  v_level int;
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
    -- Apify's spend: the report's own line, once when it passes 3/4 of the cap and once when it reaches the cap.
    -- Looking back skips a morning with no line ("spend unknown") or no report. With nothing to look back to, a morning
    -- already past a line says so: one extra email is better than a missed one.
    v_level := private.apify_level(v_report);
    if v_level > coalesce((select private.apify_level(r.report) from public.morning_reports r
                           where r.day < v_today and private.apify_level(r.report) is not null
                           order by r.day desc limit 1), 0) then
      return next (regexp_match(v_report, '^Apify: .*$', 'n'))[1];
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

  -- Reports waiting: on an Event or post still showing, as public.list_reports lists them, oldest first.
  for v_line in
    select format('A report is waiting on %s: %s. See the Review queue.',
                  case when e.kind = 'post' then 'a neighbour''s post' else format('"%s"', e.title) end,
                  string_agg(distinct replace(r.reason, '_', ' '), ', '))
    from public.reports r
    join public.club_events e on e.id = r.event_id
    where e.status = 'approved'
    group by e.id, e.kind, e.title
    order by min(r.at)
  loop
    return next v_line;
  end loop;

  -- Chat reports not settled: how many and why, nothing the message said or who sent it.
  select count(*)::int, string_agg(distinct replace(c.reason, '_', ' '), ', ') into v_n, v_line
  from private.chat_reports c
  where c.resolved_at is null;
  if v_n > 0 then
    return next format('%s chat %s waiting: %s. See the Review queue.', v_n,
                       case when v_n = 1 then 'report is' else 'reports are' end, v_line);
  end if;
  -- The weather tracker (BP app school-activities 08): its runs refused or failing, the weather not read in 3 hours
  -- (once it has read it), or its last failure in the past day. pg_cron's rare startup timeout is noise.
  for v_line, v_n in
    select split_part(d.return_message, E'\n', 1), count(*)::int
    from cron.job_run_details d
    join cron.job j on j.jobid = d.jobid
    where j.jobname = 'weather' and d.status = 'failed' and d.start_time > p_now - interval '24 hours'
      and d.return_message is distinct from 'job startup timeout'
    group by 1
    order by max(d.start_time) desc
  loop
    return next format('The weather tracker failed %s %s since yesterday: %s', v_n,
                       case when v_n = 1 then 'time' else 'times' end, left(v_line, 200));
  end loop;
  for v_line in
    select format('The weather tracker hasn''t read the weather since %s.',
                  to_char(w.alerts_read_at at time zone 'America/Chicago', 'Mon FMDD FMHH12:MI AM'))
    from private.weather w
    where w.alerts_read_at < p_now - interval '3 hours'
    union all
    select format('The weather tracker failed at %s: %s',
                  to_char(w.error_at at time zone 'America/Chicago', 'Mon FMDD FMHH12:MI AM'), w.error)
    from private.weather w
    where w.error_at > p_now - interval '24 hours'
  loop
    return next v_line;
  end loop;
end;
$$;

revoke execute on function private.morning_problems(timestamptz) from public;
