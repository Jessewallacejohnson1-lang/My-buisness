-- Nov 3 morning: Stearns County's calendar newly listed eight Outdoor U events at "2850 Abbey Plaza",
-- each already in the feed from Outdoor U's own page with a description and the Arboretum as its place
-- (kept: Animal tracking a5594faf, Banff 8459be74, Owl Hoot eb3b6cb1, Print making 9267ef80,
-- Wreath making aaa92df3, 341c04cf, 58a9d010, 03c2b9c6). The county copies are hidden.
update public.club_events set status = 'rejected', review_reason = 'other'
 where id in (
   '0437dd8a-0bc7-4622-972c-c2e078b3ad49',  -- Animal Tracking, Jan 9
   '47f6f6cb-4e7e-4cc9-a7da-6ba8a16b5659',  -- Banff Mountain Film Festival, Dec 4
   'edc733ad-2e32-4001-a28d-5090bc6e7ee5',  -- The Owl Hoot, Jan 23
   'b03ea030-55d1-4889-b810-1dd1a38b03da',  -- Print Making Workshop, Nov 20
   'e187b6da-e4fe-4480-a4c4-956acbdefdf8',  -- Christmas Wreath Making Workshop, Nov 30 4:30
   'dc010930-924e-42e0-b8a4-b86cf4a9f917',  -- Christmas Wreath Making Workshop, Dec 1 12:30
   '69cbce4d-b5e2-478d-83f8-cd17eeb466e7',  -- Christmas Wreath Making Workshop, Dec 2 12:30
   '5c2954b1-9e04-4e21-8f22-543c517b9a79'   -- Christmas Wreath Making Workshop, Dec 2 4:30
 );

-- "Time TBA" (Apollo's Bound schedule, Jan 26) is a Willmar JV meet that came in with no name.
update public.club_events set status = 'rejected', review_reason = 'wrong_title'
 where id = '50e944b9-9160-4de5-bf9c-9b5553665cb4';
