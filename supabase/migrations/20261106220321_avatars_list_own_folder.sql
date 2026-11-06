-- Anyone with the public key could list the avatars bucket, and each folder is named by a user id
-- (BP app loopholes 19, Jesse's yes 2026-11-06). Now a signed-in person lists only their own folder
-- and a signed-out person lists nothing. The bucket stays public: a photo's public link doesn't
-- read this rule, so faces keep loading everywhere, the signed-out Town feed included.

drop policy "avatars_read" on storage.objects;

create policy "avatars_read" on storage.objects
  for select to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = (auth.uid())::text);
