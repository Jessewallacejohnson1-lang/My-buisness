-- Private Groups and Ask to join (BP app docs/plans/start-a-group, ticket 03; Jesse's yes at Check-in 1, 2026-11-21).
-- A private Group shows everyone its name, photo, kind, member count and About, with Ask to join; only those in it
-- (members, the invited and its starter) see when and where it meets, its members and its chat. Its Admin (the
-- starter, until ticket 04) says yes or no to each ask; a yes puts the person in. A Group started by someone under 18
-- (`private.chat_minor`, which counts no birthday as under 18) is always private.
--   1. clubs.private, private.club_requests.
--   2. private.inside_group: the caller is in it, invited to it or started it; private.sees_members: not private, or inside_group.
--   3. "read clubs" keeps a private Group's row to those in it; "read memberships" its members.
--   4. may_join from 20261122001141_start_a_group.sql: a private live Group lets in only its invited and its starter.
--   5. start_group from 20261122001141_start_a_group.sql, line for line but for p_private (forced on under 18).
--   6. ask_to_join, get_join_requests, answer_join.
--   7. get_groups from 20261122001141_start_a_group.sql, now security definer with the same filter, and to anyone not
--      in a private Group no schedule, location or meetings; three more columns: private, asked, requests (Admin's).
--   8. get_profile from 20261117204548_profile_followers.sql, line for line but its Groups leave out a private one
--      the reader isn't in.
--   9. groups_always_private: whether New group's Private switch is fixed on.

-- 1.
alter table public.clubs add column if not exists private boolean not null default false;

create table private.club_requests (
  club_id uuid not null references public.clubs (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  answer text check (answer in ('yes', 'no')),
  answered_at timestamptz,
  primary key (club_id, user_id)
);
revoke all on private.club_requests from public, anon, authenticated;

-- 2.
create function private.inside_group(p_club uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.sees_group(p_club)
      or exists (select 1 from public.clubs c where c.id = p_club and c.submitted_by = auth.uid())
$$;

create function private.sees_members(p_club uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (select 1 from public.clubs c where c.id = p_club and not c.private) or private.inside_group(p_club)
$$;

grant execute on function private.inside_group(uuid), private.sees_members(uuid) to anon, authenticated;

-- 3.
alter policy "read clubs" on public.clubs to anon, authenticated
  using ((status = 'approved' and (not private or private.inside_group(id)))
         or submitted_by = (select auth.uid()) or public.is_admin()
         or (status = 'pending' and private.sees_group(id)));
alter policy "read memberships" on public.club_members to authenticated
  using (user_id = (select auth.uid()) or private.sees_members(club_id));

-- 4.
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
      and ((c.status = 'approved' and not c.private)
           or (c.status in ('approved', 'pending')
               and (c.submitted_by = auth.uid()
                    or exists (select 1 from private.club_invites i where i.club_id = c.id and i.user_id = auth.uid())))))
$$;

-- 5.
drop function public.start_group(uuid, text, text, text);
create function public.start_group(p_id uuid, p_name text, p_kind text default null, p_photo text default null,
                                   p_private boolean default false)
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
  insert into public.clubs (id, name, kind, image_url, status, submitted_by, private)
  values (p_id, v_name, v_kind, p_photo, 'pending', me, coalesce(p_private, false) or private.chat_minor(me));
  insert into public.club_members (club_id, user_id) values (p_id, me);
  return p_id;
end;
$$;
revoke execute on function public.start_group(uuid, text, text, text, boolean) from public, anon;
grant execute on function public.start_group(uuid, text, text, text, boolean) to authenticated;

-- 6. Ask (p_on) or take it back. Once answered it stays as it was: after a no, asking again does nothing.
create function public.ask_to_join(p_club uuid, p_on boolean default true)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  me uuid := private.need_real();
begin
  if not exists (select 1 from public.clubs c where c.id = p_club and c.status = 'approved' and c.private
                 and not exists (select 1 from public.club_members m where m.club_id = c.id and m.user_id = me)) then
    raise exception 'not a private group you can ask to join' using errcode = '22023';
  end if;
  if p_on then
    insert into private.club_requests (club_id, user_id) values (p_club, me) on conflict do nothing;
  else
    delete from private.club_requests where club_id = p_club and user_id = me and answer is null;
  end if;
end;
$$;

-- Who waits, oldest first: the Admin's alone.
create function public.get_join_requests(p_club uuid)
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
  if not exists (select 1 from public.clubs c where c.id = p_club and c.submitted_by = me) then
    raise exception 'only the Admin sees requests' using errcode = '42501';
  end if;
  return query
    select r.*
    from private.club_requests q
    cross join lateral private.neighbor_row(me, q.user_id) r
    where q.club_id = p_club and q.answer is null and private.findable(q.user_id)
    order by q.created_at;
end;
$$;

-- The Admin's yes puts them in; a no is kept, so they can't ask again.
create function public.answer_join(p_club uuid, p_user uuid, p_yes boolean)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  me uuid := private.need_real();
begin
  if not exists (select 1 from public.clubs c where c.id = p_club and c.submitted_by = me) then
    raise exception 'only the Admin answers' using errcode = '42501';
  end if;
  update private.club_requests set answer = case when p_yes then 'yes' else 'no' end, answered_at = now()
  where club_id = p_club and user_id = p_user and answer is null;
  if found and p_yes then
    insert into public.club_members (club_id, user_id) values (p_club, p_user) on conflict do nothing;
  end if;
end;
$$;

revoke execute on function public.ask_to_join(uuid, boolean), public.get_join_requests(uuid),
  public.answer_join(uuid, uuid, boolean) from public, anon;
grant execute on function public.ask_to_join(uuid, boolean), public.get_join_requests(uuid),
  public.answer_join(uuid, uuid, boolean) to authenticated;

-- 7.
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
  image_url text,
  private boolean,
  asked boolean,
  requests int
)
language sql
stable
security definer
set search_path = ''
as $$
  select g.id, g.name, g.kind,
         case when g.open then g.schedule end, case when g.open then g.location end,
         g.description, g.page_url, g.photos, g.logo,
         case when g.open then g.meetings else '[]'::jsonb end,
         g.member_count, g.joined, g.status, g.invited_by, g.image_url, g.private, g.asked, g.requests
  from (
    select c.id, c.name, c.kind, c.schedule, c.location, c.description, c.page_url, c.private,
           not c.private or private.inside_group(c.id) as open,
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
           c.image_url,
           exists (select 1 from private.club_requests q where q.club_id = c.id and q.user_id = auth.uid()
                   and q.answer is distinct from 'yes') as asked,
           case when c.submitted_by = auth.uid() then
             (select count(*)::int from private.club_requests q
               where q.club_id = c.id and q.answer is null and private.findable(q.user_id)) end as requests
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

-- 8.
create or replace function public.get_profile(p_user uuid)
returns table (bio text, cover_url text, friends int, group_ids uuid[], both_going uuid[], following int, followers int)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  me uuid := private.need_real();
begin
  if p_user is distinct from me and not private.findable(p_user) then
    return;
  end if;
  return query
    select nullif(btrim(p.bio), ''),
           -- Only a picture in their own folder of our avatars bucket, as neighbor_row's photo.
           case when p.cover_url like 'https://lxdgwhvqjqmqliobwjpi.supabase.co/storage/v1/object/public/avatars/'
                                     || p.user_id::text || '/%' then p.cover_url end,
           (select count(*)::int
            from private.friendships f
            cross join lateral (select case when f.a = p_user then f.b else f.a end as other) o
            where p_user in (f.a, f.b) and (o.other = me or private.findable(o.other))),
           -- A private Group the reader isn't in stays off it (start-a-group 03).
           array(select m.club_id from public.club_members m
                 where m.user_id = p_user and private.sees_members(m.club_id) order by m.created_at),
           case when p_user <> me and p.plans_to_friends and private.relation(me, p_user) = 'friends' then
             array(select e.id
                   from public.club_events e
                   join public.event_rsvps a on a.event_id = e.id and a.user_id = me
                   join public.event_rsvps b on b.event_id = e.id and b.user_id = p_user
                   where e.status = 'approved' and e.kind = 'event' and e.cancelled_at is null
                     and coalesce(e.end_at, (e.event_date + 1)::timestamp at time zone 'America/Chicago') > now()
                   order by e.event_date, e.start_time, e.id
                   limit 3)
           else '{}'::uuid[] end,
           -- my_follows' rows for p_user, as the reader may see them.
           (select count(*)::int
            from public.town_follows t
            where t.follower_id = p_user
              and case t.target_type
                    when 'profile' then exists (select 1 from public.town_profiles x where x.user_id = t.target_id)
                                        and (t.target_id = me or private.findable(t.target_id))
                    when 'place' then exists (select 1 from public.places pl where pl.id = t.target_id)
                    when 'team' then exists (select 1 from public.teams tm where tm.uuid = t.target_id)
                    when 'page' then exists (select 1 from public.town_pages pg where pg.id = t.target_id)
                    when 'board' then exists (select 1 from public.city_boards b where b.id = t.target_id)
                    else false
                  end),
           -- People following p_user, counted as my_followers lists them: only people the reader may
           -- find, the reader included.
           (select count(*)::int
            from public.town_follows t
            join public.town_profiles x on x.user_id = t.follower_id
            where t.target_type = 'profile' and t.target_id = p_user
              and (t.follower_id = me or private.findable(t.follower_id)))
    from public.town_profiles p
    where p.user_id = p_user;
end;
$$;

-- 9. New group's Private switch: on and fixed for an account start_group would make private anyway.
create function public.groups_always_private()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.chat_minor(auth.uid())
$$;
revoke execute on function public.groups_always_private() from public, anon;
grant execute on function public.groups_always_private() to authenticated;
