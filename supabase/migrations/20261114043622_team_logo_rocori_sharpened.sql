-- game-card 25: ROCORI's team logo moves to its sharpened file (the 100 px file drawn at 4x and lit).
-- Jesse picked it on 2026-11-13 over the two checks' note that the plume lost fine lines; ticket 27 looks for a real
-- sharper source. The old file stays in Storage, so the reverse is the same update with the two addresses swapped.
update public.teams set logo_url = 'https://lxdgwhvqjqmqliobwjpi.supabase.co/storage/v1/object/public/places/teams/rocori/logo-2e3a2e3b07.webp' where id = 'rocori' and logo_url = 'https://lxdgwhvqjqmqliobwjpi.supabase.co/storage/v1/object/public/places/teams/rocori/logo-3064eeec79.png';
