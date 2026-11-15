-- WinterWalk's schedule, the first Event on the Schedule with time slots (BP app event-schedule; Jesse, 2026-11-15: "go").
-- Written by hand from the festival's Facebook event (Apify run UWn9VIiVyJCL3m9cb, 2026-11-14), because the morning's
-- time-slot step reads only 7 days ahead and WinterWalk is Dec 4. Each part follows sources/models/event-part.md: a time the
-- host wrote, quoted exactly; the festival's own 4 to 8 PM items (luminary walk, crafts, Big Rigs) are no part. The Tree
-- Lighting and the Chorale's concert are their own Events, so their parts point at them (same_as).
-- The host's words also go on the Facebook mention (host_words), as the social read now saves them, so from Nov 27 the
-- morning step reads the same words itself; its two helpers' parts then replace these.

update public.event_mentions set host_words = $q$🎄 FESTIVAL EVENTS 🎄
Friday, December 4
All activities are free unless otherwise marked with "*"

JoeTown WinterWalk Festival is Friday, December 4 from 4–8 pm in downtown St. Joe! Here's everything happening:

4 pm
🎅 Santa and Mrs. Claus make their Grand Entrance at 4 pm on College Ave outside Bad Habit Brewing Company — then visit with them in the Brewers Lounge, 4–8 pm

4–6 pm
Holiday sausage sampling at St. Joe Meat Market (4–6 pm)
Chair massages, Young Living essential oil samples and muscle testing demos at Golden Hour Wellness

4–8 pm
🚛 Big Rigs with Brenny Transportation: climb into a real semi, College Ave outside Bad Habit, 4–8 pm
✉️ Letters to Santa: drop yours in the North Pole mailbox at W | R Home Company
🕯️ Luminary walk through downtown St. Joe
✂️ Kids' crafts with Magnifi Financial in Heritage Hall at the Church of Saint Joseph, plus kids' crafts with Parks and Rec at the St. Joseph Government Center
🎨 Gelli Plate Botanical Printing with Avon Hills Folk School in the Bad Habit Brewing Company Warehouse
🛍️ Parish craft sale* and hot turkey meal* in Heritage Hall
WinterWalk Ale* in the Bad Habit Brewing Company Tap Room
Hot cocoa (while supplies last) and spiced hot chocolate* from Obbink Distilling, on the Church of Saint Joseph lawn
Hot apple cider, vendor market* and salt room at St. Joseph Health + Wellness
Festive drinks on tap* at The House Food and Tap

5–7 pm
🎶 Carolers from the Saint John's Prep School Chamber Choir, 5–7 pm (Bad Habit, Krewe, Jupiter Moon)

5–8 pm
🎵 Aksel Krafnick, 5–8 pm at Jupiter Moon Ice Cream, plus Dark Chocolate Hot Chocolate Floats*

5:30 pm
🎵 Harp Ensemble, 5:30 pm in Heritage Hall

6–9 pm
🎵 Groovy Shoes, 6–9 pm in the Bad Habit Tap Room
🎵 Jennifer Lamb Randolph and Nick Scott, 6–9 pm at Krewe Restaurant
🎵 Jacob Ehrlichman, 6–9 pm at Obbink Distilling

7 pm
🎄 Tree Lighting at 7 pm on the Church of Saint Joseph lawn
🎵 Harp Ensemble, 7 pm at Art & Heritage Place (Whitby Gift Shop), Saint Benedict's Monastery

7:30 pm
🎵 Great River Chorale presents "Out of Darkness, Light," 7:30 pm at the Church of Saint Joseph. Tickets* $25 adult / $20 senior / $10 youth at greatriverchorale.org

Most activities are free; * means for purchase. Questions? Email joetownwinterwalkfestival@gmail.com or call (320) 348-0752.

Let's Celebrate the Season Together!$q$
where event_id = 'a3f94b84-13b6-4b80-a02f-28c519cbb486'::uuid and source_url = 'https://www.facebook.com/events/1707823090962331/';

