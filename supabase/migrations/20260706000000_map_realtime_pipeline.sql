-- Map realtime pipeline — reconstructed from MAP_BUILD_LOG.md (applied 2026-07-06).
-- Streams club_events over Supabase Realtime so a new/ended/deleted happening lights
-- or clears its pin with no manual refresh (see MapModel / RealtimeClient).
-- VERIFY against prod before relying on this as source of truth.

-- 1. Stream club_events over Supabase Realtime (the publication was EMPTY).
alter publication supabase_realtime add table public.club_events;

-- 2. Send the full OLD row on UPDATE/DELETE so Realtime can authorize the delete
--    against the SELECT policy (a DELETE's old_record otherwise carries only the PK).
alter table public.club_events replica identity full;

-- No RLS policy change was needed: the existing "submit events" INSERT policy is
--   with_check (submitted_by = auth.uid())
-- with no status constraint. (That lack of a status constraint is exactly the
-- client-side self-approval gap flagged in REVIEW.md — see the pending migration
-- 20260710_000002 below, which is NOT applied and awaits sign-off.)
