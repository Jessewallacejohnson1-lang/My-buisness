-- The Bréagán opening reception, Thursday Nov 12 at 5 PM in the Alice R. Rogers and Target Galleries, shows twice:
-- two CSB SJU listings with different titles, so the writer's same-title check let both through.
-- Kept: 1b757ea0 "Gallery Reception for Bréagán", the copy with the Event's own page and the full About.
update public.club_events set status = 'rejected', review_reason = 'other'
 where id = '59a314d3-73a7-4e73-a911-aa4ff613b76f';  -- "Bréagán" opening reception, Nov 12
