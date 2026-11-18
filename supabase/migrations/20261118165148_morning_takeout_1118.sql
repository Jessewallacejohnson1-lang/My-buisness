-- Take-out, 2026-11-18 morning report: two copies of one thing, thirteen times, and two News.

update public.club_events set status = 'rejected', review_reason = 'other' where id in (
  '3558ae1b-07a4-44fa-a0b1-ef8233bc52d8', -- "Mission Nutrition Birthday Bash", Nov 19: a second post for the same day. Kept 12d9205e "Mission Nutrition Birthday Day".
  '8f132c00-c79e-4078-84d7-37bb61962ef4', -- "Evening of Giving Back", Nov 19, 2 PM: the same benefit. Kept e855755b "Grey Face Rescue Flash Tattoos" (Just Peachy Collective, has its spot).
  '6e05072d-2be0-494c-bc9b-235462d92a7e', -- "Deep Waters: A Workshop for Writers", Nov 21 (JoeTown's calendar). Kept abd050cb (Sisters of the Order of Saint Benedict), whose About says registration is filled.
  '2000b16a-f329-413e-8259-7581593c0b16', -- "Children's Theater Performance", Nov 21 (Bound calendar, no About). Kept bd03bbea "Don't Let the Pigeon Drive the Bus!" (Sartell High School).
  '925848b1-0c01-4c31-8226-a60c69984adf', -- "Children's Theater Performance", Nov 22 (Bound calendar, no About). Kept 66396192 "Don't Let the Pigeon Drive the Bus!" (Sartell High School).
  'e945d01b-2392-4ca7-9a9d-8db3e5df3abc', -- "Trivia at The House", Nov 24: JoeTown's calendar read twice. Kept 36c40e6b "Trivia Night" (The House Food & Tap).
  '5d746f6b-0d3a-4181-85c9-a072cb5b416b', -- "Shop Small Crawl", Nov 28, 1 PM: the brewery's post names its own market. Kept 4d78be71 "Shop Small Weekend Market" (Bad Habit Brewing).
  'd489b7be-d9d4-44af-a275-1ebf6c58b1ca', -- "The Ladder of Divine Graces", Nov 30 (JoeTown's calendar). Kept bab3cb89 (Saint Benedict's Monastery).
  'e600a88b-8bbe-407e-bbcd-76c7972182de', -- "Advent Centering Prayer Retreat", Dec 4 (JoeTown's calendar). Kept f88dbb1a (Saint Benedict's Monastery).
  '837e5f90-6cf6-4099-8e4e-8aa48a741e70', -- "The Ladder of Divine Graces", Dec 7 (JoeTown's calendar). Kept a0ac16ed (Sisters of the Order of Saint Benedict).
  '9f2ef598-8106-42e7-82bb-012b87152a87', -- "Called to be Holy", Dec 11 (a diocese listing). Kept df3c21c3 "Called to Be Holy" (Saint John's School of Theology).
  '0b022de2-1ad7-48b7-84e9-de78a557adab', -- "The Ladder of Divine Graces", Dec 14 (JoeTown's calendar). Kept 69572705 (Sisters of the Order of Saint Benedict).
  'cf579871-9fd7-49e0-a3b4-ae4c5c0491f1'  -- "The Ladder of Divine Graces", Dec 21 (JoeTown's calendar). Kept 424ce4a4 (Sisters of the Order of Saint Benedict).
);

-- News "Smooshberry Smooshy Sour" (Nov 14, "returns next week") is told again with its day. Kept 287ce010 "Smooshie Sour, Harvest Stout" (Bad Habit Brewing), in the feed to Nov 24.
update public.board_items set status = 'archived' where id = '00136348-0104-4fd4-ac56-8f73b72775ae';

-- News "Holiday deals continue at W|R" says only "More details to come": it tells a neighbor nothing.
update public.board_items set status = 'archived' where id = '5d838c9f-084b-4364-9d23-f45eba27f116';
