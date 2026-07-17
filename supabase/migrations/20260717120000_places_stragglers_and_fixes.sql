-- places seed — LOCAL additions round 2 + review fixes (2026-07-17).
-- Adds the 10 St. Joseph venues OSM could not pin earlier (NE industrial park on
-- 19th/21st Ave NE, the County Rd 75 corridor, and rural farms), each geocoded via
-- the business's own site / Google Maps place pin / US Census + OSM and validated
-- inside the St. Joseph MN bounding box. Then applies code-review fixes to the
-- first local seed: correct primary_type on three venues and a fixed vet coordinate.
-- Idempotent (insert on-conflict-do-nothing; updates set fixed values). Depends on
-- 20260716120000_places_seed_local.sql.

insert into public.places (place_id, name, lat, lon, family, primary_type, types, address, source) values
  ('hygge-stjoe-sunny-mary-meadow', 'Sunny Mary Meadow', 45.644146, -94.290437, 'business', 'farm', '{farm,point_of_interest,establishment}'::text[], '8664 360th Street, St. Joseph, MN 56374', 'hygge_research'),
  ('hygge-stjoe-thomsen-s-garden-center', 'Thomsen''s Garden Center', 45.554759, -94.431901, 'business', 'garden_center', '{garden_center,point_of_interest,establishment}'::text[], '29754 156th Ave, St. Joseph, MN 56374', 'hygge_research'),
  ('hygge-stjoe-granite-city-gymnastics', 'Granite City Gymnastics', 45.575922, -94.288266, 'business', 'gym', '{gym,point_of_interest,establishment}'::text[], '922 21st Ave NE, St. Joseph, MN 56374', 'hygge_research'),
  ('hygge-stjoe-autobody-2000-inc', 'Autobody 2000 Inc', 45.570378, -94.293294, 'business', 'car_repair', '{car_repair,point_of_interest,establishment}'::text[], '611 19th Ave NE, St. Joseph, MN 56374', 'hygge_research'),
  ('hygge-stjoe-floor-to-ceiling', 'Floor to Ceiling', 45.576258, -94.288196, 'business', 'home_improvement_store', '{home_improvement_store,point_of_interest,establishment}'::text[], '942 21st Ave NE, St. Joseph, MN 56374', 'hygge_curated'),
  ('hygge-stjoe-groundsman-llc', 'Groundsman LLC', 45.569789, -94.292571, 'business', 'general_contractor', '{general_contractor,point_of_interest,establishment}'::text[], '731 19th Ave NE, St. Joseph, MN 56374', 'hygge_research'),
  ('hygge-stjoe-tiremaxx-service-centers', 'TireMaxx Service Centers', 45.577367, -94.342727, 'business', 'car_repair', '{car_repair,point_of_interest,establishment}'::text[], '11415 County Rd 75, St. Joseph, MN 56374', 'hygge_research'),
  ('hygge-stjoe-chiropractic-connection-pc', 'Chiropractic Connection, PC', 45.568998, -94.326674, 'business', 'chiropractor', '{chiropractor,point_of_interest,establishment}'::text[], '709 County Road 75 W, St. Joseph, MN 56374', 'hygge_research'),
  ('hygge-stjoe-trobec-s-bus-service-inc', 'Trobec''s Bus Service, Inc.', 45.570806, -94.289328, 'business', 'moving_company', '{moving_company,point_of_interest,establishment}'::text[], '618 21st Ave NE, St. Joseph, MN 56374', 'hygge_research'),
  ('hygge-stjoe-woodcrest-of-country-manor', 'Woodcrest of Country Manor', 45.544071, -94.313919, 'business', 'point_of_interest', '{point_of_interest,establishment}'::text[], '1200 Lanigan Way SW, St. Joseph, MN 56374', 'hygge_research')
on conflict (place_id) do nothing;

-- Review fixes to 20260716120000_places_seed_local.sql:
update public.places set primary_type='home_goods_store', types='{home_goods_store,point_of_interest,establishment}'::text[]
  where place_id='hygge-stjoe-w-r-home-co';                         -- home decor, not apparel
update public.places set primary_type='day_care_center', types='{day_care_center,point_of_interest,establishment}'::text[]
  where place_id='hygge-stjoe-little-saints-academy';               -- childcare, not retail
update public.places set primary_type='point_of_interest', types='{point_of_interest,establishment}'::text[]
  where place_id='hygge-stjoe-the-newsleaders';                     -- newspaper office, not retail
update public.places set lat=45.564727, lon=-94.293349
  where place_id='hygge-stjoe-st-joseph-veterinary-clinic';          -- was ~0.8km too far west of 1722 E Minnesota St
