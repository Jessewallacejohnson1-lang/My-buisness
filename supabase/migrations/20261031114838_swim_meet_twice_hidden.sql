-- Sartell's Oct 31 Central Lakes Conference swim meet showed twice: MSHSL's schedule gave
-- "Central Lakes Conference Swim Meet" (688507e4, kept) and Bound gave "Central Lakes Conference
-- Meet" at Sartell High School Pool, same day and 1 PM (833697bf). Hidden; a re-read keeps an
-- admin's reject.
update public.club_events set status = 'rejected', review_reason = 'other'
 where id = '833697bf-ce05-46fa-9e27-3d1e9630a49c';
