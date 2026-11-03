-- Nov 2 social watch (busy, 6pm and 9pm): what it wrote twice or wrote with nothing to know.

-- White Peony's holiday launch weekend (Sat Nov 7 and Sun Nov 8, 8 AM) was showing three times.
-- Kept: Holiday Collection Weekend fe2fba56 (newest hours, its own place). Holiday Drop also put the
-- downtown St. Joseph shop in St. Cloud; Style Hunt carries the launch weekend's About under another name.
update public.club_events set status = 'rejected', review_reason = 'other'
 where id in (
   'de06234e-b081-4277-8555-2150d575f6c1',  -- Holiday Drop, Nov 7 (Nov 2 6pm check)
   '908046be-d9bf-419a-b3ec-eca6e34b202b'   -- Style Hunt, Nov 7 (Oct 23)
 );

-- News:
--   Flour & Flower's Thanksgiving orders were in the feed three times. Kept: 97013fe9 (Oct 31, its
--   order link and phone).
--   Milkshake Monday is a weekly special already in the feed. Kept: 22403459 (Oct 22).
--   "A Very Peony Christmas" only says to comment HOLIDAY for details; the weekend itself is the
--   Holiday Collection Weekend Event.
update public.board_items set status = 'archived'
 where id in (
   '9a8dc095-2770-4788-b1c2-f6b0afa9a043',  -- Thanksgiving orders open at Flour & Flower, Oct 24
   '67415442-44e3-4e26-9c4c-ab0eb1fb8ca3',  -- Thanksgiving pre-orders, Nov 2 6pm check
   '5df11620-fe52-4b85-8cf0-71bce0737736',  -- Milkshake Monday at the Wandering Cow, Nov 2 9pm check
   '14a1ad86-f1ad-4432-8f9d-1102e375e8f8'   -- A Very Peony Christmas, Nov 2 9pm check
 );
