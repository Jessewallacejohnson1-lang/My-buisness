// Fixed stories for the Anonymous-account clean-up (supabase/migrations/*_anonymous_clean_up.sql, BP app
// docs/plans/town-feed, ticket 25), run in PGlite with stand-ins for Supabase's auth tables and pg_cron. An
// Anonymous account with no sign of life for 90 days goes, with every row tied to it, and the Going counts it
// was part of drop; anything newer, and every real account, stays. Run: `npm test` in this folder.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { PGlite } from '@electric-sql/pglite';
import { creating } from './migrations.mjs';

const migrations = process.env.MIGRATIONS ?? new URL('../migrations', import.meta.url).pathname;
const read = (f) => readFileSync(join(migrations, f), 'utf8');
const files = creating(migrations, ['private.clean_up_anonymous_accounts']);

const db = await PGlite.create();
await db.exec(`
  set timezone = 'UTC';
  create role anon; create role authenticated;
  create schema auth; create schema private; create schema cron;
  -- Supabase's own auth tables, the columns the clean-up reads. refreshed_at has no time zone there too.
  create table auth.users (id uuid primary key, is_anonymous boolean not null default false,
    created_at timestamptz, last_sign_in_at timestamptz);
  create table auth.sessions (id uuid primary key default gen_random_uuid(),
    user_id uuid not null references auth.users (id) on delete cascade,
    created_at timestamptz, updated_at timestamptz, refreshed_at timestamp);
  -- pg_cron: the stand-in keeps each job and whether it is switched on.
  create table cron.job (jobid bigserial primary key, jobname text, schedule text, command text,
    active boolean not null default true);
  create function cron.schedule(name text, sched text, cmd text) returns bigint language sql as
    $$ insert into cron.job (jobname, schedule, command) values (name, sched, cmd) returning jobid $$;
  create function cron.alter_job(job_id bigint, schedule text default null, command text default null,
    database text default null, username text default null, active boolean default null)
    returns void language sql as
    $$ update cron.job set active = coalesce(alter_job.active, cron.job.active) where jobid = job_id $$;

  -- The app's tables tied to an account, with their live foreign keys (schema.sql and later files).
  create table public.club_events (id uuid primary key default gen_random_uuid(), title text,
    submitted_by uuid references auth.users (id) on delete set null);
  create table public.event_rsvps (id uuid primary key default gen_random_uuid(),
    event_id uuid not null references public.club_events (id) on delete cascade,
    user_id uuid not null references auth.users (id) on delete cascade,
    created_at timestamptz not null default now());
  create table public.event_saves (event_id uuid not null references public.club_events (id) on delete cascade,
    user_id uuid not null references auth.users (id) on delete cascade,
    created_at timestamptz not null default now(), primary key (event_id, user_id));
  create table public.feed_actions (id uuid primary key default gen_random_uuid(),
    user_id uuid not null references auth.users (id) on delete cascade,
    item_id uuid not null references public.club_events (id) on delete cascade,
    action text not null, at timestamptz not null default now());
  create table public.app_opens (user_id uuid not null references auth.users (id) on delete cascade,
    day date not null, primary key (user_id, day));
  create table public.town_profiles (user_id uuid primary key references auth.users (id) on delete cascade,
    display_name text, created_at timestamptz not null default now(), updated_at timestamptz not null default now());
  create table public.town_follows (id uuid primary key default gen_random_uuid(),
    follower_id uuid not null references auth.users (id) on delete cascade,
    target_type text not null, target_id uuid not null, created_at timestamptz not null default now());
  create table public.content_decisions (id uuid primary key default gen_random_uuid(),
    target_user_id uuid, decided_at timestamptz not null default now());
  create table private.friendships (a uuid not null references auth.users (id) on delete cascade,
    b uuid not null references auth.users (id) on delete cascade,
    requested_by uuid not null references auth.users (id) on delete cascade,
    created_at timestamptz not null default now(), primary key (a, b));
`);
for (const f of creating(migrations, ['private.going_count'])) {
  await db.exec(read(f).match(/create or replace function private\.going_count\([\s\S]*?\$\$;/)[0]);
}
for (const f of files) await db.exec(read(f));

// The accounts, by when each was last seen.
const OLD_ANON = '00000000-0000-0000-0000-0000000000a1';     // last seen 91 days ago: goes
const RECENT_ANON = '00000000-0000-0000-0000-0000000000a2';  // last seen 89 days ago: stays
const IDLE_REAL = '00000000-0000-0000-0000-0000000000b1';    // a real account idle 200 days: stays
const REFRESHED = '00000000-0000-0000-0000-0000000000a3';    // signed in 120 days ago, session refreshed yesterday
const BUSY_ANON = '00000000-0000-0000-0000-0000000000a4';    // signed in 120 days ago, Going yesterday
const EVENT = '00000000-0000-0000-0000-00000000e001';

const ago = (days) => `now() - interval '${days} days'`;
await db.exec(`
  insert into auth.users values
    ('${OLD_ANON}', true, ${ago(150)}, ${ago(91)}),
    ('${RECENT_ANON}', true, ${ago(150)}, ${ago(89)}),
    ('${IDLE_REAL}', false, ${ago(400)}, ${ago(200)}),
    ('${REFRESHED}', true, ${ago(130)}, ${ago(120)}),
    ('${BUSY_ANON}', true, ${ago(130)}, ${ago(120)});
  insert into auth.sessions (user_id, created_at, updated_at, refreshed_at) values
    ('${OLD_ANON}', ${ago(91)}, ${ago(91)}, (${ago(91)}) at time zone 'UTC'),
    ('${REFRESHED}', ${ago(120)}, ${ago(120)}, (${ago(1)}) at time zone 'UTC');
  insert into public.club_events (id, title) values ('${EVENT}', 'Trivia night');
  insert into public.event_rsvps (event_id, user_id, created_at) values
    ('${EVENT}', '${OLD_ANON}', ${ago(95)}), ('${EVENT}', '${RECENT_ANON}', ${ago(95)}),
    ('${EVENT}', '${IDLE_REAL}', ${ago(200)}), ('${EVENT}', '${BUSY_ANON}', ${ago(1)});
  insert into public.event_saves (event_id, user_id, created_at) values ('${EVENT}', '${OLD_ANON}', ${ago(95)});
  insert into public.feed_actions (user_id, item_id, action, at) values
    ('${OLD_ANON}', '${EVENT}', 'view', ${ago(92)}), ('${OLD_ANON}', '${EVENT}', 'open', ${ago(92)});
  insert into public.app_opens values ('${OLD_ANON}', (${ago(92)})::date);
  insert into public.town_profiles (user_id, display_name, created_at, updated_at) values
    ('${OLD_ANON}', 'Sam', ${ago(100)}, ${ago(100)});
  -- A real account follows the old anonymous profile: tied to it by target, with no foreign key.
  insert into public.town_follows (follower_id, target_type, target_id, created_at) values
    ('${IDLE_REAL}', 'profile', '${OLD_ANON}', ${ago(200)});
  insert into public.content_decisions (target_user_id, decided_at) values ('${OLD_ANON}', ${ago(100)});
  insert into private.friendships (a, b, requested_by, created_at) values
    ('${OLD_ANON}', '${IDLE_REAL}', '${IDLE_REAL}', ${ago(100)});
`);

const one = async (sql, params = []) => (await db.query(sql, params)).rows[0];
const going = async () => (await one(`select private.going_count($1) n`, [EVENT])).n;
const users = async () => (await db.query(`select id from auth.users order by id`)).rows.map((r) => r.id);
const run = async (dry) => (await one(`select private.clean_up_anonymous_accounts(p_dry_run => $1) r`, [dry])).r;

// The rows tied to OLD_ANON: 1 Going, 1 save, 2 feed actions, 1 open, 1 profile, 1 follow of it,
// 1 content decision, 1 friendship.
const OLD_ANON_ROWS = 9;

test('the clean-up migration exists', () => {
  assert.ok(files.length > 0, 'no migration makes private.clean_up_anonymous_accounts');
});

test('a dry run deletes nothing and reports what a real run would remove', async () => {
  const before = { users: await users(), going: await going() };
  const r = await run(true);
  assert.equal(r.dry_run, true);
  assert.equal(r.accounts, 1);
  assert.equal(r.rows, OLD_ANON_ROWS);
  assert.deepEqual(await users(), before.users, 'a dry run deletes no account');
  assert.equal(await going(), before.going, 'a dry run changes no Going count');
  assert.equal((await one(`select count(*)::int n from public.town_follows`)).n, 1);
});

test('only the anonymous account last seen 91 days ago goes, with every row tied to it', async () => {
  assert.equal(await going(), 4);
  const r = await run(false);
  assert.equal(r.dry_run, false);
  assert.equal(r.accounts, 1, 'one account removed');
  assert.equal(r.rows, OLD_ANON_ROWS, 'the same rows the dry run counted');
  assert.equal(await going(), 3, 'its Going no longer counts');
  assert.deepEqual(await users(), [RECENT_ANON, REFRESHED, BUSY_ANON, IDLE_REAL].sort(),
    'seen 89 days ago, a session refreshed yesterday, Going yesterday and a real account all stay');
  for (const t of ['public.event_rsvps', 'public.event_saves', 'public.feed_actions', 'public.app_opens',
    'public.town_profiles', 'auth.sessions']) {
    assert.equal((await one(`select count(*)::int n from ${t} where user_id = $1`, [OLD_ANON])).n, 0, t);
  }
  assert.equal((await one(`select count(*)::int n from public.town_follows where target_id = $1`, [OLD_ANON])).n, 0);
  assert.equal((await one(`select count(*)::int n from public.content_decisions where target_user_id = $1`, [OLD_ANON])).n, 0);
  assert.equal((await one(`select count(*)::int n from private.friendships`)).n, 0);
  assert.equal((await one(`select count(*)::int n from public.club_events`)).n, 1, 'the Event itself stays');
  assert.equal((await one(`select count(*)::int n from auth.sessions where user_id = $1`, [REFRESHED])).n, 1);
});

test('a second run finds nothing more', async () => {
  const r = await run(false);
  assert.equal(r.accounts, 0);
  assert.equal(r.rows, 0);
});

test('a real account is never removed, however long it is idle', async () => {
  await db.exec(`update auth.users set last_sign_in_at = ${ago(1000)}, created_at = ${ago(1000)}
                 where id = '${IDLE_REAL}'; delete from public.event_rsvps where user_id = '${IDLE_REAL}';`);
  assert.equal((await run(false)).accounts, 0);
  assert.ok((await users()).includes(IDLE_REAL));
});

test('the nightly job is created switched off', async () => {
  const job = await one(`select schedule, command, active from cron.job where jobname = 'anonymous-clean-up'`);
  assert.ok(job, 'the job exists');
  assert.equal(job.active, false, 'applying the migration changes nothing until Jesse switches it on');
  assert.match(job.command, /private\.clean_up_anonymous_accounts\(\)/);
  assert.equal(job.schedule, '0 9 * * *');
});

test('nobody but the database itself can run the clean-up', async () => {
  for (const role of ['anon', 'authenticated']) {
    await db.exec(`set role ${role}`);
    await assert.rejects(db.query(`select private.clean_up_anonymous_accounts(true)`), /permission denied/);
    await db.exec('reset role');
  }
});
