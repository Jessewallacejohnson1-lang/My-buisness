-- The same hole as avatars (20261106220321): anyone with the public key could list `event-images`,
-- where a posted photo sits in a folder named by the poster's user id, friends-only posts' photos
-- included (BP app loopholes 19, Jesse's yes 2026-11-06). It holds no files yet. Now a signed-in
-- person lists only their own folder, which deleting your own post's photo also needs, and a
-- signed-out person lists nothing. The bucket stays public, so a photo's link keeps loading, and
-- moderate-post's own delete uses the secret key, which this rule doesn't bind.

drop policy "event images public read" on storage.objects;

create policy "event images own folder read" on storage.objects
  for select to authenticated
  using (bucket_id = 'event-images' and (storage.foldername(name))[1] = (select auth.uid())::text);
