-- Nov 5 morning review.

-- Youth volleyball and dodgeball, Thursday Nov 12: last evening's read listed both again with no place.
-- Kept: ae509bcf "Youth volleyball and dodgeball" and 2d2f0d38 "Youth dodgeball", the copies with the
-- Kennedy gym and the full About.
update public.club_events set status = 'rejected', review_reason = 'other'
 where id in (
   '321096ef-97c4-4040-a8d9-7654aed69fb2',  -- Youth Volleyball, no place, Nov 12
   'dc43cdb3-6159-4ad9-a2fd-db4a19598ddd'   -- Youth Dodgeball, no place, Nov 12
 );

-- The CLA Foundation funding story came back reworded from the same page. Kept: 325ab646, yesterday's copy.
update public.board_items set status = 'archived'
 where id = 'ff3d3a88-f3b3-4866-9045-fc4def305a6f';
