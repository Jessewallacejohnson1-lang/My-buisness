-- The bad-morning email (BP app docs/plans/loopholes, ticket 03) sends with whatever Composio key the Vault secret
-- holds. Composio's agent sign-up was down on Oct 31, so Jesse said to use his own key (Jesse, 2026-10-31: "use my
-- key"). His is a user key: it goes in other headers than a project key, and its Gmail connection needs its user
-- id beside it. So the secret 'morning_check' now carries the request's headers and that user id:
-- {"headers": {...}, "account", "user", "to"}. Swapping in a project key later is a change to the secret only.

create or replace function private.morning_check(p_now timestamptz default now())
returns void
language plpgsql
set search_path = ''
as $$
declare
  v_problems text[];
  v_secret jsonb;
  v_status int;
  v_body text;
begin
  -- pg_cron keeps UTC, so the job comes at 13:00 and 14:00 and only the one that is 8:00 in Chicago reads.
  if extract(hour from p_now at time zone 'America/Chicago') <> 8 then return; end if;
  v_problems := array(select private.morning_problems(p_now));
  if cardinality(v_problems) = 0 then return; end if;

  select s.decrypted_secret::jsonb into v_secret from vault.decrypted_secrets s where s.name = 'morning_check';
  if v_secret is null then raise exception 'morning check: no morning_check secret in Vault'; end if;

  perform extensions.http_set_curlopt('CURLOPT_TIMEOUT', '30');
  select r.status, r.content into v_status, v_body
  from extensions.http(('POST', 'https://backend.composio.dev/api/v3.1/tools/execute/GMAIL_SEND_EMAIL',
    array(select extensions.http_header(h.key, h.value) from jsonb_each_text(v_secret -> 'headers') h),
    'application/json',
    jsonb_strip_nulls(jsonb_build_object('connected_account_id', v_secret ->> 'account', 'user_id', v_secret ->> 'user',
      'arguments', jsonb_build_object(
        'recipient_email', v_secret ->> 'to',
        'subject', case when cardinality(v_problems) = 1 then 'Block Party: ' || v_problems[1]
                        else format('Block Party: %s things wrong this morning', cardinality(v_problems)) end,
        'body', '- ' || array_to_string(v_problems, E'\n- ') || E'\n\nNo email means all is well.',
        'is_html', false)))::text)::extensions.http_request) r;
  if v_status not between 200 and 299 then
    raise exception 'morning check email answered %: %', v_status, left(v_body, 300);
  end if;
  if (v_body::jsonb ->> 'successful') is distinct from 'true' then
    raise exception 'morning check email not sent: %', left(v_body, 300);
  end if;
end;
$$;

revoke execute on function private.morning_check(timestamptz) from public;
