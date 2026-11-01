-- The St. Cloud Crush's Nov 14 dance show at Apollo showed twice: MSHSL's schedule gave
-- "Crush Dance Show" at 10 AM with its description (26a0d3c7, kept) and Bound gave the same title at
-- the Apollo gym at 2 PM with none (c32125cf). Hidden; a re-read keeps an admin's reject. The two
-- schedules disagree on the time; the kept row says 10 AM.
update public.club_events set status = 'rejected', review_reason = 'other'
 where id = 'c32125cf-06bf-4dea-97ed-16e85832f624';
