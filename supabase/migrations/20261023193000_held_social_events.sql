-- The weekly social watch's held events, settled (Jesse, 2026-10-23: "approve all using your
-- determining skill"). Kept: real events neighbours can go to. Turned down: outside the area,
-- members only, or ads.

-- Coborn's St. Joseph store (1500 Elm St E); the post says times vary by store.
update public.club_events
set status = 'approved', location = 'Coborn''s', interests = array['families_kids']
where id = '753decd6-afee-4da8-8560-51ee45f1370f';

-- District 742's post: Nov 7, grand entries at 1 and 5 p.m.; it names no venue yet.
update public.club_events
set status = 'approved', interests = array['festivals', 'families_kids']
where id = '941220e1-734b-48df-9a78-80b50432ea71';

-- Turned down: Girls Night Out (a Brainerd lakes area store, outside the area), Training Tuesday
-- (online, Legion post officers only), the A'26 conference (a trade booth in Minneapolis) and both
-- Medicare seminars (a sales ad).
update public.club_events
set status = 'rejected', review_reason = case id
    when '144f7370-c7c2-4ab1-8e0d-cae2141dd1f3'::uuid then 'wrong_place'
    else 'not_event' end
where id in ('144f7370-c7c2-4ab1-8e0d-cae2141dd1f3', '552c2027-6885-4789-abe8-9677a93b152d',
             '189b86b5-c579-44a2-b83b-3d4c21634f3a', '8191cadb-e6d8-4ca3-a211-614a4b38389d',
             '387b66e4-8fc4-4951-b7f5-548b7dcea4ce');
