-- Take-out, 2026-11-19 morning report: two copies of one thing, fourteen times, and ten Sunday Masses named "Saturday Evening Mass".

update public.club_events set status = 'rejected', review_reason = 'other' where id in (
  'c605d671-9bcf-41c1-bd4a-604d41bd7bde', -- "SJU Hockey vs St. Cloud", Nov 19: the Instagram post names the arena's city, not the other team. Kept 1a24040b "SJU Hockey vs Concordia" (SJU Athletics, the game card).
  '1c425d73-766e-480e-9e00-b7bb5e140bcc', -- "SJU Hockey vs Concordia-Moorhead", Nov 19: the same game from a news story. Kept 1a24040b "SJU Hockey vs Concordia" (the game card).
  '6c72c671-7ea8-4068-b5bb-99c4feb80e06', -- "CSB Hockey vs St. Cloud", Nov 21, 4 PM: the arena's city, not the other team. Kept 44964641 "CSB Hockey vs Concordia" (CSB Athletics, the game card).
  '36ebae13-4b0d-4076-bc88-fcf89f45aba1', -- "SJU Hockey at Moorhead", Nov 21: the same game, no spot. Kept f52b5ee6 "SJU Hockey at Concordia-Moorhead" (Moorhead Sports Center, has its About).
  'eccfb5c3-42f4-478c-a4e3-41a72efde6f4', -- "Pre-Thanksgiving Market", Nov 21: the same Facebook post read twice. Kept 296cfb9d "Wildwood Ranch Maple Syrup Pop-Up".
  '81b77e7a-77ab-4e8e-aafe-74457e11e3db', -- "Weekday Mass", Nov 26, 9 AM: the same Church Center listing. Kept b6593c13 "Thanksgiving Day Mass".
  'af1041ca-36af-4dd9-9752-8f8d14b8cd78', -- "Weekday Mass", Dec 25, 9 AM: the same Church Center listing. Kept 6c101ceb "Christmas Day Mass".
  'b8d183cc-ce26-409f-9484-d0f1be4a2bba', -- "Shop Small Crawl", Nov 28 (JoeTown's calendar). Kept 5308e5a7 "Shop Small Saturday in Joetown" (JoeTown, downtown).
  'e46c4822-e914-42f4-b7bb-f6cad5c0bcba', -- "Encountering Mary", Dec 8, 9:30 AM (JoeTown's calendar, no About). Kept c8adca4a (Saint Benedict's Monastery).
  'b250d986-ccf6-40f1-97f7-746211702db0', -- "Encountering Mary: Session 1", Dec 8, 9:30 AM (JoeTown's calendar). Kept c8adca4a (Saint Benedict's Monastery).
  '22e3066c-18a7-4c25-ac7a-68636f5cae97', -- "Encountering Mary", Dec 8, 3 PM (JoeTown's calendar, no About). Kept dc42a193 (Saint Benedict's Monastery).
  '28f0828f-fde6-4df5-84b8-de7139a9ee6a', -- "Encountering Mary: Session 2", Dec 8, 3 PM (JoeTown's calendar). Kept dc42a193 (Saint Benedict's Monastery).
  '500587f3-fe85-45fc-8a05-19c2f6768192'  -- "Young Alum Social", Dec 21 (the RSVP form). Kept 2cb85493 "Young Alumni Social" (St. John's Prep's own events page).
);

-- "Enhanced Fitness", Jan 28, 10 AM: its Church Center page says 1-2 PM. Kept 6bd6d93f (1 PM).
update public.club_events set status = 'rejected', review_reason = 'wrong_when' where id = '01fee767-b2a3-441e-934f-95542cdf67a6';

-- Sunday 10 AM Mass ("Mass SJ" on Church Center) read as "Saturday Evening Mass".
update public.club_events set status = 'rejected', review_reason = 'wrong_title' where id in (
  '8ae2c7c7-e080-4cfc-a0a4-5a960a062d10', -- Nov 22
  '8b099128-cc2f-4076-9ff6-6b0b9493e8aa', -- Nov 29
  'eedd44df-a45b-433f-a972-975747a576f2', -- Dec 6
  '125b85b4-3472-453e-8cab-94d2d4982233', -- Dec 13
  '01b5a7e1-238b-4e8a-944a-390a403ac1b6', -- Dec 20
  '0e0f9f77-9d5c-48c3-b8af-0b650d5b42e2', -- Dec 27
  'a6a53353-35b9-4b6c-b3c5-46509da624e8', -- Jan 3
  '60b2c16e-4de5-4b4a-8e16-667a33544dd5', -- Jan 10
  '05807fa3-6654-41eb-a571-e121cc0dd76d', -- Jan 17
  'ec15a703-a36d-4d47-b438-e8a8dff0b3b1'  -- Jan 24
);
