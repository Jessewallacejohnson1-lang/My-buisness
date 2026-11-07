-- Each live game's own file on its school's site (BP app docs/plans/game-card/issues/21-school-file-first.md).
--
-- SIDEARM's push channel broke twice in a week (2026-10-31 its file host moved, 2026-11-06 that host's certificate
-- expired). Every SIDEARM school site serves the stat crew's file itself, uncached, at
-- https://<site>/api/livestats?game_id=<id>, and SJU and CSB athletics OK'd reading gojohnnies.com and gobennies.com
-- (Jesse, 2026-11-07). The live-scores function finds a game's id in SIDEARM's list of games on now (2 MB) and keeps
-- it here, so the list is read once per game day; a game not in the list is looked for again after 10 minutes.

create table private.live_feeds (
  event_id uuid primary key references public.club_events (id) on delete cascade,
  -- Null: looked for in SIDEARM's list and not found.
  url text check (url ~ '^https://(gobennies|gojohnnies)\.com/api/livestats\?game_id=\d+$'),
  found_at timestamptz not null default now()
);

create or replace function public.live_feeds(p_events uuid[])
returns table (event_id uuid, url text)
language sql
stable
security definer
set search_path = ''
as $$
  select f.event_id, f.url from private.live_feeds f
  where f.event_id = any(p_events) and (f.url is not null or f.found_at > now() - interval '10 minutes')
$$;

create or replace function public.save_live_feed(p_event uuid, p_url text)
returns void
language sql
security definer
set search_path = ''
as $$
  insert into private.live_feeds (event_id, url) values (p_event, p_url)
  on conflict (event_id) do update set url = excluded.url, found_at = now()
$$;

revoke execute on function public.live_feeds(uuid[]) from public, anon, authenticated;
revoke execute on function public.save_live_feed(uuid, text) from public, anon, authenticated;
grant execute on function public.live_feeds(uuid[]) to service_role;
grant execute on function public.save_live_feed(uuid, text) to service_role;
