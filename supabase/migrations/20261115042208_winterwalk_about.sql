-- WinterWalk's two Events take the festival's newest Facebook words (Jesse's yes, 2026-11-14 evening), read from
-- facebook.com/events/1707823090962331 (Apify run UWn9VIiVyJCL3m9cb). The About says what it is and what to expect; the
-- date, time, place and price keep their own lines. about_written_at keeps an older read from writing its words back.

update public.club_events set
  description = 'A volunteer-run winter night all over downtown St. Joe. Santa and Mrs. Claus make a grand entrance outside Bad Habit, then visit in the Brewers Lounge. Expect a luminary walk, letters to Santa, kids'' crafts, a real semi to climb into, carolers from the Saint John''s Prep Chamber Choir, live music at Bad Habit, Krewe, Obbink and Jupiter Moon, the tree lighting, and hot cocoa on the church lawn.',
  about_written_at = now()
where id = 'a3f94b84-13b6-4b80-a02f-28c519cbb486'::uuid;

update public.club_events set
  description = 'WinterWalk''s tree lights up for the season. Hot cocoa and Obbink''s spiced hot chocolate are on the lawn nearby, and the Great River Chorale''s concert follows in the church.',
  about_written_at = now()
where id = '100b741c-bf2e-43d9-8923-7d59725c3393'::uuid;
