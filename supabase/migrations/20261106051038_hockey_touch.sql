-- Hockey's game page (BP app game-card 09; Jesse, 2026-11-05: "Yes to all" to the mock beside the Figma draft,
-- references/hockey-power-play/): Saint John's and Saint Ben's hockey join the live job, and the page shows a power-play
-- bar running down in the team's color and shots on goal either side.
--
-- What SIDEARM's hockey file says, read on 10 real games (2026-11-05; Bethel 1-2 UW-Superior is the story's):
-- - A power play opens and closes as its own play ("Start of power play for BET.", "End of power play for BET."; a
--   Genius-scored file says "Start power play for PRO."), the team and clock on it. All 64 match SIDEARM's own count.
--   No length: a penalty's words say none ("Penalty on Brennan,Sam SUP for HOLDING.").
-- - Shots on goal are only in the whole file's Stats, not in a Game or a plays push. Live, each is a Shot play saying
--   "save", or a goal: that matched SIDEARM's totals exactly on 18 of 20 sides, 1 off on the other 2. So the plays are
--   counted while it's on, and SIDEARM's own totals come with the final.
-- - A play's clock counts up from the period's start and the Game's down to its end (a goal at 192 s, the Game's clock
--   1008 of 1200), whatever Rules.ClockDirection says. A card shows what the rink's clock read.
-- - A goal or a shot's Team is often null, its Player's Team set. Overtime's plays can say ClockSeconds -1 and open
--   "[NaN:NaN] ".
--
-- live_score.ice = {saves: [host's ids, other's], power: [{id, side, start, at}]}, kept by the play's place in SIDEARM's
-- list, as basketball's fouls are, since a push holds only the newest five. at: the game's second, none in overtime.
-- The app reads the power play on now and the shots from it (Game.Live). live_score.shots: SIDEARM's own, at the final.
--
-- sidearm_file is copied from 20261025160000_live_scores.sql, sidearm_period from 20261026001534_live_plays.sql,
-- sidearm_live from 20261101220159_basketball_bar.sql, sidearm_scoring from 20261104000619_one_play_per_goal.sql and
-- record_live_score from 20261104152336_penalty_winner.sql, the newest that make them, with only the hockey lines added.

create or replace function private.sidearm_file(p_source text, p_sport text)
returns text
language sql
immutable
set search_path = ''
as $$
  select case p_source || '/' || p_sport
    when 'SJU Athletics/Football' then 'csbsju/football'
    when 'SJU Athletics/Soccer' then 'csbsju/msoc'
    when 'SJU Athletics/Basketball' then 'csbsju/mbball'
    when 'CSB Athletics/Soccer' then 'csb/wsoc'
    when 'CSB Athletics/Volleyball' then 'csb/wvball'
    when 'CSB Athletics/Basketball' then 'csb/wbball'
    when 'SJU Athletics/Hockey' then 'csbsju/mhockey'
    when 'CSB Athletics/Hockey' then 'csb/whockey' end
$$;

create or replace function private.sidearm_period(p_sport text, p_period int)
returns text
language sql
immutable
set search_path = ''
as $$
  select case
    when p_sport in ('football', 'wbball') then case when p_period between 1 and 4 then 'Q' || p_period else 'OT' end
    when p_sport = 'wvball' then 'Set ' || p_period
    when p_sport like '%hockey' then case when p_period between 1 and 3 then 'P' || p_period else 'OT' end
    else case p_period when 1 then '1st half' when 2 then '2nd half' else 'OT' end end
$$;

