-- A stranger can't hold your photo online (BP app town-feed 46, the review round, 2026-11-14). The several_photos rule
-- kept a file from its poster's delete while any post not refused named it, and anyone can save a pending row naming
-- any address, so a stranger's row could keep your photo up after you deleted your post. Only the poster's own posts
-- count now: the folder is theirs (<uid>/...), and so is the row. Applied live only with Jesse's yes.
create or replace function private.event_image_shown(p_name text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.club_events e
    cross join (select 'https://lxdgwhvqjqmqliobwjpi.supabase.co/storage/v1/object/public/event-images/' || p_name as url) f
    where e.status <> 'rejected' and e.submitted_by::text = split_part(p_name, '/', 1)
      and (e.image_url = f.url or f.url = any (e.more_photos)))
$$;
revoke execute on function private.event_image_shown(text) from public, anon;
grant execute on function private.event_image_shown(text) to authenticated;
