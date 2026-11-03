-- The City's logo restacked to fit a square tile (Jesse, 2026-11-02: "edit it to make it fit"): the
-- skyline over "CITY OF" and "ST. JOSEPH" on two lines, the words grown to the skyline's width, still
-- in ink on a 512 px square. Replaces 20261103011853_city_logo's one-line version.
update public.town_pages
set picture = 'https://lxdgwhvqjqmqliobwjpi.supabase.co/storage/v1/object/public/places/st-joseph/city/logo-7fd3f719.png',
    picture_kind = 'logo'
where town = 'st-joseph-mn' and slug = 'city';
