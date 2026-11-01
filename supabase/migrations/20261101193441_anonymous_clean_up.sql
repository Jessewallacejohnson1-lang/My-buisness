-- Anonymous-account clean-up (BP app docs/plans/town-feed, ticket 25). Every install gets a quiet
-- Anonymous account (20261009220000_anonymous_accounts.sql), and its Going, saves and views count like
-- anyone's. One that shows no sign of life for 90 days is deleted with everything tied to it, so the
-- counts it was part of drop. A real account is never touched.
--
-- "Last sign of life" is the newest of: the account's created_at and last_sign_in_at, its sessions'
-- created, updated or refreshed time, and any timestamp on a row of the app's tables tied to it by a
-- foreign key (a Going, a view, an open, a follow, a friendship...). Erring towards keeping: a row
-- someone else wrote about the account (a friend request to it) also keeps it.
--
-- "Everything tied to it" is found from the database itself, not a list kept here: every table in
-- public or private whose foreign key to auth.users deletes with the account (ON DELETE CASCADE), so a
-- table added later is covered without touching this file. Two ties have no foreign key and are named
-- below: a follow of the account's profile (town_follows.target_id) and a content decision about it
-- (content_decisions.target_user_id). Keys that SET NULL (an Event's submitted_by) keep their row.
--
-- private.clean_up_anonymous_accounts(p_dry_run => true) only counts: it returns what a real run
-- would remove and deletes nothing. Both return {dry_run, accounts, rows, tables, cutoff}.
--
-- The nightly job is created SWITCHED OFF: applying this file changes nothing live. pg_cron runs in
-- UTC, so 09:00 UTC is 3 AM in Chicago in winter (4 AM in summer), clear of feed-views-clean-up at
-- 08:30. After a dry run Jesse is happy with, this one statement switches it on:
--
--   select cron.alter_job((select jobid from cron.job where jobname = 'anonymous-clean-up'), active := true);

create or replace function private.clean_up_anonymous_accounts(
  p_dry_run boolean default false,
  p_idle interval default interval '90 days'
)
returns jsonb
language plpgsql
set search_path = ''
as $$
declare
  v_cutoff timestamptz := now() - p_idle;
  v_ids uuid[];
  v_active uuid[];
  v_link record;
  v_n bigint;
  v_rows bigint := 0;
  v_tables jsonb := '{}';
begin
  -- Anonymous accounts whose own sign-in and sessions are all older than the cutoff. Locked, so one
  -- that signs in or becomes a real account while this runs waits for it; a missing time keeps it.
  v_ids := array(
    select u.id
    from auth.users u
    where u.is_anonymous is true
      and greatest(u.created_at, u.last_sign_in_at) < v_cutoff
      and not exists (
        select 1 from auth.sessions s
        where s.user_id = u.id
          and greatest(s.created_at, s.updated_at, s.refreshed_at at time zone 'UTC') >= v_cutoff)
    for update of u skip locked
  );

  -- Every app table tied to an account by a foreign key that deletes with it, one row per column.
  -- A newer timestamp on any row tied to an account keeps it.
  for v_link in
    select c.conrelid::regclass as rel, a.attname as col,
           (select string_agg(format('%I::timestamptz', t.attname), ', ')
            from pg_attribute t
            where t.attrelid = c.conrelid and t.attnum > 0 and not t.attisdropped
              and t.atttypid in ('timestamptz'::regtype, 'timestamp'::regtype, 'date'::regtype)) as times
    from pg_constraint c
    join pg_attribute a on a.attrelid = c.conrelid and a.attnum = c.conkey[1]
    where c.contype = 'f' and c.confrelid = 'auth.users'::regclass and c.confdeltype = 'c'
      and cardinality(c.conkey) = 1
      and c.connamespace in ('public'::regnamespace, 'private'::regnamespace)
  loop
    exit when cardinality(v_ids) = 0;
    continue when v_link.times is null;
    execute format('select array(select distinct %1$I from %2$s where %1$I = any($1) and greatest(%3$s) >= $2)',
                   v_link.col, v_link.rel, v_link.times)
      into v_active using v_ids, v_cutoff;
    v_ids := array(select unnest(v_ids) except select unnest(v_active));
  end loop;

  if cardinality(v_ids) > 0 then
    -- Each tied table once, every tie in one condition, so a row tied twice (a friendship between two
    -- old accounts) is counted once, and a dry run counts exactly what a real run deletes.
    for v_link in
      with ties as (
        select c.conrelid::regclass as rel, format('%I = any($1)', a.attname) as cond
        from pg_constraint c
        join pg_attribute a on a.attrelid = c.conrelid and a.attnum = c.conkey[1]
        where c.contype = 'f' and c.confrelid = 'auth.users'::regclass and c.confdeltype = 'c'
          and cardinality(c.conkey) = 1
          and c.connamespace in ('public'::regnamespace, 'private'::regnamespace)
        union all
        select to_regclass('public.town_follows'), '(target_type = ''profile'' and target_id = any($1))'
        where to_regclass('public.town_follows') is not null
        union all
        select to_regclass('public.content_decisions'), 'target_user_id = any($1)'
        where to_regclass('public.content_decisions') is not null
      )
      select rel, string_agg(cond, ' or ' order by cond) as cond from ties group by rel order by rel::text
    loop
      if p_dry_run then
        execute format('select count(*) from %s where %s', v_link.rel, v_link.cond) into v_n using v_ids;
      else
        execute format('delete from %s where %s', v_link.rel, v_link.cond) using v_ids;
        get diagnostics v_n = row_count;
      end if;
      v_rows := v_rows + v_n;
      if v_n > 0 then
        v_tables := v_tables || jsonb_build_object(v_link.rel::text, v_n);
      end if;
    end loop;

    -- The accounts last; their sessions and identities go with them in Supabase's own cascade.
    if not p_dry_run then
      delete from auth.users where id = any(v_ids) and is_anonymous is true;
    end if;
  end if;

  return jsonb_build_object('dry_run', p_dry_run, 'accounts', cardinality(v_ids), 'rows', v_rows,
                            'tables', v_tables, 'cutoff', v_cutoff);
end
$$;

revoke all on function private.clean_up_anonymous_accounts(boolean, interval) from public, anon, authenticated;

-- Nightly, created switched off (see the header for the statement that switches it on).
select cron.alter_job(
  cron.schedule('anonymous-clean-up', '0 9 * * *', $$select private.clean_up_anonymous_accounts()$$),
  active := false);
