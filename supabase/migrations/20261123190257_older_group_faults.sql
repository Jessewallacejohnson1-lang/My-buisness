-- Older Group faults (BP app docs/plans/start-a-group, ticket 09). No Group in the live database has an Admin, an Event, an
-- invite or an ask yet (read 2026-11-23), so nothing live changes.
--   1. A Group's photo can't be swapped: its uploader could delete the file behind a live photo and upload another under
--      its name, unchecked (item 2). event_image_shown from 20261115000142_several_photos_own_files.sql, now also a
--      Group's photo, and one being checked. start_group from 20261122031709_private_groups.sql takes only a photo
--      that is already up (the app sends it first).
--   2. "delete clubs": only Block Party's admin. The Admin of a waiting Group could delete it and, by the foreign key,
--      its members' Events (item 3). Close group is theirs.
--   3. "moderate events": a waiting Event is moved only to a Group its poster may add to (item 4), as "submit events"
--      says for a new one.
--   4. listed_for_writer from 20261117183412_writer_sees_running_shows.sql: an Event of a Group the Town can't see is
--      never the one a found Event repeats (item 5). It runs as its caller, so the Watch key may now read clubs.private
--      (status it has since 20261113203347_date_walks.sql), which the morning's standouts also ask (morning.py).
--   5. edit_group from 20261122174712_admin_and_edit_group.sql: with no name it leaves an edit that waits or is being
--      checked alone (item 8), for a save that only changes Private or who adds Events.
--   6. Joining ends your ask (item 13): its no outlived the invite that let you in, so leaving left "Asked" for good,
--      and an ask still waiting stayed on the Admin's Requests.
--   7. "Anyone reads the standouts": only of an Event the reader can see, as event_parts' rule. The morning job's reason
--      for a pick names the Event, and a members-only one could be picked (found 2026-11-23). A day whose only picks a
--      reader can't see then gives them the Town feed's own top Event, as a day with none.
-- Each function is line for line but for that one change.

-- 1.
create or replace function private.event_image_shown(p_name text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.club_events e
    cross join (select 'https://lxdgwhvqjqmqliobwjpi.supabase.co/storage/v1/object/public/event-images/' || p_name as url) f
    where e.status <> 'rejected' and e.submitted_by::text = split_part(p_name, '/', 1)
      and (e.image_url = f.url or f.url = any (e.more_photos)))
  -- Whoever runs the Group now: after a hand-over its photo is still in its old Admin's folder. Only start_group and
  -- edit_group set it, each to the Admin's own upload, so nobody can name someone else's file.
  or exists (
    select 1 from public.clubs c
    where c.image_url = 'https://lxdgwhvqjqmqliobwjpi.supabase.co/storage/v1/object/public/event-images/' || p_name)
  or exists (
    select 1 from private.group_edit_checks k
    where k.current
      and k.edit->>'photo' = 'https://lxdgwhvqjqmqliobwjpi.supabase.co/storage/v1/object/public/event-images/' || p_name)
$$;

-- start_group from 20261122031709_private_groups.sql.
create or replace function public.start_group(p_id uuid, p_name text, p_kind text default null, p_photo text default null,
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
  -- There already: a name with no file behind it fails its checks, waits for Review, and could be filled after a yes.
  if p_photo is not null and not exists (
    select 1 from storage.objects o
    where o.bucket_id = 'event-images' and o.name = me::text || '/group-' || p_id::text || '.jpg') then
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

-- 2.
alter policy "delete clubs" on public.clubs using (public.is_admin());

-- 3.
alter policy "moderate events" on public.club_events
  with check (public.is_admin()
              or (submitted_by = (select auth.uid()) and status = 'pending' and checked_at is null
                  and (club_id is null or private.adds_to_group(club_id, (select auth.uid())))));

-- 4.
grant select (private) on public.clubs to watch;
create or replace function public.listed_for_writer()
returns jsonb
language sql
stable
set search_path = ''
as $$
  select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb)
  from (
    select e.id, e.status, e.title, e.event_date, e.start_time, e.end_at, e.all_day, e.location,
           e.source_name, e.source_uid, e.category, e.shows_from, e.review_reason, e.cancelled_at,
           e.club_id is null and e.submitted_by is null as found,
           coalesce((select jsonb_agg(jsonb_build_object('source_name', m.source_name,
             'source_url', m.source_url, 'source_uid', m.source_uid, 'trust', m.trust, 'sure', m.sure))
             from public.event_mentions m where m.event_id = e.id), '[]'::jsonb) as mentions
    from public.club_events e
    where e.kind = 'event' and (e.event_date >= (now() at time zone 'America/Chicago')::date - 1
      or (e.end_at at time zone 'America/Chicago')::date >= (now() at time zone 'America/Chicago')::date)
      and (e.club_id is null
           or exists (select 1 from public.clubs c where c.id = e.club_id and c.status = 'approved' and not c.private))
  ) x;