create or replace function private.sidearm_live(p_game jsonb, p_day date, p_host text, p_file text)
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select jsonb_build_object(
    'score', case when h.ours then jsonb_build_array(h.score, v.score) else jsonb_build_array(v.score, h.score) end,
    'period', private.sidearm_period(sport, per),
    -- Football and basketball count down ("4:12"), soccer up (its minute, "67'"); volleyball has none.
    'clock', private.sidearm_clock(sport, cs),
    -- The clock in seconds, so a soccer card can run its minute on between pushes.
    'clock_s', case when cs >= 0 and sport <> 'wvball' then cs end,
    -- Each period's score, host first: volleyball's sets.
    'periods', case when h.ours then jsonb_build_array(h.periods, v.periods) else jsonb_build_array(v.periods, h.periods) end,
    'host_home', h.ours,
    -- Football's down, distance and spot, and who has the ball (game-card 08): the field bar.
    'drive', case when sport = 'football' then private.sidearm_drive(g, h.ours) end,
    'complete', coalesce(g->>'IsComplete', '') = 'true')
    -- Basketball's bar (game-card 09): the period being played, how many make the game, and its length.
    || case when sport like '%bball' and r.reg > 0 then jsonb_build_object(
         'period_n', per,
         'regulation', r.reg,
         'period_s', case when per > r.reg then r.ot else r.len end * 60)
       else '{}' end
    -- Hockey's power play counts from the period being played (game-card 09).
    || case when sport like '%hockey' then jsonb_build_object('period_n', per) else '{}' end
  from (select coalesce(p_game->'Game', p_game) as g, split_part(p_file, '/', 2) as sport) f,
       lateral (select case when g->>'Period' ~ '^\d+$' then (g->>'Period')::int end as per,
                       case when g->>'ClockSeconds' ~ '^-?\d+$' then (g->>'ClockSeconds')::int end as cs) n,
       lateral (select case when g->>'PeriodsRegulation' ~ '^\d+$' then (g->>'PeriodsRegulation')::int end as reg,
                       case when g->'Rules'->>'PeriodMinutes' ~ '^\d+$' then (g->'Rules'->>'PeriodMinutes')::int end as len,
                       case when g->'Rules'->>'OTMinutes' ~ '^\d+$' then (g->'Rules'->>'OTMinutes')::int end as ot) r,
       lateral (select coalesce(g->'HomeTeam'->>'Name', '') ~* p_host as ours,
                       case when g->'HomeTeam'->>'Score' ~ '^\d+$' then (g->'HomeTeam'->>'Score')::int end as score,
                       coalesce(g->'HomeTeam'->'PeriodScores', '[]') as periods) h,
       lateral (select coalesce(g->'VisitingTeam'->>'Name', '') ~* p_host as ours,
                       case when g->'VisitingTeam'->>'Score' ~ '^\d+$' then (g->'VisitingTeam'->>'Score')::int end as score,
                       coalesce(g->'VisitingTeam'->'PeriodScores', '[]') as periods) v
  where g->>'HasStarted' = 'true'
    and g->>'Date' ~ '^\d{1,2}/\d{1,2}/\d{4}$' and to_date(g->>'Date', 'MM/DD/YYYY') = p_day
    and h.ours <> v.ours and h.score is not null and v.score is not null and n.per is not null
$$;

create or replace function private.sidearm_scoring(p_plays jsonb, p_host_home boolean, p_file text)
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', split_part(p->>'Id', '+', 1),
           'text', regexp_replace(btrim(p->>'Narrative'), '^\[NaN:NaN\] ', ''),
           'period', private.sidearm_period(sport, (p->>'Period')::int),
           -- Hockey's plays count up and its clock down: what the rink's clock read. Overtime's length isn't on a play, so its period alone.
           'clock', private.sidearm_clock(sport, case when p->>'ClockSeconds' !~ '^-?\d+$' then null
                                                      when sport not like '%hockey' then (p->>'ClockSeconds')::int
                                                      when (p->>'Period')::int <= 3 and (p->>'ClockSeconds')::int >= 0
                                                        then 1200 - (p->>'ClockSeconds')::int end),
           'side', case when (t.team = 'HomeTeam') = p_host_home then 0 else 1 end,
           'score', case when p_host_home then jsonb_build_array((p->'Score'->>'HomeTeam')::int, (p->'Score'->>'VisitingTeam')::int)
                         else jsonb_build_array((p->'Score'->>'VisitingTeam')::int, (p->'Score'->>'HomeTeam')::int) end)
           order by o), '[]')
  from (select split_part(p_file, '/', 2) as sport) f,
       jsonb_array_elements(case jsonb_typeof(p_plays) when 'array' then p_plays
                                 when 'object' then coalesce(p_plays->'Plays', case when p_plays ? 'Id' then jsonb_build_array(p_plays) end, '[]')
                                 else '[]' end) with ordinality as x(p, o),
       -- A hockey goal's Team is often null, its Player's set.
       lateral (select case when sport like '%hockey' then coalesce(p->>'Team', p->'Player'->>'Team') else p->>'Team' end as team) t
  where sport <> 'wvball' and p_host_home is not null
    and jsonb_typeof(p->'Score') = 'object' and p->'Score'->>'HomeTeam' ~ '^\d+$' and p->'Score'->>'VisitingTeam' ~ '^\d+$'
    and t.team in ('HomeTeam', 'VisitingTeam') and coalesce(p->>'Id', '') <> '' and coalesce(btrim(p->>'Narrative'), '') <> ''
    and p->>'Period' ~ '^\d+$'
