-- Who proposed a photo swap (BP app docs/plans/place-photos, ticket 05; Jesse's yes, 2026-10-19). The
-- monthly cloud refresh and the chats working on place photos both add 'proposed' rows, and on the
-- first review page nobody could tell whose was whose. Set on proposals only; the app never reads it.
alter table public.place_photos add column if not exists proposed_by text;
