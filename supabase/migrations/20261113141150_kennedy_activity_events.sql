-- Kennedy's activities get their events (BP app docs/plans/school-search, ticket 02; Jesse, 2026-11-13: "i agree").

-- Bound calls Nordic "Nordic Ski Racing, Boys" and "Girls Nordic Ski"; the schools' rows say "Nordic Skiing". One word for
-- all of them, as swimming is swim: 15 meets on Apollo's, Cathedral's and Sauk Rapids-Rice's Bound feeds found no activity
-- (2026-11-12). 20261105152417_every_game_white.sql's sport_base but for that.
create or replace function private.sport_base(p text) returns text
language sql immutable set search_path = '' as $$
  select btrim(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(
           replace(lower(regexp_replace(regexp_replace(p, '\s*·.*$', ''), '\([^)]*\)', '', 'g')), '''s', ''),
           '\m(girls?|boys?|women|men|womens|mens|team|competitive|sju|csb)\M', '', 'g'),
           '\d+\s*-\s*\d+', '', 'g'),
           '\mswimming\M', 'swim', 'g'),
           '\mski(ing)?(\s+racing)?\M', 'ski', 'g'),
           '\s*(and|&)\s*div(e|ing)\M', '', 'g'),
           '\mtrack\s*(and|&)\s*field\M', 'track', 'g'),
           '[^a-z]+', ' ', 'g'))
$$;

-- One calendar event can be several activities': Kennedy's "Band/Choir/Orchestra Concert" is Band's, Choir's and
-- Orchestra's (read_events.finalsite_calendar_items names them "Band/Choir/Orchestra"). No sport or activity name had a
-- slash before (2026-11-12). 20261105152417_every_game_white.sql's activity_has_event but for that one line.
create or replace function public.activity_has_event(a public.team_activities, e public.club_events)
returns boolean
language sql stable set search_path = '' as $$
  select x.n is not null
    and coalesce(a.fielded_by, a.team_id) = any(array_append(coalesce(e.team_ids, '{}'), e.activity_team))
    and (private.sport_base(x.n) = private.sport_base(a.name)
         or (e.sport is null and private.sport_base(x.n) <> ''
             and ' ' || private.sport_base(a.name) || ' ' like '% ' || private.sport_base(x.n) || ' %'
             and not exists (select 1 from public.team_activities r
                             where r.team_id = a.team_id and private.sport_base(r.name) = private.sport_base(x.n)))
         or (e.sport is null and x.n like '%/%'
             and private.sport_base(a.name) in (select private.sport_base(p) from unnest(string_to_array(x.n, '/')) p)))
    and case
      when private.sport_gender(x.n) is not null
        then coalesce(private.sport_gender(a.name), private.sport_gender(x.n)) = private.sport_gender(x.n)
      else private.sport_gender(a.name) is not distinct from (
        select private.sport_gender(r.name) from public.team_activities r
        where r.team_id = coalesce(a.fielded_by, a.team_id) and r.fielded_by is null
          and private.sport_base(r.name) = private.sport_base(x.n)
        order by private.sport_gender(r.name) is not null,
                 lower(r.name) not like private.sport_base(x.n) || '%', r.sort
        limit 1)
    end
  from (select coalesce(e.sport, e.activity_name) as n) x
$$;

-- Kennedy's Adapted Floor Hockey is St. Cloud's team on Apollo's Bound feed, as its Adapted Soccer and Softball are.
update public.team_activities set fielded_by = 'apollo'
where team_id = 'kennedy' and name = 'Boys/Girls Adapted Floor Hockey' and fielded_by is null;

-- Kennedy's calendar Events already written carry no activity; the reader names them from tomorrow's read on
-- (read_events.calendar_activity), and this gives today's the same names. Read 2026-11-13.
update public.club_events e set activity_team = 'kennedy', activity_name = x.n
from (values ('b1ae2ed8-56fb-4bf2-829b-9050d71e9dea'::uuid, 'Spelling Bee'),
             ('6d0b4ce6-199b-47c2-982a-70fece75f3f2'::uuid, 'Knowledge Bowl'),
             ('8f92d063-e3d9-4835-8494-6ce696a93699'::uuid, 'Knowledge Bowl'),
             ('ab0ec721-b733-45f7-8fc7-260bcad11887'::uuid, 'Knowledge Bowl'),
             ('f9f03033-e819-4c63-b477-037dd38c5377'::uuid, 'Band/Choir/Orchestra')) as x(id, n)
where e.id = x.id and e.activity_name is null;

-- Knowledge Bowl at St. John's Prep, Nov 19: Kennedy's school calendar repeats its Bound meet. Kept 0e55ea20 (Bound, at
-- St. John's Prep, with its activity).
update public.club_events set status = 'rejected', review_reason = 'other' where id = 'fdd32f02-56af-4513-b9b5-7e9f15a35d90';
