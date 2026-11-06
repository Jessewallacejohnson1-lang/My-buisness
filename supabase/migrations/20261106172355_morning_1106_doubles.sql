-- Nov 6 morning review. Jesse's standing rule: a double or a misleading item comes out without asking.

-- One thing listed twice. Each line names the copy kept.
update public.club_events set status = 'rejected', review_reason = 'other'
 where id in (
   '236fb52e-1e4c-4921-9787-e875ad1a313a',  -- CSB Basketball vs. Minnesota-Morris, Nov 6, a poster with no time. Kept: 7163771c, 8:15 PM, Claire Lynch Hall.
   '542fffd5-d25e-490a-bfa1-116886d5d712',  -- CSB Basketball vs. Loras, Nov 7, the same poster. Kept: 4169e3f8, 2 PM.
   '6694c4e6-58db-4c0c-9d80-f318c8ee940c',  -- CSB Basketball vs. Central, Nov 13, the same poster. Kept: 1fe1f1c5, 8:15 PM.
   'b96d6202-e4d7-4b9d-a827-cd0c0b9ab438',  -- CSB Basketball vs. Simpson, Nov 14, the same poster. Kept: 917ead30, 3 PM.
   '8766ba16-9026-4cbb-9627-ecdf0e64d6fc',  -- Sisters' Holiday Sale, Nov 5 to 7. Kept: 0e4a7142, c17407ab, f38bb4a2, the monastery's own page, one for each day.
   '49212bce-9554-45a8-b3b8-ebea811e10d8',  -- Ptanyetu Powwow, Nov 7, Kennedy's repost. Kept: efbe0cf2, the campus's own page, which names Clemens Fieldhouse.
   '17859d5c-4316-4a2d-bdeb-275dc923026f',  -- Holiday Hooplah, Nov 12, one Facebook event read twice. Kept: 75173f55 "Holiday Hoopla Sale", the terms and hours.
   '1bd2a713-66e3-4290-adb7-172542abd9bf',  -- Fresh Skin Tattoos Fundraiser, Nov 19, one Facebook event read twice. Kept: e855755b, the time, price and raffle.
   'a59876fb-9b48-4266-b5c3-a3ae1ef8097c',  -- 5th Annual Andy Loso Liver Fry, Nov 25. Kept: 8e8555b3, Sal's November poster, 5 to 8 PM with the meat raffle.
   'ee2070b6-4ae8-4b8a-8ffe-c0f35de99e1f',  -- Shop Small: Vendors, Nov 28, a call for vendors. Kept: 7da9abff "Crafter's Market", Sal's poster, 10 AM to 2 PM.
   '37e5b6e4-3950-4a21-a153-b8207a0423bd',  -- Saint Joseph Shop Small Saturday, Nov 28, one stop repeating the town event. Kept: 5308e5a7 "Shop Small Saturday in JoeTown".
   '70e28058-abc1-406d-841f-fa3b6f463073',  -- Shop Small Saturday, Nov 28, one shop repeating the town event. Kept: 5308e5a7.
   '9d38dd2a-0856-4aed-a104-0c4c07d3c006',  -- SMS Fall Musical, Nov 12, its About says the title was not found. Kept: b755740a "Matilda Jr.".
   '9eeace66-ae2e-4770-a73e-b4985788bd50',  -- SMS Fall Musical, Nov 13. Kept: 3d9b8818 "Matilda Jr.".
   '30a6b89c-269f-4c86-900a-d71dbe4c1795'   -- SMS Fall Musical, Nov 14. Kept: add1d71d "Matilda Jr.".
 );

-- The wrong time or day.
update public.club_events set status = 'rejected', review_reason = 'wrong_when'
 where id in (
   'f0b9944c-c840-4842-ac66-f61081c44db1',  -- The Chicks, Nov 10 at noon. Sal's November poster says 2 to 4:30 PM. Kept: c2377ed7.
   '44822756-53a7-4283-b6cc-06d8889e6e3e',  -- Santa Visits the Zoo, Nov 22. The zoo's 2026 page says Nov 21, 27 and 28; its banner's Nov 22, 28, 29 are last year's. Kept: 0017d964, ba061a8f, 41d33c07.
   'e697bb6d-6867-40bc-b90c-ea84f0c8e286'   -- Santa Visits the Zoo, Nov 29, the same banner.
 );

