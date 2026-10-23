-- my_team_finals (20261023120000_team_follows.sql) says approved games only, as team_page does
-- (hello-drop 03 review).

-- The finals of games your followed teams played, read since `p_since`: the hello pill's "your
-- team's final". `mine` is the followed team's side, 0 or 1, in `game.teams` order.
create or replace function public.my_team_finals(p_since timestamptz)
returns table (event_id uuid, game jsonb, mine int, read_at timestamptz)
language sql
stable
security definer
set search_path = ''
as $$
  select e.id,
         private.event_game(e.sport, e.team_ids, e.occasion) || jsonb_build_object('final', e.final_score),
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
