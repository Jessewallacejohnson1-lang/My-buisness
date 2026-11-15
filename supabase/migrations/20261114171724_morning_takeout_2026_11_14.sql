-- Take-out, 2026-11-14 morning report: two copies of one thing, and two News that mislead.

-- "W|R Home Company Sale Day" (Instagram post, Nov 14 9 AM) is the same sale as the Facebook event. Kept e1d54237 "Bang For Your Buck Sale" (W|R Home Company).
update public.club_events set status = 'rejected', review_reason = 'other' where id = '45c7cf66-7e03-4380-be10-780e88f57644';

-- "Open House Week" (Cathedral, Nov 16 to 20) is the Catholic Community Schools open house week already listed. Kept c9289d73 "Catholic Schools Open House Week" (St. Joseph Catholic School).
update public.club_events set status = 'rejected', review_reason = 'other' where id = '6e354279-fccd-42c3-820a-ca16137c9d49';

-- "Grounding Our Emotions" (Sisters of the Order of Saint Benedict, no place, Nov 17 9 AM) is the same class. Kept 5c207598 (Spirituality Center, St. Benedict's Monastery).
update public.club_events set status = 'rejected', review_reason = 'other' where id = 'f242f0f0-8fd5-4a98-b236-c527223efcae';

-- Sunny Mary Meadow's Facebook events repeat its own site's classes. Kept e438a5d4 and a4890efa "Thanksgiving Centerpiece Workshop" (Nov 19, Nov 25), 16030009 and f6634034 "Wreath Workshop" (Dec 3, Dec 5), all at The Bloom Room.
update public.club_events set status = 'rejected', review_reason = 'other' where id in (
  'f161299a-5a44-410f-b7cb-0ba98c70bb18', -- Thanksgiving Centerpiece Class, Nov 19
  '11d1af6e-633b-4775-95da-973c77b435e0', -- Thanksgiving Centerpiece Class, Nov 25
  '854a2383-ef6f-4599-9f9c-54628237c9fc', -- Winter Wreath Class, Dec 3
  '8e98d1be-a2aa-403b-9fde-56d54f33ca06'  -- Winter Wreath Workshop, Dec 5
);

-- "Winter Show" (Cathedral's Bound calendar, Nov 19 and 20, 7 PM, Holy Angels Performing Arts Center) is the middle school play. Kept 54a97ada and d6828559 "10 Ways to Survive the Zombie Apocalypse" (Cathedral High School).
update public.club_events set status = 'rejected', review_reason = 'other' where id in (
  '7ab86d8f-71fa-4a60-a000-16bab6b85144',
  'ab6ae222-d1d4-4b28-b2e4-160b440b3cc5'
);

-- News "Cathedral Runners Head to State" was posted Nov 6 for the Nov 7 meet; a week later it misleads.
update public.board_items set status = 'archived' where id = '0c40e9aa-542f-4f2e-9e6c-221927924d4d';

-- News "Seasonal bakes: pumpkin roll, scone" (Instagram) repeats the bakery's Facebook post the same day. Kept c8df6322 "New Fall Pastries and Pies" (Flour & Flower Bakery).
update public.board_items set status = 'archived' where id = 'a78ab74a-096a-467c-a2d0-552a280df4e9';
