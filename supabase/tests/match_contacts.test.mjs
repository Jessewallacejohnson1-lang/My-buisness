// Fixed stories for Contacts (supabase/migrations/*_match_contacts.sql): who your scrambled contacts
// find, everyone they never find, the 5-a-day and 2,000-a-check limits, and that nothing the phone
// sends is kept (BP app docs/plans/friends, ticket 06). Run in PGlite like the others:
// `npm install && npm test` in this folder.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFileSync, readdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { PGlite } from '@electric-sql/pglite';

const here = dirname(fileURLToPath(import.meta.url));
const migrations = process.env.MIGRATIONS ?? join(here, '..', 'migrations');
const read = (suffix) => readdirSync(migrations).filter((f) => f.endsWith(suffix)).sort()
  .map((f) => readFileSync(join(migrations, f), 'utf8'));
const realAccount = read('_anonymous_accounts.sql')[0]
  .match(/create or replace function public\.is_real_account\(\)[\s\S]*?\$\$;/)[0];

const db = await PGlite.create();
await db.exec(`
  create role anon; create role authenticated;
  create schema auth;
  grant usage on schema auth to anon, authenticated;
  create function auth.jwt() returns jsonb language sql stable as
    $$ select coalesce(nullif(current_setting('request.jwt.claims', true), ''), '{}')::jsonb $$;
  create function auth.uid() returns uuid language sql stable as
    $$ select nullif(auth.jwt() ->> 'sub', '')::uuid $$;
  create table auth.users (id uuid primary key, is_anonymous boolean not null default false,
    banned_until timestamptz, email text, phone text, phone_confirmed_at timestamptz);
  create table public.town_profiles (
    user_id uuid primary key, display_name text, avatar_url text,
    onboarded_at timestamptz, created_at timestamptz not null default now());
  create table public.town_follows (
    id uuid primary key default gen_random_uuid(), follower_id uuid not null,
    target_type text not null, target_id uuid not null, created_at timestamptz not null default now(),
    unique (follower_id, target_type, target_id));
  create table public.clubs (id uuid primary key, name text not null, status text not null default 'pending');
  create table public.club_members (club_id uuid not null, user_id uuid not null, unique (club_id, user_id));
  create function public.get_feed_postings(limit_n integer default 30) returns int
    language sql as $$ select 0 $$;
  grant select, insert, update on all tables in schema public to anon, authenticated;
`);
await db.exec(realAccount);
for (const sql of [...read('_find_neighbors.sql'), ...read('_friend_requests.sql'), ...read('_unfriend_and_block.sql'),
                   ...read('_people_you_may_know.sql'), ...read('_match_contacts.sql')]) {
  await db.exec(sql);
}

const id = (n) => `00000000-0000-0000-0000-${String(n).padStart(12, '0')}`;
const [ANA, BEN, CAL, DEE, EVE, ANON, NONAME] = [1, 2, 3, 4, 5, 6, 7].map(id);
/** What the phone sends: SHA-256 hex of the lower-cased, trimmed email, or of a number's digits. */
const code = (s) => createHash('sha256').update(s).digest('hex');
const email = (e) => code(e.trim().toLowerCase());

async function reset() {
  await db.exec(`reset role; reset request.jwt.claims;
    delete from private.contact_checks; delete from private.blocks; delete from private.friend_requests;
    delete from private.friendships; delete from public.town_follows; delete from public.town_profiles;
    delete from auth.users;`);
  const people = [[ANA, 'Ana Lee', 'ana@example.com', null], [BEN, 'Ben Ortiz', 'Ben@Example.com', null],
                  [CAL, 'Cal Ruiz', 'cal@example.com', '15551230003'], [DEE, 'Dee Moss', 'dee@example.com', '15551230004'],
                  [EVE, 'Eve Park', 'eve@example.com', null]];
  for (const [who, name, mail, phone] of people) {
    // Only Cal's number was checked by a text code.
    await db.query(`insert into auth.users (id, email, phone, phone_confirmed_at)
                    values ($1, $2, $3, case when $4 then now() end)`, [who, mail, phone, who === CAL]);
    await db.query('insert into public.town_profiles (user_id, display_name) values ($1, $2)', [who, name]);
  }
  await db.query(`insert into auth.users (id, is_anonymous, email) values ($1, true, 'anon@example.com')`, [ANON]);
  await db.query(`insert into auth.users (id, email) values ($1, 'noname@example.com')`, [NONAME]);
  await db.query('insert into public.town_profiles (user_id, display_name) values ($1, $2)', [NONAME, '  ']);
}

