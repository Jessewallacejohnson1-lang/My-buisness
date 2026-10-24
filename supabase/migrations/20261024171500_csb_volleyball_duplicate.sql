-- The campus calendar lists CSB Volleyball vs Augsburg (Oct 24, 5 PM, Claire Lynch Hall) twice,
-- under two event ids (4155152 and 4797834), so the writer kept both. The later copy is hidden
-- (Jesse, 2026-10-24); a re-read keeps an admin's reject.
update public.club_events set status = 'rejected' where id = '2ce82280-4b1f-46f6-a364-978cde9952f0';
