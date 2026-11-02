-- Basketball's game page (BP app game-card 09; Jesse, 2026-11-01: "Yeah, I agree" to the mock beside the Figma
-- draft, references/basketball-bar/): the game's quarters, or a men's game's halves, as one bar filling with the
-- clock, and a Bonus tag under the team in the bonus.
--
-- private.sidearm_live is copied from 20261101001931_game_drive.sql, the newest that makes it, with three
-- numbers added for basketball only: the period being played, how many make the game (SIDEARM's
-- PeriodsRegulation: 4 quarters for CSB's women, 2 halves for SJU's men) and its length in seconds (Rules'
-- PeriodMinutes, OTMinutes past regulation), so the bar never reads the period's words.
--
-- public.record_live_score is copied from 20261031190500_live_plays_take_corrections.sql (PR 13's, applied live as
-- 20261031195727 and brought to main beside this one), the newest that makes it and the version live:
-- a kept play takes SIDEARM's latest reading of it. The fouls are added. PR 13's 20261031201500_live_clock_kept_fresh.sql
-- (not applied) re-creates record_live_score too: it must be rebuilt on this one before it is applied, or the fouls go.
--
-- The bonus: SIDEARM's game file has no foul count, but each foul is a play (Type FOUL), and a quarter's FOUL plays
-- per team matched SIDEARM's own per-quarter Personal Fouls 8 of 8 on CSB 79-57 Augsburg (2026-02-21). Pushes
-- bring plays as the Game's LastPlays (the newest five) or as a plays push, so the fouls are kept by play id:
-- live_score.fouls = {period, ids: [host's, other's]}, the quarter or half they count in (overtime counts with
-- the last one, the NCAA rule) and the ids of the fouls seen in it. A new period starts it empty. The app counts
-- them: the other team's 5th foul of a quarter, or 7th of a half, puts a team in the bonus.

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
revoke execute on function private.sidearm_live(jsonb, date, text, text) from public;

-- The fouls kept so far (p_kept) with the ones these plays list: the plays a push carries (an array, a Game's
-- LastPlays, a plays push's Plays, or one play), the host's side, how many periods make the game, and the period
-- being played when the push says (a Game), else null. The period only moves forward: the newest of the kept one,
-- the one being played and the newest foul's.
create or replace function private.sidearm_fouls(p_plays jsonb, p_host_home boolean, p_regulation int,
                                                 p_kept jsonb, p_period int)
returns jsonb
language sql
immutable
set search_path = ''
as $$
  with f as (
    select p->>'Id' as id, case when (p->>'Team' = 'HomeTeam') = p_host_home then 0 else 1 end as side,
           least((p->>'Period')::int, p_regulation) as period
    from jsonb_array_elements(case jsonb_typeof(p_plays) when 'array' then p_plays
                                   when 'object' then coalesce(p_plays->'Plays', case when p_plays ? 'Id' then jsonb_build_array(p_plays) end, '[]')
                                   else '[]' end) p
    where p_host_home is not null and p->>'Type' = 'FOUL' and p->>'Team' in ('HomeTeam', 'VisitingTeam')
      and coalesce(p->>'Id', '') <> '' and p->>'Period' ~ '^\d+$'),
  k as (select case when p_kept->>'period' ~ '^\d+$' then (p_kept->>'period')::int end as period),
  -- least() skips a null: a plays push (no period) must not read as the last one.
  now as (select greatest(k.period, case when p_period is not null then least(p_period, p_regulation) end,
                          (select max(period) from f)) as period from k)
  select case when now.period is null or p_regulation is null then p_kept else jsonb_build_object(
    'period', now.period,
    'ids', jsonb_build_array(
      (select coalesce(jsonb_agg(id order by id), '[]') from (
         select jsonb_array_elements_text(case when k.period = now.period then p_kept->'ids'->0 end) union
         select id from f where side = 0 and period = now.period) s(id)),
      (select coalesce(jsonb_agg(id order by id), '[]') from (
         select jsonb_array_elements_text(case when k.period = now.period then p_kept->'ids'->1 end) union
         select id from f where side = 1 and period = now.period) s(id))))
  end
  from k, now
$$;
revoke execute on function private.sidearm_fouls(jsonb, boolean, int, jsonb, int) from public;

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
  if v is null then return case when v_merged is distinct from v_kept then 'live' else 'ignored' end; end if;
  if (v->>'complete')::boolean and coalesce((e.live_score->>'complete')::boolean, false)
     and v->'score' = e.live_score->'score' then
    -- The last live score stays beside the final for its period scores (volleyball's sets); the final wins
    -- everywhere it's read.
    update public.club_events
    set final_score = array[(v->'score'->>0)::int, (v->'score'->>1)::int], live_score = v || jsonb_build_object('at', now()),
        final_checked_at = now()
    where id = p_event;
    return 'final';
  end if;
  -- Only a change is written, so realtime sends the app nothing for a push that moved nothing it shows.
  update public.club_events set live_score = v || jsonb_build_object('at', now())
  where id = p_event and (live_score is null or live_score - 'at' is distinct from v);
  return 'live';
end;
$$;
revoke execute on function public.record_live_score(uuid, jsonb) from public, anon, authenticated;
grant execute on function public.record_live_score(uuid, jsonb) to service_role;
