-- Follow places and people (BP app docs/plans/follows, ticket 02).
--
-- A neighbour follows a Place (a `public.places` row: a business, a restaurant) or a person. A
-- follow is one-way and free: nobody approves it and nobody is told. Only signed-up accounts
-- follow, and since this ticket only they join a Group too (rsvp-and-groups 06 let Anonymous
-- accounts join; the follows spec turned that around).
--
-- Follows go through `follow_target` and `unfollow_target`, never straight into the table, so
-- the rules live here once: a real account, and something that may be followed. A person may be
-- followed when they may be found (`private.findable`: real, named, not banned, not blocked
-- either way). A Place, when it exists.
--
-- `follow_card` answers what a page shows: whether you follow it, how many do (a Place only;
-- people never show a count), and which of your friends follow it. Nobody can list a target's
-- followers, and your own follows stay readable only to you (`my_follows`, and the table's
-- "own follows select").

alter table public.town_follows drop constraint if exists town_follows_target_type_check;
alter table public.town_follows add constraint town_follows_target_type_check
  check (target_type in ('club', 'profile', 'place'));

-- Direct writes stop: the functions below write as the definer. Reading your own stays.
drop policy if exists "own follows insert" on public.town_follows;
drop policy if exists "own follows delete" on public.town_follows;

-- Joining a Group needs a signed-up account, as following does. Members who joined before stay;
-- leaving stays open to everyone.
drop policy if exists "real accounts join groups" on public.club_members;
create policy "real accounts join groups" on public.club_members
  as restrictive for insert to public
  with check ((select public.is_real_account()));

-- May be followed by the caller.
create or replace function private.followable(p_type text, p_id uuid)
returns boolean
language sql
stable
set search_path = ''
as $$
  select case p_type
    when 'profile' then private.findable(p_id)
    when 'place' then exists (select 1 from public.places pl where pl.id = p_id)
    else false
  end
$$;

-- Follow: true once you follow it. Following twice is fine.
create function public.follow_target(p_type text, p_id uuid)
returns boolean
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  me uuid := private.need_real();
begin
  if not private.followable(p_type, p_id) then
    raise exception 'not_followable' using errcode = '42501';
  end if;
  insert into public.town_follows (follower_id, target_type, target_id)
  values (me, p_type, p_id)
  on conflict do nothing;
  return true;
end;
$$;

-- Unfollow: false once you don't. Anything you follow can be unfollowed, findable or not.
create function public.unfollow_target(p_type text, p_id uuid)
returns boolean
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  me uuid := private.need_real();
begin
  delete from public.town_follows
  where follower_id = me and target_type = p_type and target_id = p_id;
  return false;
end;
$$;

-- What a page shows of one Place or person. `followers` is null for a person. `friends` holds up
-- to three of your friends who follow it, A to Z, as {name, avatar_url}; `friends_count` all of
-- them. Signed out or Anonymous: the count alone.
create function public.follow_card(p_type text, p_id uuid)
returns table (following boolean, followers int, friends jsonb, friends_count int)
language sql
stable
security definer
set search_path = ''
as $$
  with me as (
    select auth.uid() as id, auth.uid() is not null and public.is_real_account() as real
  ), mine as (
    select case when f.a = me.id then f.b else f.a end as friend
    from me join private.friendships f on me.real and me.id in (f.a, f.b)
  ), friends as (
    select p.display_name as name, p.avatar_url
    from mine m
    join public.town_follows t on t.follower_id = m.friend and t.target_type = p_type and t.target_id = p_id
    join public.town_profiles p on p.user_id = m.friend
    where private.findable(m.friend)
  )
  select
    exists (select 1 from public.town_follows t, me
            where t.follower_id = me.id and t.target_type = p_type and t.target_id = p_id),
    case when p_type = 'profile' then null
         else (select count(*)::int from public.town_follows t
               where t.target_type = p_type and t.target_id = p_id) end,
    coalesce((select jsonb_agg(jsonb_build_object('name', f.name, 'avatar_url', f.avatar_url)
                               order by lower(f.name))
              from (select * from friends order by lower(name) limit 3) f), '[]'::jsonb),
    (select count(*)::int from friends)
$$;

-- Profile's Following list: everyone and everything you follow, A to Z. `kind` is a Place's
-- Google type, `picture` a person's photo or a Place's (`place_picture`: its photo, else its logo).
-- Groups aren't listed: the You tab's Groups row holds them.
create function public.my_follows()
returns table (target_type text, target_id uuid, name text, kind text, picture text, picture_kind text)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  me uuid := private.need_real();
begin
  return query
    select x.* from (
      select 'profile'::text, t.target_id, p.display_name, null::text, p.avatar_url, 'photo'::text
      from public.town_follows t
      join public.town_profiles p on p.user_id = t.target_id
      where t.follower_id = me and t.target_type = 'profile' and private.findable(t.target_id)
      union all
      select 'place'::text, t.target_id, pl.name, pl.primary_type, pic ->> 'url', pic ->> 'kind'
      from public.town_follows t
      join public.places pl on pl.id = t.target_id
      cross join lateral (select public.place_picture(pl.entry_id) as pic) pp
      where t.follower_id = me and t.target_type = 'place'
    ) x (target_type, target_id, name, kind, picture, picture_kind)
    order by lower(x.name), x.target_id;
end;
$$;

-- Who hosts an Event, for its page's host line: the neighbour who posted it when they may be
-- found, else the Place it's at. `friend`: the host is the caller's friend, who already follows
-- them and gets no Follow. Nothing for a Group's own Events (they have Join) or for an Event at
-- no known Place.
create function public.event_host(p_event uuid)
returns table (target_type text, target_id uuid, name text, kind text, picture text, picture_kind text,
               friend boolean)
language sql
stable
security definer
set search_path = ''
as $$
  select h.target_type, h.target_id, h.name, h.kind, h.picture, h.picture_kind,
         h.target_type = 'profile' and auth.uid() is not null
           and private.relation(auth.uid(), h.target_id) = 'friends'
  from public.club_events e
  cross join lateral (
    select 'profile'::text, p.user_id, p.display_name, null::text, p.avatar_url, 'photo'::text, 0
    from public.town_profiles p
    where p.user_id = e.submitted_by and private.findable(e.submitted_by)
    union all
    select 'place'::text, pl.id, pl.name, pl.primary_type, pic ->> 'url', pic ->> 'kind', 1
    from public.places pl
    cross join lateral (select public.place_picture(pl.entry_id) as pic) pp
    where pl.entry_id = e.place_entry_id
    order by 7, 3
    limit 1
  ) h (target_type, target_id, name, kind, picture, picture_kind, rank)
  where e.id = p_event and e.club_id is null and e.status = 'approved'
$$;

revoke execute on function public.follow_target(text, uuid), public.unfollow_target(text, uuid),
  public.my_follows() from public, anon;
grant execute on function public.follow_target(text, uuid), public.unfollow_target(text, uuid),
  public.my_follows() to authenticated;
revoke execute on function public.follow_card(text, uuid), public.event_host(uuid) from public;
grant execute on function public.follow_card(text, uuid), public.event_host(uuid) to anon, authenticated;
