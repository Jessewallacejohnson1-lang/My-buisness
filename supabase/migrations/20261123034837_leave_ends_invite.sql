-- Leaving a Group ends the invite that let you in (BP app docs/plans/start-a-group, ticket 09 item 1; Jesse's yes). The
-- invite outlived the membership, and private.sees_group counts an invite as being in, so someone invited who joined a
-- private Group (or one still waiting on its checks) and left went on reading its members, Calendar, Events and
-- get-togethers, and could walk back in. Now the row goes as the membership does, by whatever path: every app's leave
-- is a delete on club_members. Someone invited who hasn't joined keeps theirs, and a fresh invite or an approved ask
-- works again.
--
-- Nothing already live changes. Someone who left before this keeps an old invite: nothing kept says whether they ever
-- joined, so they can't be told from someone yet to answer. To read how many rows could be one:
--   select count(*) from private.club_invites i join public.clubs c on c.id = i.club_id
--   where (c.private or c.status = 'pending')
--     and not exists (select 1 from public.club_members m where m.club_id = i.club_id and m.user_id = i.user_id);

create function private.leaving_ends_invite()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from private.club_invites where club_id = old.club_id and user_id = old.user_id;
  return null;
end;
$$;
revoke execute on function private.leaving_ends_invite() from public;
create trigger leaving_ends_invite after delete on public.club_members
  for each row execute function private.leaving_ends_invite();
