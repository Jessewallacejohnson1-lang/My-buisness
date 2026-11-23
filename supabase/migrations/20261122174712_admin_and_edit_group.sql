-- A Group's Admin and Edit group (BP app docs/plans/start-a-group, ticket 04; SPEC decisions 6 and 8, Figma frame 8).
-- The Admin is the account in `clubs.submitted_by`, as in ticket 03 (its starter at first; a hand-over moves it). The
-- Admin edits the Group, says who adds Events, hands it to a member and closes it; to leave, they hand it over or close
-- it first. A deleted account's Groups go to their longest member, or close with none left.
--   1. clubs.events_by, status 'closed'; private.club_editors (Members I pick); private.group_edits (the edit that
--      waits, read through functions only: a column of clubs could be read through REST) and private.group_edit_checks.
--      private.held_groups: Groups Private can't be turned off in (Jesse, 2026-11-22). A starter known under 18 when
--      they started it: for good, whoever runs it later. A starter with no birthday: until they add an adult one, and
--      for good once the Group is handed on before that. Groups started before this are held the same.
--   2. edit_group: Private, Who adds Events and the picked members land at once. A changed name, kind, About or photo
--      waits in private.group_edits for moderate-post's `group` check (claim_group_edit, then apply_group_edit on two
--      yeses), so an edit can't skip the checks. A new photo goes up under a new name, so the live one never changes
--      under it. A waiting photo a newer edit replaces, or that a hand-over or Close leaves behind, goes in its `drop`,
--      which moderate-post takes out of Storage. A photo goes to one check, which shows it or takes it down: from then
--      on it is never in `drop`, so a live photo can't be.
--   3. get_group_members: the Admin's list of the members, for Admin and Members I pick.
--   4. private.give_group (a new Admin), hand_over_group, close_group.
--   5. "leave club": the Admin of a Group that isn't closed can't leave it.
--   6. private.pass_on_groups: what becomes of a deleted account's Groups, for both ways an account goes:
--      delete_my_account (the under-13 exit) from 20261102212013_delete_my_account.sql, and clear_account_rows
--      (Settings' Delete account, the delete-account edge function's first call, which needs no change itself) from
--      20261106204840_clear_account_rows.sql, each line for line but for that one call.
--   7. get_groups from 20261122031709_private_groups.sql, line for line but a closed Group leaves every list, and two
--      more columns: events_by, and always_private, which says the starter's age, so only to its Admin.

-- 1.
alter table public.clubs add column if not exists events_by text not null default 'admin'
  check (events_by in ('admin', 'picked', 'members'));
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

-- The edit that waits on the check: {"name", "kind", "about", "photo"?} and "drop", photos to take out of Storage. A
-- hand-over or Close leaves only "drop".
create table private.group_edits (
  club_id uuid primary key references public.clubs (id) on delete cascade,
  edit jsonb not null
);
revoke all on private.group_edits from public, anon, authenticated;

-- One row per edit the check reads, with its new photo: at most 10 a day each.
create table private.group_edit_checks (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  club_id uuid not null references public.clubs (id) on delete cascade,
  photo text,
  at timestamptz not null default now()
);
create index group_edit_checks_club on private.group_edit_checks (club_id);
create index group_edit_checks_user_at on private.group_edit_checks (user_id, at);
revoke all on private.group_edit_checks from public, anon, authenticated;

-- Groups whose Private is fixed on. `for_good`: else only until its starter, still its Admin, adds an adult birthday.
create table private.held_groups (
  club_id uuid primary key references public.clubs (id) on delete cascade,
  for_good boolean not null
);
revoke all on private.held_groups from public, anon, authenticated;

-- Private is fixed on. Adult means 18 on the day they started it: a birthday can't be changed once set (keep_birthday).
create function private.group_held(p_club uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from private.held_groups h
    join public.clubs c on c.id = h.club_id
    where h.club_id = p_club
      and (h.for_good or not exists (
        select 1 from public.town_profiles p
        where p.user_id = c.submitted_by
          and p.birthday <= (c.created_at at time zone 'America/Chicago')::date - interval '18 years')))
$$;
revoke execute on function private.group_held(uuid) from public;

