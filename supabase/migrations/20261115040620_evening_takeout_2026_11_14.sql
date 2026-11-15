-- Take-out, 2026-11-14 evening: doubles written by the day's social runs (weekly 3:45 PM, busy 7:30 PM) after the morning report.

-- "Gratitude Flow - 75 min" (KPower Facebook post, Nov 27 7:45 AM) is the same class. Kept b066127d "75 Minute Gratitude Vinyasa" (KPower Yoga, fuller About and its flyer).
update public.club_events set status = 'rejected', review_reason = 'other' where id = '9fe4d539-f811-47d8-a166-5b6b3989803a';

-- "Christmas Centerpiece Class" (Sunny Mary Meadow Facebook event, Dec 16 6 PM) is the same class as its other Facebook event. Kept 0accf55b "Christmas Centerpiece Workshop" (Sunny Mary Meadow).
update public.club_events set status = 'rejected', review_reason = 'other' where id = 'fe40054a-c6d8-4129-a30a-f223565866ad';

-- "The BLT Band at Sal's" (the band's Facebook event, Nov 28 7 PM) is the show Sal's lists itself. Kept 2572ecf8 "BLT Band: Live Music" (Sal's Bar and Grill).
update public.club_events set status = 'rejected', review_reason = 'other' where id = '8c9d5c58-e2db-47b0-a857-a36f3b841d11';

-- "Great River Chorale" (JoeTown WinterWalk Festival, Dec 4 7:30 PM, no photo) is the Chorale's own concert. Kept 73084a1e "Out of Darkness, Light" (Great River Chorale).
update public.club_events set status = 'rejected', review_reason = 'other' where id = '22b19d9b-180c-4494-b932-fab99a66d6c4';