$$;

-- What a push adds to live_score.ice: each play known by its place in SIDEARM's list, the newest reading winning, so a
-- rewrite counts once and a shot rewritten to wide stops counting. Without the host's side, what's kept.
create or replace function private.sidearm_ice(p_plays jsonb, p_host_home boolean, p_kept jsonb)
returns jsonb
language sql
immutable
set search_path = ''
as $$
  with r as (
    select split_part(p->>'Id', '+', 1) as id,
           case when (t.team = 'HomeTeam') = p_host_home then 0 else 1 end as side,
           t.team in ('HomeTeam', 'VisitingTeam') and p->>'Type' = 'Shot' and w.words ~* '\msave\M' as save,
           t.team in ('HomeTeam', 'VisitingTeam') and w.words ~ '^(Start|End)( of)? power play for ' as power,
           w.words ~ '^Start' as start,
           case when p->>'Period' ~ '^[123]$' and p->>'ClockSeconds' ~ '^\d+$'
                then ((p->>'Period')::int - 1) * 1200 + (p->>'ClockSeconds')::int end as at
    from jsonb_array_elements(case jsonb_typeof(p_plays) when 'array' then p_plays
                                   when 'object' then coalesce(p_plays->'Plays', case when p_plays ? 'Id' then jsonb_build_array(p_plays) end, '[]')
                                   else '[]' end) p,
         lateral (select coalesce(p->>'Team', p->'Player'->>'Team') as team) t,
         lateral (select regexp_replace(coalesce(p->>'Narrative', ''), '^\[NaN:NaN\] ', '') as words) w
    where split_part(p->>'Id', '+', 1) ~ '^\d+$')
  select case when p_host_home is null then p_kept else jsonb_build_object(
    'saves', jsonb_build_array(
      (select coalesce(jsonb_agg(id order by id), '[]') from (
         select jsonb_array_elements_text(p_kept->'saves'->0) except select id from r
         union select id from r where save and side = 0) s(id)),
      (select coalesce(jsonb_agg(id order by id), '[]') from (
         select jsonb_array_elements_text(p_kept->'saves'->1) except select id from r
         union select id from r where save and side = 1) s(id))),
    'power', (select coalesce(jsonb_agg(l order by (l->>'id')::int), '[]') from (
      select l from jsonb_array_elements(coalesce(p_kept->'power', '[]')) l where l->>'id' not in (select id from r)
      union all
      select jsonb_build_object('id', id, 'side', side, 'start', start, 'at', at) from r where power) q(l)))
  end
$$;
revoke execute on function private.sidearm_ice(jsonb, boolean, jsonb) from public, anon, authenticated;

