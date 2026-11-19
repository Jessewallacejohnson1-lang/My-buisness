-- Joetown Burgers' own links (BP app place-pages 09; Jesse, 2026-11-19: "joetown burgers has social media and
-- are operating inside the house food tap. you can find them on there website too"). It runs inside The House
-- Food & Tap (registry `inside: food-house-tap`), so its website is its own page on The House's site, and that
-- page links its own Instagram. Only an empty list is filled.

update public.places
set links = '[{"kind": "website", "url": "https://www.thehousefoodandtap.com/joetown-burgers"},
              {"kind": "instagram", "url": "https://www.instagram.com/joetownsmash"}]'::jsonb
where entry_id = 'joetown-smashburger' and links = '[]'::jsonb;
