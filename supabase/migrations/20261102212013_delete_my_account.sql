-- A person deletes their own account, and only their own (BP app onboarding 27). "Come back when
-- you're 13"'s Close calls it: onboarding makes the account before the birthday step, and "We
-- didn't save anything you entered" has to stay true. Everything tied to an account goes with it:
-- each table's user id cascades or blanks itself. Apple's Delete account row can call it later.
create or replace function public.delete_my_account()
returns void
language sql
security definer
set search_path = ''
as $$
  delete from auth.users where id = auth.uid();
$$;

revoke all on function public.delete_my_account() from public, anon;
grant execute on function public.delete_my_account() to authenticated;
