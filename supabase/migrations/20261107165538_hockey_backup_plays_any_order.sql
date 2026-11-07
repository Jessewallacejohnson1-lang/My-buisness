-- Hockey's two checks on the plays (game-card 09) read them in any order. A push's LastPlays holds the newest five,
-- newest first, but the live-scores backup (iOS main b9a02a91, while SIDEARM's file host is down) sends the whole file's
-- Plays oldest first, where the first is always "Game START.": every hockey game read that way stayed not on. Now a
-- game is not on while its plays are only "Game START.", and a period is over when any play says "Period END." for it.
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
                       -- A hockey period just over can read 20:00 until the next begins (CSB, 2026-11-06): it's at 0.
                       case when sport like '%hockey' and exists (
                                   select 1 from jsonb_array_elements(case jsonb_typeof(g->'LastPlays') when 'array'
                                                                      then g->'LastPlays' else '[]' end) p
                                   where p->>'Narrative' = 'Period END.' and p->>'Period' = g->>'Period') then 0
                            when g->>'ClockSeconds' ~ '^-?\d+$' then (g->>'ClockSeconds')::int end as cs) n,
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
    -- A hockey file opens half an hour before the puck with only "Game START." in it (SJU, CSB, 2026-11-06): not on yet.
    and (sport not like '%hockey' or not coalesce((
           select bool_and(p->>'Narrative' = 'Game START.')
           from jsonb_array_elements(case jsonb_typeof(g->'LastPlays') when 'array' then g->'LastPlays' else '[]' end) p), false))
$$;
revoke execute on function private.sidearm_live(jsonb, date, text, text) from public;
