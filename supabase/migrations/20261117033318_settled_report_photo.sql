-- A settled report lets go of a deleted account's chat photo (BP app five-tabs 09; Jesse, 2026-11-16). Delete account
-- leaves a chat photo that an open report names, so the report keeps its evidence (clear_account_rows). Settling that
-- report now answers with the photo's path when its owner's account is gone and no other open report names it, and the
-- settle-chat-report edge function removes the file: SQL deletes on storage.objects are refused. The report keeps its
-- words either way. Otherwise as 20261104012542_chat_with_friends.sql.
drop function public.resolve_chat_report(uuid, boolean);

create function public.resolve_chat_report(p_report uuid, p_hide boolean)
returns text
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_photo text;
begin
  if not public.is_admin() then
    raise exception 'admins only' using errcode = '42501';
  end if;
  update public.chat_messages m set hidden_at = now()
  from private.chat_reports r
  where p_hide and r.id = p_report and m.id = r.message_id;
  update private.chat_reports r set resolved_at = coalesce(r.resolved_at, now()) where r.id = p_report
  returning r.photo_path into v_photo;

  if v_photo is null
     or exists (select 1 from auth.users u where u.id::text = split_part(v_photo, '/', 1))
     or exists (select 1 from private.chat_reports r where r.photo_path = v_photo and r.resolved_at is null) then
    return null;
  end if;
  return v_photo;
end;
$$;

revoke all on function public.resolve_chat_report(uuid, boolean) from public, anon;
grant execute on function public.resolve_chat_report(uuid, boolean) to authenticated;
