-- Nov 7 morning review, missed in the first pass. Jesse's standing rule: a double comes out without asking.

-- White Peony's holiday launch weekend listed twice. Kept: 99ea01d6 "A Very Peony Christmas", 8 AM Saturday,
-- which already runs through Sunday (end_at Nov 9).
update public.club_events set status = 'rejected', review_reason = 'other'
 where id in (
   '81eb739d-1a01-4ed0-8ed3-e34ce3a98412'   -- A Very Peony Christmas holiday launch, Nov 8, the same weekend's Sunday.
 );
