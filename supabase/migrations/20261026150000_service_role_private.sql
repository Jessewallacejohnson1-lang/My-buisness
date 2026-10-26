-- The morning job writes Events and News as the service role (write_judged.py's apply_judged).
-- 20261025140000_interests_21.sql put triggers on club_events and board_items that call
-- private.interests_21, and the service role had no usage on schema private, so every write
-- failed "permission denied for schema private" (the 2026-10-26 morning watch saved nothing).
-- anon and authenticated have had usage since 20261010120000_town_feed_recipe.sql.
grant usage on schema private to service_role;
