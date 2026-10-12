-- Who's Going stays private (BP app docs/plans/town-feed, ticket 19): Going, saves and hearts
-- become readable only as the caller's own rows (20261012120100_town_feed_private.sql), so the
-- functions that show a count read it here. Security definer, so a count covers every
-- account, Anonymous ones included, while nobody reads who. In the private schema, which the
-- API doesn't expose: only get_town_feed and get_my_going call these.
create schema if not exists private;
grant usage on schema private to anon, authenticated;

create or replace function private.going_count(p_event uuid)
returns int
language sql
stable
security definer
set search_path = ''
as $$
  select count(*)::int from public.event_rsvps where event_id = p_event
$$;

create or replace function private.heart_count(p_event uuid)
returns int
language sql
stable
security definer
set search_path = ''
as $$
  select count(*)::int from public.event_likes where event_id = p_event
$$;

revoke execute on function private.going_count(uuid), private.heart_count(uuid) from public;
grant execute on function private.going_count(uuid), private.heart_count(uuid) to anon, authenticated;
