-- Contacts (BP app docs/plans/friends, ticket 06): which of your phone's contacts are on Block Party.
--
-- The phone sends only scrambled codes: the SHA-256 (hex) of each contact's lower-cased, trimmed
-- email, and of each phone number's digits with the country code (US numbers get a leading 1).
-- Here they're compared with the same codes of real accounts' emails, and of phone numbers a text
-- code has checked (friends 08; none yet). Nothing the phone sends is stored. Only how many checks
-- an account made today is, so nobody can fish for who owns an email: 5 checks a day, at most 2,000
-- contacts each. A refused check rolls its own count back, so the count stays at 5.
--
-- Never matched: anyone `private.findable` says no to (you, anonymous, nameless, banned, blocked
-- either way) and anyone who turned off "Suggest me to people I may know" (Jesse, 2026-10-22: one
-- switch for both).

create table private.contact_checks (
  user_id uuid not null references auth.users (id) on delete cascade,
  day date not null default current_date,
  checks int not null default 1,
  primary key (user_id, day)
);
revoke all on private.contact_checks from public, anon, authenticated;

-- ponytail: scrambles every account's email and checked phone on each call. Fine at a Town's size;
-- store the codes in a column with an index once accounts pass ~50k.
create function public.match_contacts(p_emails text[], p_phones text[])
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
  insert into private.contact_checks as c (user_id) values (me)
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
             case when u.email is not null
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

revoke execute on function public.match_contacts(text[], text[]) from public, anon;
grant execute on function public.match_contacts(text[], text[]) to authenticated;
