-- Jesse, 2026-11-16 ("i agree to all"), after the morning report.

-- History Heist Escape Room: one card a day, not one per time slot. Kept the slot still open each day:
-- 6696ed76 (Dec 10, 5 PM), 8f6d0104 (Dec 11, 5 PM), 77756373 (Dec 12, 1 PM), 4f03bc9e (Dec 17, 7 PM),
-- 10d1c4e3 (Dec 18, 5 PM), be25eaff (Dec 19, 1 PM).
update public.club_events set status = 'rejected', review_reason = 'other' where id in (
  '8b446d6a-be73-42d4-b34e-99bc2c1e255c', -- Dec 10, 7 PM (full)
  '8a0804af-8b86-4c2f-98d0-2b24b4ead296', -- Dec 11, 7 PM
  '386b1e4a-9a12-4069-9240-413fc994a87e', -- Dec 12, 3 PM
  '9f21a2fe-438e-4c14-bc40-445ab6d55e99', -- Dec 17, 5 PM (closed)
  'aab14002-be72-4799-bfaa-d254f34f2eea', -- Dec 18, 7 PM
  'f2e06212-2f96-4fc9-b02b-9ab2db27ea12'  -- Dec 19, 3 PM
);

-- Luminary Hike: Outdoor U at CSB/SJU runs it, not Stearns County.
-- Stearns County's Feb 12 copy repeats Outdoor U's own listing. Kept 44cf04c5 "Luminary Hikes at the Abbey Arboretum".
update public.club_events set status = 'rejected', review_reason = 'other' where id = '8629d015-0082-4881-a44d-1e18846fcafa';
-- The second night (Feb 13) stays, under its real host.
update public.club_events
   set source_name = 'CSB SJU Outdoor U', source_url = 'https://www.csbsju.edu/outdooru/events/luminary/'
 where id = '2e617979-1a30-46fc-abdc-00e5ce1b062d';
