-- Sartell High's fall play is The Crucible (Sartell High's Instagram), but Bound lists it as "Fall Play"
-- and the morning re-read writes that title back. So the Instagram copies show, named for the play with
-- "Sartell High School's play." below, and the Bound copies are hidden (Jesse, 2026-10-29).
update public.club_events
   set status = 'approved', review_reason = null, what = 'Play', activity_team = 'sartell',
       description = 'Sartell High School''s play.'
 where id in ('33bb054d-f3a2-4eb2-ba23-d10a9808eeb7', '7e8a1ea5-3eb0-4725-83f5-b57811ad9db3',
              '21e4e333-e596-4637-af26-98b7e0f12cfe');

-- wrong_title: a re-read with the same "Fall Play" keeps them hidden.
update public.club_events
   set status = 'rejected', review_reason = 'wrong_title'
 where id in ('8a26a38d-a1a8-4831-8579-be243d84cc07', '44d7c98a-6207-405f-86a5-195284fa590a',
              '19176979-a475-4779-9d63-71b251a9d9a3');
