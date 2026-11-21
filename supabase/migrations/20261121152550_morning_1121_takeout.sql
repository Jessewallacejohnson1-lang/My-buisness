-- Morning report 2026-11-21 take-out.

-- Children's Theater Performance (Sartell High School, Bound, Nov 21 2 PM) is the same show as
-- "Don't Let the Pigeon Drive the Bus!" at 2 PM; keeps d2f343a8 (names the show, has an About).
update public.club_events set status = 'rejected', review_reason = 'other'
where id = '0b715f35-2fcb-4fd8-94df-0b61fc6c2eec';

-- Art & Heritage Place WinterWalk Hours (Saint Benedict's Monastery, Dec 4) is the same as
-- "Special Hours at Art and Heritage Place"; keeps 0a8d958b (the Art & Heritage Place's own
-- spot, pairs with the Dec 5 copy b9e55833) and gives it the fuller About.
update public.club_events set description = (
  select description from public.club_events where id = 'ff5f14a4-47ed-4201-b2af-92832b13acb9')
where id = '0a8d958b-00cb-4e2b-867b-2507e211e55c';
update public.club_events set status = 'rejected', review_reason = 'other'
where id = 'ff5f14a4-47ed-4201-b2af-92832b13acb9';

-- News "Kindergarten registration for 2026-2027" (Sartell, Nov 20): the school year it names
-- is already half over, so the headline misleads.
update public.board_items set status = 'archived'
where id = 'fc456375-ec89-4c6f-8904-080b166a4584';
