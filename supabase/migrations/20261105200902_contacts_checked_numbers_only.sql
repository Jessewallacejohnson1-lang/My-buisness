-- Contacts finds people only by a phone number a text code checked (BP app docs/plans/loopholes, ticket 14;
-- Jesse, 2026-11-05). Sign-up doesn't check an email yet ("Confirm email" is off), so every account's email counts
-- as confirmed, and someone who signed up with another person's email would show up in that person's friends'
-- Contacts under their own name and photo. The app still sends its contacts' scrambled emails: they are counted
-- against the cap and otherwise ignored. Ticket 17 brings emails back when sign-up checks them.

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
      select u.id, encode(sha256(convert_to(regexp_replace(u.phone, '\D', '', 'g'), 'UTF8')), 'hex') as phone_code
      from auth.users u
      where u.phone is not null and u.phone_confirmed_at is not null
    ), hits as materialized (
      select x.id, x.phone_code as code
      from scrambled x
      where x.phone_code = any (coalesce(p_phones, '{}'))
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
