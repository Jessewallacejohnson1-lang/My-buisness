-- BP app backlog 20: Kennedy Community School's live logo row (place_photos 190) names a file Storage no longer has
-- (HTTP 400), so the Town feed's Kennedy cards showed no host mark. Point it at the file places.search_logo already
-- uses (the same lit K, 512 x 512). Reverse: the same update with the two addresses and 800 x 800 swapped back.
update public.place_photos
   set url = 'https://lxdgwhvqjqmqliobwjpi.supabase.co/storage/v1/object/public/places/st-joseph/kennedy-community-school/logo-d43aad30.webp',
       width = 512, height = 512
 where id = 190
   and url = 'https://lxdgwhvqjqmqliobwjpi.supabase.co/storage/v1/object/public/places/st-joseph/kennedy-community-school/logo-14e0e9e7e8.webp';
