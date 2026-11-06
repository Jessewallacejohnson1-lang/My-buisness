-- Nov 5 take-outs. Yes from Jesse (2026-11-05) for the Cathedral cards and the doubled MSU-Moorhead row; the rest fall
-- under his standing rule that a double or a misleading item comes out without asking.

-- Three listings that name no opponent: Knowledge Bowl meets filed as games (game-card 11). "vs TBD" reads wrong.
update public.club_events set status = 'rejected', review_reason = 'wrong_title'
 where id in (
   '63fe6827-7857-4d1d-82d2-b70243c67023',  -- St. Cloud Cathedral vs TBD, Nov 16
   '68891258-bf16-4be6-965f-e137a7d80ff6',  -- St. Cloud Cathedral vs TBD, Nov 19
   'c1a0e805-9cc8-449f-9e62-cb888ec40db1'   -- St. Cloud Cathedral vs TBD, Nov 30
 );

-- SJU wrestling, Nov 6. The school's schedule (gojohnnies.com, read 2026-11-05) says MSU-Moorhead at 5 PM, Saskatchewan
-- at 7 PM. The older listings have the old times, and their Abouts describe the old order.
update public.club_events set status = 'rejected', review_reason = 'wrong_when'
 where id in (
   '2c7fe5a2-793c-4d52-8046-0ed2a835b51e',  -- vs MSU-Moorhead at 6 PM. Kept: 64b99aa7, 5 PM.
   'af6c8313-74da-4bb1-a3c5-6d72ab882d09'   -- vs Saskatchewan at 5 PM. Kept: 940d898f, 7 PM.
 );

-- The same night again as one listing with no time. Kept: the two duals above.
update public.club_events set status = 'rejected', review_reason = 'other'
 where id = '88ff6f4a-499b-477b-8d41-a0ccaf21a328';  -- SJU Wrestling season opener, Nov 6

-- Says "this Halloween weekend", now past. Jesse was told on Nov 1 it would go on Nov 2; it never did.
update public.board_items set status = 'archived'
 where id = 'e1e42eb5-583a-4cba-88e2-8a343c23924a';  -- Magic with Luke, The House Food & Tap
