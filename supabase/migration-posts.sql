-- migration-posts.sql — adds the Trail post-kind to club_events.
-- Run AFTER migration-community.sql, migration-quests.sql, migration-event-images.sql.
--
-- Context: Events already live in club_events (with image_url + the event-images
-- bucket). Clubs are a separate table (clubs) with their own flow. This migration
-- only adds Trails as a lightweight, undated kind on club_events — reusing
-- image_url, location, description, and the existing event-images bucket.

-- 1. Kind discriminator (event today; trail new). Clubs are NOT here — separate table.
alter table public.club_events
  add column if not exists kind       text not null default 'event',
  add column if not exists length     text,   -- Trail: e.g. "2.4 mi"
  add column if not exists difficulty text;   -- Trail: e.g. "Easy"

alter table public.club_events
  drop constraint if exists club_events_kind_check;
alter table public.club_events
  add constraint club_events_kind_check
  check (kind in ('event', 'trail'));

-- 2. Only Events require a date/time; Trails are undated.
alter table public.club_events alter column event_date drop not null;
alter table public.club_events alter column start_time drop not null;
