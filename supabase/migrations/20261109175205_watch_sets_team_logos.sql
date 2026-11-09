-- The morning's team logos step (sources/scripts/team_logos.py, BP app game-card 17): a team with no logo gets the
-- one its school's own page shows, when the page's title names the school and two readings of the cheap model find
-- nothing on it against that school (Jesse, 2026-11-09: "i dont have to accept rather it has evals to make sure its
-- the correct team"). The job runs as `watch` (20261031040831_watch_key.sql), which could add a team but not give it a
-- logo. Only these three columns: a team's name, its page and its aliases stay the migrations' and Jesse's. The logo
-- file goes in the places bucket under teams/, which "watch uploads place photos" already allows.
grant update (logo_url, color, colors) on public.teams to watch;

-- A wrong logo comes down with a migration that empties logo_url (its games hide again,
-- private.game_waits_for_logos) and adds the logo's address here, so the morning never puts it back: the report's
-- take-down line writes both. Only a migration writes it.
alter table public.teams add column if not exists logo_refused text[] not null default '{}';
