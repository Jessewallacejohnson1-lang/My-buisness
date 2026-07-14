-- migration-event-category.sql
-- Adds an optional `category` to club_events (music, food, outdoors, …).
--
-- Twin of the native iOS repo's supabase/migrations/20260714000000_club_events_category.sql
-- (both apps share this Supabase project). Additive + backward-compatible: the column
-- is NULLABLE with no default, so every existing row stays valid and neither app is
-- forced to set it. A null / legacy / unrecognized value is read as "other" client-side.
--
-- Vocabulary mirrors the INTERESTS taxonomy (apps/mobile/src/lib/interests.ts):
-- outdoors · music_arts · food · families · faith · sports · books · service · games.
-- Stored as free text (no CHECK constraint) so the two apps can evolve the list
-- without a lockstep migration. Run once in the Supabase SQL editor.

alter table public.club_events
    add column if not exists category text;

comment on column public.club_events.category is
    'Optional event category id, mirroring the INTERESTS taxonomy (outdoors, music_arts, food, families, faith, sports, books, service, games). Null = uncategorized (client reads as "other").';
