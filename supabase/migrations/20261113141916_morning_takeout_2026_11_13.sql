-- Morning take-out, 2026-11-13 (covers Nov 12 and Nov 13): a title that names no event.

-- "JV Varsity Basketball, B squad after", Nov 21 at Park High School (Sauk Rapids-Rice's Bound page): the title is a schedule note, not the tournament's name. No other copy.
update public.club_events set status = 'rejected', review_reason = 'wrong_title' where id::text like '67619f65%';
