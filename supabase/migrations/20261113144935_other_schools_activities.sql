-- Other schools' events land on their activities (BP app docs/plans/school-search, ticket 07; Jesse, 2026-11-13: "yes i
-- agree to all"). 31 upcoming events named a school and landed on none of its activities (2026-11-13); this lands 27.

-- "MS" and "coed" say who plays, not the sport: Sauk Rapids-Rice's "MS Coed Wrestling" meets are its Wrestling's (Jesse:
-- a middle school meet goes on the high school's row). "Adapted Floor Hockey" is Apollo's and Tech's "Adapted Hockey",
-- and "Adapted Sports: Soccer" Sauk Rapids-Rice's adapted soccer.
-- A bracket that lists what an activity covers stays in its name, so an event naming one of them lands on it through
-- activity_has_event's name-inside-the-name test (an event that is no game, at a school with no activity of that very
-- name): Sauk Rapids-Rice's "Theatre (Fall Musical, One-Act Play, Spring Play)" takes its One Act Play and its fall
-- musical, Tech's "Language Clubs (French, Spanish)" a Spanish club day. Any other bracket still goes ("Soccer (boys)").
-- Here rather than in activity_has_event, so team_page's and activities_next's quick test (activity_may_have, ticket
-- 06) reads it too.
-- 20261113141150_kennedy_activity_events.sql's sport_base but for those. Checked live: of every activity, sport and
-- activity name, only those 11 names read otherwise.
create or replace function private.sport_base(p text) returns text
language sql immutable set search_path = '' as $$
  select btrim(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(
           regexp_replace(
           replace(lower(regexp_replace(regexp_replace(p, '\s*·.*$', ''), '\([^),]*\)', '', 'g')), '''s', ''),
           '\m(girls?|boys?|women|men|womens|mens|team|competitive|sju|csb|coed|ms)\M', '', 'g'),
           '\d+\s*-\s*\d+', '', 'g'),
           '\mswimming\M', 'swim', 'g'),
           '\mski(ing)?(\s+racing)?\M', 'ski', 'g'),
           '\s*(and|&)\s*div(e|ing)\M', '', 'g'),
           '\mtrack\s*(and|&)\s*field\M', 'track', 'g'),
           '[^a-z]+', ' ', 'g'),
           '\madapted( sports)?( floor)?\M', 'adapted', 'g'))
$$;

-- Bound's concerts, shows and club days already written carry no activity; the reader names them from tomorrow's read on
-- (read_events.bound_items, from the title), and this gives today's the same names. Read 2026-11-13.
update public.club_events e set activity_name = x.n
from (values ('09754fab-943b-4782-8e84-54d5db92f481'::uuid, 'Art Club'),   -- Cathedral, Nov 18
             ('9b354589-52b3-4f98-9c31-6a58acedccad'::uuid, 'Art Club'),   -- Cathedral, Dec 2
             ('3696e038-d8cb-4bf2-9382-1232586c4bf0'::uuid, 'Art Club'),   -- Cathedral, Dec 16
             ('723013de-6dac-41d3-8b36-eb6b8218ad7c'::uuid, 'Art Club'),   -- Cathedral, Jan 13
             ('e319e173-f5c4-4017-a073-2da6a0396e56'::uuid, 'Art Club'),   -- Cathedral, Jan 27
             ('06b0a31f-47d5-4845-a6d9-83b739b66ed3'::uuid, 'Art Club'),   -- Cathedral, Feb 3
             ('d8629667-b489-427a-98ca-47080fbcecaf'::uuid, 'Orchestra'),  -- Sartell, SMS Orchestra Concerts, Dec 10
             ('25549ce8-d390-46fc-92f6-c1f71386d4a8'::uuid, 'Musical'),    -- Sauk Rapids-Rice, The Little Mermaid, Nov 13
             ('5c833f65-2a23-46b0-8b50-6d37f5bb1323'::uuid, 'Musical'),    -- Nov 14
             ('777719f5-edb3-4000-b448-673bb128fc6a'::uuid, 'Musical'),    -- Nov 14
             ('f2e5aed4-3df6-4e47-8cfe-4f132edc62cd'::uuid, 'Band'),       -- HS Fall Band Concert, Nov 17
             ('bc66d6d0-8427-45f6-acc5-1ac79749cff9'::uuid, 'Choir'),      -- HS Fall Choir Concert, Nov 23
             ('43ebdbee-37eb-4c49-a50d-f96190d2f821'::uuid, 'Choir'),      -- MS Choir Concert, Dec 10
             ('84e18b1d-8a14-40ed-a007-07ee5cc9ad42'::uuid, 'Band'),       -- MS Band Concert 7th & 8th, Dec 15
             ('f8682a3b-d158-4d6e-be21-8f5159cfa1d1'::uuid, 'Band'),       -- MS Band Concert 6th Grade, Dec 17
             ('5e327d5a-fa3f-4364-81a6-4ab5cc07a82a'::uuid, 'Choir')       -- HS Winter Choir Concert, Feb 8
     ) as x(id, n)
where e.id = x.id and e.activity_name is null;
