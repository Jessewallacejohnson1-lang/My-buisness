-- "Unplugged at Alcuin: June Kapinos", Nov 18: the campus calendar's clock says 7 to 8 AM, its own About says
-- "7-8pm" (a student concert in the Learning Commons). Jesse's yes, 2026-11-18.
update public.club_events
set start_time = '7 PM', all_day = false, end_at = '2026-11-18 20:00:00 America/Chicago'
where id::text like '6047c0ab%' and event_date = '2026-11-18';
