// Fixed stories for People you may know (supabase/migrations/*_people_you_may_know.sql): who is
// on your list and in what order, everyone who never is, and a reason that only says what both
// could already see (BP app docs/plans/daily-tab, ticket 22; town-feed ticket 15). Run in PGlite
// like the others: `npm install && npm test` in this folder.
import { test } from 'node:test';
import assert from 'node:assert/strict';
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
    banned_until timestamptz);
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
for (const sql of [...read('_find_neighbors.sql'), ...read('_friend_requests.sql'),
                   ...read('_unfriend_and_block.sql'), ...read('_people_you_may_know.sql')]) {
  await db.exec(sql);
}

const id = (n) => `00000000-0000-0000-0000-${String(n).padStart(12, '0')}`;
const [ANA, BEN, CAL, DEE, EVE, FAY, ANON] = [1, 2, 3, 4, 5, 7, 6].map(id);
const [RUNNERS, PENDING] = [id(900), id(901)];
const people = [[ANA, 'Ana Lee'], [BEN, 'Ben Ortiz'], [CAL, 'Cal Ruiz'], [DEE, 'Dee Moss'],
                [EVE, 'Eve Park'], [FAY, 'Fay Lund']];

async function reset() {
  await db.exec(`reset role; reset request.jwt.claims;
    delete from private.suggestion_hides; delete from private.blocks; delete from private.friend_requests;
    delete from private.friendships; delete from public.town_follows; delete from public.club_members;
    delete from public.clubs; delete from public.town_profiles; delete from auth.users;`);
  for (const [who, name] of people) {
    await db.query('insert into auth.users (id) values ($1)', [who]);
    await db.query('insert into public.town_profiles (user_id, display_name) values ($1, $2)', [who, name]);
  }
  await db.query('insert into auth.users (id, is_anonymous) values ($1, true)', [ANON]);
  await db.query(`insert into public.clubs values ($1, 'Running Club', 'approved'), ($2, 'Secret Club', 'pending')`,
                 [RUNNERS, PENDING]);
}

async function as(who, sql, params = [], { anonymous = false } = {}) {
  await db.exec(`set role authenticated; set request.jwt.claims = '${JSON.stringify({ sub: who, is_anonymous: anonymous })}'`);
  try {
    return (await db.query(sql, params)).rows;
  } finally {
    await db.exec('reset role; reset request.jwt.claims');
  }
}
const one = async (who, fn, other) => (await as(who, `select public.${fn}($1) as r`, [other]))[0].r;
const makeFriends = async (a, b) => { await one(a, 'send_friend_request', b); await one(b, 'confirm_friend_request', a); };
const hide = (who, other) => as(who, 'select public.hide_suggestion($1)', [other]);
const join_ = (who, club) => db.query('insert into public.club_members values ($1, $2)', [club, who]);
/** "Name: reason" for each suggestion, in order. */
const list = async (who) => (await as(who, 'select * from public.get_people_you_may_know()')).map((r) =>
  `${r.display_name}: ${r.mutual_friends ? `${r.mutual_friends} mutual` : r.shared_group ?? 'follows'}`);

test('an anonymous account gets no list and hides nobody', async () => {
  await reset();
  await assert.rejects(as(ANON, 'select * from public.get_people_you_may_know()', [], { anonymous: true }));
  await assert.rejects(as(ANON, 'select public.hide_suggestion($1)', [BEN], { anonymous: true }));
});

test('a brand-new neighbour with no friends, groups or followers sees nobody', async () => {
  await reset();
  assert.deepEqual(await list(ANA), []);
});

test('friends of friends, most friends shared first, then groups, then followers', async () => {
  await reset();
  await makeFriends(ANA, BEN);
  await makeFriends(ANA, CAL);
  await makeFriends(BEN, DEE);
  await makeFriends(CAL, DEE);   // Dee shares Ben and Cal with Ana
  await makeFriends(BEN, EVE);   // Eve shares Ben
  await join_(ANA, RUNNERS);
  await join_(FAY, RUNNERS);
  assert.deepEqual(await list(ANA), ['Dee Moss: 2 mutual', 'Eve Park: 1 mutual', 'Fay Lund: Running Club']);
});

test('someone who follows you is suggested, with no reason given', async () => {
  await reset();
  await as(FAY, `insert into public.town_follows (follower_id, target_type, target_id) values ($1, 'profile', $2)`, [FAY, ANA]);
  assert.deepEqual(await list(ANA), ['Fay Lund: follows']);
  // Following a group isn't following you.
  await reset();
  await as(FAY, `insert into public.town_follows (follower_id, target_type, target_id) values ($1, 'club', $2)`, [FAY, ANA]);
  assert.deepEqual(await list(ANA), []);
});

test('a group not yet approved suggests nobody and names nothing', async () => {
  await reset();
  await join_(ANA, PENDING);
  await join_(FAY, PENDING);
  assert.deepEqual(await list(ANA), []);
});

test('never your friends, anyone you asked or who asked you, or yourself', async () => {
  await reset();
  await makeFriends(ANA, BEN);
  await makeFriends(BEN, CAL);
  await makeFriends(BEN, DEE);
  await one(ANA, 'send_friend_request', CAL);
  await one(DEE, 'send_friend_request', ANA);
  await join_(ANA, RUNNERS);
  await join_(BEN, RUNNERS);
  assert.deepEqual(await list(ANA), []);
});

test('never anyone blocked, either way, and a friend who blocked you counts for nothing', async () => {
  await reset();
  await makeFriends(ANA, BEN);
  await makeFriends(ANA, CAL);
  await makeFriends(BEN, DEE);
  await makeFriends(CAL, DEE);
  await makeFriends(BEN, EVE);
  await one(ANA, 'block_neighbor', EVE);
  assert.deepEqual(await list(ANA), ['Dee Moss: 2 mutual']);
  await one(DEE, 'block_neighbor', ANA);
  assert.deepEqual(await list(ANA), []);
  // Cal blocks Ana: Dee now shares only Ben with her.
  await one(ANA, 'unblock_neighbor', EVE);
  await one(DEE, 'unblock_neighbor', ANA);
  await makeFriends(CAL, EVE);
  await one(CAL, 'block_neighbor', ANA);
  assert.deepEqual(await list(ANA), ['Dee Moss: 1 mutual', 'Eve Park: 1 mutual']);
});

test('the X hides someone for good, for you only, and twice is fine', async () => {
  await reset();
  await makeFriends(ANA, BEN);
  await makeFriends(BEN, CAL);
  await makeFriends(DEE, BEN);
  await hide(ANA, CAL);
  await hide(ANA, CAL);
  assert.deepEqual(await list(ANA), ['Dee Moss: 1 mutual']);
  assert.deepEqual(await list(DEE), ['Ana Lee: 1 mutual', 'Cal Ruiz: 1 mutual']);
  await assert.rejects(hide(ANA, ANA));
  // Nobody can read who hid whom.
  await assert.rejects(as(ANA, 'select * from private.suggestion_hides'));
});

test('"Suggest me to people I may know" off keeps you off every list', async () => {
  await reset();
  await makeFriends(ANA, BEN);
  await makeFriends(BEN, CAL);
  await as(CAL, 'update public.town_profiles set suggest_me = false where user_id = $1', [CAL]);
  assert.deepEqual(await list(ANA), []);
  // It's yours: you still see others.
  assert.deepEqual(await list(CAL), ['Ana Lee: 1 mutual']);
});
