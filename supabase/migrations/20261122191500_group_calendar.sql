-- A Group's Calendar (BP app docs/plans/start-a-group, ticket 05; SPEC decisions 10 and 11, Figma frame 6). The Group
-- page's month Calendar shows the Group's Events as far ahead as they go and its repeating get-togethers 4 months ahead;
-- its + opens New post's New event with the Group as host, and "Add when you meet" sets the repeats.
--   1. private.adds_to_group: who may add an Event to a live Group: its Admin (clubs.submitted_by), and the members
--      Edit group's Who can add events lets in (clubs.events_by, private.club_editors; ticket 04).
--   2. "submit events": a row naming a Group only from someone who may add to it.
--   3. claim_submit from 20261114153201_several_photos.sql, line for line but an Event may carry the Group of
--      someone who may add to it. The check and the Town feed then treat it as any New event.
--   4. "read events": a private Group's Event only to those in it (private.sees_members), so the Town feed, the
--      Event page and every read under these rules leave it out for anyone else. The Town feed needs no change: it
--      reads as the caller, and "read clubs" (20261122031709) already keeps a private Group's row, so its name and
--      Join, off a stranger's card (a story checks).
--   5. get_group_events from 20261120193226_group_events.sql: the Group's own Events too, every one still to come
--      (up to 200), not the next three, and none of a private Group's to anyone outside it.
--   6. get_group_calendar: the get-togethers 120 days ahead (group_meetings' reach) and whether the caller may add.
--   7. set_group_meets: Add when you meet, the Admin's; it writes clubs.meets in 20261018150000_groups.sql's format,
--      and the when line (schedule, location) from the same picks.

-- 1.
create function private.adds_to_group(p_club uuid, p_user uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select p_user is not null and exists (
    select 1 from public.clubs c
    where c.id = p_club and c.status = 'approved'
      and (c.submitted_by = p_user
           or (c.events_by = 'members'
               and exists (select 1 from public.club_members m where m.club_id = c.id and m.user_id = p_user))
           -- A picked member is a member: club_editors' key is club_members'.
           or (c.events_by = 'picked'
               and exists (select 1 from private.club_editors e where e.club_id = c.id and e.user_id = p_user))))
$$;
revoke execute on function private.adds_to_group(uuid, uuid) from public;
grant execute on function private.adds_to_group(uuid, uuid) to authenticated, service_role;

-- 2.
alter policy "submit events" on public.club_events
  with check (submitted_by = (select auth.uid()) and (status = 'pending' or public.is_admin())
              and (club_id is null or public.is_admin() or private.adds_to_group(club_id, (select auth.uid()))));

-- 3.
create or replace function public.claim_submit(p_event uuid, p_user uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_photo text := '^https://lxdgwhvqjqmqliobwjpi\.supabase\.co/storage/v1/object/public/event-images/'
                  || p_user::text || '/[0-9a-f-]+\.jpg$';
  -- A post's later photos: <its id>-2.jpg to -10.jpg in the poster's own folder (town-feed 46).
  v_more text := '^https://lxdgwhvqjqmqliobwjpi\.supabase\.co/storage/v1/object/public/event-images/' || p_user::text || '/';
  v_claimed boolean;
begin
  perform pg_advisory_xact_lock(hashtextextended('claim_submit:' || p_user::text, 0));
  if (select count(*) from public.club_events
      where submitted_by = p_user and checked_at > now() - interval '24 hours') >= 10 then
    return false;
  end if;
  with c as (
    update public.club_events e
    set checked_at = now(),
        tagged = (select array_agg(x.id order by x.n)
                  from (select u.id, min(u.n) as n from unnest(e.tagged) with ordinality as u(id, n) group by u.id) x
                  where exists (select 1 from private.friendships f
                                where f.a = least(p_user, x.id) and f.b = greatest(p_user, x.id))),
        at_names = private.checked_at_names(p_user, e.title, e.at_names)
    where e.id = p_event and e.submitted_by = p_user and e.status = 'pending' and e.checked_at is null
      and (
        (e.kind = 'event' and not e.friends_only and e.tagged is null and e.at_names is null)
        or (e.kind = 'post' and e.event_date is null and e.start_time is null and e.end_at is null
            and not e.all_day and (btrim(e.title) <> '' or e.image_url is not null)
            and char_length(e.title) <= 2000 and coalesce(cardinality(e.tagged), 0) <= 20
            and coalesce(jsonb_array_length(e.at_names), 0) <= 20)
      )
      and coalesce(e.category, 'other') = 'other'
      and (e.image_url is null or e.image_url ~ v_photo)
      and (e.more_photos is null
           or (e.kind = 'post' and e.image_url is not null and cardinality(e.more_photos) between 1 and 9
               and (select count(distinct m) from unnest(e.more_photos) m) = cardinality(e.more_photos)
               and not exists (select 1 from unnest(e.more_photos) m where m is null or m !~ (v_more || e.id::text || '-([2-9]|10)\.jpg$'))))
      -- A Group's Event only from someone who may add to it (start-a-group 05).
      and (e.club_id is null or (e.kind = 'event' and private.adds_to_group(e.club_id, p_user)))
      and e.source_name is null and e.source_uid is null and e.source_url is null
      and e.place_entry_id is null and e.team_ids is null and e.activity_team is null
      and e.activity_name is null and e.sport is null and e.occasion is null and e.what is null
      and e.draw is null and e.shows_from is null and coalesce(cardinality(e.interests), 0) = 0 and e.interests_tagged_at is null
      and e.lat is null and e.lng is null and coalesce(e.followers_only, false) = false
      and e.cancelled_at is null and e.moved_at is null and e.moved_from is null
      and e.live_score is null and e.final_score is null and e.scoring_plays is null
      and e.review_reason is null and e.rechecked_at is null
    returning 1
  )
  select exists (select 1 from c) into v_claimed;
  return v_claimed;
end
$$;
revoke execute on function public.claim_submit(uuid, uuid) from public, anon, authenticated;
grant execute on function public.claim_submit(uuid, uuid) to service_role;

-- 4.
alter policy "read events" on public.club_events to anon, authenticated
  using ((status = 'approved' and (not friends_only or private.sees_post(submitted_by))
          and (club_id is null or private.sees_members(club_id)))
         or submitted_by = (select auth.uid()) or public.is_admin());

-- 5.
create or replace function public.get_group_events(p_group uuid)
returns table (card jsonb)
language sql
stable
security invoker
set search_path = public
as $$
  with found as (
    select e.id, e.event_date
    from public.club_events e
    where e.status = 'approved'
      and e.kind = 'event'
      and e.cancelled_at is null
      and not coalesce(e.friends_only, false)
      and e.event_date >= (now() at time zone 'America/Chicago')::date
      and private.sees_members(p_group)
      -- Its own (start-a-group 05), or found for it: event_group (security definer: neighbours can't read sources)
      -- runs once per upcoming found Event, a few hundred to two thousand rows: cheap for a page open.
      and (e.club_id = p_group
           or (e.club_id is null and e.source_name is not null
               and private.event_group(e.source_name, e.place_entry_id, e.title) = p_group))
    order by e.event_date, e.id
    limit 200
  )
  select ec.card
  from found f
  join private.event_cards(array(select id from found)) ec on ec.id = f.id
  order by f.event_date, f.id
$$;

-- 6. {"meetings": [...], "adds": bool}: get_groups' meetings, every one 120 days ahead rather than its next 10, from
-- the Group's own Google calendar when it has one; none to anyone outside a private Group.
create function public.get_group_calendar(p_group uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'meetings', case when private.sees_members(c.id) then
      (select coalesce(jsonb_agg(m order by m->>'day', m->>'time' nulls first), '[]'::jsonb)
       from jsonb_array_elements(case when c.calendar is null
                                      then public.group_meetings(c.meets, today.d, 1000) else c.calendar end) m
       where jsonb_typeof(m) = 'object' and m->>'day' >= today.d::text)
      else '[]'::jsonb end,
    'adds', private.adds_to_group(c.id, auth.uid()))
  from public.clubs c
  cross join (select (now() at time zone 'America/Chicago')::date as d) today
  where c.id = p_group and c.status <> 'closed'
$$;
revoke execute on function public.get_group_calendar(uuid) from public;
grant execute on function public.get_group_calendar(uuid) to anon, authenticated;

-- 7. Days ('sun' to 'sat'), the weeks of the month (null for every week; [1, 3] for the 1st and 3rd; one for once a
-- month), a 24-hour time and a Place, any of the last three left out. No days clears them. Hands back the when line
-- it wrote: "1st & 3rd Tuesdays at 6:30 PM".
create function public.set_group_meets(p_club uuid, p_days text[], p_weeks int[], p_time text, p_where text)
returns text
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  me uuid := private.need_real();
  v_where text := nullif(btrim(coalesce(p_where, '')), '');
  v_days text[];
  v_schedule text;
begin
  if not private.runs_group(p_club, me) then
    raise exception 'only the Admin sets when it meets' using errcode = '42501';
  end if;
  if not coalesce(p_days, '{}') <@ array['sun', 'mon', 'tue', 'wed', 'thu', 'fri', 'sat'] then
    raise exception 'days: sun to sat' using errcode = '22023';
  end if;
  if not coalesce(p_weeks, '{}') <@ array[1, 2, 3, 4, 5] or cardinality(p_weeks) = 0 then
    raise exception 'weeks: 1 to 5' using errcode = '22023';
  end if;
  if p_time is not null and p_time !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' then
    raise exception 'a time as 18:30' using errcode = '22023';
  end if;
  if char_length(v_where) > 120 then
    raise exception 'a place of at most 120 letters' using errcode = '22023';
  end if;
  -- Each day once, in the week's order.
  select array_agg(d order by array_position(array['sun', 'mon', 'tue', 'wed', 'thu', 'fri', 'sat'], d))
    into v_days from (select distinct unnest(p_days) as d) x;
  if v_days is not null then
    v_schedule := concat_ws(' ',
      (select string_agg(w || case w when 1 then 'st' when 2 then 'nd' when 3 then 'rd' else 'th' end, ' & ' order by w)
       from (select distinct unnest(p_weeks) as w) x),
      (select string_agg(case d when 'sun' then 'Sundays' when 'mon' then 'Mondays' when 'tue' then 'Tuesdays'
                                when 'wed' then 'Wednesdays' when 'thu' then 'Thursdays' when 'fri' then 'Fridays'
                                else 'Saturdays' end, ' & ' order by o)
       from unnest(v_days) with ordinality as u(d, o)))
      || coalesce(' at ' || replace(to_char(p_time::time, 'FMHH12:MI AM'), ':00 ', ' '), '');
  end if;
  update public.clubs
  set meets = case when v_days is null then null else jsonb_build_array(jsonb_strip_nulls(jsonb_build_object(
                'what', 'Get-together', 'days', to_jsonb(v_days),
                'weeks', (select to_jsonb(array_agg(distinct w order by w)) from unnest(p_weeks) w),
                'time', p_time))) end,
      schedule = v_schedule,
      location = case when v_days is null then location else v_where end
  where id = p_club;
  return v_schedule;
end;
$$;
revoke execute on function public.set_group_meets(uuid, text[], int[], text, text) from public, anon;
grant execute on function public.set_group_meets(uuid, text[], int[], text, text) to authenticated;