create function private.hold_new_group()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.submitted_by = auth.uid() and private.chat_minor(new.submitted_by) then
    insert into private.held_groups (club_id, for_good)
    values (new.id, exists (select 1 from public.town_profiles p
                            where p.user_id = new.submitted_by and p.birthday is not null));
  end if;
  return null;
end;
$$;
create trigger hold_new_group after insert on public.clubs
  for each row execute function private.hold_new_group();

-- Groups started before this, whose starter is still clubs.submitted_by (nothing handed one on yet), public ones from
-- before private Groups too: theirs turn private. A starter with no birthday only since Start a group went live
-- (2026-11-21): an older row's account is from before birthdays.
insert into private.held_groups (club_id, for_good)
select c.id, p.birthday is not null
from public.clubs c
left join public.town_profiles p on p.user_id = c.submitted_by
where c.submitted_by is not null
  and case when p.birthday is null then c.created_at >= '2026-11-21 00:00-06'
           else p.birthday > (c.created_at at time zone 'America/Chicago')::date - interval '18 years' end;
update public.clubs c set private = true
from private.held_groups h where h.club_id = c.id and not c.private;

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
  v_photo text;
  v_old jsonb;
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
  select w.edit into v_old from private.group_edits w where w.club_id = p_club;
  -- Not the live photo, nor one a check has read already: that check shows it or takes it down.
  v_photo := case when p_photo is distinct from c.image_url
                       and not exists (select 1 from private.group_edit_checks k
                                       where k.club_id = p_club and k.photo = p_photo) then p_photo end;
  v_edit := case when v_name is distinct from c.name or v_kind is distinct from c.kind
                      or v_about is distinct from c.description or v_photo is not null
                 then jsonb_build_object('name', v_name, 'kind', v_kind, 'about', v_about)
                      || case when v_photo is null then '{}' else jsonb_build_object('photo', v_photo) end end;
  -- The photo of an edit still waiting, which this one replaces: nothing will show it.
  v_drop := coalesce(v_old->'drop', '[]'::jsonb)
            || case when v_old ? 'photo' then jsonb_build_array(v_old->'photo') else '[]'::jsonb end;
  if v_photo is not null then
    v_drop := v_drop - v_photo;
  end if;
  if v_drop <> '[]'::jsonb then
    v_edit := coalesce(v_edit, '{}'::jsonb) || jsonb_build_object('drop', v_drop);
  end if;
  if v_edit is null then
    delete from private.group_edits where club_id = p_club;
  else
    insert into private.group_edits (club_id, edit) values (p_club, v_edit)
    on conflict (club_id) do update set edit = excluded.edit;
  end if;
  update public.clubs
  set private = coalesce(p_private, false) or private.chat_minor(me) or private.group_held(p_club),
      events_by = p_events_by
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
-- {"limit": true} when the day's 10 are used; null with nothing waiting or someone else asking. Only photos to take
-- down (a hand-over's, a Close's) go to whoever asks: the one who handed it over or closed it runs it no more, and
-- moderate-post tells its caller nothing but "ok".
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
  select w.edit into v_edit from private.group_edits w where w.club_id = p_club for update;
  if v_edit is null or (v_edit ? 'name' and not private.runs_group(p_club, p_user)) then
    return null;
  end if;
  -- Nothing to check, so it costs none of the day's 10.
  if v_edit ? 'name' then
    if (select count(*) from private.group_edit_checks where user_id = p_user and at > now() - interval '24 hours') >= 10 then
      return jsonb_build_object('limit', true);
    end if;
    insert into private.group_edit_checks (user_id, club_id, photo) values (p_user, p_club, v_edit->>'photo');
  end if;
  delete from private.group_edits where club_id = p_club;
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

-- 4. An edit that waits is let go, its photo and any other to take down kept for moderate-post: true when there is one.
create function private.let_go_group_edit(p_club uuid)
returns boolean
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_old jsonb;
  v_drop jsonb;
begin
  select w.edit into v_old from private.group_edits w where w.club_id = p_club for update;
  v_drop := coalesce(v_old->'drop', '[]'::jsonb)
            || case when v_old ? 'photo' then jsonb_build_array(v_old->'photo') else '[]'::jsonb end;
  if v_drop = '[]'::jsonb then
    delete from private.group_edits where club_id = p_club;
    return false;
  end if;
  update private.group_edits set edit = jsonb_build_object('drop', v_drop) where club_id = p_club;
  return true;
