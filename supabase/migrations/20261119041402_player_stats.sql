-- Each player's stats on a college basketball game's page (BP app docs/plans/game-card/issues/35-player-stats.md;
-- Jesse, 2026-11-18: "yes and each players stats", then "yes to all" to the mock, references/all-plays/, and "yes" to
-- this live change at Check-in 1).
--
-- SIDEARM's whole game file, the one the live-scores function reads every 30 s from the school's site and every 10
-- minutes from sidearmstats.com, carries each player's line under Stats.<HomeTeam|VisitingTeam>.PlayerGroups.Players
-- .Values (Uni, Name "L. ARNOLD", Position, Points, TotalRebounds, Assists, Fgam "1-1", Tpam "1-1", all strings) and
-- the team's under Stats.<team>.Totals.Values; the proper-case names are in Stats.<team>.Players by uniform number.
-- Values holds only those who played. The function now passes Stats along (live-scores/index.ts, wholeFile).
--
-- club_events.player_stats = [{rows: [{uni, name, pos, pts, reb, ast, fg, tp}], total: {pts, reb, ast, fg, tp}}, ...],
-- the host's team first, its rows most points first, then in the file's own order so a tie never swaps on a re-read.
-- Kept after the final, as the plays are.
--
-- record_live_read is copied from 20261107213654_never_blind.sql, the newest that makes it, with only the stats step
-- added.

alter table public.club_events add column player_stats jsonb;

-- A count SIDEARM writes as a string ("5"): its number, or 0 for a blank or a dash before a player has one.
create or replace function private.sidearm_n(p text)
returns int
language sql
immutable
set search_path = ''
as $$
  select case when btrim(coalesce(p, '')) ~ '^\d{1,4}$' then btrim(p)::int else 0 end
$$;

-- Made and tried ("3-9"), or "0-0".
create or replace function private.sidearm_ma(p text)
returns text
language sql
immutable
set search_path = ''
as $$
  select case when btrim(coalesce(p, '')) ~ '^\d{1,4}-\d{1,4}$' then btrim(p) else '0-0' end
$$;

-- A basketball game's whole file's player lines, the host's team first; null unless both teams have players.
create or replace function private.sidearm_box(p_full jsonb, p_host text, p_file text)
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select case when count(*) = 2 then jsonb_agg(b.box order by k.side) end
  from (select coalesce(p_full -> 'Game' -> 'HomeTeam' ->> 'Name', '') ~* p_host as home_ours,
               coalesce(p_full -> 'Game' -> 'VisitingTeam' ->> 'Name', '') ~* p_host as away_ours) h,
       lateral (values ('HomeTeam', case when h.home_ours then 0 else 1 end),
                       ('VisitingTeam', case when h.home_ours then 1 else 0 end)) k(key, side),
       lateral (select p_full -> 'Stats' -> k.key as s) t,
       lateral (select jsonb_build_object(
         'rows', (select jsonb_agg(jsonb_build_object(
                    'uni', btrim(coalesce(v ->> 'Uni', '')),
                    -- "L. Arnold" from the roster by uniform number; else the line's own "L. ARNOLD", cased.
                    'name', coalesce((select left(btrim(p ->> 'FirstName'), 1) || '. ' || btrim(p ->> 'LastName')
                                      from jsonb_array_elements(case jsonb_typeof(t.s -> 'Players') when 'array'
                                                                     then t.s -> 'Players' else '[]' end) p
                                      where p ->> 'UniformNumber' = v ->> 'Uni'
                                        and coalesce(btrim(p ->> 'FirstName'), '') <> ''
                                        and coalesce(btrim(p ->> 'LastName'), '') <> ''
                                      limit 1),
                                     initcap(btrim(v ->> 'Name'))),
                    'pos', btrim(coalesce(v ->> 'Position', '')),
                    'pts', private.sidearm_n(v ->> 'Points'),
                    'reb', private.sidearm_n(v ->> 'TotalRebounds'),
                    'ast', private.sidearm_n(v ->> 'Assists'),
                    'fg', private.sidearm_ma(v ->> 'Fgam'),
                    'tp', private.sidearm_ma(v ->> 'Tpam'))
                  -- Most points first, then the file's own order, so a tie never swaps places on the next read.
                  order by private.sidearm_n(v ->> 'Points') desc, o)
                  from jsonb_array_elements(case jsonb_typeof(t.s -> 'PlayerGroups' -> 'Players' -> 'Values') when 'array'
                                                 then t.s -> 'PlayerGroups' -> 'Players' -> 'Values' else '[]' end)
                       with ordinality x(v, o)
                  where coalesce(btrim(v ->> 'Name'), '') <> ''),
         'total', (select jsonb_build_object('pts', private.sidearm_n(tv ->> 'Points'),
                                             'reb', private.sidearm_n(tv ->> 'TotalRebounds'),
                                             'ast', private.sidearm_n(tv ->> 'Assists'),
                                             'fg', private.sidearm_ma(tv ->> 'Fgam'),
                                             'tp', private.sidearm_ma(tv ->> 'Tpam'))
                   from (select t.s -> 'Totals' -> 'Values' as tv) z)) as box) b
  where p_file like '%bball' and h.home_ours <> h.away_ours and jsonb_typeof(t.s) = 'object'
    and jsonb_typeof(b.box -> 'rows') = 'array'
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
  v_scored boolean;
  v_box jsonb;
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

  -- Each player's line (game-card 35), from a whole file of this game: the school's or the backup's, never a push. A
  -- backup held behind the card holds its stats too, being as old. Never at the cost of the score: a file it can't
  -- read leaves the stats as they were.
  if p_why is null and jsonb_typeof(p_game -> 'Stats') = 'object' and v_result is distinct from 'failed'
     and not (p_source = 'backup' and v_result = 'held') then
    begin
      v_box := private.sidearm_box(p_game, private.sidearm_host(e.source_name), private.sidearm_file(e.source_name, e.sport));
      if v_box is not null then
        update public.club_events c set player_stats = v_box where c.id = p_event and c.player_stats is distinct from v_box;
      end if;
    exception when others then
      raise warning 'record_live_read: player stats of %: %', p_event, sqlerrm;
    end;
  end if;

  -- A plays push writes plays, not the score: it neither holds the sources below nor brings a dark game back.
  v_scored := v_result in ('live', 'final') and jsonb_typeof(g) = 'object' and g ? 'HomeTeam';
  insert into private.live_reads as r (event_id, source, reads, failed, wrote, tried_at, failed_at, scored_at, why)
  values (p_event, p_source, 1, (v_result = 'failed')::int, v_scored::int, p_now,
          case when v_result = 'failed' then p_now end, case when v_scored then p_now end, p_why)
  on conflict (event_id, source) do update
  set reads = r.reads + 1, failed = r.failed + excluded.failed, wrote = r.wrote + excluded.wrote, tried_at = p_now,
      failed_at = coalesce(excluded.failed_at, r.failed_at), scored_at = coalesce(excluded.scored_at, r.scored_at),
      why = coalesce(excluded.why, r.why);
  return v_result;
end;
$$;

revoke execute on function private.sidearm_n(text) from public, anon, authenticated;
revoke execute on function private.sidearm_ma(text) from public, anon, authenticated;
revoke execute on function private.sidearm_box(jsonb, text, text) from public, anon, authenticated;
revoke execute on function public.record_live_read(uuid, text, jsonb, text, timestamptz) from public, anon, authenticated;
grant execute on function public.record_live_read(uuid, text, jsonb, text, timestamptz) to service_role;
