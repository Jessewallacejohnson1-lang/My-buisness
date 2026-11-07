-- Nov 7 morning review. Jesse's standing rule: a double or a misleading item comes out without asking.

-- One game listed twice. Kept: 845fbfb4 "CSB Volleyball vs Carleton", 7 PM, Claire Lynch Hall, the fuller About.
update public.club_events set status = 'rejected', review_reason = 'other'
 where id in (
   'ad8f0692-2345-4ac2-ba06-e223fe7743c8'   -- CSB Volleyball vs Carleton: Senior Night, Nov 7, a second campus calendar listing.
 );

-- Today's Event of the day #7 pointed at the copy taken out above; it moves to the kept copy.
update public.daily_standouts set event_id = '845fbfb4-0eef-4f15-b01a-9de5f2bbc0ea'
 where town = 'st-joseph-mn' and day = '2026-11-07' and event_id = 'ad8f0692-2345-4ac2-ba06-e223fe7743c8';

-- News that repeats something already showing, or reads wrong now.
update public.board_items set status = 'archived'
 where id in (
   'daca62c5-ff6c-4f89-be73-1e84eb7377cd',  -- Holiday Sales at the Art and Heritage Place, the campus calendar's copy of the sisters' sale. Kept: Events 0e4a7142, c17407ab, f38bb4a2, one for each sale day.
   '3928033f-fe0c-40e0-ad7c-09e8030a48f0',  -- Collegeville Orchards Open Through Nov 29, the Nov 5 post. Kept: 847c987a "Open weekends through November 29", the same news from the next post.
   '2015aa70-ce9b-4754-b839-5fab790abed0'   -- Twinkle & Toast holiday collection: its "tonight at 8 PM" was Friday, Nov 6; read now it names the wrong night.
 );
