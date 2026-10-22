-- Contacts, after friends 06's review (BP app docs/plans/friends, ticket 06).
--
-- The day of the 5-a-day count is the Town's (St. Joseph, Central time), so "try again tomorrow"
-- means after midnight here, not 7 pm. And an email matches only once it's confirmed, as a phone
-- number does, so nobody shows up in your contacts under an email they never proved was theirs.

create or replace function private.town_today()
returns date
language sql
stable
set search_path = ''
as $$ select (now() at time zone 'America/Chicago')::date $$;
revoke execute on function private.town_today() from public, anon, authenticated;

alter table private.contact_checks alter column day set default private.town_today();

create or replace function public.match_contacts(p_emails text[], p_phones text[])
returns table (user_id uuid, display_name text, avatar_url text, since timestamptz,
               relation text, mutual_friends int, friends_since timestamptz, code text)
language plpgsql
volatile
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  me uuid := private.need_real();
  used int;
begin
  if coalesce(cardinality(p_emails), 0) + coalesce(cardinality(p_phones), 0) > 2000 then
    raise exception 'contacts_too_many';
  end if;
  insert into private.contact_checks as c (user_id, day) values (me, private.town_today())
  on conflict (user_id, day) do update set checks = c.checks + 1
  returning c.checks into used;
  if used > 5 then
    raise exception 'contacts_limit';
  end if;
  return query
    -- The codes first, then who may be found among those they matched, as `search_neighbors` does.
    -- `code`: the one the phone sent that matched, so the phone knows which contact it was and
    -- leaves them out of Invite. It tells the phone nothing it didn't send.
    with scrambled as (
      select u.id,
             case when u.email is not null and u.email_confirmed_at is not null
                  then encode(sha256(convert_to(lower(btrim(u.email)), 'UTF8')), 'hex') end as email_code,
             case when u.phone is not null and u.phone_confirmed_at is not null
                  then encode(sha256(convert_to(regexp_replace(u.phone, '\D', '', 'g'), 'UTF8')), 'hex') end as phone_code
      from auth.users u
    ), hits as materialized (
      select x.id,
             case when x.email_code = any (coalesce(p_emails, '{}')) then x.email_code else x.phone_code end as code
      from scrambled x
      where x.email_code = any (coalesce(p_emails, '{}')) or x.phone_code = any (coalesce(p_phones, '{}'))
    ), shown as (
      select h.id, h.code
      from hits h
      join public.town_profiles p on p.user_id = h.id and p.suggest_me
      where private.findable(h.id)
      limit 200
    )
    select r.*, s.code
    from shown s
    cross join lateral private.neighbor_row(me, s.id) r
    order by lower(r.display_name), r.user_id;
end;
$$;

