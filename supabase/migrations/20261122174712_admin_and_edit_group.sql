-- A Group's Admin and Edit group (BP app docs/plans/start-a-group, ticket 04; SPEC decisions 6 and 8, Figma frame 8).
-- The Admin is the account in `clubs.submitted_by`, as in ticket 03 (its starter at first; a hand-over moves it). The
-- Admin edits the Group, says who adds Events, hands it to a member and closes it; to leave, they hand it over or close
-- it first. A deleted account's Groups go to their longest member, or close with none left.
--   1. clubs.events_by, clubs.edit, status 'closed'; private.club_editors (Members I pick); private.group_edit_checks;
--      clubs.always_private: started by someone under 18 (SPEC decision 5), set as it is made and kept through a
--      hand-over, so an adult who runs it later can't turn Private off. Groups started before: a private one whose
--      starter (still clubs.submitted_by, as nothing handed a Group on before this) is under 18.
--   2. edit_group: Private, Who adds Events and the picked members land at once. A changed name, kind, About or photo
--      waits in clubs.edit for moderate-post's `group` check (claim_group_edit, then apply_group_edit on two yeses), so
--      an edit can't skip the checks. A new photo goes up under a new name, so the live one never changes under it.
--      A waiting photo a newer edit replaces goes in its `drop`, which moderate-post takes out of Storage.
--   3. get_group_members: the Admin's list of the members, for Admin and Members I pick.
--   4. hand_over_group, close_group.
--   5. "leave club": the Admin of a Group that isn't closed can't leave it.
--   6. delete_my_account from 20261102212013_delete_my_account.sql, now handing the Groups on first, to a member
--      someone can find (private.findable, as hand_over_group).
--   7. get_groups from 20261122031709_private_groups.sql, line for line but a closed Group leaves every list, and two
--      more columns: events_by, always_private.

-- 1.
alter table public.clubs add column if not exists events_by text not null default 'admin'
  check (events_by in ('admin', 'picked', 'members'));
alter table public.clubs add column if not exists edit jsonb;
alter table public.clubs drop constraint clubs_status_check;
alter table public.clubs add constraint clubs_status_check
  check (status in ('pending', 'approved', 'rejected', 'closed'));

create table private.club_editors (
  club_id uuid not null,
  user_id uuid not null,
  primary key (club_id, user_id),
  -- A member who leaves is no longer picked.
  foreign key (club_id, user_id) references public.club_members (club_id, user_id) on delete cascade
);
revoke all on private.club_editors from public, anon, authenticated;

-- One row per edit the check reads: at most 10 a day each.
create table private.group_edit_checks (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  club_id uuid not null references public.clubs (id) on delete cascade,
  at timestamptz not null default now()
);
create index group_edit_checks_user_at on private.group_edit_checks (user_id, at);
revoke all on private.group_edit_checks from public, anon, authenticated;

alter table public.clubs add column if not exists always_private boolean not null default false;
create function private.club_always_private()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  new.always_private := coalesce(new.submitted_by = auth.uid() and private.chat_minor(new.submitted_by), false);
  return new;
end;
$$;
create trigger club_always_private before insert on public.clubs
  for each row execute function private.club_always_private();
update public.clubs set always_private = true
where private and submitted_by is not null and private.chat_minor(submitted_by);

