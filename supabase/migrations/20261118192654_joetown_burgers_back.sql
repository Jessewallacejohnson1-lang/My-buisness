-- Joetown Burgers is a place (Jesse, 2026-11-18: "joetown burgers is a place"). It was hidden on
-- 2026-11-16 as "a double: the kitchen inside The House Food and Tap" (20261117011231), against
-- Jesse's word of 2026-10-18: one of four restaurants inside The House, each run on its own.
-- Back on Search and the map. It has no Apple Maps id, so the morning's Apple check won't hide it.
update public.places set closed_at = null, apple_place_id = null
where id = 'd2737fe2-749c-4473-8346-35b2c5c774b0';
