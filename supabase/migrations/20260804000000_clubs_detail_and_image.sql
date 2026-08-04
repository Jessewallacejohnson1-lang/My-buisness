-- clubs: detail fields + organizer photo.
--
-- Historical record, not a new change. These four columns were applied by hand
-- to the live project from the Expo repo's ad-hoc files
-- (my-business @ community-rebuild: migration-clubs-detail.sql, migration-clubs-image.sql)
-- and were never captured in this migrations directory.
--
-- Verified against prod (lxdgwhvqjqmqliobwjpi) on 2026-08-04 via
-- information_schema.columns: all four already exist. Every statement below is
-- `if not exists`, so applying this is a no-op on the live project and a
-- correct replay on a fresh one.
--
-- Consumed by BlockParty/Backend/CommunityAPI.swift (submitClub) and the club
-- detail view. Club photos reuse the existing public `event-images` bucket —
-- its upload policy is path-agnostic (with check (bucket_id = 'event-images')),
-- so a `clubs/…` key needs no new bucket or policy.

alter table public.clubs
    add column if not exists location     text,
    add column if not exists description  text,
    add column if not exists expectations text,
    add column if not exists image_url    text;

-- NOTE: the two `delete from` statements in the Expo repo's
-- migration-clubs-detail.sql are deliberately NOT replayed here. They removed
-- five named placeholder seed clubs and their orphaned events, already ran
-- against prod, and are destructive data changes rather than schema — replaying
-- them on a fresh environment would be meaningless and on prod, unsafe.
