-- The popular places lead onboarding's Follow 3 (BP app onboarding 50; Jesse, 2026-11-23: "put at the top the ones
-- that post the most or popular", then yes to this column). `follow_spot` holds a place's spot in line, 1 first, and
-- the photo that fills its circle; a null photo shows its logo, as does one no longer live in `place_photos`.
-- Null for every other place. The table's own policies cover the column.
--   1 Flour & Flower
--   2 White Peony Boutique
--   3 Sal's Bar & Grill
--   4 Bad Habit Brewing Company
--   5 College of Saint Benedict
--   6 The House Food and Tap
--   7 Milk & Honey Ciders
--   8 Coborn's Grocery Store
--   9 Grey Face Rescue & Retirement
--   10 Saint Benedict's Monastery
--   11 Sunny Mary Meadow
--   12 Krewe Restaurant
--   13 The Local Blend
--   14 Kennedy Community School
--   15 Jupiter Moon Ice Cream - St. Joseph
--   16 KPower Yoga
--   17 Neighbors Route 75
--   18 The Wandering Cow Ice Cream
--   19 Clemens Library
--   20 St Joseph Meat Market Inc
--   21 Mission Nutrition
--   22 Thomsen's Garden Center
--   23 W|R Home Co.
--   24 Bruno Press
alter table public.places
  add column follow_spot jsonb
  constraint places_follow_spot_shape check (
    follow_spot is null
    or (jsonb_typeof(follow_spot -> 'spot') = 'number'
        and coalesce(jsonb_typeof(follow_spot -> 'photo'), 'null') in ('string', 'null')));

comment on column public.places.follow_spot is
  'Its spot at the top of onboarding''s Follow 3 and the photo in its circle: {"spot": 1, "photo": url or null}.';

update public.places p
set follow_spot = jsonb_build_object('spot', v.spot, 'photo', v.photo)
from (values
    ('fed769b6-ec34-4cc6-bb05-8e7016e79aec'::uuid, 1, 'https://lxdgwhvqjqmqliobwjpi.supabase.co/storage/v1/object/public/places/st-joseph/flour-and-flower/photo-a821f12c19.webp'),
    ('606a751d-98e2-4f3a-8926-a1d3966592e0'::uuid, 2, null),
    ('6b0f79a9-fff6-4e60-af98-a6a45ce51223'::uuid, 3, null),
    ('3f3c5259-67f9-491e-9af5-5c4b21a80b58'::uuid, 4, 'https://lxdgwhvqjqmqliobwjpi.supabase.co/storage/v1/object/public/places/st-joseph/bad-habit-brewing/photo-bac3eb6a41.webp'),
    ('ca5e86c5-0d61-45c7-bd08-b0ab97892463'::uuid, 5, 'https://lxdgwhvqjqmqliobwjpi.supabase.co/storage/v1/object/public/places/st-joseph/csb/photo-63e905acfe.webp'),
    ('7a27d0a0-126d-412c-871d-20a531a8ba72'::uuid, 6, 'https://lxdgwhvqjqmqliobwjpi.supabase.co/storage/v1/object/public/places/st-joseph/food-house-tap/photo-b101ca5bfc.webp'),
    ('796f4577-dd1a-49f6-aac5-49d3f8632ecb'::uuid, 7, null),
    ('cbd3dec1-e1ed-4aa7-b32d-a02f7ae4ff8d'::uuid, 8, null),
    ('b843e372-c9e1-44e1-bed0-fe255251d58e'::uuid, 9, 'https://lxdgwhvqjqmqliobwjpi.supabase.co/storage/v1/object/public/places/st-joseph/grey-face-rescue-retirement/photo-94a2114ab4.webp'),
    ('eb9183fc-e63c-426c-9321-a0128375c7d9'::uuid, 10, 'https://lxdgwhvqjqmqliobwjpi.supabase.co/storage/v1/object/public/places/st-joseph/benedict-of-of-order-sisters-st/photo-113f9b217e.webp'),
    ('448b008c-6c70-4591-b3e6-f094d6e41899'::uuid, 11, 'https://lxdgwhvqjqmqliobwjpi.supabase.co/storage/v1/object/public/places/st-joseph/mary-meadow-sunny/photo-18741af195.webp'),
    ('02280501-5d7d-4c2b-8a6b-2ec671ce9c7c'::uuid, 12, 'https://lxdgwhvqjqmqliobwjpi.supabase.co/storage/v1/object/public/places/st-joseph/krewe/photo-0b64c28f75.webp'),
    ('ed7a8833-6520-42b5-8eda-b11694731209'::uuid, 13, 'https://lxdgwhvqjqmqliobwjpi.supabase.co/storage/v1/object/public/places/st-joseph/local-blend/photo-0d70f6b936.webp'),
    ('07685957-4965-43a1-92a4-94d9c158f917'::uuid, 14, null),
    ('63fd93ff-7254-461c-9e64-b7c9169a56ae'::uuid, 15, 'https://lxdgwhvqjqmqliobwjpi.supabase.co/storage/v1/object/public/places/st-joseph/jupiter-moon/photo-d4994f51fa.webp'),
    ('e70d7fad-c801-48f5-b874-2191defaf9b5'::uuid, 16, null),
    ('3a51b1c2-eb45-4de4-8e38-5b48ca6ef44f'::uuid, 17, 'https://lxdgwhvqjqmqliobwjpi.supabase.co/storage/v1/object/public/places/st-joseph/neighbors-route-75/photo-26bcd3a956.webp'),
    ('01ed0060-197a-4ce3-bfb4-a15ba1777285'::uuid, 18, 'https://lxdgwhvqjqmqliobwjpi.supabase.co/storage/v1/object/public/places/st-joseph/cow-wandering/photo-a256e2e1d5.webp'),
    ('a4753fd1-f16b-4e91-b735-d4c1cf9e03bb'::uuid, 19, 'https://lxdgwhvqjqmqliobwjpi.supabase.co/storage/v1/object/public/places/st-joseph/clemens-library/photo-8f91d4b791.webp'),
    ('8d32d5e6-2c7b-47d4-8b58-86afc63e6442'::uuid, 20, null),
    ('dbdd2050-5e8e-47d3-a91d-19669a89a198'::uuid, 21, null),
    ('f97e06d6-8cf9-4a75-9acd-b891ba516509'::uuid, 22, 'https://lxdgwhvqjqmqliobwjpi.supabase.co/storage/v1/object/public/places/st-joseph/center-garden-thomsens/photo-1442869d90.webp'),
    ('132e001b-e5b6-45fa-8db8-18ec28eb0c85'::uuid, 23, 'https://lxdgwhvqjqmqliobwjpi.supabase.co/storage/v1/object/public/places/st-joseph/home-r-w/photo-c82a0a3c86.webp'),
    ('443332c9-0465-49f3-9afc-f5f103eb3bad'::uuid, 24, 'https://lxdgwhvqjqmqliobwjpi.supabase.co/storage/v1/object/public/places/st-joseph/bruno-press/photo-bbecf79f68.webp')
  ) as v (id, spot, photo)
where p.id = v.id;
