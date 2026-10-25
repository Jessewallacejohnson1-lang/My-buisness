-- A neighbour's event waits for review. "submit events" checked only who submitted the row, so
-- any real account could insert an event as status 'approved' and skip moderation straight into
-- the Town feed. Now it matches "submit clubs": pending unless an admin posts it.
-- The restrictive "real accounts publish events" rule (20261009220000) still applies on top.

drop policy if exists "submit events" on public.club_events;
create policy "submit events" on public.club_events
  for insert to public
  with check (((submitted_by = auth.uid()) AND ((status = 'pending'::text) OR is_admin())));