-- SIDEARM's own shots on goal in a game's whole file, host first, for the final: {"shots": [56, 24]}. Null when it can't
-- say: another game's file, one still on, a file with no totals.
create or replace function private.sidearm_shots(p_full jsonb, p_day date, p_host text)
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select jsonb_build_object('shots', case when h.ours then jsonb_build_array(s.home::int, s.away::int)
                                          else jsonb_build_array(s.away::int, s.home::int) end)
  from (select p_full->'Game' as g) f,
       lateral (select coalesce(g->'HomeTeam'->>'Name', '') ~* p_host as ours,
                       coalesce(g->'VisitingTeam'->>'Name', '') ~* p_host as theirs) h,
       lateral (select p_full->'Stats'->'HomeTeam'->'Totals'->'Values'->>'Shots' as home,
                       p_full->'Stats'->'VisitingTeam'->'Totals'->'Values'->>'Shots' as away) s
  where g->>'IsComplete' = 'true' and h.ours <> h.theirs and s.home ~ '^\d+$' and s.away ~ '^\d+$'
    and g->>'Date' ~ '^\d{1,2}/\d{1,2}/\d{4}$' and to_date(g->>'Date', 'MM/DD/YYYY') = p_day
$$;
revoke execute on function private.sidearm_shots(jsonb, date, text) from public, anon, authenticated;

-- Reads a game's whole file for its shots, as read_shootout does for kicks. Five seconds at most: it runs with the game's
-- row held. Null when the read fails: the count from the plays stands.
create or replace function private.read_shots(p_source text, p_sport text, p_day date)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_file text := private.sidearm_file(p_source, p_sport);
  v_status int;
  v_body text;
begin
  if v_file is null then return null; end if;
  perform extensions.http_set_curlopt('CURLOPT_TIMEOUT', '5');
  select r.status, r.content into v_status, v_body
  from extensions.http(('GET', format('https://sidearmstats.com/%s/game.json?detail=full', v_file),
    array[extensions.http_header('User-Agent', 'BlockPartyBot/1.0 (+https://blockpartystjoe.com)')],
    null, null)::extensions.http_request) r;
  return case when v_status = 200 then private.sidearm_shots(v_body::jsonb, p_day, private.sidearm_host(p_source)) end;
exception when others then
  return null;
end;
$$;
revoke execute on function private.read_shots(text, text, date) from public, anon, authenticated;


create or replace function public.record_live_score(p_event uuid, p_game jsonb)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  e record;
  v jsonb;
  v_file text;
  v_plays jsonb;
  v_read jsonb;
  v_kept jsonb;
  v_merged jsonb;
  v_host boolean;
  v_reg int;
  v_fouls jsonb;
  v_ice jsonb;
