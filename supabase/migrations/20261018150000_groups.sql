-- Groups go live (BP app docs/plans/rsvp-and-groups, ticket 05; Jesse, 2026-10-17 and 2026-10-18).
-- St. Joseph's real groups get what their page needs, and one read gives the Search tab's Groups
-- shelf and a Group page everything: approved groups only, with their pictures, their next
-- get-togethers, how many members they have and whether you're in. It runs on the server so
-- Android reads the same.
--
-- New columns on public.clubs (the database keeps its clubs names; neighbours read "groups"):
--   kind            what kind of group, as its page says it ("Book club").
--   page_url        the group's own website.
--   entry_id        the group's own key for its pictures in public.place_photos (its photos and
--                   logo, saved once by Block Party from its own pages, like a place's).
--   place_entry_id  where it meets: a registry entry, as club_events.place_entry_id. Its picture
--                   stands in when the group has none of its own.
--   meets           when it gets together, as rules the server turns into dates (Coming up):
--                   [{"what": "Meeting", "days": ["tue"], "weeks": [1, 3], "time": "18:00",
--                     "months_off": [6, 7], "where": "Heritage Hall"}]
--                   days: Postgres's three-letter day names; weeks: the weeks of the month (1 for
--                   days 1-7, 4 for days 22-28), absent for every week; time: 24-hour, absent when
--                   unknown; months_off: months it doesn't meet; where: only when it isn't the
--                   group's usual place.

alter table public.clubs
  add column if not exists kind text,
  add column if not exists page_url text,
  add column if not exists entry_id text,
  add column if not exists place_entry_id text,
  add column if not exists meets jsonb;

-- How many people are in a group. Memberships are readable by signed-in accounts only, and a
-- signed-out neighbour still sees the count, so it is counted as the owner, like going_count.
create or replace function private.member_count(p_club uuid)
returns int
language sql
stable
security definer
set search_path = ''
as $$
  select count(*)::int from public.club_members where club_id = p_club
$$;

revoke execute on function private.member_count(uuid) from public;
grant execute on function private.member_count(uuid) to anon, authenticated;

-- A group's next get-togethers from its rules: up to p_n, from the town date p_from on, within
-- 120 days, soonest first, each {"what", "day" ("2026-10-20"), "time" ("18:00" or null),
-- "where" (or null)}.
-- ponytail: rules only, so a meeting a group skips for a holiday still shows; add dated
-- exceptions when a group's calendar needs them.
create or replace function public.group_meetings(p_meets jsonb, p_from date, p_n int default 3)
returns jsonb
language sql
immutable
set search_path = public
as $$
  select coalesce(jsonb_agg(jsonb_build_object('what', m.what, 'day', m.day, 'time', m.time, 'where', m.place)
                            order by m.day, m.time), '[]'::jsonb)
  from (
    select r->>'what' as what, to_char(d, 'YYYY-MM-DD') as day, r->>'time' as time, r->>'where' as place
    from jsonb_array_elements(case when jsonb_typeof(p_meets) = 'array' then p_meets else '[]'::jsonb end) r
    cross join generate_series(p_from, p_from + 120, interval '1 day') d
    where to_char(d, 'dy') in (select jsonb_array_elements_text(r->'days'))
      and (jsonb_typeof(r->'weeks') is distinct from 'array'
           or ((extract(day from d)::int - 1) / 7 + 1) in (select (jsonb_array_elements_text(r->'weeks'))::int))
      and extract(month from d)::int not in
          (select (jsonb_array_elements_text(case when jsonb_typeof(r->'months_off') = 'array'
                                                  then r->'months_off' else '[]'::jsonb end))::int)
    order by 2, 3
    limit p_n
  ) m
$$;

grant execute on function public.group_meetings(jsonb, date, int) to anon, authenticated;

-- Every approved group, in the shelf's order: most members first, then those with a photo, then
-- those with a logo, then by name. Its pictures follow the rule Events already follow, the group's
-- own first: photos, its own, else its meeting place's (photo only); a logo for when there is no
-- photo, its own, else its place's. Both in public.place_picture's shape, so the app reads them alike.
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
           public.group_meetings(c.meets, (now() at time zone 'America/Chicago')::date) as meetings,
           private.member_count(c.id) as member_count,
           auth.uid() is not null
             and exists (select 1 from public.club_members m where m.club_id = c.id and m.user_id = auth.uid())
             as joined
    from public.clubs c
    left join lateral (select public.place_picture(c.place_entry_id) as pic) place on true
    where c.status = 'approved'
  ) g
  order by g.member_count desc, (g.photos <> '[]'::jsonb) desc, (g.logo is not null) desc, g.name
$$;

grant execute on function public.get_groups() to anon, authenticated;
