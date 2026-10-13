-- Unfriend and Block (BP app docs/plans/friends, ticket 04). Nobody is ever told.
--
-- Unfriend ends a friendship and the two follows it made. Block ends the friendship, the
-- requests both ways and the follows both ways, and from then on neither person can find the
-- other, read the other or ask the other: `private.findable` says no either way, and every
-- read and write already asks it. Unblock gives back only being findable.
--
-- A block marks requests cancelled rather than deleting them, so blocking and unblocking can't
-- lower anyone's count against the 40-a-day limit (it counts requests created in 24 hours).

create table private.blocks (
  blocker_id uuid not null references auth.users (id) on delete cascade,
  blocked_id uuid not null references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  check (blocker_id <> blocked_id)
);
create index blocks_blocked_idx on private.blocks (blocked_id);
revoke all on private.blocks from public, anon, authenticated;

-- Ticket 03's rule, now with blocks: nobody you blocked, nobody who blocked you.
create or replace function private.findable(p_user uuid)
returns boolean
language sql
stable
set search_path = ''
as $$
  select exists (
    select 1
    from public.town_profiles p
    join auth.users u on u.id = p.user_id
    where p.user_id = p_user
      and p_user is distinct from auth.uid()
      and not coalesce(u.is_anonymous, false)
      and (u.banned_until is null or u.banned_until < now())
      and p.display_name ~ '[[:alpha:]]'
      and not exists (select 1 from private.blocks b
                      where (b.blocker_id = auth.uid() and b.blocked_id = p_user)
                         or (b.blocker_id = p_user and b.blocked_id = auth.uid()))
  )
$$;

-- Ticket 03's row plus when the friendship began, for the friend sheet's "Friends since".
-- The return type changes, so it and the two reads built on it are dropped and made again.
drop function public.search_neighbors(text);
drop function public.get_friends();
drop function private.neighbor_row(uuid, uuid);

create function private.neighbor_row(p_me uuid, p_user uuid)
returns table (user_id uuid, display_name text, avatar_url text, since timestamptz,
               relation text, mutual_friends int, friends_since timestamptz)
language sql
stable
set search_path = ''
as $$
  select p.user_id, btrim(p.display_name),
         -- Only a photo in their own folder of our avatars bucket (ticket 02).
         case when p.avatar_url like 'https://lxdgwhvqjqmqliobwjpi.supabase.co/storage/v1/object/public/avatars/'
                                     || p.user_id::text || '/%' then p.avatar_url end,
         coalesce(p.onboarded_at, p.created_at),
         private.relation(p_me, p.user_id), private.mutual_friends(p_me, p.user_id),
         (select f.created_at from private.friendships f
          where f.a = least(p_me, p.user_id) and f.b = greatest(p_me, p.user_id))
  from public.town_profiles p
  where p.user_id = p_user
$$;

-- Ticket 03's search, as it was, with the new column.
create function public.search_neighbors(p_words text)
returns table (user_id uuid, display_name text, avatar_url text, since timestamptz,
               relation text, mutual_friends int, friends_since timestamptz)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  me uuid := private.need_real();
  -- The iPhone keyboard types a curly apostrophe: O’Brien finds O'Brien.
  words text := translate(lower(btrim(coalesce(p_words, ''))), '’', '''');
begin
  if words = '' then
    return;
  end if;
  return query
    -- The name first, then who may be found among those it matched: the check runs on a
    -- handful of names, not on every profile in the Town.
    with named as (
      select p.user_id, translate(lower(btrim(p.display_name)), '’', '''') as folded
      from public.town_profiles p
      where p.display_name is not null
    ), matched as materialized (
      select n.user_id, n.folded
      from named n
      where starts_with(n.folded, words)
         or exists (select 1 from regexp_split_to_table(n.folded, '\s+') w where starts_with(w, words))
    ), hits as (
      select m.user_id, m.folded
      from matched m
      where private.findable(m.user_id)
      order by starts_with(m.folded, words) desc, m.folded, m.user_id
      limit 20
    )
    select r.*
    from hits h
    cross join lateral private.neighbor_row(me, h.user_id) r
    order by starts_with(h.folded, words) desc, h.folded, h.user_id;
end;
$$;

-- Ticket 03's Friends page, as it was, with the new column.
create function public.get_friends()
returns table (kind text, user_id uuid, display_name text, avatar_url text, since timestamptz,
               relation text, mutual_friends int, friends_since timestamptz, at timestamptz)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  me uuid := private.need_real();
  seen timestamptz := coalesce((select s.seen_at from private.friends_seen s where s.user_id = me), '-infinity');
