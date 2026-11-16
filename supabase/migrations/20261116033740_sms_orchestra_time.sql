-- "SMS Orchestra Concerts" Dec 10 (d8629667, from Bound) said 6 AM. The district calendar
-- (isd748.org/calendars?cal_date=2026-12-01) lists SMS Grade 6 Orchestra Concert 6:00-7:00 PM and
-- Grades 7 & 8 Orchestra Concert 7:00-8:00 PM, both SMS PAC: 6 PM to 8 PM (Jesse's yes, 2026-11-15).
update public.club_events
set start_time = '6 PM', all_day = false, end_at = '2026-12-10 20:00:00 America/Chicago'
where id = 'd8629667-b489-427a-98ca-47080fbcecaf';
