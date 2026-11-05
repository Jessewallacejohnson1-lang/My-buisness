-- A doubled Event: Goodin's plumbing course on Dec. 3 was found twice. Keeps aadf4121, "Plumbing Training",
-- which has the fuller About and the same place.
update public.club_events
   set status = 'rejected', review_reason = 'other'
 where id = 'e55862ed-e05a-4252-baec-17ae0b0cfa5b';