begin
  select c.event_date, c.source_name, c.sport, c.live_score, c.final_score, c.scoring_plays into e
  from public.club_events c where c.id = p_event
  -- Held until this write is done: a score and its play arrive on two channels at once, and two writes
  -- reading the same row would both add the play, or an older score land last.
  for update;
  if not found or e.final_score is not null then return 'ignored'; end if;
  v_file := private.sidearm_file(e.source_name, e.sport);
  v := case when jsonb_typeof(p_game) = 'object' and (p_game ? 'Game' or p_game ? 'HomeTeam')
            then private.sidearm_live(p_game, e.event_date, private.sidearm_host(e.source_name), v_file) end;
  -- Scoring plays from the Game's last plays or a plays push, the host's side known from this or the last read.
  v_plays := case when jsonb_typeof(p_game) = 'object' and (p_game ? 'Game' or p_game ? 'HomeTeam')
                  then coalesce(p_game->'Game'->'LastPlays', p_game->'LastPlays') else p_game end;
  v_host := coalesce((v->>'host_home')::boolean, (e.live_score->>'host_home')::boolean);
  v_read := private.sidearm_scoring(v_plays, v_host, v_file);
  v_kept := coalesce(e.scoring_plays, '[]');
  -- Each kept play as SIDEARM reads it now (its correction), in its place; then the new ones, oldest first.
  v_merged := (select coalesce(jsonb_agg(coalesce((select n from jsonb_array_elements(v_read) n
                                                   where n->>'id' = k->>'id' limit 1), k) order by ko), '[]')
               from jsonb_array_elements(v_kept) with ordinality as y(k, ko))
           || (select coalesce(jsonb_agg(n order by o), '[]')
               from jsonb_array_elements(v_read) with ordinality as x(n, o)
               where not exists (select 1 from jsonb_array_elements(v_kept) k where k->>'id' = n->>'id'));
  -- Only a change is written, so realtime sends the app nothing for a push that moved nothing it shows.
  if v_merged is distinct from v_kept then
    update public.club_events set scoring_plays = v_merged where id = p_event;
  end if;
  -- Basketball's fouls this quarter or half (game-card 09): ride a Game's score, or join the kept score when a
  -- plays push brings one, its time kept.
  v_reg := coalesce((v->>'regulation')::int, (e.live_score->>'regulation')::int);
  if v_reg is not null then
    v_fouls := private.sidearm_fouls(v_plays, v_host, v_reg, e.live_score->'fouls', (v->>'period_n')::int);
    if v is not null and v_fouls is not null then
      v := v || jsonb_build_object('fouls', v_fouls);
    elsif v is null and e.live_score is not null and v_fouls is distinct from e.live_score->'fouls' then
      update public.club_events set live_score = live_score || jsonb_build_object('fouls', v_fouls) where id = p_event;
      return 'live';
    end if;
  end if;
  -- Hockey's shots and power plays (game-card 09), the same way.
  if v_file like '%hockey' then
    v_ice := private.sidearm_ice(v_plays, v_host, e.live_score->'ice');
    if v is not null and v_ice is not null then
      v := v || jsonb_build_object('ice', v_ice);
    elsif v is null and e.live_score is not null and v_ice is distinct from e.live_score->'ice' then
      update public.club_events set live_score = live_score || jsonb_build_object('ice', v_ice) where id = p_event;
      return 'live';
    end if;
  end if;
  if v is null then return case when v_merged is distinct from v_kept then 'live' else 'ignored' end; end if;
  if (v->>'complete')::boolean and coalesce((e.live_score->>'complete')::boolean, false)
     and v->'score' = e.live_score->'score' then
    -- A tie in overtime may have gone to penalty kicks: who won comes with the final, in this one write, so nothing
    -- ever reads it as a tie (game-card 15). A read that fails leaves it for read_finals to try again.
    if v_file like '%hockey' then
      -- SIDEARM's own shots on goal come with the final; a hockey tie has no kicks to read.
      v := v || coalesce(private.read_shots(e.source_name, e.sport, e.event_date), '{}');
    elsif v->'score'->>0 = v->'score'->>1 and v->>'period' = 'OT' then
      v := v || coalesce(private.read_shootout(e.source_name, e.sport, e.event_date), '{}');
    end if;
    -- The last live score stays beside the final for its period scores (volleyball's sets); the final wins
    -- everywhere it's read.
    update public.club_events
    set final_score = array[(v->'score'->>0)::int, (v->'score'->>1)::int], live_score = v || jsonb_build_object('at', now()),
        final_checked_at = now()
    where id = p_event;
    return 'final';
  end if;
  -- Only a change is written, so realtime sends the app nothing for a push that moved nothing it shows; but an
  -- unchanged score is written again once its 'at' is a minute old, so 'at' says SIDEARM still confirms it and the
  -- app keeps the clock it would otherwise hide as stale after 2 minutes (Game.Live.staleAfter).
  update public.club_events set live_score = v || jsonb_build_object('at', now())
  where id = p_event and (live_score is null or live_score - 'at' is distinct from v
                          or coalesce((live_score->>'at')::timestamptz, '-infinity') < now() - interval '60 seconds');
  return 'live';
end;
$$;
revoke execute on function private.sidearm_file(text, text) from public;
revoke execute on function private.sidearm_period(text, int) from public;
revoke execute on function private.sidearm_live(jsonb, date, text, text) from public;
revoke execute on function private.sidearm_scoring(jsonb, boolean, text) from public;
revoke execute on function public.record_live_score(uuid, jsonb) from public, anon, authenticated;
grant execute on function public.record_live_score(uuid, jsonb) to service_role;
