-- @ names (BP app town-feed 60), the review: a place's name as Search shows it can drop a word from the middle of
-- its own ("CentraCare - St. Joseph Clinic" shows as "CentraCare Clinic"; 4 open places, read 2026-11-11), and the
-- check dropped that name. Now every word of the name shown must be in the place's own name, in any order.
-- checked_at_names from 20261111233423_at_names.sql, line for line but for that.
create or replace function private.checked_at_names(p_user uuid, p_title text, p_names jsonb)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  with a as (
    select x.v, x.n, x.v->>'kind' as kind, lower(x.v->>'id') as id, x.v->>'name' as name
    from jsonb_array_elements(case when jsonb_typeof(p_names) = 'array' then p_names else '[]'::jsonb end)
         with ordinality x(v, n)
    where jsonb_typeof(x.v) = 'object' and char_length(btrim(coalesce(x.v->>'name', ''))) > 0
      and strpos(coalesce(p_title, ''), '@' || (x.v->>'name')) > 0
  ),
  kept as (
    select 'user' as kind, t.user_id::text as id, a.n,
           jsonb_build_object('kind', 'user', 'id', t.user_id, 'name', a.name) as v
    from a
    join public.town_profiles t on t.user_id::text = a.id
    where a.kind = 'user' and strpos(coalesce(t.display_name, ''), a.name) > 0
      and exists (select 1 from private.friendships f
                  where f.a = least(p_user, t.user_id) and f.b = greatest(p_user, t.user_id))
    union all
    select 'place', pl.id::text, a.n, jsonb_build_object('kind', 'place', 'id', pl.id, 'name', a.name)
    from a
    join public.places pl on pl.id::text = a.id
    where a.kind = 'place' and pl.closed_at is null
      -- Every word of the name shown is in the place's own: Search drops " Company", " Restaurant", " - St. Joseph"
      -- and " | Italian" anywhere, so CentraCare - St. Joseph Clinic shows as "CentraCare Clinic".
      and not exists (select 1 from regexp_split_to_table(btrim(a.name), '\s+') w where strpos(pl.name, w) = 0)
  )
  select jsonb_agg(k.v order by k.n)
  from (select distinct on (kind, id) v, n from kept order by kind, id, n) k
$$;
revoke execute on function private.checked_at_names(uuid, text, jsonb) from public, anon, authenticated;
