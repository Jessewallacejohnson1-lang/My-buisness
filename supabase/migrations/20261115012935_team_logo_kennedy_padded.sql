-- search-logo-size (BP app): Kennedy's crest moves to the same lit K with clear space round it, filling 85% of its
-- box, so it sits like the Schools row's other crests (Jesse, 2026-11-14: "look like others", then 85% on the mock).
-- The old file stays in Storage, so the reverse is the same update with the two addresses swapped (BP app
-- docs/plans/game-card/assets/25-clean-logos/raw/kennedy/move_team_logos_back.sql).
update public.teams set logo_url = 'https://lxdgwhvqjqmqliobwjpi.supabase.co/storage/v1/object/public/places/teams/kennedy/logo-fa86de2603.webp' where id = 'kennedy' and logo_url = 'https://lxdgwhvqjqmqliobwjpi.supabase.co/storage/v1/object/public/places/teams/kennedy/logo-e88815de71.webp';
