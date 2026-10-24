-- Neighbors Route 75 posted events at its Albertville location, out of the area (Jesse, 2026-10-24).
update public.club_events
set status = 'rejected', review_reason = 'wrong_place'
where id in ('585684c8-4de4-4dc0-94d1-7b684005285d', 'c027eb3c-15c0-4958-88fc-10907abf95ce');
