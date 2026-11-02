-- A friend tagged in a post sees their own name on it (town-feed 29, BP app references/post-screen): the
-- tagged list kept only names `findable` by the reader, and `findable` leaves out the reader themselves,
-- so Blake's own tag was missing from the post he was tagged in (proof, 2026-11-02). post_poster from
-- 20261102005713_post_screen_feed.sql, line for line but for that.
create or replace function private.post_poster(p_user uuid, p_tagged uuid[])
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'id', p.user_id,
    'name', btrim(p.display_name),
    'photo', case when p.avatar_url like 'https://lxdgwhvqjqmqliobwjpi.supabase.co/storage/v1/object/public/avatars/'
                                        || p.user_id::text || '/%' then p.avatar_url end,
    'tagged', coalesce((select jsonb_agg(jsonb_build_object('id', t.user_id, 'name', btrim(t.display_name))
                                         order by array_position(p_tagged, t.user_id))
                        from public.town_profiles t
                        where t.user_id = any (p_tagged)
                          and (t.user_id = auth.uid() or private.findable(t.user_id))), '[]'::jsonb))
  from public.town_profiles p
  where p.user_id = p_user
$$;
revoke execute on function private.post_poster(uuid, uuid[]) from public;
grant execute on function private.post_poster(uuid, uuid[]) to anon, authenticated;