async function as(who, sql, params = [], { anonymous = false } = {}) {
  await db.exec(`set role authenticated; set request.jwt.claims = '${JSON.stringify({ sub: who, is_anonymous: anonymous })}'`);
  try {
    return (await db.query(sql, params)).rows;
  } finally {
    await db.exec('reset role; reset request.jwt.claims');
  }
}
const match = async (who, emails = [], phones = []) =>
  (await as(who, 'select * from public.match_contacts($1, $2)', [emails, phones])).map((r) => r.display_name);

test('an anonymous account matches nothing', async () => {
  await reset();
  await assert.rejects(as(ANON, 'select * from public.match_contacts($1, $2)', [[email('ana@example.com')], []],
                          { anonymous: true }));
});

test('an email finds its account, whatever its case and spaces, A to Z', async () => {
  await reset();
  assert.deepEqual(await match(ANA, [email(' BEN@example.COM '), email('eve@example.com'), email('nobody@example.com')]),
                   ['Ben Ortiz', 'Eve Park']);
  // Each row names the code that found it, so the phone leaves that contact out of Invite.
  const rows = await as(ANA, 'select display_name, code from public.match_contacts($1, $2)',
                        [[email('eve@example.com')], [code('15551230003')]]);
  assert.deepEqual(rows.map((r) => [r.display_name, r.code]),
                   [['Cal Ruiz', code('15551230003')], ['Eve Park', email('eve@example.com')]]);
});

test('a phone number finds its account only once a text code checked it', async () => {
  await reset();
  assert.deepEqual(await match(ANA, [], [code('15551230003'), code('15551230004')]), ['Cal Ruiz']);
});

test('never yourself, anonymous, nameless, blocked either way, or someone who turned suggestions off', async () => {
  await reset();
  await as(ANA, 'select public.block_neighbor($1)', [BEN]);
  await as(CAL, 'select public.block_neighbor($1)', [ANA]);
  await db.query('update public.town_profiles set suggest_me = false where user_id = $1', [DEE]);
  const all = ['ana@example.com', 'ben@example.com', 'cal@example.com', 'dee@example.com', 'eve@example.com',
               'anon@example.com', 'noname@example.com'].map(email);
  assert.deepEqual(await match(ANA, all), ['Eve Park']);
});

test('a friend comes back marked as a friend, a request as asked', async () => {
  await reset();
  await as(ANA, 'select public.send_friend_request($1)', [BEN]);
  await as(BEN, 'select public.confirm_friend_request($1)', [ANA]);
  await as(ANA, 'select public.send_friend_request($1)', [EVE]);
  const rows = await as(ANA, 'select display_name, relation from public.match_contacts($1, $2)',
                        [[email('ben@example.com'), email('eve@example.com')], []]);
  const relations = rows.map((r) => [r.display_name, r.relation]);
  assert.equal(relations.length, 2);
  assert.equal(relations[0][0], 'Ben Ortiz');
  assert.notEqual(relations[0][1], relations[1][1], 'a friend and a request read differently');
});

test('5 checks a day, then refused, and the count stays at 5', async () => {
  await reset();
  for (let i = 0; i < 5; i++) await match(ANA, [email('eve@example.com')]);
  await assert.rejects(match(ANA, [email('eve@example.com')]), /contacts_limit/);
  await assert.rejects(match(ANA, [email('eve@example.com')]), /contacts_limit/);
  assert.equal((await db.query('select checks from private.contact_checks where user_id = $1', [ANA])).rows[0].checks, 5);
  // Another account has its own 5.
  assert.deepEqual(await match(BEN, [email('eve@example.com')]), ['Eve Park']);
});

test('more than 2,000 contacts in one check is refused and not counted', async () => {
  await reset();
  const many = Array.from({ length: 2001 }, (_, i) => email(`p${i}@example.com`));
  await assert.rejects(match(ANA, many), /contacts_too_many/);
  assert.equal((await db.query('select count(*)::int as n from private.contact_checks')).rows[0].n, 0);
});

test('nothing the phone sends is kept: only the count of checks is written', async () => {
  await reset();
  const tables = async () => (await db.query(`select table_schema || '.' || table_name as t from information_schema.tables
                                              where table_schema in ('public', 'private', 'auth')
                                                and table_type = 'BASE TABLE' order by 1`)).rows.map((r) => r.t);
  const counts = async () => {
    const out = {};
    for (const t of await tables()) out[t] = (await db.query(`select count(*)::int as n from ${t}`)).rows[0].n;
    return out;
  };
  const before = await counts();
  await match(ANA, [email('eve@example.com'), email('zed@example.com')], [code('15559990000')]);
  const after = await counts();
  for (const t of Object.keys(before)) {
    assert.equal(after[t], before[t] + (t === 'private.contact_checks' ? 1 : 0), t);
  }
  const row = (await db.query('select * from private.contact_checks')).rows[0];
  assert.deepEqual(Object.keys(row).sort(), ['checks', 'day', 'user_id']);
});