-- The caller runs this Group: its Admin, and it isn't closed or turned down.
create function private.runs_group(p_club uuid, p_user uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (select 1 from public.clubs c
                 where c.id = p_club and c.submitted_by = p_user and c.status in ('approved', 'pending'))
$$;
revoke execute on function private.runs_group(uuid, uuid) from public;
grant execute on function private.runs_group(uuid, uuid) to authenticated, service_role;

-- 2. True when a name, kind, About or photo waits on the check: the app then asks moderate-post's `group` mode.
create function public.edit_group(p_club uuid, p_name text, p_kind text, p_about text, p_photo text,
                                  p_private boolean, p_events_by text, p_editors uuid[] default null)
returns boolean
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  me uuid := private.need_real();
  c public.clubs;
  v_name text := regexp_replace(btrim(coalesce(p_name, '')), '\s+', ' ', 'g');
  v_kind text := nullif(btrim(coalesce(p_kind, '')), '');
  v_about text := nullif(btrim(coalesce(p_about, '')), '');
  v_edit jsonb;
  v_drop jsonb;
begin
  if not private.runs_group(p_club, me) then
    raise exception 'only the Admin edits' using errcode = '42501';
  end if;
  if char_length(v_name) not between 3 and 60 or v_name !~ '[[:alpha:]]' then
    raise exception 'a name of 3 to 60 letters' using errcode = '22023';
  end if;
  if char_length(v_kind) > 30 then
    raise exception 'a kind of at most 30 letters' using errcode = '22023';
  end if;
  if char_length(v_about) > 1000 then
    raise exception 'an About of at most 1000 letters' using errcode = '22023';
  end if;
  if p_photo is not null and p_photo !~ ('^https://lxdgwhvqjqmqliobwjpi\.supabase\.co/storage/v1/object/public/event-images/'
                                         || me::text || '/group-' || p_club::text || '-[a-z0-9]{1,36}\.jpg$') then
    raise exception 'the photo must be your own new upload for this group' using errcode = '22023';
  end if;
  if p_events_by is null or p_events_by not in ('admin', 'picked', 'members') then
    raise exception 'who adds events: admin, picked or members' using errcode = '22023';
  end if;
  select * into c from public.clubs where id = p_club for update;
  v_edit := case when v_name is distinct from c.name or v_kind is distinct from c.kind
                      or v_about is distinct from c.description
                      or (p_photo is not null and p_photo is distinct from c.image_url)
                 then jsonb_build_object('name', v_name, 'kind', v_kind, 'about', v_about)
                      || case when p_photo is distinct from c.image_url and p_photo is not null
                              then jsonb_build_object('photo', p_photo) else '{}' end end;
  -- The photo of an edit still waiting, which this one replaces: nothing will show it.
  v_drop := coalesce(c.edit->'drop', '[]'::jsonb)
            || case when c.edit->>'photo' is distinct from v_edit->>'photo' and c.edit->>'photo' is not null
                    then jsonb_build_array(c.edit->>'photo') else '[]'::jsonb end;
  if v_drop <> '[]'::jsonb then
    v_edit := coalesce(v_edit, '{}'::jsonb) || jsonb_build_object('drop', v_drop);
  end if;
  update public.clubs
  set private = coalesce(p_private, false) or private.chat_minor(me) or c.always_private,
      events_by = p_events_by,
      edit = v_edit
  where id = p_club;
  -- No list (the app couldn't read the members): the picks stay as they were.
  if p_editors is not null then
    delete from private.club_editors where club_id = p_club;
    insert into private.club_editors (club_id, user_id)
    select p_club, m.user_id from public.club_members m
    where m.club_id = p_club and m.user_id = any (p_editors) and m.user_id <> me;
  end if;
  return v_edit is not null;
end;
$$;
revoke execute on function public.edit_group(uuid, text, text, text, text, boolean, text, uuid[]) from public, anon;
grant execute on function public.edit_group(uuid, text, text, text, text, boolean, text, uuid[]) to authenticated;

-- moderate-post's claim on the Admin's waiting edit: it is taken off the Group (so it is read once) and handed back;
-- {"limit": true} when the day's 10 are used; null with nothing waiting or someone else asking.
create function public.claim_group_edit(p_club uuid, p_user uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_edit jsonb;
begin
  perform pg_advisory_xact_lock(hashtextextended('claim_group_edit:' || p_user::text, 0));
  select c.edit into v_edit from public.clubs c
  where c.id = p_club and c.edit is not null and private.runs_group(p_club, p_user) for update;
  if v_edit is null then
    return null;
  end if;
  -- Only a photo to take down: nothing to check, so it costs none of the day's 10.
  if not v_edit ? 'name' then
    update public.clubs set edit = null where id = p_club;
    return v_edit;
  end if;
  if (select count(*) from private.group_edit_checks where user_id = p_user and at > now() - interval '24 hours') >= 10 then
    return jsonb_build_object('limit', true);
  end if;
  update public.clubs set edit = null where id = p_club;
  insert into private.group_edit_checks (user_id, club_id) values (p_user, p_club);
  return v_edit;
end;
$$;

-- The edit both checks said yes to. False when the Group was closed or handed on while it was checked.
create function public.apply_group_edit(p_club uuid, p_user uuid, p_edit jsonb)
returns boolean
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  update public.clubs
  set name = p_edit->>'name', kind = p_edit->>'kind', description = p_edit->>'about',
      image_url = coalesce(p_edit->>'photo', image_url)
  where id = p_club and private.runs_group(p_club, p_user) and p_edit ? 'name';
  return found;
end;
$$;
revoke execute on function public.claim_group_edit(uuid, uuid), public.apply_group_edit(uuid, uuid, jsonb)
  from public, anon, authenticated;
grant execute on function public.claim_group_edit(uuid, uuid), public.apply_group_edit(uuid, uuid, jsonb)
  to service_role;

-- 3. The members but the Admin, longest first, each as a Friends row, and whether the Admin picked them to add Events.
create function public.get_group_members(p_club uuid)
returns table (user_id uuid, display_name text, avatar_url text, since timestamptz,
               relation text, mutual_friends int, friends_since timestamptz, editor boolean)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  me uuid := private.need_real();
begin
  if not private.runs_group(p_club, me) then
    raise exception 'only the Admin sees this' using errcode = '42501';
  end if;
  return query
    select r.*, exists (select 1 from private.club_editors e where e.club_id = p_club and e.user_id = m.user_id)
    from public.club_members m
    cross join lateral private.neighbor_row(me, m.user_id) r
    where m.club_id = p_club and m.user_id <> me and private.findable(m.user_id)
    order by m.created_at, m.user_id;
end;
$$;
revoke execute on function public.get_group_members(uuid) from public, anon;
grant execute on function public.get_group_members(uuid) to authenticated;

-- 4. A member becomes the Admin; the old Admin stays a member.
create function public.hand_over_group(p_club uuid, p_user uuid)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  me uuid := private.need_real();
begin
  if not private.runs_group(p_club, me) then
    raise exception 'only the Admin hands over' using errcode = '42501';
  end if;
  if p_user = me or not exists (select 1 from public.club_members m where m.club_id = p_club and m.user_id = p_user)
     or not private.findable(p_user) then
    raise exception 'only to a member' using errcode = '22023';
  end if;
  update public.clubs set submitted_by = p_user, edit = null where id = p_club;
  delete from private.club_editors where club_id = p_club and user_id = p_user;
end;
$$;

-- The Group leaves every list, its chat and its Calendar with it (each reads only a live or pending Group).
create function public.close_group(p_club uuid)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  me uuid := private.need_real();
begin
  if not private.runs_group(p_club, me) then
    raise exception 'only the Admin closes' using errcode = '42501';
  end if;
  update public.clubs set status = 'closed', edit = null where id = p_club;
end;
$$;
revoke execute on function public.hand_over_group(uuid, uuid), public.close_group(uuid) from public, anon;
grant execute on function public.hand_over_group(uuid, uuid), public.close_group(uuid) to authenticated;

-- 5.
alter policy "leave club" on public.club_members
  using (user_id = (select auth.uid()) and not private.runs_group(club_id, (select auth.uid())));

-- 6. Each Group the account runs goes to the member who joined longest ago; with none left, it closes.
create or replace function public.delete_my_account()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  me uuid := auth.uid();
  g record;
begin
  for g in
    select c.id,
           (select m.user_id from public.club_members m
            where m.club_id = c.id and m.user_id <> me and private.findable(m.user_id)
            order by m.created_at, m.user_id limit 1) as heir
    from public.clubs c
    where c.submitted_by = me and c.status in ('approved', 'pending')
  loop
    if g.heir is null then
      update public.clubs set status = 'closed', edit = null where id = g.id;
    else
      update public.clubs set submitted_by = g.heir, edit = null where id = g.id;
      delete from private.club_editors where club_id = g.id and user_id = g.heir;
    end if;
  end loop;
  delete from auth.users where id = me;
end;
$$;
revoke all on function public.delete_my_account() from public, anon;
grant execute on function public.delete_my_account() to authenticated;

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
  requests int,
  events_by text,
  always_private boolean
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
         g.member_count, g.joined, g.status, g.invited_by, g.image_url, g.private, g.asked, g.requests, g.events_by,
         g.always_private
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
               where q.club_id = c.id and q.answer is null and private.findable(q.user_id)) end as requests,
           c.events_by, c.always_private
    from public.clubs c
    cross join (select (now() at time zone 'America/Chicago')::date as d) today
    left join lateral (select public.place_picture(c.place_entry_id) as pic) place on true
    where c.status <> 'closed'
      and (c.status = 'approved'
       or (auth.uid() is not null
           and (c.submitted_by = auth.uid() or (c.status = 'pending' and private.sees_group(c.id)))))
  ) g
  order by g.member_count desc, (g.photos <> '[]'::jsonb) desc, (g.logo is not null) desc, g.name
$$;
grant execute on function public.get_groups() to anon, authenticated;

