-- A game decided on penalty kicks says who won (Saint Ben's 1-1 Macalester, CSB 5-4 on kicks, 2026-11-03; BP app
-- game-card 15; Jesse: "yes to all" to the mock). The final stays 1-1, so the kicks are their own key,
-- live_score.shootout: {"score": [5, 4], "who": "CSB"}, in the final's order, host first, with the winner's letters as
-- SIDEARM has them. The app fades the loser and says "CSB wins 5-4 on penalties" from it.
--
-- Only SIDEARM's whole file has the kicks: detail=game ends its period scores 0-0 and a push holds the newest 5 plays.
-- It has no word of the game's day but Game.Date, and moves on to the next game, so that is checked.
--
-- record_live_score is copied line for line from 20261102144455_live_clock_kept_fresh.sql, read_finals from
-- 20261026001534_live_plays.sql and my_team_finals from 20261023120200_team_finals_approved.sql, the newest that make
-- them, with only the marked lines added.

-- The kicks in a game's whole file, merged into live_score by the caller: {"shootout": {...}}, or {"shootout": null}
-- for a finished game with no kicks, a draw. Null when it can't say yet: another game's file, one still on, or level
-- counts, which a real shootout never ends on. A kick went in unless it was saved, missed or hit the post: every kick
-- says "onTarget", saved ones too, so the words after the shooter and the goalmouth decide, as they do for a shot.
create or replace function private.sidearm_shootout(p_full jsonb, p_day date, p_host text)
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select case
    when k.kicks = 0 then jsonb_build_object('shootout', null)
    when k.home = k.away then null
    else jsonb_build_object('shootout', jsonb_build_object(
      'score', case when h.ours then jsonb_build_array(k.home, k.away) else jsonb_build_array(k.away, k.home) end,
      'who', case when k.home > k.away then g->'HomeTeam'->>'Id' else g->'VisitingTeam'->>'Id' end))
    end
  from (select p_full->'Game' as g) f,
       lateral (select coalesce(g->'HomeTeam'->>'Name', '') ~* p_host as ours,
                       coalesce(g->'VisitingTeam'->>'Name', '') ~* p_host as theirs) h,
       lateral (select count(*) as kicks,
                       count(*) filter (where p->>'Team' = 'HomeTeam' and in_goal) as home,
                       count(*) filter (where p->>'Team' = 'VisitingTeam' and in_goal) as away
                from jsonb_array_elements(case when jsonb_typeof(p_full->'Plays') = 'array' then p_full->'Plays' else '[]' end) as x(p),
                     lateral (select coalesce(p->>'Narrative', '') !~ 'Shootout save by'
                                     and coalesce(p->>'Qualifiers', '') !~ '"(blocked|goalmouth:(out|woodwork)[a-z]*)"' as in_goal) i
                where p->>'Type' = 'SHOOTOUTKICK') k
  where g->>'IsComplete' = 'true' and h.ours <> h.theirs
    and g->>'Date' ~ '^\d{1,2}/\d{1,2}/\d{4}$' and to_date(g->>'Date', 'MM/DD/YYYY') = p_day
$$;
revoke execute on function private.sidearm_shootout(jsonb, date, text) from public, anon, authenticated;

-- Reads a game's whole file for its kicks. Five seconds at most: it runs with the game's row held. Null when the read
-- fails, for the job to try again.
create or replace function private.read_shootout(p_source text, p_sport text, p_day date)
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
  return case when v_status = 200 then private.sidearm_shootout(v_body::jsonb, p_day, private.sidearm_host(p_source)) end;
exception when others then
  return null;
end;
$$;
revoke execute on function private.read_shootout(text, text, date) from public, anon, authenticated;

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
    -- A tie in overtime may have gone to penalty kicks: who won comes with the final, in this one write, so nothing
    -- ever reads it as a tie (game-card 15). A read that fails leaves it for read_finals to try again.
    if v->'score'->>0 = v->'score'->>1 and v->>'period' = 'OT' then
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

revoke execute on function public.record_live_score(uuid, jsonb) from public, anon, authenticated;
grant execute on function public.record_live_score(uuid, jsonb) to service_role;

create or replace function private.read_finals(p_now timestamptz default now())
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  g record;
  v_status int;
  v_body text;
  v_final int[];
  v_url text;
  v_file text;
  v_host text;
  n_league int := 0;
  n_files int := 0;
  n_finals int := 0;
  v_refused boolean := false;
  v_shootout jsonb;
  v_today date := (p_now at time zone 'America/Chicago')::date;
