-- Friend requests (BP app docs/plans/friends, ticket 03). A friend is a request accepted.
-- Requests, friendships and what each neighbour has seen live in the `private` schema, which
-- the API doesn't expose: only the functions below read or write them, each for a real
-- account only. Every write locks the pair of people it touches (and a send locks the
-- sender too, for the daily limit), then answers with where the two now stand: `none`,
-- `sent`, `received` or `friends`.
--
-- A request the recipient deletes stays stored with `deleted_at`, so the sender still reads
-- Request sent; sending it again never brings it back to them. A cancelled one keeps its
-- `created_at`, so cancelling and sending again neither escapes the limit nor lights the dot
-- again. A friendship removes the requests both ways and adds both follows.

create schema if not exists private;

create table private.friend_requests (
  from_id uuid not null references auth.users (id) on delete cascade,
  to_id uuid not null references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  cancelled_at timestamptz,
  deleted_at timestamptz,
  primary key (from_id, to_id),
  check (from_id <> to_id)
);
create index friend_requests_to_idx on private.friend_requests (to_id);

create table private.friendships (
  a uuid not null references auth.users (id) on delete cascade,
  b uuid not null references auth.users (id) on delete cascade,
  -- Who asked first: they see "{name} accepted your friend request." once.
  requested_by uuid not null references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (a, b),
  check (a < b)
);
create index friendships_b_idx on private.friendships (b);

-- When the neighbour last had the Friends page open: the dot is a request newer than this,
-- the accepted line a friendship newer than this.
create table private.friends_seen (
  user_id uuid primary key references auth.users (id) on delete cascade,
  seen_at timestamptz not null default now()
);

revoke all on private.friend_requests, private.friendships, private.friends_seen
  from public, anon, authenticated;

-- A real account calling, or no further.
create or replace function private.need_real()
returns uuid
language plpgsql
stable
set search_path = ''
as $$
begin
  if auth.uid() is null or not public.is_real_account() then
    raise exception 'a real account is needed for friends' using errcode = '42501';
  end if;
  return auth.uid();
end;
$$;

-- Someone others may find: real, not banned, a name with a letter in it, not the caller.
-- Ticket 04 adds blocks here, once, for every function.
create or replace function private.findable(p_user uuid)
returns boolean
language sql
stable
security definer
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
  )
$$;

