-- Nov 5, doubles the Town feed work found: two listings of one Event, the same day, start and place, with different
-- titles, so the writer's check let both through (Jesse: same date, time and place are one Event, 2026-10-19).
update public.club_events set status = 'rejected', review_reason = 'other'
 where id in (
   'b21bac14-7785-41f7-979b-1ea16b5ccf2e',  -- Celebrate Dolly Parton, Nov 6. Kept: 94a323b7 "Dolly Parton Party", its own page and the full About.
   'd1108851-591e-45c0-a8c6-8d75f878134d',  -- Red Cross Blood Drive, Nov 6. Kept: 828dbf67 "Saint John's Prep Blood Drive", its own page and the hours.
   '1595e0db-ead0-4b85-b12c-b7068fb95cd5',  -- Scholastica Convent Craft Sale, Nov 6. Kept: aeadcc72 "Christmas Craft Sale", its own page and the full About.
   'cfabc1fa-feb3-4130-bbf1-15a75dd8d972',  -- Scholastica Convent Craft Sale, Nov 7. Kept: baed9e4f "Christmas Craft Sale".
   'fe2fba56-1b6c-44c3-b8fb-58c30b0203e0',  -- Holiday Collection Weekend, Nov 7. Kept: 99ea01d6 "A Very Peony Christmas", the sale by its name.
   'c4de51b6-e69b-4fc6-80d4-9c4c9d0b8589'   -- Stone Road at The La Playette, Nov 7. Kept: 9129cbc9 "Stone Road Live", the full About.
 );
