-- A football clock that stands still stays on the card (SJU Football vs Gustavus, 2026-10-31; Jesse: "It doesn't
-- have a game clock"). The app hides a clock whose live_score.at is over 2 minutes old (Game.Live.staleAfter), and
-- 'at' only moved when the score, period or clock changed. Football's clock stands still between plays, through
-- timeouts and at breaks, so a clock SIDEARM still showed (Q4 10:37 at 20:11 UTC) was over 2 minutes old here and
-- hidden. Now a push that confirms the same score writes it again once 'at' is a minute old: at most one quiet
-- write a minute a game.
--
-- record_live_score is copied line for line from 20261101220159_basketball_bar.sql, the newest that makes it and
-- the version live, with only that rewrite added. The rewrite writes v, which already carries basketball's fouls,
-- period_n, regulation and period_s, so Bonus keeps its count. This replaces PR 13's 20261031201500 version, which
-- was built on the record_live_score from before basketball and would have dropped the fouls.

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
  -- Only a change is written, so realtime sends the app nothing for a push that moved nothing it shows; but an
  -- unchanged score is written again once its 'at' is a minute old, so 'at' says SIDEARM still confirms it and the
  -- app keeps the clock it would otherwise hide as stale after 2 minutes (Game.Live.staleAfter).
  update public.club_events set live_score = v || jsonb_build_object('at', now())
  where id = p_event and (live_score is null or live_score - 'at' is distinct from v
                          or coalesce((live_score->>'at')::timestamptz, '-infinity') < now() - interval '60 seconds');
  return 'live';
end;
$$;
revoke execute on function public.record_live_score(uuid, jsonb) from public, anon, authenticated;
grant execute on function public.record_live_score(uuid, jsonb) to service_role;
