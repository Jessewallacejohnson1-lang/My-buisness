-- Search trips on places filed under the wrong kind or none (BP app search-helpful 05, Jesse's yes at Check-in 1).
-- Each kind is one two separate research agents agreed on (BP app docs/plans/search-helpful/assets/05-data-fixes/
-- research.json and research2.json, with sources). Six they didn't agree on keep no kind: Consumer Directions,
-- Beumer Outdoors, K & L Lawncare, Malibu Tan, Heymans Design, Steve's Landscape Service.
-- `types` keeps the place type (business, church, school...) after the new kind. family is business for all:
-- Kidstop was food only because of coffee_shop. Undo: each line's old kind is in its comment (none: no kind).

update public.places set primary_type = 'sports_club', types = array['sports_club', 'business'], family = 'business' where id = '6bf793c3-35ea-47a4-9977-7186d00ed946'; -- St. Joseph Joes
update public.places set primary_type = 'hair_salon', types = array['hair_salon', 'business'], family = 'business' where id = '2d652189-e2cc-4d30-8a62-2afaa92822d5'; -- 2nd Avenue Cuts
update public.places set primary_type = 'agricultural_service', types = array['agricultural_service', 'business'], family = 'business' where id = '3677bb03-9587-4951-bf14-d068d3946eb5'; -- Avon Ag-Lime
update public.places set primary_type = 'supplier_or_distributor', types = array['supplier_or_distributor', 'business'], family = 'business' where id = 'cad04bf2-1891-4574-8932-444f25ad00bb'; -- Cole Papers
update public.places set primary_type = 'marketing_agency', types = array['marketing_agency', 'business'], family = 'business' where id = '3589fb91-cad0-4f34-826f-2506ad0783e9'; -- Curtis Marketing Group
update public.places set primary_type = 'car_repair', types = array['car_repair', 'business'], family = 'business' where id = '97725c16-b0f4-48c5-aa28-e1342797bee2'; -- Fifth Gear Repair
update public.places set primary_type = 'general_contractor', types = array['general_contractor', 'business'], family = 'business' where id = 'd6f8e86a-b1a2-47df-8840-4fa9329a30aa'; -- Jet Black
update public.places set primary_type = 'general_contractor', types = array['general_contractor', 'business'], family = 'business' where id = 'f33591a2-1bce-4770-9ca5-ca43a1eec039'; -- John Mondloch Remodeling
update public.places set primary_type = 'manufacturer', types = array['manufacturer', 'business'], family = 'business' where id = '062aa60c-6a7d-4ceb-b403-69203b9e33b9'; -- Little Shop Welding & Repair
update public.places set primary_type = 'professional_service', types = array['professional_service', 'business'], family = 'business' where id = '0bfbab6c-b800-4e4a-b9bf-94858eee18ba'; -- NAMI Solutions, Inc.
update public.places set primary_type = 'financial_service', types = array['financial_service', 'business'], family = 'business' where id = '56f21f83-3d64-4bd4-8c6a-a2cb5d1261f6'; -- Mortgages on Main
update public.places set primary_type = 'real_estate_agency', types = array['real_estate_agency', 'business'], family = 'business' where id = '5cf1fecf-25e0-44a0-a1d4-fa796f3a494f'; -- Golden Rule Real Estate
-- Kidstop: Boys & Girls Clubs' before- and after-school care, grades K-6, at Kennedy (bgcmn.org). Overture
-- called it a coffee shop, so "coffee" found it.
update public.places set primary_type = 'day_care_center', types = array['day_care_center', 'school'], family = 'business' where id = '41f48914-db1c-4577-b86f-a7681192cd6b'; -- Kidstop (was coffee_shop)
update public.places set primary_type = 'park', types = array['park'], family = 'business' where id = 'c8c398b7-2d0c-45b8-9a67-96984ff98c0c'; -- Cloverdale Park
update public.places set primary_type = 'art_studio', types = array['art_studio', 'school'], family = 'business' where id = 'ae5e2bd6-a25c-49a4-83d7-d2a87d27eb07'; -- Meyer Farm Project
update public.places set primary_type = 'city_hall', types = array['city_hall', 'government'], family = 'business' where id = 'b6b0dcc9-7d18-4a50-90a7-3a08de81ef59'; -- St. Joseph Government Center
update public.places set primary_type = 'park', types = array['park', 'business'], family = 'business' where id = 'ab521488-ccec-42c8-885d-fcac4ff1cd97'; -- Millstream Park
update public.places set primary_type = 'health_food_store', types = array['health_food_store', 'business'], family = 'business' where id = 'fcf21d57-f622-43a0-9fdb-a3676ffe20df'; -- Victory Nutrition
update public.places set primary_type = 'insurance_agency', types = array['insurance_agency', 'business'], family = 'business' where id = '66f39423-a657-4805-b67f-ce08b2976626'; -- Ross Nesbit Agencies
update public.places set primary_type = 'event_or_party_service', types = array['event_or_party_service', 'business'], family = 'business' where id = 'c1331513-9c25-495d-ae38-e3a0c703570e'; -- Bloom Styling & Events
update public.places set primary_type = 'church', types = array['church', 'business'], family = 'business' where id = 'd9f0ce3c-f1d6-429a-be50-3fad14419734'; -- River of Life Church (was nonprofits_charities)
update public.places set primary_type = 'school_district', types = array['school_district', 'school'], family = 'business' where id = '4602d253-49b9-41ff-8386-dabd6786791a'; -- St. Cloud Area School District 742 (was gov)
update public.places set primary_type = 'park', types = array['park'], family = 'business' where id = 'fb6ad725-598b-48f8-9b26-c00bc6e3a9fa'; -- St. Wendel Tamarack Bog Scientific & Natural Area (was political_organization)

-- Not open: off Search and the map, as American Burger Bar (20261116142612).
-- DSL Saint Joseph: not a place, a page that sells CenturyLink by phone (dslsaintjoseph.com)
update public.places set closed_at = now() where id = 'ea2aa75e-ba26-41e2-8604-574f3f90d012' and closed_at is null;
-- JR's Mobil & Radiator Repair: closed, building torn down (WJON, 2023-11-08, wjon.com/jr-mobile-site-st-joseph)
update public.places set closed_at = now() where id = 'a308c256-61f0-4049-a396-d1c835981f03' and closed_at is null;

-- Church of Saint Joseph (registry church-jospehs-st, the Catholic parish at 12 W Minnesota St) had no row:
-- it gained its spot and site on 2026-11-15, after the last place_rows.py run. The row place_rows.py makes from its
-- registry entry (category catholic_church, place type Church since this commit), with its Apple Maps id.
insert into public.places (entry_id, name, address, lat, lon, family, primary_type, types, source, links, apple_place_id)
select 'church-jospehs-st', 'Church of Saint Joseph', '12 W Minnesota St, St. Joseph, MN', 45.56417, -94.31874,
       'business', 'catholic_church', array['catholic_church', 'church'], 'registry',
       '[{"kind": "website", "url": "https://www.benedictinecatholiccommunities.org/saint-joseph"}, {"kind": "facebook", "url": "https://www.facebook.com/ChurchSJStJoseph"}]'::jsonb,
       'IF51B509E0A12B5B8'  -- apple_maps.py match: Church of Saint Joseph, 35 m
where not exists (select 1 from public.places where entry_id = 'church-jospehs-st');
