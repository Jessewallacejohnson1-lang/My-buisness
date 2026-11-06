-- The rows half of Settings' Delete account (BP app docs/plans/launch-ready, ticket 01; Jesse, 2026-11-06). The
-- delete-account edge function calls this, removes the files, then deletes the account. club_events.submitted_by is
-- `on delete set null`, so deleting the account alone leaves a person's posts up with no author.
--
-- An upcoming Event other people are Going to is Canceled rather than deleted, so they hear about it from
-- get_my_changes, which reads cancelled_at off the row, and it doesn't vanish from their plans. Its photo goes because
-- its file is about to, and the account's delete blanks its author. Everything else they posted goes. A Group they
-- submitted stays, because other people are in it.
--
-- It answers with the chat photos of theirs that a report still open names, for the function to leave in place: a
-- report is meant to outlive the account, or deleting one would erase the evidence.
--
-- Safe to run again, so a retry can finish a delete that stopped partway.
create function public.clear_account_rows(p_user uuid)
returns text[]
language plpgsql
security definer
set search_path = ''
as $$
begin
  with kept as (
    update public.club_events e
    set cancelled_at = coalesce(e.cancelled_at, now()), image_url = null
    where e.submitted_by = p_user and e.kind = 'event' and e.status = 'approved'
      and e.event_date >= private.town_today()
      and exists (select 1 from public.event_rsvps r where r.event_id = e.id and r.user_id <> p_user)
    returning e.id
  )
  delete from public.club_events e
  where e.submitted_by = p_user and e.id not in (select k.id from kept k);

  return array(select c.photo_path from private.chat_reports c
               where c.resolved_at is null and split_part(c.photo_path, '/', 1) = p_user::text);
end;
$$;

revoke all on function public.clear_account_rows(uuid) from public, anon, authenticated;
grant execute on function public.clear_account_rows(uuid) to service_role;
