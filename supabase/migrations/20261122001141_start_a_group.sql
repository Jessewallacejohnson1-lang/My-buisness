-- Start a group (BP app docs/plans/start-a-group, ticket 02; Jesse's yes at Check-in 1, 2026-11-21): any
-- real account starts a Group from the Friends tab or You with a name, maybe a kind and a photo. It is
-- pending until two separate checks (moderate-post `group`) both say yes; until then only its starter,
-- its members and the friends invited see it. Both no: rejected, and only the starter sees that.
--   1. clubs.checked_at: the check runs once per Group (claim_group_check).
--   2. private.club_invites and invite_to_group: a member invites friends; the invite puts the Group first
--      in their Groups to join, "Sam invited you", with the dot on the Friends icon (friends_dot).
--   3. start_group: the only way a new Group is made (the "submit clubs" insert rule goes), 3 a day.
--   4. Who sees and joins a pending Group: "read clubs" and "join club" read private.sees_group and
--      private.may_join. The starter's pending-edit rule goes until Edit group (ticket 04): an edit
--      after the check would skip it.
--   5. get_groups from 20261101185732_group_calendar_loopholes.sql, line for line but for the pending
--      Groups you started, joined or were invited to, a rejected one to its starter, and three columns:
--      status, invited_by and image_url (the starter's photo, also the photos' last fallback).
--   6. friends_dot from 20261013150000_friend_requests.sql, line for line but for an invite since the
--      last visit.

-- 1.
alter table public.clubs add column if not exists checked_at timestamptz;

-- 2.
create table private.club_invites (
  club_id uuid not null references public.clubs (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  invited_by uuid not null references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (club_id, user_id)
);
create index club_invites_user_idx on private.club_invites (user_id);
revoke all on private.club_invites from public, anon, authenticated;

-- The caller is in this Group or was invited to it.
create or replace function private.sees_group(p_club uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select auth.uid() is not null and (
    exists (select 1 from public.club_members m where m.club_id = p_club and m.user_id = auth.uid())
    or exists (select 1 from private.club_invites i where i.club_id = p_club and i.user_id = auth.uid()))
$$;

-- The caller may join: the Group is live, or they started it, or a member invited them to it while it waits.
create or replace function private.may_join(p_club uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.clubs c
    where c.id = p_club
      and (c.status = 'approved'
           or (c.status = 'pending'
               and (c.submitted_by = auth.uid()
                    or exists (select 1 from private.club_invites i where i.club_id = c.id and i.user_id = auth.uid())))))
$$;

-- Who invited the caller, first name only ("Sam"), while they aren't in it yet; nil otherwise.
create or replace function private.invited_by(p_club uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select split_part(btrim(p.display_name), ' ', 1)
  from private.club_invites i
  join public.town_profiles p on p.user_id = i.invited_by
  where i.club_id = p_club and i.user_id = auth.uid()
    and not exists (select 1 from public.club_members m where m.club_id = p_club and m.user_id = auth.uid())
    and private.findable(i.invited_by)
  order by i.created_at
  limit 1
$$;

grant execute on function private.sees_group(uuid), private.may_join(uuid), private.invited_by(uuid)
  to anon, authenticated;

-- A member invites friends (at most 50 at a time); a friend already invited, or no longer findable, is
-- skipped. How many invites were new.
create or replace function public.invite_to_group(p_club uuid, p_users uuid[])
returns int
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  me uuid := private.need_real();
  v_new int;
begin
  if cardinality(p_users) > 50 then
    raise exception 'at most 50 invites at a time' using errcode = '22023';
  end if;
  if not exists (select 1 from public.club_members m join public.clubs c on c.id = m.club_id
                 where m.club_id = p_club and m.user_id = me and c.status in ('approved', 'pending')) then
    raise exception 'only a member invites' using errcode = '42501';
  end if;
  insert into private.club_invites (club_id, user_id, invited_by)
  select p_club, u, me
  from (select distinct unnest(p_users) as u) x
  where exists (select 1 from private.friendships f where f.a = least(me, x.u) and f.b = greatest(me, x.u))
    and private.findable(x.u)
    and not exists (select 1 from public.club_members m where m.club_id = p_club and m.user_id = x.u)
  on conflict do nothing;
  get diagnostics v_new = row_count;
  return v_new;
end;
$$;
revoke execute on function public.invite_to_group(uuid, uuid[]) from public, anon;
grant execute on function public.invite_to_group(uuid, uuid[]) to authenticated;

-- 3. A new Group, pending, with you as its first member. The app makes its id, so its photo
-- (event-images/<you>/group-<id>.jpg) goes up first; a photo anywhere else is refused. 3 a day.
create or replace function public.start_group(p_id uuid, p_name text, p_kind text default null, p_photo text default null)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  me uuid := private.need_real();
  v_name text := regexp_replace(btrim(coalesce(p_name, '')), '\s+', ' ', 'g');
  v_kind text := nullif(btrim(coalesce(p_kind, '')), '');
begin
  if char_length(v_name) not between 3 and 60 or v_name !~ '[[:alpha:]]' then
    raise exception 'a name of 3 to 60 letters' using errcode = '22023';
  end if;
  if char_length(v_kind) > 30 then
    raise exception 'a kind of at most 30 letters' using errcode = '22023';
  end if;
  if p_photo is not null and p_photo <> 'https://lxdgwhvqjqmqliobwjpi.supabase.co/storage/v1/object/public/event-images/'
                                       || me::text || '/group-' || p_id::text || '.jpg' then
    raise exception 'the photo must be your own upload for this group' using errcode = '22023';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('start_group:' || me::text, 0));
  if (select count(*) from public.clubs where submitted_by = me and created_at > now() - interval '24 hours') >= 3 then
    raise exception '3 new groups a day' using errcode = 'P0001', hint = 'limit';
  end if;
  insert into public.clubs (id, name, kind, image_url, status, submitted_by)
  values (p_id, v_name, v_kind, p_photo, 'pending', me);
  insert into public.club_members (club_id, user_id) values (p_id, me);
  return p_id;
end;
$$;
revoke execute on function public.start_group(uuid, text, text, text) from public, anon;
grant execute on function public.start_group(uuid, text, text, text) to authenticated;

-- moderate-post's `group` check, once per Group: only the caller's own, still pending, never checked.
create or replace function public.claim_group_check(p_club uuid, p_user uuid)
returns boolean
language sql
volatile
security definer
set search_path = ''
as $$
  with c as (
    update public.clubs set checked_at = now()
    where id = p_club and submitted_by = p_user and status = 'pending' and checked_at is null
    returning 1
  )
  select exists (select 1 from c)
$$;
revoke execute on function public.claim_group_check(uuid, uuid) from public, anon, authenticated;
grant execute on function public.claim_group_check(uuid, uuid) to service_role;

-- 4.
drop policy "submit clubs" on public.clubs;
drop policy "real accounts start clubs" on public.clubs;
alter policy "moderate clubs" on public.clubs using (public.is_admin()) with check (public.is_admin());
alter policy "read clubs" on public.clubs to anon, authenticated
  using (status = 'approved' or submitted_by = (select auth.uid()) or public.is_admin()
         or (status = 'pending' and private.sees_group(id)));
alter policy "join club" on public.club_members
  with check (user_id = (select auth.uid()) and private.may_join(club_id));

-- 5.
drop function public.get_groups();
create function public.get_groups()
returns table (
  id uuid,
  name text,
  kind text,
  schedule text,
  location text,
  about text,
  page_url text,
  photos jsonb,
  logo jsonb,
  meetings jsonb,
  member_count int,
  joined boolean,
  status text,
  invited_by text,
  image_url text
)
language sql
stable
security invoker
set search_path = public
as $$
  select g.id, g.name, g.kind, g.schedule, g.location, g.description, g.page_url, g.photos, g.logo,
         g.meetings, g.member_count, g.joined, g.status, g.invited_by, g.image_url
  from (
    select c.id, c.name, c.kind, c.schedule, c.location, c.description, c.page_url,
           coalesce(
             (select jsonb_agg(jsonb_build_object('url', p.url, 'kind', 'photo', 'credit', p.credit,
                                                  'site', p.source_url) order by p.position)
                from public.place_photos p
               where p.entry_id = c.entry_id and p.status = 'live' and p.kind = 'photo'),
             case when place.pic->>'kind' = 'photo' then jsonb_build_array(place.pic) end,
             case when c.image_url is not null then jsonb_build_array(jsonb_build_object('url', c.image_url, 'kind', 'photo')) end,
             '[]'::jsonb) as photos,
           coalesce(
             (select jsonb_build_object('url', p.url, 'kind', 'logo', 'hue', p.hue)
                from public.place_photos p
               where p.entry_id = c.entry_id and p.status = 'live' and p.kind = 'logo'
               order by p.position limit 1),
             case when place.pic->>'kind' = 'logo' then place.pic end) as logo,
           private.coming_up(case when c.calendar is null then public.group_meetings(c.meets, today.d, 10)
                                  else c.calendar end, now()) as meetings,
           private.member_count(c.id) as member_count,
           auth.uid() is not null
             and exists (select 1 from public.club_members m where m.club_id = c.id and m.user_id = auth.uid())
             as joined,
           c.status,
           case when c.status <> 'rejected' then private.invited_by(c.id) end as invited_by,
           c.image_url
    from public.clubs c
    cross join (select (now() at time zone 'America/Chicago')::date as d) today
    left join lateral (select public.place_picture(c.place_entry_id) as pic) place on true
    where c.status = 'approved'
       or (auth.uid() is not null
           and (c.submitted_by = auth.uid() or (c.status = 'pending' and private.sees_group(c.id))))
  ) g
  order by g.member_count desc, (g.photos <> '[]'::jsonb) desc, (g.logo is not null) desc, g.name
$$;
grant execute on function public.get_groups() to anon, authenticated;

-- 6.
create or replace function public.friends_dot()
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  me uuid := private.need_real();
  seen timestamptz := coalesce((select s.seen_at from private.friends_seen s where s.user_id = me), '-infinity');
begin
  return exists (
    select 1 from private.friend_requests q
    where q.to_id = me and q.cancelled_at is null and q.deleted_at is null
      and q.created_at > seen
      and private.findable(q.from_id)
  ) or exists (
    select 1 from private.club_invites i join public.clubs c on c.id = i.club_id
    where i.user_id = me and i.created_at > seen and c.status in ('approved', 'pending')
      and private.findable(i.invited_by)
      and not exists (select 1 from public.club_members m where m.club_id = i.club_id and m.user_id = me)
  );
end;
$$;
