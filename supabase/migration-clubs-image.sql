-- Club photos. Run once in the Supabase SQL editor.
-- Gives clubs the same organizer-uploaded photo path events already have
-- (see migration-event-images.sql for club_events.image_url). Clubs still post
-- fine without it — submitClub() retries without the image if the column is
-- missing, and uploadClubImage() returns null if the bucket is missing.
--
-- No new bucket/policy is needed: club photos reuse the existing public
-- `event-images` bucket, whose upload policy is path-agnostic
-- (with check (bucket_id = 'event-images')), so a `clubs/…` key is allowed.

alter table public.clubs
  add column if not exists image_url text;
