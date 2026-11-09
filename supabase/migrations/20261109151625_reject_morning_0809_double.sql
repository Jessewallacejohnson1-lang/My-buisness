-- Same game twice (Nov 12, 7 PM, Herb Brooks): kept 2a0881f4 "SJU Hockey vs UW-Stout" (showing),
-- rejected 4bbcb1a2 "... UW-Stout Polytechnic" (a second listing of the same game, waiting on a logo).
update public.club_events set status = 'rejected', review_reason = 'other'
where id = '4bbcb1a2-d1a9-4258-a682-3526e4a5b4a0';
