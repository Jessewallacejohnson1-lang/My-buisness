-- Nov 4 morning review.

-- Therapy Dogs, tonight at 7: the campus calendar lists one night twice. Kept: 4e40da39 "Therapy Dogs",
-- the copy with the full About and both libraries.
update public.club_events set status = 'rejected', review_reason = 'other'
 where id = 'dd2f4f13-842a-422b-b28f-c7abef2b7605';  -- Therapy Dogs at Clemens Library, Nov 4

-- Titles from the schools' Bound calendars that name no event: nothing else to keep.
update public.club_events set status = 'rejected', review_reason = 'wrong_title'
 where id in (
   '7ab86d8f-71fa-4a60-a000-16bab6b85144',  -- "vs St. Cloud Cathedral", Holy Angels Performing Arts Center, Nov 19
   'ab6ae222-d1d4-4b28-b2e4-160b440b3cc5',  -- "vs St. Cloud Cathedral", Holy Angels Performing Arts Center, Nov 20
   '22b67930-56b1-46b2-bb22-cb6d9cef19f7',  -- "Boys MS", Washington Educational Services Building, Dec 7
   '43bc4eed-f632-4756-bb86-fec4df2a4287'   -- "Boys MS", Washington Educational Services Building, Jan 11
 );
