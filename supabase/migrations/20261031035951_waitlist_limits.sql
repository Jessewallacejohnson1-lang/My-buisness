-- Waitlist limits (BP app docs/plans/loopholes, ticket 06). The website's bot trap only works in a
-- browser, so anyone with the public key could post signups straight to the table and pump the
-- public count. Each email was already in once only (waitlist_email_lower_idx). Applied live only
-- with Jesse's yes.

-- 1. The website sends five fields. id and created_at are the database's own, so a row can't be
-- backdated past the cap below, or out of the morning email's "new today".
revoke insert on public.waitlist from anon;
grant insert (email, first_name, town, business_name, business_kind) on public.waitlist to anon;

-- 2. At most 10 signups a minute, everyone together; the busiest minute so far had 2. A refused
-- signup is never saved, so the public count never sees it. PT429 reaches the website as HTTP 429,
-- which it already shows as "Something went wrong. Try again in a moment."
-- ponytail: one cap for every town; a per-town cap when a second town's launch could pass 10 a minute.
-- Security definer: nobody reads this table through the API, the caller included.
create or replace function private.waitlist_per_minute()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- One signup at a time, so a burst sent all at once can't pass the count together.
  perform pg_advisory_xact_lock(hashtext('public.waitlist'));
  if (select count(*) from public.waitlist where created_at > now() - interval '1 minute') >= 10 then
    raise sqlstate 'PT429' using message = 'Too many waitlist signups this minute';
  end if;
  return new;
end
$$;
revoke execute on function private.waitlist_per_minute() from public, anon, authenticated;

create trigger waitlist_per_minute
  before insert on public.waitlist
  for each row execute function private.waitlist_per_minute();
