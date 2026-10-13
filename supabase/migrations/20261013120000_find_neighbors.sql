-- Find neighbors (BP app docs/plans/friends, ticket 02). A neighbour's name, photo and
-- Neighbor since reach the app only through this function, and only for a real account:
-- town_profiles stays readable as your own row alone, so nobody can list the Town's people
-- without signing in. It leaves out anonymous accounts, people with no name, and the caller.
-- Blocks join it in ticket 04, the mutual-friends count in ticket 03.
-- ponytail: a person has no Town yet and St. Joseph is the only one, so search covers every
-- real account; filter by the caller's Town when a second Town opens.

create or replace function public.search_neighbors(p_words text)
returns table (user_id uuid, display_name text, avatar_url text, since timestamptz)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  -- The iPhone keyboard types a curly apostrophe: O’Brien finds O'Brien.
  words text := translate(lower(btrim(coalesce(p_words, ''))), '’', '''');
begin
  if auth.uid() is null or not public.is_real_account() then
    raise exception 'a real account is needed to find neighbors' using errcode = '42501';
  end if;
  if words = '' then
    return;
  end if;
  return query
    with named as (
      select p.user_id, btrim(p.display_name) as name, p.avatar_url, p.user_id::text as uid,
             coalesce(p.onboarded_at, p.created_at) as since,
             translate(lower(btrim(p.display_name)), '’', '''') as folded
      from public.town_profiles p
      join auth.users u on u.id = p.user_id
      where p.user_id <> auth.uid()
        and not coalesce(u.is_anonymous, false)
        and p.display_name ~ '[[:alpha:]]'
    )
    select n.user_id, n.name,
           -- Only a photo in their own folder of our avatars bucket, so a search never
           -- loads an address someone typed in (it would tell them who searched).
           case when n.avatar_url like 'https://lxdgwhvqjqmqliobwjpi.supabase.co/storage/v1/object/public/avatars/'
                                       || n.uid || '/%' then n.avatar_url end,
           -- Neighbor since: onboarding's date, or the profile's first save for accounts
           -- made after onboarding went away.
           n.since
    from named n
    where starts_with(n.folded, words)
       or exists (select 1 from regexp_split_to_table(n.folded, '\s+') w where starts_with(w, words))
    order by starts_with(n.folded, words) desc, n.folded, n.user_id
    limit 20;
end;
$$;

revoke execute on function public.search_neighbors(text) from public, anon;
grant execute on function public.search_neighbors(text) to authenticated;
