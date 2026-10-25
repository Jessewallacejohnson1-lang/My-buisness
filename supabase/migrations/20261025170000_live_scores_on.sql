-- Live scores switched on (BP app docs/plans/game-card, ticket 03): SJU and CSB athletics said yes on
-- 2026-10-25 to Block Party showing their live scores (Jesse). Every minute while one of their games is on,
-- private.wake_live_scores (20261025160000_live_scores.sql) starts the live-scores edge function.

select cron.schedule('live-scores', '* * * * *', $$select private.wake_live_scores()$$);
