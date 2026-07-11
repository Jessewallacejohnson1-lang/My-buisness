-- ============================================================================
-- SUNSET THE WELLNESS APP (Hygge Health)  —  DESTRUCTIVE · RUN MANUALLY
-- ============================================================================
-- This permanently deletes the wellness app's three tables from the SHARED
-- Supabase project (lxdgwhvqjqmqliobwjpi). Run it YOURSELF in the Supabase SQL
-- editor after taking a backup. It is intentionally NOT in supabase/migrations/
-- so it never auto-applies.
--
-- SCOPE — removes ONLY:  public.food_logs, public.workouts, public.profiles
-- KEEPS (untouched):     auth.users (shared login), every community table
--                        (clubs, club_events, event_rsvps, town_profiles,
--                        daily_quests, board_items, …), and the event-images /
--                        avatars storage buckets (both community).
--
-- Verified read-only on 2026-07-11 before writing this script:
--   • no inbound foreign keys reference these 3 tables
--   • no views or materialized views depend on them
--   • no triggers or functions reference profiles/food_logs/workouts
--     (so dropping profiles will NOT break new-user signup)
--   • no wellness-only storage buckets exist
-- => the drop is isolated and cannot break the St. Joseph community app.
--
-- ── STEP 1: BACK UP FIRST (do this before running the drops) ────────────────
--   Supabase Dashboard → Table Editor → open each table → Export → CSV
--     (food_logs · workouts · profiles), OR:
--   Dashboard → Database → Backups (download a snapshot), OR from a shell:
--     pg_dump "postgresql://…@db.lxdgwhvqjqmqliobwjpi.supabase.co:5432/postgres" \
--       -t public.food_logs -t public.workouts -t public.profiles \
--       --data-only --column-inserts > wellness_backup_20260711.sql
--
-- ── STEP 2: RUN THE TEARDOWN (only after the backup exists) ─────────────────

drop table if exists public.food_logs;
drop table if exists public.workouts;
drop table if exists public.profiles;

-- ── STEP 3 (optional): remove wellness edge functions ──────────────────────
--   If the wellness app deployed any edge functions (e.g. nutrition scoring),
--   delete them from Dashboard → Edge Functions. The community app's functions
--   (daily-almanac, the moderation function) must stay.
-- ============================================================================
