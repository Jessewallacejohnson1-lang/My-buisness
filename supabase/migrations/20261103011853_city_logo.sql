-- The City of St. Joseph's own logo on its page (BP app onboarding 26; Jesse, 2026-11-02: "use the
-- city logo"). The City's white skyline mark, drawn in ink so it shows on Block Party's light pages,
-- on a 512 px square in the public places bucket. It shows wherever the City's page is a tile or a
-- row: Follow 3, Following, an Event's host. The page's own photo stays the app's (Town.cityPagePhoto).
update public.town_pages
set picture = 'https://lxdgwhvqjqmqliobwjpi.supabase.co/storage/v1/object/public/places/st-joseph/city/logo-2807161c.png',
    picture_kind = 'logo'
where town = 'st-joseph-mn' and slug = 'city';
