-- A bad morning emails Jesse at 8:00 (BP app docs/plans/loopholes, ticket 03). At 8:00 Chicago the database
-- reads what went wrong since yesterday and, only when something did, sends one email through Composio's Gmail.
-- No email means all is well. It runs here, not on Jesse's Mac and not in the morning run, so a run that never
-- started, or a Claude plan out of room, still gets reported.
--
-- The Composio key, its Gmail account and the address to write to sit in Vault as one JSON secret named
-- 'morning_check' ({"key", "account", "to"}), never in this repo. The key is a Composio agent account's that
-- holds only Gmail. Ceiling: if the email itself fails, the cron run fails and nobody hears; the next morning
-- tries again.

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
end;
$$;

create or replace function private.morning_check(p_now timestamptz default now())
returns void
language plpgsql
set search_path = ''
as $$
declare
  v_problems text[];
  v_secret jsonb;
  v_status int;
  v_body text;
begin
  -- pg_cron keeps UTC, so the job comes at 13:00 and 14:00 and only the one that is 8:00 in Chicago reads.
  if extract(hour from p_now at time zone 'America/Chicago') <> 8 then return; end if;
  v_problems := array(select private.morning_problems(p_now));
  if cardinality(v_problems) = 0 then return; end if;

  select s.decrypted_secret::jsonb into v_secret from vault.decrypted_secrets s where s.name = 'morning_check';
  if v_secret is null then raise exception 'morning check: no morning_check secret in Vault'; end if;

  perform extensions.http_set_curlopt('CURLOPT_TIMEOUT', '30');
  select r.status, r.content into v_status, v_body
  from extensions.http(('POST', 'https://backend.composio.dev/api/v3.1/tools/execute/GMAIL_SEND_EMAIL',
    array[extensions.http_header('x-api-key', v_secret ->> 'key')], 'application/json',
    jsonb_build_object('connected_account_id', v_secret ->> 'account', 'arguments', jsonb_build_object(
      'recipient_email', v_secret ->> 'to',
      'subject', case when cardinality(v_problems) = 1 then 'Block Party: ' || v_problems[1]
                      else format('Block Party: %s things wrong this morning', cardinality(v_problems)) end,
      'body', '- ' || array_to_string(v_problems, E'\n- ') || E'\n\nNo email means all is well.',
      'is_html', false))::text)::extensions.http_request) r;
  if v_status not between 200 and 299 then
    raise exception 'morning check email answered %: %', v_status, left(v_body, 300);
  end if;
  if (v_body::jsonb ->> 'successful') is distinct from 'true' then
    raise exception 'morning check email not sent: %', left(v_body, 300);
  end if;
end;
$$;

revoke execute on function private.morning_problems(timestamptz) from public;
revoke execute on function private.morning_check(timestamptz) from public;

select cron.schedule('morning-check', '0 13,14 * * *', $$select private.morning_check()$$);
