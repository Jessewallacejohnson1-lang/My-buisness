-- Reads each game's final once it's over (BP app docs/plans/game-card, ticket 02; Jesse, 2026-10-21:
-- "check and update once game is finished"). Every 15 minutes, a game that ended (two hours after its
-- start, or its end), yesterday or today, with no final yet, is read again at most once an hour until
-- its final is in:
--   - a high school game: its lister's schedule at the state league, for that day
--     (mshsl.org's robots.txt allows /api/ and asks no crawl delay; it turned a quick eighth request
--     away on 2026-10-21, so five seconds apart, six at most a run, and a refusal ends the run);
--   - an SJU or CSB home game: SIDEARM's live stats file for the school and sport, one file a run
--     (sidearmstats.com's robots.txt asks for one read every 10 minutes).
-- The readers are private.league_final and private.sidearm_final (20261021120000_game_finals.sql).

create extension if not exists http with schema extensions;

alter table public.club_events
  add column if not exists final_checked_at timestamptz;

create or replace function private.read_finals(p_now timestamptz default now())
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  g record;
  v_status int;
  v_body text;
  v_final int[];
  v_url text;
  v_file text;
  v_host text;
  n_league int := 0;
  n_files int := 0;
  n_finals int := 0;
  v_refused boolean := false;
  v_today date := (p_now at time zone 'America/Chicago')::date;
begin
  perform extensions.http_set_curlopt('CURLOPT_TIMEOUT', '20');
  for g in
    select e.id, e.event_date, e.team_ids, e.sport, e.source_name, e.source_uid, e.source_url
    from public.club_events e
    cross join lateral (select regexp_match(lower(btrim(e.start_time)), '^(\d{1,2})(?::(\d{2}))?\s*([ap])\.?m\.?$') as m) t
    where e.team_ids is not null and e.final_score is null and e.cancelled_at is null and e.status = 'approved'
      and e.event_date between v_today - 1 and v_today
      and (e.final_checked_at is null or e.final_checked_at < p_now - interval '55 minutes')
      -- Over: its end, else two hours after its start, else the day's end.
      and p_now > coalesce(e.end_at,
            (e.event_date + make_interval(mins => (t.m[1]::int % 12) * 60 + coalesce(t.m[2], '0')::int
                                                  + case when t.m[3] = 'p' then 720 else 0 end))
              at time zone 'America/Chicago' + interval '2 hours',
            (e.event_date + 1)::timestamp at time zone 'America/Chicago')
    order by e.event_date, e.created_at
  loop
    v_final := null;
    v_url := null;
    if g.source_uid like 'mshsl:%' and g.source_url ~ '/group/\d+/' then
      continue when n_league >= 6 or v_refused;
      v_url := format('https://www.mshsl.org/api/team-data/schedule/%s/varsity/%s?start_date=%s&end_date=%s',
                      (regexp_match(g.source_url, '/group/(\d+)/'))[1], (regexp_match(g.source_uid, '^mshsl:(\d+):'))[1],
                      g.event_date, g.event_date + 1);
      if n_league > 0 then perform pg_sleep(5); end if;
      n_league := n_league + 1;
    else
      -- The file for the school and sport, as SIDEARM names them; another sport waits until its file is seen.
      v_file := case g.source_name || '/' || g.sport
        when 'SJU Athletics/Football' then 'csbsju/football'
        when 'SJU Athletics/Soccer' then 'csbsju/msoc'
        when 'CSB Athletics/Soccer' then 'csb/wsoc'
        when 'CSB Athletics/Volleyball' then 'csb/wvball' end;
      v_host := case g.source_name when 'SJU Athletics' then 'john' when 'CSB Athletics' then 'benedict' end;
      continue when v_file is null or n_files >= 1;
      v_url := format('https://sidearmstats.com/%s/game.json?detail=game', v_file);
      n_files := n_files + 1;
    end if;
    v_status := null;
    begin
      select r.status, r.content into v_status, v_body
      from extensions.http(('GET', v_url,
        array[extensions.http_header('User-Agent', 'BlockPartyBot/1.0 (+https://blockpartystjoe.com)')],
        null, null)::extensions.http_request) r;
      if v_status = 200 then
        v_final := case when g.source_uid like 'mshsl:%'
          then private.league_final(v_body::jsonb, g.source_uid, g.event_date, g.team_ids)
          else private.sidearm_final(v_body::jsonb, g.event_date, v_host) end;
      end if;
    exception when others then
      v_final := null;  -- unreachable or not JSON: tried again in an hour
    end;
    update public.club_events set final_checked_at = p_now, final_score = v_final where id = g.id;
    n_finals := n_finals + (v_final is not null)::int;
    -- The league turning us away ends this run's reads there.
    if g.source_uid like 'mshsl:%' and v_status in (403, 429) then v_refused := true; end if;
  end loop;
  return jsonb_build_object('league_reads', n_league, 'files', n_files, 'finals', n_finals, 'refused', v_refused);
end;
$$;

revoke execute on function private.read_finals(timestamptz) from public;

select cron.schedule('game-finals', '*/15 * * * *', $$select private.read_finals()$$);
