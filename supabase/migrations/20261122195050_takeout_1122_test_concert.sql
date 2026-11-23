-- Take-out 2026-11-22 (BP app morning-report: a wrong Event comes out without asking; Jesse, 2026-10-29): "Test Concert",
-- Sartell High School's GoBound listing on Dec 7 at 7 PM, names no event. It sits beside the school's SHS Choir Concert
-- that day, which stays. Seen in the photo judge's first batch (BP app event-photos 30).
update public.club_events set status = 'rejected', review_reason = 'not_event'
 where id = 'd6967505-a594-40e2-a2b6-1b228dae08b6';
