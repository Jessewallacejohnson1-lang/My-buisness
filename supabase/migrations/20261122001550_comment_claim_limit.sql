-- BP app backlog 38, Check-in 2 (Jesse's yes, 2026-11-21): the comment check tells the day's 50 apart from a comment it
-- can't check (sent twice, a post gone, a block), so only the first says "You've hit today's limit." claim_comment
-- now answers 'claimed', 'limit' or 'no' (claim_edit's shape) in place of true / false.

drop function public.claim_comment(uuid, uuid);

create function public.claim_comment(p_comment uuid, p_user uuid)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_claimed boolean;
begin
  perform pg_advisory_xact_lock(hashtextextended('claim_comment:' || p_user::text, 0));
  if (select count(*) from private.comment_checks
      where user_id = p_user and at > now() - interval '24 hours') >= 50 then
    return 'limit';
  end if;
  with c as (
    update public.event_comments c
    set checked_at = now(),
        created_at = now(),
        at_names = private.comment_at_names(p_user, c.event_id, c.body, c.at_names)
    where c.id = p_comment and c.user_id = p_user and c.status = 'pending' and c.checked_at is null
      and exists (select 1 from public.club_events e
                  where e.id = c.event_id and e.kind = 'post' and e.status = 'approved'
                    and not private.blocked_between(p_user, e.submitted_by)
                    and (not e.friends_only or e.submitted_by = p_user
                         or exists (select 1 from private.friendships f
                                    where f.a = least(p_user, e.submitted_by) and f.b = greatest(p_user, e.submitted_by))))
    returning 1
  )
  select exists (select 1 from c) into v_claimed;
  if not v_claimed then
    return 'no';
  end if;
  insert into private.comment_checks (user_id) values (p_user);
  return 'claimed';
end
$$;
revoke execute on function public.claim_comment(uuid, uuid) from public, anon, authenticated;
grant execute on function public.claim_comment(uuid, uuid) to service_role;
