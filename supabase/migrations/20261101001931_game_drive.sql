-- A live football game's down, distance and spot, and who has the ball (BP app game-card 08): the field
-- bar on its Event page. private.sidearm_live is copied from 20261026001534_live_plays.sql, the newest
-- that makes it, with the drive added; live_score reaches the app whole, so nothing else changes.

create or replace function private.sidearm_drive(p_game jsonb, p_host_home boolean)
returns jsonb
language sql
immutable
set search_path = ''
as $$
  -- No play yet: no row, so null. A newest play with no down (a kickoff, an extra point) is none too, never
  -- the snap before it: after a touchdown that would give the ball to the team that just scored.
  select case when p.down between 1 and 4 and p.spot is not null and p.team in ('HomeTeam', 'VisitingTeam') then
    jsonb_build_object(
      'down', p.down,
      'togo', p.togo,
      'spot', p.spot,
      'side', case when (p.team = 'HomeTeam') = p_host_home then 0 else 1 end,
      'ball', case
        when s.yard is null or s.yard > 50 then null
        when s.side = '' then case when s.yard = 50 then 50 end
        when s.side = upper(coalesce(g->(case when p_host_home then 'HomeTeam' else 'VisitingTeam' end)->>'Id', '')) then s.yard
        when s.side = upper(coalesce(g->(case when p_host_home then 'VisitingTeam' else 'HomeTeam' end)->>'Id', '')) then 100 - s.yard
        end)
  end
  from (select coalesce(p_game->'Game', p_game) as g) f,
       lateral (select case when x->>'Down' ~ '^\d$' then (x->>'Down')::int end as down,
                       nullif(x->>'ToGo', '') as togo,
                       nullif(upper(replace(x->>'Spot', ' ', '')), '') as spot,
                       x->>'Team' as team
                -- The newest real play: "End of game." and the quarter breaks (Type "#") name a team that hasn't the ball.
                from (select x from jsonb_array_elements(coalesce(g->'LastPlays', '[]')) with ordinality as l(x, o)
                      where coalesce(x->>'Type', '') <> '#' order by o limit 1) l) p,
       lateral (select coalesce(substring(p.spot from '^([A-Z]*)'), '') as side,
                       case when substring(p.spot from '(\d+)$') is not null then substring(p.spot from '(\d+)$')::int end as yard) s
$$;
revoke execute on function private.sidearm_drive(jsonb, boolean) from public;

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
  from (select coalesce(p_game->'Game', p_game) as g, split_part(p_file, '/', 2) as sport) f,
       lateral (select case when g->>'Period' ~ '^\d+$' then (g->>'Period')::int end as per,
                       case when g->>'ClockSeconds' ~ '^-?\d+$' then (g->>'ClockSeconds')::int end as cs) n,
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