-- Real games tonight, sent to the wrong place with no time. CSB plays at Ritsche Arena and SJU at the Herb Brooks
-- National Hockey Center, both in St. Cloud at 7 PM (gobennies.com, gojohnnies.com, read 2026-11-06).
update public.club_events set status = 'rejected', review_reason = 'wrong_place'
 where id in (
   '20419ae9-218d-4801-b364-bf3b6abdf395',  -- CSB Hockey vs. Lake Forest, Nov 6, place "Bennie Hockey".
   '9e6b7518-33b8-4baf-a2d8-04ef138997ca'   -- SJU Hockey Senior Night, Nov 6, place "Collegeville".
 );

-- One dance meet read as five games against a team called "CLC Dance Team", the conference's meet. None was showing:
-- each waited on a logo. Kept: 393c2a00 "CLC Dance Team", the meet at Tech.
update public.club_events set status = 'rejected', review_reason = 'wrong_title'
 where id in (
   'd29ba25f-924b-4306-b40b-2906e877b5fa',  -- ROCORI Dance Team vs CLC Dance Team, Dec 4
   '1c16efa4-8aa5-42b2-886e-f0c1becb9877',  -- Tech Dance Team vs CLC Dance Team, Dec 4
   '637ae1ba-6592-4e2c-aa60-a3cbfb75b90a',  -- Apollo Dance Team vs CLC Dance Team, Dec 4
   '3d5c8ff7-79ce-48e2-8b6e-bab2b3499f40',  -- Sartell Dance Team vs CLC Dance Team, Dec 4
   'b42f1201-12b6-4a59-a93c-26fc3c1156d9'   -- Sauk Rapids Dance Team vs CLC Dance Team, Dec 4
 );

-- News saying what another card already says, and one that is wrong for this town.
update public.board_items set status = 'archived'
 where id in (
   '5d10ec5e-75f2-4ab8-872e-d56626da3e72',  -- Holiday Sales at the Art and Heritage Place, Nov 6. Kept: the sale's Events c17407ab and f38bb4a2.
   'e75bdb49-34f1-48e5-a7e9-9715b7dc04ce',  -- The same, Nov 7.
   '94b96856-284e-4059-a7b6-c17849096847',  -- The same, Nov 5.
   '994912ab-dd7b-4eda-b5bf-e0eb77e9edbe',  -- Winter gymnastics sign-up opens Nov 16. Kept: 9d2757e2, the first copy.
   '3cbc0754-9550-403a-b9a5-accec2087432',  -- Granite City Gymnastics winter registration. Kept: 9d2757e2.
   '7ff1b23f-1bc2-4ec8-baae-75bbaf64320f',  -- White Peony's Holiday Email List. Kept: d174cb49, the newer post's sign-up word.
   '6c21e571-bb61-4a63-861d-e5262c5600a4',  -- Double Punch Thursday, says "today", which was yesterday. Kept: 3d564553, "on Thursdays".
   '7353851c-d5b9-4b5f-b364-769e832622a8',  -- Morning Happy Hour at Mission Nutrition, "days and times not given". Kept: 7d9c7a67, with both.
   '0678c15e-c27c-4483-9b8a-f28f880c94c7',  -- Host a Grey Face Giving Tree. Kept: 7f563a44, the first copy.
   '0aa55f39-f712-437f-adbc-9c582321309e',  -- Give to the Max, the Sisters. Kept: 74c60e13, which says what the gifts are for.
   '5a5d35a3-679c-4803-b055-1df458158734',  -- Grey Face joins Give to the Max. Kept: its Event d18292f8.
   '01c2d598-9180-482a-aeee-532b8bb8ebec',  -- Collegeville Orchards fall hours. Kept: 3928033f, the hours and the apples.
   '3d97b3a0-a34a-4bc8-bf4d-513482d6d273'   -- Pine Pointe pays your December rent: an ad for apartments in St. Cloud, from the manager's page, shown as Graceview Estates in St. Joseph.
 );