$$;

-- 5.
create or replace function public.edit_group(p_club uuid, p_name text, p_kind text, p_about text, p_photo text,
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
  v_again boolean := false;
  v_old jsonb;
  v_edit jsonb;
  v_drop jsonb;
begin
  if not private.runs_group(p_club, me) then
    raise exception 'only the Admin edits' using errcode = '42501';
  end if;
  if p_name is not null and (char_length(v_name) not between 3 and 60 or v_name !~ '[[:alpha:]]') then
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
  -- No name: nothing the checks read was touched, so an edit that waits or is being checked goes on.
  if p_name is not null then
    select w.edit into v_old from private.group_edits w where w.club_id = p_club;
    v_photo := case when p_photo is distinct from c.image_url then p_photo end;
    v_edit := case when v_name is distinct from c.name or v_kind is distinct from c.kind
                        or v_about is distinct from c.description or v_photo is not null
                   then jsonb_build_object('name', v_name, 'kind', v_kind, 'about', v_about)
                        || case when v_photo is null then '{}' else jsonb_build_object('photo', v_photo) end end;
    -- A photo a check has read is that check's, which shows it or takes it down. The same edit sent again while it is
    -- checked is that edit; any other needs a new upload.
    if exists (select 1 from private.group_edit_checks k where k.club_id = p_club and k.edit->>'photo' = v_photo) then
      v_again := exists (select 1 from private.group_edit_checks k
                         where k.club_id = p_club and k.current and k.edit - 'drop' = v_edit);
      if not v_again then
        raise exception 'the photo must be your own new upload for this group' using errcode = '22023';
      end if;
    end if;
    if not v_again then
      update private.group_edit_checks set current = false where club_id = p_club and current;
    end if;
    -- The photo of an edit still waiting, which this one replaces: nothing will show it.
    v_drop := coalesce(v_old->'drop', '[]'::jsonb)
              || case when v_old ? 'photo' then jsonb_build_array(v_old->'photo') else '[]'::jsonb end;
    if v_photo is not null then
      v_drop := v_drop - v_photo;
    end if;
    if v_again then
      v_edit := null;
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
  end if;
  update public.clubs
  set private = coalesce(p_private, false) or private.group_held(p_club),
      events_by = p_events_by
  where id = p_club;
  -- No list (the app couldn't read the members): the picks stay as they were.
  if p_editors is not null then
    delete from private.club_editors where club_id = p_club;
    insert into private.club_editors (club_id, user_id)
    select p_club, m.user_id from public.club_members m
    where m.club_id = p_club and m.user_id = any (p_editors) and m.user_id <> me;
  end if;
  return v_edit is not null or v_again;
end;
$$;

-- 6.
create function private.joining_ends_ask()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from private.club_requests where club_id = new.club_id and user_id = new.user_id;
  return null;
end;
$$;
revoke execute on function private.joining_ends_ask() from public;
create trigger joining_ends_ask after insert on public.club_members
  for each row execute function private.joining_ends_ask();

-- 7.
alter policy "Anyone reads the standouts" on public.daily_standouts
  using (exists (select 1 from public.club_events e where e.id = daily_standouts.event_id));
