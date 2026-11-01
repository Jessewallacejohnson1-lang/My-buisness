-- A group calendar's loopholes (Jesse, 2026-11-01: "yes i agree to all", to the review of
-- 20261101184307_group_calendars.sql):
--   - On a Sunday afternoon Coming up showed that morning's run, already over, and not next Sunday's, 7 days out:
--     the coming week stopped a day short. Now a meeting drops once it has started, every group's, and the
--     coming week runs through the same weekday next week (private.coming_up).
--   - A saved meeting with a broken day or time is left out, never the whole Groups list (as
--     20261018150200_group_meetings_guard.sql does for rules).
--   - A member's home is no place to publish, and River Runners' runs outside St. Joseph say so ("St. Cloud
--     area", the club's own words) and carry `away`, which the member's hello skips (BlockParty HelloDrop).

alter table public.clubs add column if not exists calendar_area text;
update public.clubs set calendar_area = 'St. Cloud area' where entry_id = 'group-st-cloud-river-runners';

-- A group's coming meetings from a list of {what, day, time, where}, soonest first: from now on (an untimed one
-- through its day), the next 3, or every one through this weekday next week when there are more.
create or replace function private.coming_up(p_meetings jsonb, p_now timestamptz)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select coalesce(jsonb_agg(x.m order by x.n), '[]'::jsonb)
  from (
    select m, d.day, row_number() over (order by m->>'day', m->>'time' nulls first) as n
    from jsonb_array_elements(case when jsonb_typeof(p_meetings) = 'array' then p_meetings else '[]'::jsonb end) m
    cross join lateral (select case when pg_input_is_valid(m->>'day', 'date') then (m->>'day')::date end as day,
                               case when pg_input_is_valid(m->>'time', 'time') then (m->>'time')::time end as at) d
    where d.day is not null
      and case when d.at is null then d.day >= (p_now at time zone 'America/Chicago')::date
               else d.day + d.at >= p_now at time zone 'America/Chicago' end
  ) x
  where x.n <= 3 or x.day <= (p_now at time zone 'America/Chicago')::date + 7
$$;

grant execute on function private.coming_up(jsonb, timestamptz) to anon, authenticated;

create or replace function private.read_group_calendars(p_now timestamptz default now())
returns void
language plpgsql
set search_path = ''
as $$
declare
  v_key text;
  v_club record;
  v_status int;
  v_body text;
begin
  select s.decrypted_secret into v_key from vault.decrypted_secrets s where s.name = 'google_calendar_key';
  if v_key is null then raise exception 'group calendars: no google_calendar_key in Vault'; end if;

  perform extensions.http_set_curlopt('CURLOPT_TIMEOUT', '30');
  for v_club in select c.id, c.calendar_id, c.calendar_area from public.clubs c where c.calendar_id is not null and c.status = 'approved' loop
    select r.status, r.content into v_status, v_body
    from extensions.http(('GET',
      format('https://www.googleapis.com/calendar/v3/calendars/%s/events?singleEvents=true&orderBy=startTime'
             '&maxResults=250&timeZone=America%%2FChicago&timeMin=%s&timeMax=%s',
             replace(v_club.calendar_id, '@', '%40'),
             to_char(p_now at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
             to_char((p_now + interval '120 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
      array[extensions.http_header('X-goog-api-key', v_key)], null, null)::extensions.http_request) r;
    continue when v_status is distinct from 200;

    -- "Breakfast Run @ Kitchenette" is the Breakfast Run at Kitchenette; else the place is the location's first
    -- part ("The Local Blend, 19 W Minnesota St, ..."). TBD, TBA and "Check Facebook ..." name no place, and a
    -- member's home ("Home of Jess and Mark") isn't one to publish. A group with a calendar_area meets mostly
    -- outside St. Joseph: a run whose location doesn't say St. Joseph is away, its place followed by the area
    -- ("Coborn's Grocery Store, St. Cloud area": that Coborn's is Sauk Rapids', not St. Joseph's), and the
    -- member's hello leaves it out. ponytail: a St. Joseph place named only in the title reads as away.
    update public.clubs set calendar_read_at = p_now, calendar = (
      select coalesce(jsonb_agg(jsonb_build_object(
               'what', btrim(split_part(i ->> 'summary', ' @ ', 1)),
               'day', coalesce(left(i -> 'start' ->> 'dateTime', 10), i -> 'start' ->> 'date'),
               'time', substr(i -> 'start' ->> 'dateTime', 12, 5),
               'where', case when a.away then concat_ws(', ', p.place, v_club.calendar_area) else p.place end,
               'away', a.away)
             order by coalesce(i -> 'start' ->> 'dateTime', i -> 'start' ->> 'date')), '[]'::jsonb)
      from jsonb_array_elements(v_body::jsonb -> 'items') i
      cross join lateral (select btrim(case when position(' @ ' in i ->> 'summary') > 0
                                            then substr(i ->> 'summary', position(' @ ' in i ->> 'summary') + 3)
                                            else split_part(i ->> 'location', ',', 1) end) as place) w
      cross join lateral (select case when w.place !~* '^(tbd|tba|check |home of )' then nullif(w.place, '') end as place) p
      cross join lateral (select v_club.calendar_area is not null
                                 and coalesce(i ->> 'location', '') !~* '(st\.? joseph|saint joseph|56374)' as away) a
      where i ->> 'summary' is not null and i ->> 'status' is distinct from 'cancelled')
    where id = v_club.id;
  end loop;
end;
$$;

revoke execute on function private.read_group_calendars(timestamptz) from public;

create or replace function public.get_groups()
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
  joined boolean
)
language sql
stable
security invoker
set search_path = public
as $$
  select g.id, g.name, g.kind, g.schedule, g.location, g.description, g.page_url, g.photos, g.logo,
         g.meetings, g.member_count, g.joined
  from (
    select c.id, c.name, c.kind, c.schedule, c.location, c.description, c.page_url,
           coalesce(
             (select jsonb_agg(jsonb_build_object('url', p.url, 'kind', 'photo', 'credit', p.credit,
                                                  'site', p.source_url) order by p.position)
                from public.place_photos p
               where p.entry_id = c.entry_id and p.status = 'live' and p.kind = 'photo'),
             case when place.pic->>'kind' = 'photo' then jsonb_build_array(place.pic) end,
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
             as joined
    from public.clubs c
    cross join (select (now() at time zone 'America/Chicago')::date as d) today
    left join lateral (select public.place_picture(c.place_entry_id) as pic) place on true
    where c.status = 'approved'
  ) g
  order by g.member_count desc, (g.photos <> '[]'::jsonb) desc, (g.logo is not null) desc, g.name
$$;
grant execute on function public.get_groups() to anon, authenticated;