delete from public.event_parts where event_id = 'a3f94b84-13b6-4b80-a02f-28c519cbb486'::uuid;
insert into public.event_parts (event_id, title, starts_at, ends_at, source_url, source_line, same_as) values
  ('a3f94b84-13b6-4b80-a02f-28c519cbb486'::uuid, $q$Santa's Grand Entrance$q$, '2026-12-04 16:00:00-06'::timestamptz, null, 'https://www.facebook.com/events/1707823090962331/', $q$🎅 Santa and Mrs. Claus make their Grand Entrance at 4 pm on College Ave outside Bad Habit Brewing Company$q$, null),
  ('a3f94b84-13b6-4b80-a02f-28c519cbb486'::uuid, $q$Sausage sampling, Meat Market$q$, '2026-12-04 16:00:00-06'::timestamptz, '2026-12-04 18:00:00-06'::timestamptz, 'https://www.facebook.com/events/1707823090962331/', $q$Holiday sausage sampling at St. Joe Meat Market (4–6 pm)$q$, null),
  ('a3f94b84-13b6-4b80-a02f-28c519cbb486'::uuid, $q$Chair massages, Golden Hour$q$, '2026-12-04 16:00:00-06'::timestamptz, '2026-12-04 18:00:00-06'::timestamptz, 'https://www.facebook.com/events/1707823090962331/', $q$4–6 pm
Holiday sausage sampling at St. Joe Meat Market (4–6 pm)
Chair massages, Young Living essential oil samples and muscle testing demos at Golden Hour Wellness$q$, null),
  ('a3f94b84-13b6-4b80-a02f-28c519cbb486'::uuid, $q$Saint John's Prep carolers$q$, '2026-12-04 17:00:00-06'::timestamptz, '2026-12-04 19:00:00-06'::timestamptz, 'https://www.facebook.com/events/1707823090962331/', $q$🎶 Carolers from the Saint John's Prep School Chamber Choir, 5–7 pm (Bad Habit, Krewe, Jupiter Moon)$q$, null),
  ('a3f94b84-13b6-4b80-a02f-28c519cbb486'::uuid, $q$Aksel Krafnick at Jupiter Moon$q$, '2026-12-04 17:00:00-06'::timestamptz, '2026-12-04 20:00:00-06'::timestamptz, 'https://www.facebook.com/events/1707823090962331/', $q$🎵 Aksel Krafnick, 5–8 pm at Jupiter Moon Ice Cream, plus Dark Chocolate Hot Chocolate Floats*$q$, null),
  ('a3f94b84-13b6-4b80-a02f-28c519cbb486'::uuid, $q$Harp Ensemble, Heritage Hall$q$, '2026-12-04 17:30:00-06'::timestamptz, null, 'https://www.facebook.com/events/1707823090962331/', $q$🎵 Harp Ensemble, 5:30 pm in Heritage Hall$q$, null),
  ('a3f94b84-13b6-4b80-a02f-28c519cbb486'::uuid, $q$Groovy Shoes at Bad Habit$q$, '2026-12-04 18:00:00-06'::timestamptz, '2026-12-04 21:00:00-06'::timestamptz, 'https://www.facebook.com/events/1707823090962331/', $q$🎵 Groovy Shoes, 6–9 pm in the Bad Habit Tap Room$q$, null),
  ('a3f94b84-13b6-4b80-a02f-28c519cbb486'::uuid, $q$Lamb Randolph & Scott at Krewe$q$, '2026-12-04 18:00:00-06'::timestamptz, '2026-12-04 21:00:00-06'::timestamptz, 'https://www.facebook.com/events/1707823090962331/', $q$🎵 Jennifer Lamb Randolph and Nick Scott, 6–9 pm at Krewe Restaurant$q$, null),
  ('a3f94b84-13b6-4b80-a02f-28c519cbb486'::uuid, $q$Jacob Ehrlichman at Obbink$q$, '2026-12-04 18:00:00-06'::timestamptz, '2026-12-04 21:00:00-06'::timestamptz, 'https://www.facebook.com/events/1707823090962331/', $q$🎵 Jacob Ehrlichman, 6–9 pm at Obbink Distilling$q$, null),
  ('a3f94b84-13b6-4b80-a02f-28c519cbb486'::uuid, $q$Tree Lighting$q$, '2026-12-04 19:00:00-06'::timestamptz, null, 'https://www.facebook.com/events/1707823090962331/', $q$🎄 Tree Lighting at 7 pm on the Church of Saint Joseph lawn$q$, '100b741c-bf2e-43d9-8923-7d59725c3393'::uuid),
  ('a3f94b84-13b6-4b80-a02f-28c519cbb486'::uuid, $q$Harp Ensemble at the Monastery$q$, '2026-12-04 19:00:00-06'::timestamptz, null, 'https://www.facebook.com/events/1707823090962331/', $q$🎵 Harp Ensemble, 7 pm at Art & Heritage Place (Whitby Gift Shop), Saint Benedict's Monastery$q$, null),
  ('a3f94b84-13b6-4b80-a02f-28c519cbb486'::uuid, $q$Great River Chorale$q$, '2026-12-04 19:30:00-06'::timestamptz, null, 'https://www.facebook.com/events/1707823090962331/', $q$🎵 Great River Chorale presents "Out of Darkness, Light," 7:30 pm at the Church of Saint Joseph.$q$, '73084a1e-5b4c-47e5-b2f0-1b72e22bc2f6'::uuid);
