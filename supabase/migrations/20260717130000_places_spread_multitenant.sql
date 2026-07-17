-- places — spread co-located tenants so every pin is individually tappable (2026-07-17).
-- 15 businesses share 6 building coordinates (salon suites, a title/chiro office, etc.);
-- the Mapbox POI layer doesn't spread exact-overlap points, so 9 were hidden behind the
-- top pin. This fans each building's tenants ~11 m around the true point on a fixed circle
-- (deterministic, order-by-name) — imperceptible geographically, but each pin selectable.
-- Idempotent: sets fixed coordinates. Depends on the two local seed migrations.

update public.places set lat=45.564646, lon=-94.31902 where place_id='hygge-stjoe-hair-by-hanna';
update public.places set lat=45.564474, lon=-94.31902 where place_id='hygge-stjoe-joseph-s-spa-and-salon';
update public.places set lat=45.56456, lon=-94.319232 where place_id='hygge-stjoe-uptown-styles';
update public.places set lat=45.564801, lon=-94.319976 where place_id='hygge-stjoe-her-hair-studio';
update public.places set lat=45.564629, lon=-94.319976 where place_id='hygge-stjoe-jan-s-barbershop';
update public.places set lat=45.564715, lon=-94.320188 where place_id='hygge-stjoe-two-bits-men-s-grooming-salon';
update public.places set lat=45.565353, lon=-94.319956 where place_id='hygge-stjoe-st-joseph-health-wellness-llc';
update public.places set lat=45.565181, lon=-94.319956 where place_id='hygge-stjoe-the-newsleaders';
update public.places set lat=45.565267, lon=-94.320168 where place_id='hygge-stjoe-the-perfect-fit-llc';
update public.places set lat=45.564858, lon=-94.32 where place_id='hygge-stjoe-w-r-home-co';
update public.places set lat=45.564686, lon=-94.320142 where place_id='hygge-stjoe-white-peony-boutique';
update public.places set lat=45.564888, lon=-94.321713 where place_id='hygge-stjoe-laser-dentistry';
update public.places set lat=45.564716, lon=-94.321855 where place_id='hygge-stjoe-pierce-insurance-agency';
update public.places set lat=45.567034, lon=-94.307345 where place_id='hygge-stjoe-home-town-title';
update public.places set lat=45.566862, lon=-94.307487 where place_id='hygge-stjoe-medelberg-family-chiropractic';