begin
  perform extensions.http_set_curlopt('CURLOPT_TIMEOUT', '20');
  for g in
    select e.id, e.event_date, e.team_ids, e.sport, e.source_name, e.source_uid, e.source_url
    from public.club_events e
    cross join lateral (select regexp_match(lower(btrim(e.start_time)), '^(\d{1,2})(?::(\d{2}))?\s*([ap])\.?m\.?$') as m) t
    where e.team_ids is not null and e.final_score is null and e.cancelled_at is null and e.status = 'approved'
      and e.event_date between v_today - 1 and v_today
      and (e.final_checked_at is null or e.final_checked_at < p_now - interval '55 minutes')
      -- Over: its end, else three hours after its start (as the Town feed keeps a game), else the day's end.
      and p_now > coalesce(e.end_at,
            (e.event_date + make_interval(mins => (t.m[1]::int % 12) * 60 + coalesce(t.m[2], '0')::int
                                                  + case when t.m[3] = 'p' then 720 else 0 end))
              at time zone 'America/Chicago' + interval '3 hours',
            (e.event_date + 1)::timestamp at time zone 'America/Chicago')
    order by e.event_date, e.created_at
  loop
    v_final := null;
    v_url := null;
    if g.source_uid like 'mshsl:%' and g.source_url ~ '/group/\d+/' then
      continue when n_league >= 6 or v_refused;
      v_url := format('https://www.mshsl.org/api/team-data/schedule/%s/varsity/%s?start_date=%s&end_date=%s',
                      (regexp_match(g.source_url, '/group/(\d+)/'))[1], (regexp_match(g.source_uid, '^mshsl:(\d+):'))[1],
                      g.event_date, g.event_date + 1);
      if n_league > 0 then perform pg_sleep(5); end if;
      n_league := n_league + 1;
    else
      v_file := private.sidearm_file(g.source_name, g.sport);
      v_host := private.sidearm_host(g.source_name);
      continue when v_file is null or n_files >= 1;
      v_url := format('https://sidearmstats.com/%s/game.json?detail=game', v_file);
      n_files := n_files + 1;
    end if;
    v_status := null;
    begin
      select r.status, r.content into v_status, v_body
      from extensions.http(('GET', v_url,
        array[extensions.http_header('User-Agent', 'BlockPartyBot/1.0 (+https://blockpartystjoe.com)')],
        null, null)::extensions.http_request) r;
      if v_status = 200 then
        v_final := case when g.source_uid like 'mshsl:%'
          then private.league_final(v_body::jsonb, g.source_uid, g.event_date, g.team_ids)
          else private.sidearm_final(v_body::jsonb, g.event_date, v_host) end;
      end if;
    exception when others then
      v_final := null;  -- unreachable or not JSON: tried again in an hour
    end;
    -- A final wins over the live score wherever it's read; the last live score stays beside it for its
    -- period scores (volleyball's sets, game-card 05).
    update public.club_events set final_checked_at = p_now, final_score = v_final where id = g.id;
    n_finals := n_finals + (v_final is not null)::int;
    -- The league turning us away ends this run's reads there.
    if g.source_uid like 'mshsl:%' and v_status in (403, 429) then v_refused := true; end if;
  end loop;
  -- A tied final with no word yet on penalty kicks: one this job read itself, or one whose read failed when it landed
  -- (game-card 15). Only with this run's one file unspent, and in any order, so a game whose file has moved on can't
  -- hold up another. A draw is read once: no kicks is its own answer. Not final_checked_at: that says a final is new,
  -- and would drop a second hello pill.
  if n_files = 0 then
    select e.id, e.source_name, e.sport, e.event_date, e.final_score, e.live_score into g
    from public.club_events e
    where e.team_ids is not null and e.final_score is not null and e.final_score[1] = e.final_score[2]
      and e.cancelled_at is null and e.status = 'approved' and e.event_date between v_today - 1 and v_today
      and private.sidearm_file(e.source_name, e.sport) is not null
      and not coalesce(e.live_score, '{}') ? 'shootout'
    order by random() limit 1;
    if found then
      n_files := 1;
      v_shootout := private.read_shootout(g.source_name, g.sport, g.event_date);
      if v_shootout is not null then
        -- A final this job read can have no live score, and the app reads none without a score and a period.
        update public.club_events
        set live_score = coalesce(live_score, jsonb_build_object('score', to_jsonb(g.final_score), 'period', 'OT', 'complete', true))
                         || v_shootout
        where id = g.id;
      end if;
    end if;
  end if;
  return jsonb_build_object('league_reads', n_league, 'files', n_files, 'finals', n_finals, 'refused', v_refused);
end;
$$;

create or replace function public.my_team_finals(p_since timestamptz)
returns table (event_id uuid, game jsonb, mine int, read_at timestamptz)
language sql
stable
security definer
set search_path = ''
as $$
  select e.id,
         -- The live score carries who won a tied game on penalties.
         private.event_game(e.sport, e.team_ids, e.occasion) || jsonb_build_object('final', e.final_score, 'live', e.live_score),
         case when e.team_ids[1] = t.id then 0 else 1 end,
         e.final_checked_at
  from public.town_follows f
  join public.teams t on t.uuid = f.target_id
  join public.club_events e on t.id = any(e.team_ids)
  where f.follower_id = auth.uid() and f.target_type = 'team'
    and e.status = 'approved' and e.final_score is not null and e.cancelled_at is null
    and e.final_checked_at > p_since
  order by e.final_checked_at desc
$$;
revoke execute on function public.my_team_finals(timestamptz) from public, anon;
grant execute on function public.my_team_finals(timestamptz) to authenticated;

-- Tuesday's game, read from SIDEARM's file and matching gobennies.com's "CSB advances in PKs, 5-4".
update public.club_events
   set live_score = live_score || '{"shootout": {"score": [5, 4], "who": "CSB"}}'
 where id = '040aae3e-0234-409b-af3a-d94b94956eb6' and final_score = array[1, 1];
