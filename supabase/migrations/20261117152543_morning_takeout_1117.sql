-- Take-out, 2026-11-17 morning report: two copies of one thing, seven times.

update public.club_events set status = 'rejected', review_reason = 'other' where id in (
  '4f677e6c-35e8-41ba-aa3f-8d679fc66762', -- "Paula's Birthday at Mission Nutrition", Nov 19: same Facebook post. Kept 12d9205e "Mission Nutrition Birthday Day".
  '5ed150d9-51e8-4d6a-bf7b-06036ed77060', -- "Sportsmen's Night Out", Nov 23, no place: same banquet. Kept fa2d553a "Ducks Unlimited Sportsman's Night Out" (Sal's Bar and Grill).
  'a56d78cf-9dcc-4daf-b99d-a538fc6bc367', -- "Winter Walk", Dec 4: the parish calendar repeats the festival. Kept a3f94b84 "JoeTown WinterWalk Festival".
  '193662b9-2326-48db-be06-64a5cc6ae56b', -- "Animal Tracking Program", Jan 9. Kept a5594faf "Animal tracking at Outdoor U".
  'b2e98929-a584-4516-9f84-d1009dff0c2f', -- "Master Naturalist Course", Feb 1. Kept 7b0a4f92 "MN Master Naturalist" (Outdoor U).
  'ba2ba0a3-3b1f-4b93-ade7-4a8f07f76fe6', -- "Luminary Hikes", Feb 12. Kept 44cf04c5 "Luminary Hikes at the Abbey Arboretum" (Outdoor U).
  'f8ae9439-8cca-430e-a8bb-a074a216f746'  -- "Luminary Hike", Feb 13 (Stearns County, no About). Kept 2e617979 "Luminary Hike" (Outdoor U).
);
