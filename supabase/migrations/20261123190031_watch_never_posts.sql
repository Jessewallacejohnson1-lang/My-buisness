-- The Watch key never reaches a neighbour's post (BP app docs/plans/loopholes/issues/22-watch-key-reaches-posts.md).
-- 20261031040831_watch_key.sql says so, but a post is a club_events row (kind 'post') and that table's "watch rows" is a
-- plain `true`, so the key could read, change, approve and write posts. It is kept a plain `true` on purpose (see there).
-- A restrictive rule is asked as well as it, not instead of it: Postgres still drops the neighbours' rules that call
-- is_admin(). A neighbour's own Event stays in reach: the job tags it and sets its map spot (loopholes 23).
create policy "watch never posts" on public.club_events as restrictive to watch
  using (kind <> 'post') with check (kind <> 'post');
