-- A final read live is a final read (BP app game-card, 2026-10-29): my_team_finals, the hello pill's "your team's
-- final", lists finals by when they were read (final_checked_at), which only private.read_finals set. A game the
-- live scores carried to its final never showed there. record_live_score is 20261026020227_live_score_lock.sql
-- line for line but for that.

-- Live since 20261021120100_game_finals_job.sql; named here so this file stands alone.
alter table public.club_events add column if not exists final_checked_at timestamptz;

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
  v_new jsonb;
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
  v_new := (select coalesce(jsonb_agg(n order by o), '[]')
            from jsonb_array_elements(private.sidearm_scoring(v_plays,
                   coalesce((v->>'host_home')::boolean, (e.live_score->>'host_home')::boolean), v_file)) with ordinality as x(n, o)
            where not exists (select 1 from jsonb_array_elements(coalesce(e.scoring_plays, '[]')) k where k->>'id' = n->>'id'));
  if jsonb_array_length(v_new) > 0 then
    update public.club_events set scoring_plays = coalesce(scoring_plays, '[]') || v_new where id = p_event;
  end if;
  if v is null then return case when jsonb_array_length(v_new) > 0 then 'live' else 'ignored' end; end if;
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
