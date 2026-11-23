-- Private Groups (BP app docs/plans/start-a-group, ticket 03), a fix from the review: a yes kept its request row,
-- so someone let in who later left could never ask again (ask_to_join's insert met the old row and did nothing).
-- A yes now takes the ask away once they're in; a no is still kept, so a turned-down asker can't ask again.

create or replace function public.answer_join(p_club uuid, p_user uuid, p_yes boolean)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  me uuid := private.need_real();
begin
  if not exists (select 1 from public.clubs c where c.id = p_club and c.submitted_by = me) then
    raise exception 'only the Admin answers' using errcode = '42501';
  end if;
  if p_yes then
    delete from private.club_requests where club_id = p_club and user_id = p_user and answer is null;
    if found then
      insert into public.club_members (club_id, user_id) values (p_club, p_user) on conflict do nothing;
    end if;
  else
    update private.club_requests set answer = 'no', answered_at = now()
    where club_id = p_club and user_id = p_user and answer is null;
  end if;
end;
$$;

delete from private.club_requests where answer = 'yes';
