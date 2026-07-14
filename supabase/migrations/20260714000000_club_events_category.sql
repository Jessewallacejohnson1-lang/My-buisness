-- club_events.category — an optional event category (music, food, outdoors, …).
-- Shared project also backs the Expo/RN app; the mirror migration in that repo is
-- supabase/migration-event-category.sql. VERIFY against prod.
--
-- Additive + backward-compatible: the column is NULLABLE with no default, so every
-- existing row (and the Expo app, which doesn't set it) stays valid. A null / legacy
-- / unrecognized value is read as `.other` client-side (EventCategory.from), so
-- nothing renders blank. The vocabulary mirrors the Expo INTERESTS taxonomy
-- (apps/mobile/src/lib/interests.ts): outdoors · music_arts · food · families ·
-- faith · sports · books · service · games (+ other). Stored as free text (not a
-- CHECK constraint) so the two apps can evolve the list without a lockstep migration.

alter table public.club_events
    add column if not exists category text;

comment on column public.club_events.category is
    'Optional event category id, mirroring the Expo INTERESTS taxonomy (outdoors, music_arts, food, families, faith, sports, books, service, games). Null = uncategorized (client reads as "other").';
