-- Same Event twice (Dec 21, St. John's Prep Young Alumni Social at The House): kept 2cb85493 "Young Alumni Social"
-- (St. John's Prep's events page, 10 AM, at The House), rejected 2edb0ef0 "Young Alum Social" (its RSVP form,
-- filed under Birdie's inside The House).
update public.club_events set status = 'rejected', review_reason = 'other'
where id = '2edb0ef0-60c5-4264-a8d5-fe3cdce9ee2e';
