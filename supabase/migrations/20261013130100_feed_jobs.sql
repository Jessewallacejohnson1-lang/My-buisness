-- The two jobs behind views (BP app docs/plans/town-feed, ticket 20): the summary every 10
-- minutes, and views older than 60 days deleted each night at 3:30 am Central (08:30 UTC).
-- pg_cron is already on (schema.sql). Not loaded by the PGlite stories, which have no pg_cron.
-- Applied live only with Jesse's yes (given at Check-in 1, 2026-10-13).
select cron.schedule('feed-item-stats', '*/10 * * * *',
  $$refresh materialized view concurrently private.feed_item_stats$$);
select cron.schedule('feed-views-clean-up', '30 8 * * *',
  $$select private.feed_clean_up()$$);
