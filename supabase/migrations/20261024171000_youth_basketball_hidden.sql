-- "Youth basketball, grades 3-5, starts Nov. 8" came from the city's Recreation page in
-- September. That page now forwards to the city's rec1 catalog, which (2026-10-24) lists youth
-- crafts, volleyball and dodgeball but no basketball. Hidden until the city posts it (Jesse,
-- 2026-10-24); the morning watch adds it again from the catalog when it appears.
update public.club_events set status = 'rejected' where id = '5d02c8b8-34aa-47ff-aafa-11f818824011';
