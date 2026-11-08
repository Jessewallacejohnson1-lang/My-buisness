-- This morning's take-out (2026-11-08). Each line names the copy kept.

-- Ladies Weekend: Holiday Edition, today 8 AM at White Peony Boutique, is the same holiday weekend as White
-- Peony's "A Very Peony Christmas", which runs Saturday through Sunday. Kept: 99ea01d6.
update public.club_events set status = 'rejected', review_reason = 'other'
  where id = '42d4ec4c-c1fd-4803-a4f1-2885633211cf';

-- Shop Small Saturday, Nov 28: Minnesota Street Market's one post was written twice ("in JoeTown" with no
-- place, "in St Joe" at "All across"), and both repeat JoeTown's own listing downtown. Kept: 5308e5a7.
update public.club_events set status = 'rejected', review_reason = 'other'
  where id in ('33eb3201-0e22-4e9a-9b5f-83f2b9b8560b', '92e5cced-111f-4fe1-b3da-3dab90bbe943');

-- Deep Waters: A Workshop for Writers on Nov 14: Saint Benedict's Monastery lists it Oct 31, Nov 7 and
-- Nov 21 only. Nov 21 is already listed (abd050cb).
update public.club_events set status = 'rejected', review_reason = 'wrong_when'
  where id = '1f789dc4-df06-4bea-be70-deff6d3b6550';

-- Eight District 742 posts on Kennedy's news page came back under shorter titles. Each was already
-- published (Oct 14, Oct 27 or Oct 29) and had its week in the feed; the forum recording and the
-- quartet's "free concert this week" are past. Kept: the first copies, by the same post link.
update public.board_items set status = 'archived'
  where id in ('a8485cbb-0077-4f92-b835-44fbeddc22e0', 'bc660a85-99aa-427b-91f4-a4ff21e897a8',
               'ac4726cd-546c-4038-a284-e04c749e234b', '5d757760-485a-4b5b-873d-a285f9b2287b',
               '35791c5b-7c74-4fbd-862b-3286b30cd358', '430b4858-1a7c-4e73-a186-06fb4cf137d0',
               'fb0a6927-ee9b-41d5-bbc1-fd38c4ef1099', '63853b6c-b91f-43d6-8b96-0debad89d42c');

-- Holiday drop at White Peony is the same Instagram post as the weekend Event above, and with no end
-- date its "open this weekend" would show until Nov 15. Kept: the Event, 99ea01d6.
update public.board_items set status = 'archived'
  where id = '0308ae79-2c96-4d5a-9fd0-c0006655a283';
