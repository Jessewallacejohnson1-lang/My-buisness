-- "First Trimester Ends" (Kennedy's Bound calendar) is a school-calendar date, not something people go to.
update public.club_events set status = 'rejected', review_reason = 'not_event'
 where id = '5d1985b4-c765-4835-9e71-5c8e647f113c';
