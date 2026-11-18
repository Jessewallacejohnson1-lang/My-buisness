-- A banned person's words leave every chat while the ban lasts (BP app five-tabs 09; Jesse's yes, 2026-11-17). Until
-- now a banned stranger's old words stayed in a Going or Group chat, only unnamed. A ban now reads as everyone's block:
-- their messages, Messages' row of what was said last, the dot and a report all skip them, as for someone you blocked,
-- and they come back when the ban ends. Every one of those reads asks private.blocked_between, so it alone changes.
-- Applied live only with Jesse's yes.

-- From 20261104012542_chat_with_friends.sql.
create or replace function private.blocked_between(p_x uuid, p_y uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (select 1 from private.blocks b
                 where (b.blocker_id = p_x and b.blocked_id = p_y) or (b.blocker_id = p_y and b.blocked_id = p_x))
      or exists (select 1 from auth.users u where u.id in (p_x, p_y) and u.banned_until > now())
$$;
