-- One play per goal (Saint John's 3-2 Augsburg and Saint Ben's 1-1 Macalester, 2026-11-03; BP app game-card 13).
-- SIDEARM writes a play's Id as its place in the game's list and a hash of its words ("73+FC3012F3"), and rewrites a
-- goal as its words fill in ("Shot by CSB , GOAL", then the scorer, then the assists), or names another scorer: same
-- place, new hash. Kept by the whole Id, each rewrite was a new play, so one goal showed on two or three cards and
-- scorers read "Warren 29', 29'". A play is now known by its place alone, so record_live_score's correction (the newest
-- reading, in the play's place) takes each rewrite; a foul the same way, or a rewritten foul would count twice toward
-- Bonus. Should SIDEARM ever renumber a game's list, a moved play reads as a new one, or takes the place of the play
-- kept there. No real file shows a renumbering or two readings of one place.
--
-- Both functions are copied line for line from the newest migrations that make them (20261026001534_live_plays.sql,
-- 20261101220159_basketball_bar.sql) with only the id changed.

create or replace function private.sidearm_scoring(p_plays jsonb, p_host_home boolean, p_file text)
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', split_part(p->>'Id', '+', 1),
           'text', btrim(p->>'Narrative'),
           'period', private.sidearm_period(sport, (p->>'Period')::int),
           'clock', private.sidearm_clock(sport, case when p->>'ClockSeconds' ~ '^-?\d+$' then (p->>'ClockSeconds')::int end),
           'side', case when (p->>'Team' = 'HomeTeam') = p_host_home then 0 else 1 end,
           'score', case when p_host_home then jsonb_build_array((p->'Score'->>'HomeTeam')::int, (p->'Score'->>'VisitingTeam')::int)
                         else jsonb_build_array((p->'Score'->>'VisitingTeam')::int, (p->'Score'->>'HomeTeam')::int) end)
           order by o), '[]')
  from (select split_part(p_file, '/', 2) as sport) f,
       jsonb_array_elements(case jsonb_typeof(p_plays) when 'array' then p_plays
                                 when 'object' then coalesce(p_plays->'Plays', case when p_plays ? 'Id' then jsonb_build_array(p_plays) end, '[]')
                                 else '[]' end) with ordinality as x(p, o)
  where sport <> 'wvball' and p_host_home is not null
    and jsonb_typeof(p->'Score') = 'object' and p->'Score'->>'HomeTeam' ~ '^\d+$' and p->'Score'->>'VisitingTeam' ~ '^\d+$'
    and p->>'Team' in ('HomeTeam', 'VisitingTeam') and coalesce(p->>'Id', '') <> '' and coalesce(btrim(p->>'Narrative'), '') <> ''
    and p->>'Period' ~ '^\d+$'
$$;

create or replace function private.sidearm_fouls(p_plays jsonb, p_host_home boolean, p_regulation int,
                                                 p_kept jsonb, p_period int)
returns jsonb
language sql
immutable
set search_path = ''
as $$
  with f as (
    select split_part(p->>'Id', '+', 1) as id, case when (p->>'Team' = 'HomeTeam') = p_host_home then 0 else 1 end as side,
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

-- The plays already kept: one per place, the newest reading, where its first reading stood. No game is live now, and
-- none has fouls kept. A finished game takes no more pushes, so nothing else would clean these.
update public.club_events c
   set scoring_plays = (
     select jsonb_agg(r.p || jsonb_build_object('id', r.place) order by r.first)
     from (select split_part(x.p->>'id', '+', 1) as place, min(x.o) as first, (array_agg(x.p order by x.o desc))[1] as p
           from jsonb_array_elements(c.scoring_plays) with ordinality as x(p, o)
           group by 1) r)
 where jsonb_array_length(c.scoring_plays) > 0;
