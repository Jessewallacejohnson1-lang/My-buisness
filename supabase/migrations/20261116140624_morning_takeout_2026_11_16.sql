-- Take-out, 2026-11-16 morning report: two copies of one thing, three times.

-- "Ducks Unlimited Dinner" (Sal's Bar, Nov 23, no time) is the same banquet. Kept fa2d553a "Ducks Unlimited Sportsman's Night Out" (Sal's Bar and Grill, 6 PM).
update public.club_events set status = 'rejected', review_reason = 'other' where id = 'dbb92913-6281-4ffc-8fdb-6c158e72258a';

-- "Wreath Making Workshop" (City of St. Joseph, Nov 30) repeats Outdoor U's own listing. Kept aaa92df3 "Wreath making at Outdoor U" (CSB SJU Outdoor U, Saint John's Abbey Arboretum).
update public.club_events set status = 'rejected', review_reason = 'other' where id = '34008ac4-1bce-4b4e-a181-73a765b2f923';

-- The music department's Facebook events repeat the Christmas concert its own site and the ticket site list. Kept 4780b81d (Dec 4, 7:30 PM) and d1fd4802 (Dec 5, 2 PM) "Christmas with CSB SJU", Great Hall.
update public.club_events set status = 'rejected', review_reason = 'other' where id in (
  'ea1a5a37-cad8-4d84-9b28-8bd526e0d491', -- Christmas with Saint Ben's & John's, Dec 4
  '996311c9-7413-4fe2-b8cb-4d424b5589b0'  -- Christmas with Saint Ben's & John's, Dec 5
);
