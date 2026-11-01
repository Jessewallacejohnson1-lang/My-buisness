-- A scoring play takes SIDEARM's correction (SJU Football vs Gustavus, 2026-10-31): SIDEARM first sent Hansen's
-- 2nd-quarter field goal with the score before it (14-3), then corrected it to 17-3 a moment later. Plays were kept
-- once each by SIDEARM's play id, the first reading only, so the Event page said 14-3 for good. Now each play
-- already kept takes SIDEARM's latest reading of it, in its place; a new play still joins at the end.
-- record_live_score is 20261029185452_live_final_read_at.sql line for line but for that.

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
  v_read := private.sidearm_scoring(v_plays,
              coalesce((v->>'host_home')::boolean, (e.live_score->>'host_home')::boolean), v_file);
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
