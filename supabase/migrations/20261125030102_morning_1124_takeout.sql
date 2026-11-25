-- Morning report 2026-11-24 take-out. Nobody was Going to, saved or liked any of the three Events.

-- "Tech Winter Week" (Tech High School, Dec 7 to 11, all day): gone from the school's December calendar (read 2026-11-24),
-- which lists the "Winter Break Countdown Dress Up" days (Dec 4 to 18) in its place. Keeps those.
update public.club_events set status = 'rejected', review_reason = 'other'
where id = '2b9c1955-c2dd-4bac-aec1-fb3adf606c72';

-- "Black Friday 20% off all products" (Well & Company, Nov 27 to 30, all day) is the News "Black Friday Glow Offers" again:
-- the same four days, filler and Sculptra with a free facial, 20% off skincare. Keeps the News a99d06e1 (shows until Nov 30).
update public.club_events set status = 'rejected', review_reason = 'other'
where id = 'f1cd6b4f-dd9a-4213-a9f7-ede9126ea4dd';

-- "RIS Grade 5 Band, Choir & Orchestra" (Sartell, Dec 8 6 PM): placed at "Rock Ridge Intermediate, Sartell", a school the
-- morning's check could not find in Sartell. The post says only "RIS", which is Riverview Intermediate School
-- (our own gymnastics listings name it in Sartell). No other copy.
update public.club_events set status = 'rejected', review_reason = 'wrong_place'
where id = '678565e7-5801-4a93-a79f-a2c0f27170c9';

-- News "Bad Habit Black Friday Deals" (Nov 20: the line-up drops next week) is told again, now with the line-up, by
-- "Bad Habit Black Friday weekend". Keeps 60722764 (shows until Nov 29).
update public.board_items set status = 'archived' where id = 'c6f258dd-63f2-498e-9247-65d6dff1f303';
