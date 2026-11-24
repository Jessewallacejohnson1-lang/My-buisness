-- Take-out 2026-11-23: six Events nobody can still sign up for (BP app watch-every-place 49; Jesse, 2026-10-17: "if your not
-- able ot signup or go dont recommend it"; a misleading Event comes out without asking, 2026-10-29). Each page read again
-- 2026-11-23, 1:20 to 1:30 PM. Nobody was Going to, saved or liked any of them.

-- Saint Benedict's Monastery: Advent Sacred Pause (Dec 2, 9, 16, 23) and the Advent Centering Prayer Retreat (Dec 4). Each
-- day's own page on sbm.osb.org says "Registration is filled."
update public.club_events set status = 'rejected', review_reason = 'other'
where id in (select e.id from public.club_events e
             where left(e.id::text, 8) in ('a2cbfb64', 'cb01fb87', 'a7f1ccbd', '0a6ec453', 'f88dbb1a')
               and e.source_url like 'https://sbm.osb.org/event/advent-%');

-- City of St. Joseph, Winter Paint and Sip (Dec 11): its details say registrationOver, "Registration: Oct 12-Nov 1", and it
-- is gone from the catalog's list.
update public.club_events set status = 'rejected', review_reason = 'other'
where left(id::text, 8) = 'fb96a3b7' and source_uid = 'rec1:4553613';
