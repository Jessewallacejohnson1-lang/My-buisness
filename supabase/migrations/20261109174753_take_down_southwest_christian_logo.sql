-- Southwest Christian's logo was Southwest Minnesota Christian's (Edgerton, the Eagles), another school: its game is at
-- Southwest Christian High School in Chaska, the Stars (BP app game-card 17; Jesse's yes, 2026-11-09). Emptied, its
-- game hides again (private.game_waits_for_logos) until the morning's team logos step finds Chaska's.
update public.teams set logo_url = null, color = null, colors = null where id = 'southwest-christian';
