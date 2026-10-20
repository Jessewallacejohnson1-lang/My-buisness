-- End times found on each event's own page, 2026-10-20 (BP app docs/plans/event-card, ticket 04).
-- Jesse: "make sure you checked all the spots though to find dates and times". A card says Now
-- until its end, and the Town feed keeps it that long. No reader sends these rows again: the
-- kiln's calendar entry is past, and the others came from the old board.

-- The Johanna Kiln: lit Fri Oct 16 at 4 PM, a ten-day firing through Sun Oct 25 (CSB+SJU news,
-- KNSI). The calendar listed only the hour-long lighting.
update public.club_events set end_at = '2026-10-26 00:00:00-05'
where id = '9bbc2cc2-acd4-4dcc-b115-7a376f226111';

-- Outdoor U's print making: 10:00 am to 4:00 pm (csbsju.edu/outdooru/events).
update public.club_events set end_at = '2026-11-20 16:00:00-06'
where id = '9267ef80-25d5-4816-ad9c-71896994da29';

-- Outdoor U's first wreath session: Monday, November 30 from 4:30 to 6:00 PM (the same page).
update public.club_events set end_at = '2026-11-30 18:00:00-06'
where id = 'aaa92df3-a11f-464c-8d72-4a023f825301';

-- The district's school board meeting: 6:30 to 9:30 PM (its BoardBook agenda).
update public.club_events set end_at = '2026-10-21 21:30:00-05'
where id = '23a5a80b-d61e-410e-9d58-7954232846fb';
