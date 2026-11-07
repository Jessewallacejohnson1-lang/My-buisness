-- Admin by account, not by email (BP app docs/plans/loopholes, ticket 20). is_admin() said yes to whoever's login
-- carried one address, and sign-ups confirm themselves, so once the account holding that address was deleted (Delete
-- account, launch-ready 01) anyone could sign up with it and be admin. Now admin is a flag in one account's
-- app_metadata: only the service key writes it, every access token carries it, and deleting the account takes it away.
-- A person can write their own user_metadata, never app_metadata. Every policy and function that calls is_admin()
-- keeps calling it, and it stays a read of the token, as cheap as before.

-- Jesse's admin account, by id: an id unlocks nothing, and the address stays out of this file. It reaches his token
-- at its next refresh, or at once on a fresh log-in.
update auth.users set raw_app_meta_data = coalesce(raw_app_meta_data, '{}'::jsonb) || '{"admin": true}'::jsonb
where id = '32b7e6f2-470d-40bf-be54-d587b1df4be5';

-- Only a JSON true counts: compared as jsonb, an odd value is a plain no rather than a cast error in every policy.
create or replace function public.is_admin()
returns boolean
language sql
stable
set search_path = ''
as $$
  select coalesce(auth.jwt() -> 'app_metadata' -> 'admin' = 'true'::jsonb, false)
$$;
