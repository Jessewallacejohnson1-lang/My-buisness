-- The morning's team logos step (sources/scripts/team_logos.py, BP app game-card 17): a team with no logo gets the
-- one its school's page shows, when the page's title names the school and the cheap model says yes (Jesse,
-- 2026-11-09: "i dont have to accept rather it has evals to make sure its the correct team"). The job runs as
-- `watch` (20261031040831_watch_key.sql), which could add a team but not give it a logo. Only these three columns:
-- a team's name, its page and its aliases stay the migrations' and Jesse's. The logo file goes in the places
-- bucket under teams/, which "watch uploads place photos" already allows. A wrong one comes down with a migration
-- that empties logo_url, and its games hide again (private.game_waits_for_logos).
grant update (logo_url, color, colors) on public.teams to watch;
