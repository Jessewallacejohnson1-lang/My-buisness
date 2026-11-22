-- Morning report 2026-11-22 take-out.

-- The SpongeBob Musical (Apollo High School, Bound, Nov 22 2 PM) is the same show as
-- "Apollo Fall Musical" at 2 PM; keeps b6210048 (has the About, which names the show, and an end time).
update public.club_events set status = 'rejected', review_reason = 'other'
where id = 'a77d75ff-ea24-4c07-bef1-76ec8f4a84f2';

-- Black Friday Event with White Peony (WR Home & Clothing Co., Facebook, Nov 27 5 AM, no place)
-- is White Peony's own Black Friday at 5 AM (the two shops share a spot); keeps 238ea1de
-- (White Peony's own listing, its place and the longer About).
update public.club_events set status = 'rejected', review_reason = 'other'
where id = 'd0538a00-4611-4178-8aa8-547157637aad';

-- Sing the Season: All College Choir (Facebook, Dec 6 3 PM, Abbey Church) is the same concert as
-- "All College Choir"; the Music Department's own page puts it in The Great Hall, and the
-- Facebook event gives only SJU's street address. Keeps c0694c82 (Great Hall, the longer About).
update public.club_events set status = 'rejected', review_reason = 'other'
where id = '4d8d23bf-7af6-49f3-9dc3-6192dba4d366';

-- "St. Francis Xaiver: Buffalo" (Cathedral, Bound, Nov 23): a misspelled opponent and town,
-- no sport; the title names no event.
update public.club_events set status = 'rejected', review_reason = 'wrong_title'
where id = 'a1c7fa85-054b-472c-9968-4b2f7ad47991';
