-- Sal's "Puzzle Mania" (Sun Nov 22, 11 AM, new on Nov 3) is the City's "Fall Adult Puzzle Competition"
-- at Sal's the same day and hour (b8588e8f, kept: same $50 team entry, 500-piece puzzle). Hidden.
update public.club_events set status = 'rejected', review_reason = 'other'
 where id = 'c1cb8e68-3100-459e-8455-cf78a5da9622';
