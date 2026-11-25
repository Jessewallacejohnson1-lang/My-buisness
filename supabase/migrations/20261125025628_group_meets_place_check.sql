-- The Place in When you meet goes through the checks (BP app docs/plans/start-a-group, ticket 08). set_group_meets put it on
-- the public Group page unread. It now takes only the Place the Group already has, or none; a new one goes through
-- moderate-post's `group` mode with the days and time it came with, and all of them land on its two yeses or none do, as a
-- post's edit (claim_edit, apply_post_edit). Nothing waits in a table.
-- No live Group has an Admin yet (read 2026-11-24), so nothing live changes.
--   1. private.write_group_meets: set_group_meets' rules and write from 20261122204701_group_calendar.sql, line for line but
--      a Place's spaces and line ends are one space (a line end could pass for another line of what the check reads).
--   2. set_group_meets: Admin only, as before; a new Place is refused with PT409, which PostgREST answers as HTTP 409 and
--      the app takes to the check. An older app can keep a Place or take it off, never add one.
--   3. claim_group_meets, apply_group_meets: moderate-post's.

-- 1.
create function private.write_group_meets(p_club uuid, p_days text[], p_weeks int[], p_time text, p_where text)
returns text
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_where text := nullif(regexp_replace(btrim(coalesce(p_where, '')), '\s+', ' ', 'g'), '');
  v_days text[];
  v_schedule text;
begin
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
      location = case when v_days is not null then v_where end
  where id = p_club;
  return v_schedule;
end;
$$;
revoke execute on function private.write_group_meets(uuid, text[], int[], text, text) from public, anon, authenticated, service_role;

-- 2.
create or replace function public.set_group_meets(p_club uuid, p_days text[], p_weeks int[], p_time text, p_where text)
returns text
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  me uuid := private.need_real();
  v_where text := nullif(regexp_replace(btrim(coalesce(p_where, '')), '\s+', ' ', 'g'), '');
begin
  if not private.runs_group(p_club, me) then
    raise exception 'only the Admin sets when it meets' using errcode = '42501';
  end if;
  -- As edit_group locks, the Group first: the Place it has can't change under this.
  perform 1 from public.clubs where id = p_club for update;
  -- No days clears the Place with them, so there is none to check.
  if cardinality(p_days) > 0 and v_where is not null
     and v_where is distinct from (select c.location from public.clubs c where c.id = p_club) then
    raise exception 'a new Place goes through the checks' using errcode = 'PT409';
  end if;
  return private.write_group_meets(p_club, p_days, p_weeks, p_time, p_where);
end;
$$;

-- 3. The Group's name, for the check to read, and when and where it meets now, which apply_group_meets asks for; {"limit":
-- true} when the day's 10 are used, Edit group's checks counted with these; null from anyone but the Admin. The row it
-- keeps holds no words and is never `current`, so Edit group's saves leave it alone.
create function public.claim_group_meets(p_club uuid, p_user uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  perform pg_advisory_xact_lock(hashtextextended('claim_group_edit:' || p_user::text, 0));
  if not private.runs_group(p_club, p_user) then
    return null;
  end if;
  if (select count(*) from private.group_edit_checks where user_id = p_user and at > now() - interval '24 hours') >= 10 then
    return jsonb_build_object('limit', true);
  end if;
  insert into private.group_edit_checks (user_id, club_id, edit, current) values (p_user, p_club, '{}', false);
  return (select jsonb_build_object('name', c.name, 'was',
                   jsonb_build_object('meets', c.meets, 'schedule', c.schedule, 'location', c.location))
          from public.clubs c where c.id = p_club);
end;
$$;

-- What both checks said yes to: the when line it wrote. Null when the Group was closed or handed on while it was checked, or
-- when and where it meets was saved from another phone meanwhile (p_was, from the claim).
create function public.apply_group_meets(p_club uuid, p_user uuid, p_was jsonb, p_days text[], p_weeks int[], p_time text,
                                         p_where text)
returns text
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  -- As edit_group locks, the Group first: a save and this can't pass each other.
  perform 1 from public.clubs c
  where c.id = p_club
    and p_was = jsonb_build_object('meets', c.meets, 'schedule', c.schedule, 'location', c.location)
  for update;
  if not found or not private.runs_group(p_club, p_user) then
    return null;
  end if;
  return private.write_group_meets(p_club, p_days, p_weeks, p_time, p_where);
end;
$$;
revoke execute on function public.claim_group_meets(uuid, uuid),
  public.apply_group_meets(uuid, uuid, jsonb, text[], int[], text, text) from public, anon, authenticated;
grant execute on function public.claim_group_meets(uuid, uuid),
  public.apply_group_meets(uuid, uuid, jsonb, text[], int[], text, text) to service_role;