begin
  return query
    select x.kind, r.*, x.at
    from (
      select 'accepted' as kind, case when f.a = me then f.b else f.a end as other, f.created_at as at, 0 as part
      from private.friendships f
      where me in (f.a, f.b) and f.requested_by = me and f.created_at > seen
      union all
      select 'request', q.from_id, q.created_at, 1
      from private.friend_requests q
      where q.to_id = me and q.cancelled_at is null and q.deleted_at is null
      union all
      select 'friend', case when f.a = me then f.b else f.a end, f.created_at, 2
      from private.friendships f
      where me in (f.a, f.b)
    ) x
    cross join lateral private.neighbor_row(me, x.other) r
    where private.findable(x.other)
    order by x.part,
             case when x.part = 1 then x.at end desc,
             lower(r.display_name), r.user_id;
end;
$$;

-- Ticket 03's send, with who may be asked checked only once the pair is locked: a block that
-- lands in between can no longer leave a request standing across it.
create or replace function public.send_friend_request(p_to uuid)
returns text
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  me uuid := private.need_real();
  now_is text;
begin
  if not exists (select 1 from public.town_profiles p where p.user_id = me and p.display_name ~ '[[:alpha:]]') then
    raise exception 'friend_name_needed';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('friend-send:' || me::text, 0));
  perform private.lock_pair(me, p_to);
  if not private.findable(p_to) then
    raise exception 'nobody to ask' using errcode = '42501';
  end if;
  now_is := private.relation(me, p_to);
  if now_is in ('friends', 'sent') then
    return now_is;
  end if;
  -- They asked first (even if I deleted it): friends at once, and they see I accepted.
  if exists (select 1 from private.friend_requests q
             where q.from_id = p_to and q.to_id = me and q.cancelled_at is null) then
    perform private.befriend(me, p_to, p_to);
    return 'friends';
  end if;
  if (select count(*) from private.friend_requests q
      where q.from_id = me and q.created_at > now() - interval '24 hours') >= 40 then
    raise exception 'friend_limit';
  end if;
  insert into private.friend_requests (from_id, to_id) values (me, p_to)
  on conflict (from_id, to_id) do update set cancelled_at = null;
  return private.relation(me, p_to);
end;
$$;

-- Unfriend: the friendship goes, and with it the two follows it made. Not a friend: nothing.
create function public.unfriend(p_user uuid)
returns text
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  me uuid := private.need_real();
begin
  perform private.lock_pair(me, p_user);
  delete from private.friendships
  where a = least(me, p_user) and b = greatest(me, p_user);
  if found then
    delete from public.town_follows
    where target_type = 'profile'
      and ((follower_id = me and target_id = p_user) or (follower_id = p_user and target_id = me));
  end if;
  return private.relation(me, p_user);
end;
$$;

-- Block: anyone but yourself (the table's key and check refuse that), found or not: they
-- may have blocked you first.
create function public.block_neighbor(p_user uuid)
returns text
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  me uuid := private.need_real();
begin
  perform private.lock_pair(me, p_user);
  insert into private.blocks (blocker_id, blocked_id) values (me, p_user)
  on conflict do nothing;
  delete from private.friendships
  where a = least(me, p_user) and b = greatest(me, p_user);
  update private.friend_requests set cancelled_at = now()
  where cancelled_at is null
    and ((from_id = me and to_id = p_user) or (from_id = p_user and to_id = me));
  delete from public.town_follows
  where target_type = 'profile'
    and ((follower_id = me and target_id = p_user) or (follower_id = p_user and target_id = me));
  return 'blocked';
end;
$$;

-- Unblock: findable again, nothing more. No friendship or request comes back.
create function public.unblock_neighbor(p_user uuid)
returns text
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  me uuid := private.need_real();
begin
  perform private.lock_pair(me, p_user);
  delete from private.blocks where blocker_id = me and blocked_id = p_user;
  return private.relation(me, p_user);
end;
$$;

-- Profile's Blocked list: the people you blocked, newest first.
-- ponytail: someone who wipes their name after you block them drops off the list (a row
-- needs a name) and stays blocked; show them nameless if that ever matters.
create function public.get_blocked()
returns table (user_id uuid, display_name text, avatar_url text, since timestamptz,
               relation text, mutual_friends int, friends_since timestamptz)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  me uuid := private.need_real();
begin
  return query
    select r.user_id, r.display_name, r.avatar_url, r.since, 'blocked'::text, r.mutual_friends, r.friends_since
    from private.blocks b
    cross join lateral private.neighbor_row(me, b.blocked_id) r
    where b.blocker_id = me and r.display_name ~ '[[:alpha:]]'
    order by b.created_at desc, r.user_id;
end;
$$;

revoke execute on function private.neighbor_row(uuid, uuid) from public, anon, authenticated;
revoke execute on function public.search_neighbors(text), public.get_friends(), public.unfriend(uuid),
  public.block_neighbor(uuid), public.unblock_neighbor(uuid), public.get_blocked() from public, anon;
grant execute on function public.search_neighbors(text), public.get_friends(), public.unfriend(uuid),
  public.block_neighbor(uuid), public.unblock_neighbor(uuid), public.get_blocked() to authenticated;
