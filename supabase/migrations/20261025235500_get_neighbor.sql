-- One neighbour by id, as search_neighbors answers them: for a page opened from a list that
-- knows only who they are (BP app docs/plans/follows, ticket 05: a Following row opens their
-- page). Nobody when they can't be found (blocked, anonymous, nameless). Real accounts only.
create function public.get_neighbor(p_user uuid)
returns table (user_id uuid, display_name text, avatar_url text, since timestamptz,
               relation text, mutual_friends int, friends_since timestamptz)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  me uuid := private.need_real();
begin
  if not private.findable(p_user) then
    return;
  end if;
  return query select r.* from private.neighbor_row(me, p_user) r;
end;
$$;

revoke execute on function public.get_neighbor(uuid) from public, anon;
grant execute on function public.get_neighbor(uuid) to authenticated;
