-- MSHSL's schedule lists St. Cloud girls hockey vs Academy of Holy Angels on Nov 20, 2026, but
-- Holy Angels' own 2026-27 schedule (academyofholyangelsstarsathletics.com, read 2026-10-24) has
-- no game that day and no St. Cloud game at all: its varsity opens Nov 12 vs Chisago Lakes, then
-- Nov 24 vs Blake. Hidden; a re-read keeps an admin's reject.
update public.club_events set status = 'rejected' where id = '0e7e8c11-614d-4839-8d3e-ea5929ea35b9';
