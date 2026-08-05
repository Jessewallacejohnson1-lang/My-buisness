-- ============================================================================
-- Cover the unindexed foreign keys
-- ============================================================================
-- NOT YET APPLIED — safe to run whenever; committed unapplied only so it lands
-- with the migration above rather than out of band.
--
-- Flagged by the Supabase performance linter (0001_unindexed_foreign_keys): ten
-- FK constraints have no covering index. Two costs, both of which bite later
-- rather than now:
--
--   1. Every `on delete cascade` / `on delete set null` has to sequential-scan
--      the child table. Deleting a club scans club_events and club_members;
--      deleting a user scans nearly everything.
--   2. The `submitted_by` / `user_id` lookups the app makes ("my posts", "my
--      RSVPs") scan rather than seek.
--
-- Harmless today — club_events is 14 rows and places is 91 — which is exactly
-- why it is worth doing before launch rather than after.
--
-- `if not exists` throughout, so this is re-runnable. Rollback is `drop index`.
--
-- Deliberately NOT using `create index concurrently`: these tables are tiny, the
-- locks are sub-millisecond, and CONCURRENTLY cannot run inside the transaction
-- that wraps a migration. Revisit that trade-off if these tables ever get large.

-- club_events: both FKs uncovered. club_id drives the cascade when a club is
-- deleted; submitted_by drives "events I posted" and the auth.users cascade.
create index if not exists club_events_club_id_idx
    on public.club_events using btree (club_id);
create index if not exists club_events_submitted_by_idx
    on public.club_events using btree (submitted_by);

-- clubs.submitted_by: "clubs I created", plus the auth.users set-null path.
create index if not exists clubs_submitted_by_idx
    on public.clubs using btree (submitted_by);

-- The user_id side of each join table. The event_id/club_id sides are already
-- covered by existing indexes; these are the halves that were missed.
create index if not exists club_members_user_id_idx
    on public.club_members using btree (user_id);
create index if not exists event_comments_user_id_idx
    on public.event_comments using btree (user_id);
create index if not exists event_likes_user_id_idx
    on public.event_likes using btree (user_id);
create index if not exists event_rsvps_user_id_idx
    on public.event_rsvps using btree (user_id);
create index if not exists event_saves_user_id_idx
    on public.event_saves using btree (user_id);
create index if not exists quest_completions_user_id_idx
    on public.quest_completions using btree (user_id);

-- daily_quests.created_by: admin-authored, so tiny, but it is an FK to
-- auth.users and participates in the same cascade scan.
create index if not exists daily_quests_created_by_idx
    on public.daily_quests using btree (created_by);
