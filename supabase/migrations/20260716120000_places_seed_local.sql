-- places seed — LOCAL additions (52 independently-owned St. Joseph venues:
-- 5 food, 47 business), researched + web-verified 2026-07-16. Extends the
-- Google-swept seed (20260715120000_places_seed.sql) with the hyper-local businesses a
-- Google Nearby sweep misses: boutiques, makers, florists, a distillery & cidery, most
-- salons, and local clinics/services. Every venue was verified real, currently open, in
-- St. Joseph MN 56374 (not the MO/MI St. Josephs), and locally owned — chains excluded.
--
-- Coordinates: OSM Nominatim building matches, or (source=hygge_curated) hand-verified
-- against a same-building seeded venue. place_id is a synthetic 'hygge-stjoe-<slug>' (no
-- Google id), source tags provenance. Idempotent: on conflict (place_id) do nothing.
-- Depends on 20260715000000_places.sql. ~14 edge/rural-address venues + market-only
-- vendors still need a precise coordinate before pinning — tracked separately.

insert into public.places (place_id, name, lat, lon, family, primary_type, types, address, source) values
  ('hygge-stjoe-joetown-smashburger', 'Joetown Smashburger', 45.564311, -94.32182, 'food', 'restaurant', '{restaurant,point_of_interest,establishment}'::text[], '13 2nd Ave NW, St. Joseph, MN 56374', 'hygge_research'),
  ('hygge-stjoe-john-kuebelbeck-american-legion-post-328', 'John Kuebelbeck American Legion Post 328', 45.563545, -94.320782, 'food', 'bar', '{bar,point_of_interest,establishment}'::text[], '101 W Minnesota St, St. Joseph, MN 56374', 'hygge_research'),
  ('hygge-stjoe-milk-honey-ciders', 'Milk & Honey Ciders', 45.560485, -94.352052, 'food', 'brewery', '{brewery,point_of_interest,establishment}'::text[], '11738 County Road 51, St. Joseph, MN 56374', 'hygge_research'),
  ('hygge-stjoe-obbink-distilling', 'Obbink Distilling', 45.568417, -94.317459, 'food', 'bar', '{bar,point_of_interest,establishment}'::text[], '11 Date St E, St. Joseph, MN 56374', 'hygge_research'),
  ('hygge-stjoe-tacoholic', 'Tacoholic', 45.565153, -94.31794, 'food', 'mexican_restaurant', '{mexican_restaurant,point_of_interest,establishment}'::text[], '14 College Ave N, Ste A, St. Joseph, MN 56374', 'hygge_research'),
  ('hygge-stjoe-all-occasion-floral-gifts', 'All Occasion Floral & Gifts', 45.567036, -94.315845, 'business', 'florist', '{florist,point_of_interest,establishment}'::text[], '38 E Birch St , St. Joseph, MN 56374', 'hygge_research'),
  ('hygge-stjoe-ams-tax-accounting-solutions-pa', 'AMS Tax & Accounting Solutions, PA', 45.567774, -94.313405, 'business', 'accounting', '{accounting,point_of_interest,establishment}'::text[], '303 Cedar St E, St. Joseph, MN 56374', 'hygge_research'),
  ('hygge-stjoe-amy-hedtke-state-farm', 'Amy Hedtke - State Farm', 45.567991, -94.305657, 'business', 'insurance_agency', '{insurance_agency,point_of_interest,establishment}'::text[], '414 8th Ave NE, St. Joseph, MN 56374', 'hygge_research'),
  ('hygge-stjoe-brenny-transportation-inc', 'Brenny Transportation, Inc.', 45.565924, -94.284438, 'business', 'moving_company', '{moving_company,point_of_interest,establishment}'::text[], '8505 Ridgewood Road, St. Joseph, MN 56374', 'hygge_research'),
  ('hygge-stjoe-bruno-press', 'Bruno Press', 45.563216, -94.309548, 'business', 'store', '{store,point_of_interest,establishment}'::text[], '154 5th Ave SE, St. Joseph, MN 56374', 'hygge_research'),
  ('hygge-stjoe-cedar-street-salon-spa', 'Cedar Street Salon & Spa', 45.567855, -94.314647, 'business', 'hair_salon', '{hair_salon,point_of_interest,establishment}'::text[], '235 E Cedar St, St. Joseph, MN 56374', 'hygge_research'),
  ('hygge-stjoe-centracare-st-joseph-clinic', 'CentraCare - St. Joseph Clinic', 45.568978, -94.295814, 'business', 'doctor', '{doctor,point_of_interest,establishment}'::text[], '1360 Elm Street East, St. Joseph, MN 56374', 'hygge_research'),
  ('hygge-stjoe-central-mn-realty', 'Central MN Realty', 45.566143, -94.318652, 'business', 'real_estate_agency', '{real_estate_agency,point_of_interest,establishment}'::text[], '111 College Ave N, St. Joseph, MN 56374', 'hygge_research'),
  ('hygge-stjoe-csb-benedicta-arts-center-galleries', 'CSB Benedicta Arts Center Galleries (Gorecki Gallery)', 45.564201, -94.317602, 'business', 'art_gallery', '{art_gallery,point_of_interest,establishment}'::text[], '37 College Ave S, St. Joseph, MN 56374', 'hygge_research'),
  ('hygge-stjoe-daisy-a-day-floral-gift', 'Daisy A Day Floral & Gift', 45.568501, -94.319022, 'business', 'florist', '{florist,point_of_interest,establishment}'::text[], '307 College Ave N, St. Joseph, MN 56374', 'hygge_research'),
  ('hygge-stjoe-exponential-chiropractic-healing-center', 'Exponential Chiropractic Healing Center', 45.566154, -94.318891, 'business', 'chiropractor', '{chiropractor,point_of_interest,establishment}'::text[], '103 College Ave N, St. Joseph, MN 56374', 'hygge_research'),
  ('hygge-stjoe-floral-arts-inc', 'Floral Arts Inc.', 45.567918, -94.317237, 'business', 'florist', '{florist,point_of_interest,establishment}'::text[], '307 1st Ave NE, St. Joseph, MN 56374', 'hygge_research'),
  ('hygge-stjoe-golden-hour-tanning', 'Golden Hour Tanning', 45.565672, -94.320552, 'business', 'beauty_salon', '{beauty_salon,point_of_interest,establishment}'::text[], '109 W Ash St, Suite B, St. Joseph, MN 56374', 'hygge_research'),
  ('hygge-stjoe-hair-by-hanna', 'Hair By Hanna', 45.56456, -94.319091, 'business', 'hair_salon', '{hair_salon,point_of_interest,establishment}'::text[], '33 W Minnesota St, Suite 101, St Joseph, MN 56374', 'hygge_research'),
  ('hygge-stjoe-hansen-company-woodworks', 'Hansen & Company Woodworks', 45.569226, -94.275632, 'business', 'store', '{store,point_of_interest,establishment}'::text[], '30701 Pearl Drive, Suite 3, St. Joseph, MN 56374', 'hygge_research'),
  ('hygge-stjoe-heim-kins-rescued-treasures', 'Heim-kins Rescued Treasures', 45.568051, -94.313881, 'business', 'store', '{store,point_of_interest,establishment}'::text[], '219 Cedar St E, St. Joseph, MN 56374', 'hygge_research'),
  ('hygge-stjoe-her-hair-studio', 'Her Hair Studio', 45.564715, -94.320047, 'business', 'hair_salon', '{hair_salon,point_of_interest,establishment}'::text[], '21 1st Ave NW, St. Joseph, MN 56374', 'hygge_research'),
  ('hygge-stjoe-home-town-title', 'Home Town Title', 45.566948, -94.307416, 'business', 'real_estate_agency', '{real_estate_agency,point_of_interest,establishment}'::text[], '710 County Road 75 E, Ste. 101, St. Joseph, MN 56374', 'hygge_curated'),
  ('hygge-stjoe-hudson-company', 'Hudson & Company', 45.564859, -94.318117, 'business', 'clothing_store', '{clothing_store,point_of_interest,establishment}'::text[], '11 College Ave N, St. Joseph, MN 56374', 'hygge_research'),
  ('hygge-stjoe-insurance-advisors', 'Insurance Advisors', 45.567037, -94.315887, 'business', 'insurance_agency', '{insurance_agency,point_of_interest,establishment}'::text[], '26 E Birch St, St. Joseph, MN 56374', 'hygge_research'),
  ('hygge-stjoe-jan-s-barbershop', 'Jan''s Barbershop', 45.564715, -94.320047, 'business', 'barber_shop', '{barber_shop,point_of_interest,establishment}'::text[], '21 1st Ave NW, St. Joseph, MN 56374', 'hygge_research'),
  ('hygge-stjoe-joseph-s-spa-and-salon', 'Joseph''s Spa and Salon', 45.56456, -94.319091, 'business', 'hair_salon', '{hair_salon,point_of_interest,establishment}'::text[], '33 W Minnesota St, Ste 101, St. Joseph, MN 56374', 'hygge_research'),
  ('hygge-stjoe-kensington-bank', 'Kensington Bank', 45.565775, -94.320477, 'business', 'bank', '{bank,point_of_interest,establishment}'::text[], '103 1st Ave NW, St. Joseph, MN 56374', 'hygge_research'),
  ('hygge-stjoe-laser-dentistry', 'Laser Dentistry', 45.564802, -94.321784, 'business', 'dentist', '{dentist,point_of_interest,establishment}'::text[], '26 2nd Ave NW, St. Joseph, MN 56374', 'hygge_research'),
  ('hygge-stjoe-little-saints-academy', 'Little Saints Academy', 45.56314, -94.315787, 'business', 'store', '{store,point_of_interest,establishment}'::text[], '124 1st Ave SE, St. Joseph, MN 56374', 'hygge_research'),
  ('hygge-stjoe-m-t-off-sale-liquor', 'M & T Off Sale Liquor', 45.566615, -94.3193, 'business', 'liquor_store', '{liquor_store,point_of_interest,establishment}'::text[], '21 W Birch St, St. Joseph, MN 56374', 'hygge_research'),
  ('hygge-stjoe-medelberg-family-chiropractic', 'Medelberg Family Chiropractic', 45.566948, -94.307416, 'business', 'chiropractor', '{chiropractor,point_of_interest,establishment}'::text[], '710 County Road 75 E, Ste 103, St. Joseph, MN 56374', 'hygge_curated'),
  ('hygge-stjoe-milbert-johnson-family-dentistry', 'Milbert Johnson Family Dentistry', 45.565787, -94.297545, 'business', 'dentist', '{dentist,point_of_interest,establishment}'::text[], '1514 E Minnesota St, St. Joseph, MN 56374', 'hygge_research'),
  ('hygge-stjoe-omann-insurance-agency-llc', 'Omann Insurance Agency, LLC', 45.568434, -94.322146, 'business', 'insurance_agency', '{insurance_agency,point_of_interest,establishment}'::text[], '305 E Cedar St, St. Joseph, MN 56374', 'hygge_research'),
  ('hygge-stjoe-pierce-insurance-agency', 'Pierce Insurance Agency', 45.564802, -94.321784, 'business', 'insurance_agency', '{insurance_agency,point_of_interest,establishment}'::text[], '26 2nd Ave NW, St. Joseph, MN 56374', 'hygge_research'),
  ('hygge-stjoe-rj-s-auto-repair', 'RJ''s Auto Repair', 45.576525, -94.347975, 'business', 'car_repair', '{car_repair,point_of_interest,establishment}'::text[], '30999 115th Ave, St. Joseph, MN 56374', 'hygge_research'),
  ('hygge-stjoe-saint-joseph-off-sale-liquor', 'Saint Joseph Off Sale Liquor (Hollander''s St. Joseph Liquor Shoppe)', 45.568024, -94.313094, 'business', 'liquor_store', '{liquor_store,point_of_interest,establishment}'::text[], '225 E Cedar St, St. Joseph, MN 56374', 'hygge_research'),
  ('hygge-stjoe-sheryl-matters-massage', 'Sheryl Matters Massage', 45.562682, -94.299431, 'business', 'spa', '{spa,point_of_interest,establishment}'::text[], '201 Pondview Ln E, St. Joseph, MN 56374', 'hygge_research'),
  ('hygge-stjoe-st-joseph-farmers-market', 'St. Joseph Farmers'' Market', 45.559244, -94.338356, 'business', 'market', '{market,point_of_interest,establishment}'::text[], '610 County Road 2, St. Joseph, MN 56374', 'hygge_research'),
  ('hygge-stjoe-st-joseph-health-wellness-llc', 'St. Joseph Health & Wellness, LLC', 45.565267, -94.320027, 'business', 'spa', '{spa,point_of_interest,establishment}'::text[], '32 1st Ave NW, St. Joseph, MN 56374', 'hygge_research'),
  ('hygge-stjoe-st-joseph-veterinary-clinic', 'St. Joseph Veterinary Clinic', 45.56529, -94.308435, 'business', 'veterinary_care', '{veterinary_care,point_of_interest,establishment}'::text[], '1722 E Minnesota St, St. Joseph, MN 56374', 'hygge_research'),
  ('hygge-stjoe-the-estates-bed-breakfast', 'The Estates Bed & Breakfast', 45.565126, -94.316503, 'business', 'lodging', '{lodging,point_of_interest,establishment}'::text[], '29 E Minnesota St, St. Joseph, MN 56374', 'hygge_research'),
  ('hygge-stjoe-the-newsleaders', 'The Newsleaders', 45.565267, -94.320027, 'business', 'store', '{store,point_of_interest,establishment}'::text[], '32 First Ave. NW , St. Joseph, MN 56374', 'hygge_curated'),
  ('hygge-stjoe-the-perfect-fit-llc', 'The Perfect Fit, LLC', 45.565267, -94.320027, 'business', 'gym', '{gym,point_of_interest,establishment}'::text[], '32 1st Ave NW, St. Joseph, MN 56374', 'hygge_research'),
  ('hygge-stjoe-two-bits-men-s-grooming-salon', 'Two Bits Men''s Grooming Salon', 45.564715, -94.320047, 'business', 'barber_shop', '{barber_shop,point_of_interest,establishment}'::text[], '21 1st Ave NW, St. Joseph, MN 56374', 'hygge_research'),
  ('hygge-stjoe-unwind-collaborative-healing-center', 'Unwind: Collaborative Healing Center', 45.56623, -94.317721, 'business', 'spa', '{spa,point_of_interest,establishment}'::text[], '19 E Ash St, St. Joseph, MN 56374', 'hygge_research'),
  ('hygge-stjoe-uptown-styles', 'Uptown Styles', 45.56456, -94.319091, 'business', 'hair_salon', '{hair_salon,point_of_interest,establishment}'::text[], '33 W Minnesota St, Ste 101, St. Joseph, MN 56374', 'hygge_research'),
  ('hygge-stjoe-well-company-st-joseph', 'WELL & Company St. Joseph', 45.565539, -94.322096, 'business', 'doctor', '{doctor,point_of_interest,establishment}'::text[], '106 2nd Ave NW, Suite 2, St. Joseph, MN 56374', 'hygge_research'),
  ('hygge-stjoe-whitby-gift-shop-gallery', 'Whitby Gift Shop & Gallery', 45.56299, -94.31912, 'business', 'gift_shop', '{gift_shop,point_of_interest,establishment}'::text[], '104 Chapel Lane, St. Joseph, MN 56374', 'hygge_curated'),
  ('hygge-stjoe-white-peony-boutique', 'White Peony Boutique', 45.564772, -94.320071, 'business', 'clothing_store', '{clothing_store,point_of_interest,establishment}'::text[], '25 1st Ave NW, Suite #200, St. Joseph, MN 56374', 'hygge_research'),
  ('hygge-stjoe-wildwood-ranch-maple-syrup', 'Wildwood Ranch Maple Syrup', 45.553413, -94.368411, 'business', 'farm', '{farm,point_of_interest,establishment}'::text[], '29709 Kipper Road, St. Joseph, MN 56374', 'hygge_research'),
  ('hygge-stjoe-w-r-home-co', 'W|R Home Co.', 45.564772, -94.320071, 'business', 'clothing_store', '{clothing_store,point_of_interest,establishment}'::text[], '25 1st Ave NW, Ste 100, St. Joseph, MN 56374', 'hygge_research')
on conflict (place_id) do nothing;