end;
$$;

-- A new Admin. Held until its starter adds an adult birthday: held for good from here, or free if they had.
create function private.give_group(p_club uuid, p_user uuid)
returns boolean
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  if private.group_held(p_club) then
    update private.held_groups set for_good = true where club_id = p_club;
  else
    delete from private.held_groups where club_id = p_club;
  end if;
  update public.clubs set submitted_by = p_user where id = p_club;
  delete from private.club_editors where club_id = p_club and user_id = p_user;
  return private.let_go_group_edit(p_club);
end;
$$;
revoke execute on function private.let_go_group_edit(uuid), private.give_group(uuid, uuid) from public;

-- A member becomes the Admin; the old Admin stays a member. True when a waiting photo is left to take down: the app
-- then asks moderate-post's `group` mode.
create function public.hand_over_group(p_club uuid, p_user uuid)
returns boolean
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
  return private.give_group(p_club, p_user);
end;
$$;

-- The Group leaves every list, its chat, its Events and its Calendar with it (each reads only a live or pending Group).
-- True as hand_over_group.
create function public.close_group(p_club uuid)
returns boolean
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
  update public.clubs set status = 'closed' where id = p_club;
  return private.let_go_group_edit(p_club);
end;
$$;
revoke execute on function public.hand_over_group(uuid, uuid), public.close_group(uuid) from public, anon;
grant execute on function public.hand_over_group(uuid, uuid), public.close_group(uuid) to authenticated;

-- 5.
alter policy "leave club" on public.club_members
  using (user_id = (select auth.uid()) and not private.runs_group(club_id, (select auth.uid())));

-- 6. Each Group the account runs goes to the member who joined longest ago, a real account with a name that isn't
-- banned; a block between the two goes with the account. With none left, it closes. A photo in the account's own folder
-- goes with its files, so no Group points at it, one it handed on before among them.
create function private.pass_on_groups(p_user uuid)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  g record;
begin
  for g in
    select c.id,
           (select m.user_id
            from public.club_members m
            join auth.users u on u.id = m.user_id
            join public.town_profiles p on p.user_id = m.user_id
            where m.club_id = c.id and m.user_id <> p_user and not coalesce(u.is_anonymous, false)
              and (u.banned_until is null or u.banned_until < now()) and p.display_name ~ '[[:alpha:]]'
            order by m.created_at, m.user_id limit 1) as heir
    from public.clubs c
    where c.submitted_by = p_user and c.status in ('approved', 'pending')
  loop
    if g.heir is null then
      update public.clubs set status = 'closed' where id = g.id;
      perform private.let_go_group_edit(g.id);
    else
      perform private.give_group(g.id, g.heir);
    end if;
  end loop;
  update public.clubs set image_url = null where image_url like '%/event-images/' || p_user::text || '/%';
end;
$$;
revoke execute on function private.pass_on_groups(uuid) from public;

create or replace function public.delete_my_account()
returns void
language sql
security definer
set search_path = ''
as $$
  select private.pass_on_groups(auth.uid());
  delete from auth.users where id = auth.uid();
$$;
revoke all on function public.delete_my_account() from public, anon;
grant execute on function public.delete_my_account() to authenticated;

create or replace function public.clear_account_rows(p_user uuid)
returns text[]
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.pass_on_groups(p_user);
  with kept as (
    update public.club_events e
    set cancelled_at = coalesce(e.cancelled_at, now()), image_url = null
    where e.submitted_by = p_user and e.kind = 'event' and e.status = 'approved'
      and e.event_date >= private.town_today()
      and exists (select 1 from public.event_rsvps r where r.event_id = e.id and r.user_id <> p_user)
    returning e.id
  )
  delete from public.club_events e
  where e.submitted_by = p_user and e.id not in (select k.id from kept k);

  return array(select c.photo_path from private.chat_reports c
               where c.resolved_at is null and split_part(c.photo_path, '/', 1) = p_user::text);
end;
$$;

revoke all on function public.clear_account_rows(uuid) from public, anon, authenticated;
grant execute on function public.clear_account_rows(uuid) to service_role;

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
           c.events_by,
           coalesce(c.submitted_by = auth.uid() and private.group_held(c.id), false) as always_private
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

