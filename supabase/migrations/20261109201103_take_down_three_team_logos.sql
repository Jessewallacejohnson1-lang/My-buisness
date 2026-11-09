-- Three live team logos that aren't one school's own today (BP app game-card 17; Jesse's yes, 2026-11-09: a logo must
-- be the school's, never a town's or a district's). Minneapolis Camden's eagle is out of date: its Bound page shows a
-- red C with a star. Crookston's and Proctor's are their districts' seals ("Crookston Public Schools, ISD 593",
-- "Proctor Public Schools"). Emptied, their games hide (private.game_waits_for_logos) until the morning's team logos
-- step puts in each school's own logo from Bound, or says in the report why it couldn't.
update public.teams set logo_url = null, color = null, colors = null
where id in ('minneapolis-camden', 'crookston', 'proctor');
