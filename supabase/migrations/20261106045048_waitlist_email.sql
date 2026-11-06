-- The daily waitlist email runs in the database, not on Jesse's Mac (BP app docs/plans/loopholes, ticket 07). About
-- half the Mac's runs failed asleep or offline. Subject and body are word for word what scripts/waitlist-digest.ts's
-- digest() made in the website repo. It sends through the Vault secret 'morning_check', the same way as
-- private.morning_check, so it goes to the address there, and only there.
-- Ceiling: if the send fails, the cron run fails and nobody hears; the next morning's window still covers the missed day.

-- When the last email went out: the next one's "Since". Starts from the Mac's ~/.blockparty-digest-last-run.
create table private.waitlist_email_sent (one boolean primary key default true check (one), sent_at timestamptz not null);
insert into private.waitlist_email_sent (sent_at) values ('2026-11-05T14:00:13.182Z');

-- One line per town since p_since: most signups first, then by name, as the script's localeCompare put them.
-- Spelled out because the live database and the stories' sort text differently by default.
create or replace function private.waitlist_towns(p_since timestamptz)
returns text[]
language sql
stable
set search_path = ''
as $$
  select coalesce(array_agg(format('  %s  %s', t.n, t.town)
                            order by t.n desc, lower(t.town) collate "C", t.town collate "C" desc), '{}')
  from (select w.town, count(*) as n from public.waitlist w where w.created_at > p_since group by w.town) t
$$;

create or replace function private.waitlist_digest(p_since timestamptz, out subject text, out body text)
language plpgsql
stable
set search_path = ''
as $$
declare
  v_new int;
  v_new_owners int;
  v_all int;
  v_all_owners int;
  v_lines text[];
begin
  select count(*) filter (where w.created_at > p_since),
         count(*) filter (where w.created_at > p_since and w.business_name <> ''),
         count(*),
         count(*) filter (where w.business_name <> '')
    into v_new, v_new_owners, v_all, v_all_owners
  from public.waitlist w;

  v_lines := array[
    format('Since %s: %s new (%s business, %s neighbour)', to_char(p_since at time zone 'America/Chicago', 'Mon FMDD'),
           v_new, v_new_owners, v_new - v_new_owners),
    format('On the list: %s total (%s business, %s neighbour)', v_all, v_all_owners, v_all - v_all_owners),
    ''];

  if v_new > 0 then
    v_lines := v_lines || 'New signups'::text || array(
      select format('  %s, %s%s', w.first_name, w.town,
                    case when w.business_name <> '' then
                      ' — ' || w.business_name
                            || case when w.business_kind <> '' then ' (' || w.business_kind || ')' else '' end
                    else '' end)
      from public.waitlist w
      where w.created_at > p_since
      order by w.created_at desc)
      || ''::text || 'New by town'::text || private.waitlist_towns(p_since) || ''::text;
  end if;

  v_lines := v_lines || 'All-time by town'::text || (private.waitlist_towns('-infinity'))[1:10];

  subject := format('Block Party waitlist — %s new, %s total', v_new, v_all);
  body := array_to_string(v_lines, E'\n');
end;
$$;

create or replace function private.waitlist_email(p_now timestamptz default now())
returns void
language plpgsql
set search_path = ''
as $$
declare
  v_since timestamptz;
  v_mail record;
  v_secret jsonb;
  v_status int;
  v_body text;
begin
  -- pg_cron keeps UTC, so the job comes at 13:00 and 14:00 and only the one that is 8:00 in Chicago sends.
  if extract(hour from p_now at time zone 'America/Chicago') <> 8 then return; end if;

  select s.sent_at into strict v_since from private.waitlist_email_sent s;
  select d.subject, d.body into v_mail from private.waitlist_digest(v_since) d;

  select s.decrypted_secret::jsonb into v_secret from vault.decrypted_secrets s where s.name = 'morning_check';
  if v_secret is null then raise exception 'waitlist email: no morning_check secret in Vault'; end if;

  perform extensions.http_set_curlopt('CURLOPT_TIMEOUT', '30');
  select r.status, r.content into v_status, v_body
  from extensions.http(('POST', 'https://backend.composio.dev/api/v3.1/tools/execute/GMAIL_SEND_EMAIL',
    array(select extensions.http_header(h.key, h.value) from jsonb_each_text(v_secret -> 'headers') h),
    'application/json',
    jsonb_strip_nulls(jsonb_build_object('connected_account_id', v_secret ->> 'account', 'user_id', v_secret ->> 'user',
      'arguments', jsonb_build_object(
        'recipient_email', v_secret ->> 'to',
        'subject', v_mail.subject,
        'body', v_mail.body,
        'is_html', false)))::text)::extensions.http_request) r;
  if v_status not between 200 and 299 then
    raise exception 'waitlist email answered %: %', v_status, left(v_body, 300);
  end if;
  if (v_body::jsonb ->> 'successful') is distinct from 'true' then
    raise exception 'waitlist email not sent: %', left(v_body, 300);
  end if;

  -- p_now, not the time after sending: someone who signs up during the send is in tomorrow's email.
  update private.waitlist_email_sent set sent_at = p_now;
end;
$$;

revoke all on table private.waitlist_email_sent from public, anon, authenticated;
revoke execute on function private.waitlist_towns(timestamptz) from public, anon, authenticated;
revoke execute on function private.waitlist_digest(timestamptz) from public, anon, authenticated;
revoke execute on function private.waitlist_email(timestamptz) from public, anon, authenticated;

select cron.schedule('waitlist-email', '0 13,14 * * *', $$select private.waitlist_email()$$);
