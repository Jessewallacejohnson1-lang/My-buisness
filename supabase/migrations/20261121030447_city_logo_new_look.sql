-- The City's logo in the new look (BP app place-photos 12; Jesse, 2026-11-20: "yes"): the same ink skyline
-- over "CITY OF" and "ST. JOSEPH", sharpened, trimmed to fit and lit by logo-3d's logo module, as every other
-- logo in the app. A 512 px see-through WebP. The old file stays in Storage: putting
-- places/st-joseph/city/logo-7fd3f719.png back is the way back.
update public.town_pages
set picture = 'https://lxdgwhvqjqmqliobwjpi.supabase.co/storage/v1/object/public/places/st-joseph/city/logo-933db6fc16.webp',
    picture_kind = 'logo'
where town = 'st-joseph-mn' and slug = 'city';
