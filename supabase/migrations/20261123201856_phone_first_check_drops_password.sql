-- Phone sign-in (BP app onboarding 17): no password put on a number before its owner joined still opens it.
--
-- With the public key, anyone can POST /auth/v1/signup with someone else's number and a password of their own. That
-- leaves an unchecked account holding the password. When the number's owner then types their texted code, Supabase
-- confirms that same account and keeps the password (GoTrue's signup.go and ConfirmPhone, read 2026-11-23), so the
-- stranger could log in with it. An account with no email signs in by code only, so its password goes the moment its
-- number is first checked. One with an email chose its own password while signed in, and keeps it.
create or replace function private.phone_checked()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.encrypted_password := '';
  return new;
end;
$$;
revoke execute on function private.phone_checked() from public, anon, authenticated;

create trigger phone_checked
  before update of phone_confirmed_at on auth.users
  for each row
  when (old.phone_confirmed_at is null and new.phone_confirmed_at is not null and nullif(new.email, '') is null)
  execute function private.phone_checked();
