-- Take-out, 2026-11-22: Lori Hendrickson's two craniosacral workshops at Golden Hour Wellness, each listed twice: once
-- from Golden Hour Tanning's Facebook post (all day) and again from Golden Hour Wellness's own Facebook events (11 AM),
-- found while building BP app watch-every-place 42's fixture. Keeps the host's own timed listings and gives each the
-- post's fuller About.

-- Jan 23, part 1: keeps b17b9218 "CST with Lori Hendrickson: Level 1".
update public.club_events set description = (
  select description from public.club_events where id = '8d689e4c-5015-4779-b5e0-87ef3f2e93cb')
where id = 'b17b9218-4923-45bf-afef-642d5e052dc6';
update public.club_events set status = 'rejected', review_reason = 'other'
where id = '8d689e4c-5015-4779-b5e0-87ef3f2e93cb';

-- Jan 24, part 2: keeps c59e0b2f "CST with Lori Hendrickson: Part 2".
update public.club_events set description = (
  select description from public.club_events where id = '4c1c4365-5601-479f-a7ea-4ad0dd95451a')
where id = 'c59e0b2f-6bbf-4059-81c5-6a39a2ee04aa';
update public.club_events set status = 'rejected', review_reason = 'other'
where id = '4c1c4365-5601-479f-a7ea-4ad0dd95451a';
