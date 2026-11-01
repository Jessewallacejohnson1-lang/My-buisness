-- The MSHSL State Cross Country Meet on Sat Nov 7 at 10 AM showed twice: Sartell's Bound schedule gave
-- "MSHSL State Cross Country Meet" at Majestic Oaks Golf Course (caf1c75a, kept) and Cathedral's gave
-- "State Cross Country Meet: Blaine" with no place (fa8c77f7). Hidden; a re-read keeps an admin's reject.
update public.club_events set status = 'rejected', review_reason = 'other'
 where id = 'fa8c77f7-85bf-418b-8f32-a4c79fae43ba';
