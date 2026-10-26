-- 20261023120000_team_follows.sql's my_follows, with a person's photo only from their own folder of
-- our avatars bucket, as private.neighbor_row draws it (BP app docs/plans/follows, ticket 06): a
-- profile may store any address, and the Following list would fetch it from that server.
create or replace function public.my_follows()
returns table (target_type text, target_id uuid, name text, kind text, picture text, picture_kind text)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  me uuid := private.need_real();
begin
  return query
    select x.* from (
      select 'profile'::text, t.target_id, p.display_name, null::text,
             case when p.avatar_url like 'https://lxdgwhvqjqmqliobwjpi.supabase.co/storage/v1/object/public/avatars/'
                                         || p.user_id::text || '/%' then p.avatar_url end,
             'photo'::text
      from public.town_follows t
      join public.town_profiles p on p.user_id = t.target_id
      where t.follower_id = me and t.target_type = 'profile' and private.findable(t.target_id)
      union all
      select 'place'::text, t.target_id, pl.name, pl.primary_type, pic ->> 'url', pic ->> 'kind'
      from public.town_follows t
      join public.places pl on pl.id = t.target_id
      cross join lateral (select public.place_picture(pl.entry_id) as pic) pp
      where t.follower_id = me and t.target_type = 'place'
      union all
      select 'team'::text, t.target_id, tm.short_name, 'team'::text, tm.logo_url, 'logo'::text
      from public.town_follows t
      join public.teams tm on tm.uuid = t.target_id
      where t.follower_id = me and t.target_type = 'team'
    ) x (target_type, target_id, name, kind, picture, picture_kind)
    order by lower(x.name), x.target_id;
end;
$$;
