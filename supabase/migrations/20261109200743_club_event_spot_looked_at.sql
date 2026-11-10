-- A place line no registry, hand file or map gives a spot for is looked up each morning by two searches that must
-- agree on its street address (BP app docs/plans/inside-cards 20; sources/scripts/venue_spots.py).
-- club_events.spot_looked_at: when a place line's Events were last looked at, found or not. A line found gets its spot
-- (lat, lng) with it; one not found waits 14 days, so a venue no page names is tried once a fortnight, never daily.
-- Another Event at a line one of ours placed copies that spot with no search. A mark in the future (take-down) holds
-- the line off for good.

alter table public.club_events add column if not exists spot_looked_at timestamptz;
