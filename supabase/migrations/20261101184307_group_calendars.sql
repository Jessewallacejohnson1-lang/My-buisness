-- A group's Coming up from its own calendar (Jesse, 2026-11-01: "read every morning", "yes add them"). St. Cloud
-- River Runners keep a public Google Calendar of every run (scrr.org/dynamic-calendar); a fixed rule can't know a
-- skipped Sunday, the year's end or where Saturday's breakfast run is. calendar.google.com's robots.txt turns
-- readers away from the page and its iCal feed, so the database reads it through Google's Calendar API with
-- Block Party's own key (Vault secret 'google_calendar_key', Jesse's, never in this repo).
--
-- Each morning private.read_group_calendars() keeps the next 120 days of each group's calendar in
-- clubs.calendar, as the meetings get_groups already sends: {what, day, time, where}. A failed read keeps the last
-- good copy, and the 8:00 check names a calendar not read in over a day. get_groups sends the calendar's
-- meetings in place of the rule's: the next 3, or every one in the coming week when there are more, so a group
-- that runs five times a week still shows its Sunday.

alter table public.clubs add column if not exists calendar_id text;
alter table public.clubs add column if not exists calendar jsonb;
alter table public.clubs add column if not exists calendar_read_at timestamptz;

update public.clubs set calendar_id = '71420aab7f8c91352053d2252d6f799c2009cdc467e4b99fb04ffd105442c70a@group.calendar.google.com'
where entry_id = 'group-st-cloud-river-runners';

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
  for v_club in select c.id, c.calendar_id from public.clubs c where c.calendar_id is not null and c.status = 'approved' loop
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
    -- part ("The Local Blend, 19 W Minnesota St, ..."). TBD, TBA and "Check Facebook ..." name no place.
    update public.clubs set calendar_read_at = p_now, calendar = (
      select coalesce(jsonb_agg(jsonb_build_object(
               'what', btrim(split_part(i ->> 'summary', ' @ ', 1)),
               'day', coalesce(left(i -> 'start' ->> 'dateTime', 10), i -> 'start' ->> 'date'),
               'time', substr(i -> 'start' ->> 'dateTime', 12, 5),
               'where', case when w.place !~* '^(tbd|tba|check )' then nullif(w.place, '') end)
             order by coalesce(i -> 'start' ->> 'dateTime', i -> 'start' ->> 'date')), '[]'::jsonb)
      from jsonb_array_elements(v_body::jsonb -> 'items') i
      cross join lateral (select btrim(case when position(' @ ' in i ->> 'summary') > 0
                                            then substr(i ->> 'summary', position(' @ ' in i ->> 'summary') + 3)
                                            else split_part(i ->> 'location', ',', 1) end) as place) w
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
           case when c.calendar is null then public.group_meetings(c.meets, today.d)
                else (select coalesce(jsonb_agg(x.m order by x.n), '[]'::jsonb)
                        from (select m, row_number() over (order by m->>'day', m->>'time' nulls first) as n
                                from jsonb_array_elements(c.calendar) m
                               where (m->>'day')::date >= today.d) x
                       where x.n <= 3 or (x.m->>'day')::date < today.d + 7) end as meetings,
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

-- Before 8:00's check (10:30 UTC is 4:30 or 5:30 in Chicago).
select cron.schedule('group-calendars', '30 10 * * *', $$select private.read_group_calendars()$$);
