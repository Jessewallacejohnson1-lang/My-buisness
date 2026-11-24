-- Take-out 2026-11-23: one game listed twice (a double comes out without asking; Jesse, 2026-10-29). "NCAA Football Playoffs
-- Second Round" (32b9f954, from SJU Athletic Activities' Instagram, before the opponent was known) is SJU Football vs Hanover
-- (5cd5d801, the campus calendar's), which shows since Hanover got its logo today (BP app game-card 37): the same noon kickoff
-- at Clemens Stadium. The game stays, with the fuller About (Jesse, 2026-11-20), its opponent now named: ncaa.com, Nov 21,
-- Hanover 30, Benedictine (IL) 24. Nobody was Going to, saved or liked the copy.
update public.club_events set status = 'rejected', review_reason = 'other'
where id = '32b9f954-6d5f-4cee-b04c-f1fce3c3ae50';
update public.club_events
set description = 'Saint John''s, 10-0 and the No. 3 seed, hosts Hanover (Ind.) in the NCAA Division III playoffs'' second round.'
where id = '5cd5d801-a27d-4c8f-8467-93ce146a3966';
