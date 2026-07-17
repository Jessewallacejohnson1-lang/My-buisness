-- Remove national chains from the POI map — keep it local-independent (the on-brand
-- bar rejects anything that feels like a big-corp app). The Google Nearby sweep in
-- 20260715120000_places_seed.sql surfaced national chains alongside the town's real
-- venues; this strips the 10 national brands so the map shows locally-owned businesses
-- only. Regional Minnesota companies (Coborn's, Sentry Bank) and the post office are
-- intentionally KEPT — they're community anchors, not big-corp chains.
-- Idempotent (delete by Google place_id). Safe to re-run.

delete from public.places where place_id in (
    'ChIJya0xj_FZtFIR9HcG5x8Qn3A', -- Dollar General
    'ChIJD2riN8VZtFIRehXwgKUkA8c', -- Holiday Stationstores
    'ChIJzeuDh9pZtFIRvj4UdbHclJE', -- Kwik Trip
    'ChIJQ08RPqlZtFIRz9DQ5PHSyYk', -- Kwik Trip #575
    'ChIJQ_UrhrlZtFIRuBFsbDvOtck', -- O'Reilly Auto Parts
    'ChIJCZ-6KbpZtFIRT_g9iebWlWM', -- Snap Fitness St. Joseph
    'ChIJv9tI5l9ZtFIRYzLLIRe5zr8', -- Caribou Coffee
    'ChIJ67OQp6VZtFIRfxt_gnI6w-g', -- McDonald's
    'ChIJ1YBBDWFXtFIRpN_AoK_WPi8', -- Subway
    'ChIJ48M5DWFXtFIRhX2uzqCRgPo'  -- Taco John's
);
