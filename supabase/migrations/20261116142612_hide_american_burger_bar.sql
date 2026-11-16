-- American Burger Bar closed long ago (Jesse, 2026-11-16: "not a business, they closed many moons ago").
-- Off Search and the map. It has no Apple Maps id, so the morning finish never checked it
-- (BP app watch-every-place 32 researches how to catch places like it). No upcoming Events to cancel.
update public.places
set closed_at = now()
where id = '87cd8550-0e48-4c53-82a5-acef01765ed2' and closed_at is null;
