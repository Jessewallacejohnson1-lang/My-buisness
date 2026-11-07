-- A live game never goes blind quietly (BP app docs/plans/game-card/issues/22-never-blind-quietly.md).
--
-- The live-scores function reads each game from up to three sources: the school's own file on gobennies.com or
-- gojohnnies.com every 30 s (game-card 21), SIDEARM's push channel, and sidearmstats.com's cached file once per 10
-- minutes. Until now a source that broke said so only in the function's log, and nobody knew until the morning report
-- said "never went live" (2026-11-06: the push host's certificate expired and every push failed; 2026-11-07: CSB
-- Basketball vs Loras showed nothing all afternoon while its file answered every minute).
--
-- - Every read now goes through public.record_live_read, which keeps a mark per game and source: reads, failed reads
--   and why, and reads that put a score on the card (private.live_reads).
-- - One writer at a time: a source writes only while every source above it (school, then push, then backup) has put
--   no score on the card for 3 minutes, so the cached backup never lands an older score over a newer one. The backup
--   also never moves a score backward.
-- - The every-minute job 'live-dark' sends Jesse one push (ntfy, Jesse: "yes" to the agent's pick, 2026-11-07) when a
--   game on has had no fresh score for 12 minutes, or none at all 30 minutes past its listed start, then stays quiet
--   until the school's file or the push brings a score back. The topic sits in Vault as the secret 'live_alarm',
--   never in this repo.
-- - The morning report names the source that carried each game (public.live_marks).
--
-- live_games is 20261025160000_live_scores.sql's, its start read through private.live_start so the alarm reads the
-- same start.

create or replace function private.live_start(p_day date, p_time text)
returns timestamptz
language sql
stable
set search_path = ''
as $$
  select (p_day + make_interval(mins => (t.m[1]::int % 12) * 60 + coalesce(t.m[2], '0')::int
                                       + case when t.m[3] = 'p' then 720 else 0 end))
           at time zone 'America/Chicago'
  from (select regexp_match(lower(btrim(p_time)), '^(\d{1,2})(?::(\d{2}))?\s*([ap])\.?m\.?$') as m) t
  where t.m is not null
$$;

create or replace function private.live_games(p_now timestamptz)
returns table (id uuid, grp text)
language sql
stable
set search_path = ''
as $$
  with games as (
    select e.id, e.event_date, private.sidearm_file(e.source_name, e.sport) as file, s.starts_at
    from public.club_events e
    cross join lateral (select private.live_start(e.event_date, e.start_time) as starts_at) s
    where e.team_ids is not null and e.final_score is null and e.cancelled_at is null and e.status = 'approved'
      and e.event_date between (p_now at time zone 'America/Chicago')::date - 1 and (p_now at time zone 'America/Chicago')::date
      and s.starts_at is not null
  )
  select g.id, 'livestats/' || g.file || '/game'
  from games g
  where g.file is not null
    and p_now between g.starts_at - interval '15 minutes' and g.starts_at + interval '5 hours'
    and (select count(*) from games o where o.file = g.file and o.event_date = g.event_date) = 1
$$;

-- One row per game and source.
create table private.live_reads (
  event_id uuid not null references public.club_events (id) on delete cascade,
  -- In the order they write: the school's own file, SIDEARM's push, sidearmstats.com's cached file.
  source text not null check (source in ('school', 'push', 'backup')),
  reads int not null default 0,
  -- Of those, the ones that brought nothing of this game; why holds the last one's reason.
  failed int not null default 0,
  -- The ones that put the score on the card.
  wrote int not null default 0,
  tried_at timestamptz,
  failed_at timestamptz,
  scored_at timestamptz,
  why text,
  primary key (event_id, source)
);

-- Who a source is, in words: the school's site by its host.
create or replace function private.live_source_name(p_event uuid, p_source text)
returns text
language sql
stable
set search_path = ''
as $$
  select case p_source
    when 'school' then coalesce((select substring(f.url from '^https://([^/]+)') from private.live_feeds f
                                 where f.event_id = p_event), 'the school''s site')
    when 'push' then 'SIDEARM''s push'
    else 'sidearmstats.com' end
$$;

-- One read of one game from one source: a file (p_game), or nothing and the reason (p_why). Returns 'failed' (the
-- file isn't this game, or nothing came), 'held' (a source above wrote in the last 3 minutes, or the backup is behind
-- the card), or record_live_score's answer.
create or replace function public.record_live_read(p_event uuid, p_source text, p_game jsonb, p_why text default null,
                                                   p_now timestamptz default now())
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  e record;
  g jsonb := coalesce(p_game -> 'Game', p_game);
  v jsonb;
  v_result text;
begin
  select c.event_date, c.source_name, c.sport, c.live_score into e from public.club_events c where c.id = p_event;
  if not found then return 'ignored'; end if;
  -- A game file that holds another game: last week's left in it (2026-10-24), or the gym's earlier one before ours
  -- begins (CSB's file held Hamline vs Morris before Loras, 2026-11-07). A plays push carries no teams.
  if p_game is null then
    p_why := coalesce(p_why, 'nothing came');
  elsif jsonb_typeof(g) = 'object' and g ? 'HomeTeam' then
    if g ->> 'Date' ~ '^\d{1,2}/\d{1,2}/\d{4}$' and to_date(g ->> 'Date', 'MM/DD/YYYY') <> e.event_date then
      p_why := 'holds the game of ' || (g ->> 'Date');
    elsif not (coalesce(g -> 'HomeTeam' ->> 'Name', '') ~* private.sidearm_host(e.source_name)
               or coalesce(g -> 'VisitingTeam' ->> 'Name', '') ~* private.sidearm_host(e.source_name)) then
      p_why := format('holds %s vs %s', g -> 'VisitingTeam' ->> 'Name', g -> 'HomeTeam' ->> 'Name');
    else
      p_why := null;
    end if;
  else
    p_why := null;
  end if;

  if p_why is not null then
    v_result := 'failed';
  elsif exists (select 1 from private.live_reads r
                where r.event_id = p_event and r.scored_at > p_now - interval '3 minutes'
                  and array_position('{school,push,backup}'::text[], r.source)
                      < array_position('{school,push,backup}'::text[], p_source)) then
    v_result := 'held';
  else
    if p_source = 'backup' then
      -- The backup's file is cached: a score below the card's is an older read, never a correction.
      v := private.sidearm_live(p_game, e.event_date, private.sidearm_host(e.source_name),
                                private.sidearm_file(e.source_name, e.sport));
      if (v -> 'score' ->> 0)::int < (e.live_score -> 'score' ->> 0)::int
         or (v -> 'score' ->> 1)::int < (e.live_score -> 'score' ->> 1)::int then
        v_result := 'held';
      end if;
    end if;
    if v_result is null then
      v_result := public.record_live_score(p_event, p_game);
    end if;
  end if;

  insert into private.live_reads as r (event_id, source, reads, failed, wrote, tried_at, failed_at, scored_at, why)
  values (p_event, p_source, 1, (v_result = 'failed')::int, (v_result in ('live', 'final'))::int, p_now,
          case when v_result = 'failed' then p_now end, case when v_result in ('live', 'final') then p_now end, p_why)
  on conflict (event_id, source) do update
  set reads = r.reads + 1, failed = r.failed + excluded.failed, wrote = r.wrote + excluded.wrote, tried_at = p_now,
      failed_at = coalesce(excluded.failed_at, r.failed_at), scored_at = coalesce(excluded.scored_at, r.scored_at),
      why = coalesce(excluded.why, r.why);
  return v_result;
end;
$$;

-- The backup's one read in 10 minutes: of the games whose school file and push have put no score on the card for
-- 3 minutes, the one it tried longest ago, so two dark games take turns.
create or replace function public.live_backup_turn(p_events uuid[], p_now timestamptz default now())
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select g.id
  from unnest(p_events) as g (id)
  where not exists (select 1 from private.live_reads r where r.event_id = g.id and r.source in ('school', 'push')
                      and r.scored_at > p_now - interval '3 minutes')
  order by (select r.tried_at from private.live_reads r where r.event_id = g.id and r.source = 'backup') nulls first, g.id
  limit 1
$$;

-- One alert per dark spell. sent_at null: the send failed (why says how) and the next minute tries again.
create table private.live_alerts (
  event_id uuid primary key references public.club_events (id) on delete cascade,
  dark_at timestamptz not null,
  sent_at timestamptz,
  why text
);

-- The games on now with no fresh score: none for 12 minutes (the backup reads once in 10), or none yet 30 minutes past
-- the listed start (a late start, or the gym's earlier game running long), and no alert since a score came back from
-- the school's file or the push (the 10-minute backup alone would alert again every 20 minutes with two games on it).
-- The alert's words: the game, since when, and where each source stands.
create or replace function private.live_dark(p_now timestamptz default now())
returns table (id uuid, since timestamptz, title text, message text)
language sql
stable
set search_path = ''
as $$
  select e.id, s.since, 'Live score dark: ' || e.title,
         format('No score since %s. ', to_char(s.since at time zone 'America/Chicago', 'FMHH12:MI AM'))
         || coalesce((select string_agg(format('%s: %s (%s).', private.live_source_name(e.id, r.source),
                                               case when r.failed_at = r.tried_at then r.why
                                                    when r.scored_at = r.tried_at then 'scored'
                                                    else 'no score in it' end,
                                               to_char(r.tried_at at time zone 'America/Chicago', 'FMHH12:MI AM')), ' '
                                        order by array_position('{school,push,backup}'::text[], r.source))
                      from private.live_reads r where r.event_id = e.id), 'No source has read it.')
  from private.live_games(p_now) g
  join public.club_events e on e.id = g.id
  cross join lateral (select (e.live_score ->> 'at')::timestamptz as at,
                             private.live_start(e.event_date, e.start_time) as starts_at) t
  cross join lateral (select coalesce(t.at, t.starts_at) as since) s
  where case when t.at is not null then t.at < p_now - interval '12 minutes'
             else p_now > t.starts_at + interval '30 minutes' end
    and not exists (select 1 from private.live_alerts a
                    where a.event_id = e.id and a.sent_at is not null
                      and not exists (select 1 from private.live_reads r where r.event_id = e.id
                                        and r.source in ('school', 'push') and r.scored_at > a.sent_at))
$$;

create or replace function private.live_dark_alarm(p_now timestamptz default now())
returns void
language plpgsql
set search_path = ''
as $$
declare
  d record;
  v_topic text;
  v_status int;
  v_body text;
begin
  for d in select * from private.live_dark(p_now) loop
    begin
      select s.decrypted_secret into v_topic from vault.decrypted_secrets s where s.name = 'live_alarm';
      if v_topic is null then raise exception 'no live_alarm secret in Vault'; end if;
      perform extensions.http_set_curlopt('CURLOPT_TIMEOUT', '10');
      -- ntfy's JSON publish, so a title with an accent or a curly apostrophe needs no header encoding.
      select r.status, r.content into v_status, v_body
      from extensions.http(('POST', 'https://ntfy.sh/',
        array[extensions.http_header('User-Agent', 'BlockPartyBot/1.0 (+https://blockpartystjoe.com)')], 'application/json',
        jsonb_build_object('topic', v_topic, 'title', d.title, 'message', d.message, 'priority', 4,
                           'tags', jsonb_build_array('warning'))::text)::extensions.http_request) r;
      if v_status not between 200 and 299 then
        raise exception 'ntfy answered %: %', v_status, left(v_body, 200);
      end if;
      insert into private.live_alerts as a (event_id, dark_at, sent_at, why) values (d.id, d.since, p_now, null)
      on conflict (event_id) do update set dark_at = excluded.dark_at, sent_at = excluded.sent_at, why = null;
    exception when others then
      insert into private.live_alerts as a (event_id, dark_at, sent_at, why) values (d.id, d.since, null, left(sqlerrm, 200))
      on conflict (event_id) do update set dark_at = excluded.dark_at, sent_at = null, why = excluded.why;
    end;
  end loop;
end;
$$;

-- The morning report's line per game: each source's reads, failed reads and why, and the alert.
create or replace function public.live_marks(p_events uuid[])
returns table (event_id uuid, sources jsonb, alerted_at timestamptz, alert_why text)
language sql
stable
security definer
set search_path = ''
as $$
  select g.id,
         coalesce((select jsonb_agg(jsonb_build_object('name', private.live_source_name(g.id, r.source), 'reads', r.reads,
                                                       'failed', r.failed, 'wrote', r.wrote, 'why', r.why)
                                    order by array_position('{school,push,backup}'::text[], r.source))
                   from private.live_reads r where r.event_id = g.id), '[]'),
         a.sent_at, a.why
  from unnest(p_events) as g (id)
  left join private.live_alerts a on a.event_id = g.id
$$;

revoke execute on function private.live_start(date, text) from public;
revoke execute on function private.live_source_name(uuid, text) from public;
revoke execute on function private.live_dark(timestamptz) from public;
revoke execute on function private.live_dark_alarm(timestamptz) from public;
revoke execute on function public.record_live_read(uuid, text, jsonb, text, timestamptz) from public, anon, authenticated;
revoke execute on function public.live_backup_turn(uuid[], timestamptz) from public, anon, authenticated;
revoke execute on function public.live_marks(uuid[]) from public, anon, authenticated;
grant execute on function public.record_live_read(uuid, text, jsonb, text, timestamptz) to service_role;
grant execute on function public.live_backup_turn(uuid[], timestamptz) to service_role;
grant execute on function public.live_marks(uuid[]) to service_role;

select cron.schedule('live-dark', '* * * * *', $$select private.live_dark_alarm()$$);