create or replace function private.relation(p_me uuid, p_other uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when exists (select 1 from private.friendships f
                 where f.a = least(p_me, p_other) and f.b = greatest(p_me, p_other)) then 'friends'
    when exists (select 1 from private.friend_requests r
                 where r.from_id = p_me and r.to_id = p_other and r.cancelled_at is null) then 'sent'
    when exists (select 1 from private.friend_requests r
                 where r.from_id = p_other and r.to_id = p_me
                   and r.cancelled_at is null and r.deleted_at is null) then 'received'
    else 'none'
  end
$$;

create or replace function private.mutual_friends(p_me uuid, p_other uuid)
returns int
language sql
stable
security definer
set search_path = ''
as $$
  with mine as (
    select case when f.a = p_me then f.b else f.a end as friend
    from private.friendships f where p_me in (f.a, f.b)
  ), theirs as (
    select case when f.a = p_other then f.b else f.a end as friend
    from private.friendships f where p_other in (f.a, f.b)
  )
  select count(*)::int from mine join theirs using (friend)
$$;

create or replace function private.lock_pair(p_x uuid, p_y uuid)
returns void
language sql
volatile
set search_path = ''
as $$
  select pg_advisory_xact_lock(hashtextextended('friends:' || least(p_x, p_y)::text || greatest(p_x, p_y)::text, 0))
$$;

-- Friends at once: the friendship, both follows, and no requests left either way.
create or replace function private.befriend(p_x uuid, p_y uuid, p_requested_by uuid)
returns void
language sql
volatile
security definer
set search_path = ''
as $$
  insert into private.friendships (a, b, requested_by)
  values (least(p_x, p_y), greatest(p_x, p_y), p_requested_by)
  on conflict do nothing;
  delete from private.friend_requests
  where (from_id = p_x and to_id = p_y) or (from_id = p_y and to_id = p_x);
  insert into public.town_follows (follower_id, target_type, target_id)
  values (p_x, 'profile', p_y), (p_y, 'profile', p_x)
  on conflict do nothing;
$$;

-- One person as search and the Friends page show them.
create or replace function private.neighbor_row(p_me uuid, p_user uuid)
returns table (user_id uuid, display_name text, avatar_url text, since timestamptz,
               relation text, mutual_friends int)
language sql
stable
security definer
set search_path = ''
as $$
  select p.user_id, btrim(p.display_name),
         -- Only a photo in their own folder of our avatars bucket (ticket 02).
         case when p.avatar_url like 'https://lxdgwhvqjqmqliobwjpi.supabase.co/storage/v1/object/public/avatars/'
                                     || p.user_id::text || '/%' then p.avatar_url end,
         coalesce(p.onboarded_at, p.created_at),
         private.relation(p_me, p.user_id), private.mutual_friends(p_me, p.user_id)
  from public.town_profiles p
  where p.user_id = p_user
$$;

-- Search, as in ticket 02, now saying where you stand with each person and how many
-- friends you share. The return type changes, so it is dropped and made again.
drop function if exists public.search_neighbors(text);
create function public.search_neighbors(p_words text)
returns table (user_id uuid, display_name text, avatar_url text, since timestamptz,
               relation text, mutual_friends int)
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
    with named as (
      select p.user_id, translate(lower(btrim(p.display_name)), '’', '''') as folded
      from public.town_profiles p
      where private.findable(p.user_id)
    ), hits as (
      select n.user_id, n.folded
      from named n
      where starts_with(n.folded, words)
         or exists (select 1 from regexp_split_to_table(n.folded, '\s+') w where starts_with(w, words))
      order by starts_with(n.folded, words) desc, n.folded, n.user_id
      limit 20
    )
    select r.*
    from hits h
    cross join lateral private.neighbor_row(me, h.user_id) r
    order by starts_with(h.folded, words) desc, h.folded, h.user_id;
end;
$$;

-- The Friends page: accepted lines (newer than the last visit), requests newest first,
-- then friends A to Z.
create or replace function public.get_friends()
returns table (kind text, user_id uuid, display_name text, avatar_url text, since timestamptz,
               relation text, mutual_friends int, at timestamptz)
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

-- The dot on the friends mark: a request newer than the last visit.
create or replace function public.friends_dot()
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  me uuid := private.need_real();
begin
  return exists (
    select 1 from private.friend_requests q
    where q.to_id = me and q.cancelled_at is null and q.deleted_at is null
      and q.created_at > coalesce((select s.seen_at from private.friends_seen s where s.user_id = me), '-infinity')
      and private.findable(q.from_id)
  );
end;
$$;

-- Called once the Friends page has drawn what it read: the dot clears and accepted lines go.
create or replace function public.mark_friends_seen()
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  me uuid := private.need_real();
begin
  insert into private.friends_seen (user_id, seen_at) values (me, now())
  on conflict (user_id) do update set seen_at = excluded.seen_at;
end;
$$;

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
  if not private.findable(p_to) then
    raise exception 'nobody to ask' using errcode = '42501';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('friend-send:' || me::text, 0));
  perform private.lock_pair(me, p_to);
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

create or replace function public.cancel_friend_request(p_to uuid)
returns text
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  me uuid := private.need_real();
begin
  perform private.lock_pair(me, p_to);
  update private.friend_requests set cancelled_at = now()
  where from_id = me and to_id = p_to and cancelled_at is null;
  return private.relation(me, p_to);
end;
$$;

create or replace function public.confirm_friend_request(p_from uuid)
returns text
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  me uuid := private.need_real();
begin
  perform private.lock_pair(me, p_from);
  -- Only a request they really sent: nobody can make a friend of someone who never asked.
  if private.findable(p_from) and exists (
       select 1 from private.friend_requests q
       where q.from_id = p_from and q.to_id = me and q.cancelled_at is null) then
    perform private.befriend(me, p_from, p_from);
  end if;
  return private.relation(me, p_from);
end;
$$;

create or replace function public.delete_friend_request(p_from uuid)
returns text
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  me uuid := private.need_real();
begin
  perform private.lock_pair(me, p_from);
  update private.friend_requests set deleted_at = now()
  where from_id = p_from and to_id = me and cancelled_at is null and deleted_at is null;
  return private.relation(me, p_from);
end;
$$;

revoke execute on function private.need_real(), private.findable(uuid), private.relation(uuid, uuid),
  private.mutual_friends(uuid, uuid), private.lock_pair(uuid, uuid), private.befriend(uuid, uuid, uuid),
  private.neighbor_row(uuid, uuid) from public, anon, authenticated;
revoke execute on function public.search_neighbors(text), public.get_friends(), public.friends_dot(),
  public.mark_friends_seen(), public.send_friend_request(uuid), public.cancel_friend_request(uuid),
  public.confirm_friend_request(uuid), public.delete_friend_request(uuid) from public, anon;
grant execute on function public.search_neighbors(text), public.get_friends(), public.friends_dot(),
  public.mark_friends_seen(), public.send_friend_request(uuid), public.cancel_friend_request(uuid),
  public.confirm_friend_request(uuid), public.delete_friend_request(uuid) to authenticated;

-- Friends now follow each other, so a poster's follower count would all but count their
-- friends (no friend count anywhere: ticket 03). Nothing calls it: not the app, the
-- Android port or the website.
revoke execute on function public.get_feed_postings(integer) from authenticated;
