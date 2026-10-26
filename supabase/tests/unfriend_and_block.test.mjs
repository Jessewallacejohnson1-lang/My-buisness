// Fixed stories for Unfriend and Block (supabase/migrations/*_unfriend_and_block.sql): unfriend
// ends a friendship and its two follows; a block ends everything between two people and hides
// each from the other everywhere; unblock gives back only being findable (BP app
// docs/plans/friends, ticket 04). Run in PGlite like the others: `npm install && npm test` in
// this folder. The schema below is the subset of schema.sql the functions read.
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
  create function public.get_feed_postings(limit_n integer default 30) returns int
    language sql as $$ select 0 $$;

  -- The live rules (schema.sql): your own profile row; your own follows, any target.
  alter table public.town_profiles enable row level security;
  create policy "town_profiles_select_own" on public.town_profiles for select to public
    using (auth.uid() = user_id);
  alter table public.town_follows enable row level security;
  create policy "own follows select" on public.town_follows for select to public
    using (auth.uid() = follower_id);
  create policy "own follows insert" on public.town_follows for insert to public
    with check (auth.uid() = follower_id);
  grant select, insert on all tables in schema public to anon, authenticated;
`);
await db.exec(realAccount);
for (const sql of [...read('_find_neighbors.sql'), ...read('_friend_requests.sql'), ...read('_unfriend_and_block.sql'),
                   ...read('_get_neighbor.sql')]) {
  await db.exec(sql);
}

const id = (n) => `00000000-0000-0000-0000-${String(n).padStart(12, '0')}`;
const [ANA, BEN, CAL, ANON] = [1, 2, 3, 6].map(id);
const CLUB = id(900);

async function reset() {
  await db.exec(`reset role; reset request.jwt.claims;
    delete from private.blocks; delete from private.friend_requests; delete from private.friendships;
    delete from private.friends_seen; delete from public.town_follows; delete from public.town_profiles;
    delete from auth.users;`);
  for (const [who, name, anonymous] of [[ANA, 'Ana Lee', false], [BEN, 'Ben Ortiz', false],
                                        [CAL, 'Cal Ruiz', false], [ANON, 'Anon Ymous', true]]) {
    await db.query('insert into auth.users (id, is_anonymous) values ($1, $2)', [who, anonymous]);
    await db.query('insert into public.town_profiles (user_id, display_name) values ($1, $2)', [who, name]);
  }
}

/** Runs one call as `who`: a real account unless `anonymous`. */
async function as(who, sql, params = [], { anonymous = false } = {}) {
  await db.exec(`set role authenticated; set request.jwt.claims = '${JSON.stringify({ sub: who, is_anonymous: anonymous })}'`);
  try {
    return (await db.query(sql, params)).rows;
  } finally {
    await db.exec('reset role; reset request.jwt.claims');
  }
}
const one = async (who, fn, other) => (await as(who, `select public.${fn}($1) as r`, [other]))[0].r;
const send = (who, to) => one(who, 'send_friend_request', to);
const confirm = (who, from) => one(who, 'confirm_friend_request', from);
const unfriend = (who, other) => one(who, 'unfriend', other);
const block = (who, other) => one(who, 'block_neighbor', other);
const unblock = (who, other) => one(who, 'unblock_neighbor', other);
const friends = (who) => as(who, 'select kind, display_name from public.get_friends()')
  .then((rows) => rows.map((r) => `${r.kind} ${r.display_name}`));
const blocked = (who) => as(who, 'select display_name, relation from public.get_blocked()')
  .then((rows) => rows.map((r) => `${r.display_name}: ${r.relation}`));
const dot = async (who) => (await as(who, 'select public.friends_dot() as d'))[0].d;
const stand = async (who, words) => (await as(who, 'select display_name, relation from public.search_neighbors($1)', [words]))
  .map((r) => `${r.display_name}: ${r.relation}`);
const follows = async () => (await db.query(
  `select follower_id, target_type, target_id from public.town_follows order by 2, 1, 3`)).rows
  .map((r) => `${r.follower_id.slice(-1)}>${r.target_type === 'club' ? 'club' : r.target_id.slice(-1)}`);
const makeFriends = async (a, b) => { await send(a, b); await confirm(b, a); };

test('an anonymous account can do none of it', async () => {
  await reset();
  for (const sql of ['select public.unfriend($1)', 'select public.block_neighbor($1)', 'select public.unblock_neighbor($1)']) {
    await assert.rejects(as(ANON, sql, [BEN], { anonymous: true }));
  }
  await assert.rejects(as(ANON, 'select * from public.get_blocked()', [], { anonymous: true }));
});

test('unfriend ends the friendship and both follows, and nothing else', async () => {
  await reset();
  await makeFriends(ANA, BEN);
  await as(ANA, `insert into public.town_follows (follower_id, target_type, target_id) values ($1, 'club', $2)`, [ANA, CLUB]);
  assert.equal(await unfriend(ANA, BEN), 'none');
  assert.deepEqual(await friends(ANA), []);
  assert.deepEqual(await friends(BEN), []);
  assert.deepEqual(await stand(BEN, 'ana'), ['Ana Lee: none']);
  assert.deepEqual(await follows(), ['1>club']);
});

test('unfriending someone who is not a friend leaves their follow alone', async () => {
  await reset();
  await as(ANA, `insert into public.town_follows (follower_id, target_type, target_id) values ($1, 'profile', $2)`, [ANA, BEN]);
  assert.equal(await unfriend(ANA, BEN), 'none');
  assert.deepEqual(await follows(), ['1>2']);
});

test('friends see when their friendship began', async () => {
  await reset();
  await makeFriends(ANA, BEN);
  const [row] = await as(ANA, 'select friends_since from public.search_neighbors($1)', ['ben']);
  assert.ok(row.friends_since);
  const [stranger] = await as(ANA, 'select friends_since from public.search_neighbors($1)', ['cal']);
  assert.equal(stranger.friends_since, null);
});

test('a block ends the friendship and the follows both ways', async () => {
  await reset();
  await makeFriends(ANA, BEN);
  assert.equal(await block(ANA, BEN), 'blocked');
  assert.deepEqual(await friends(ANA), []);
  assert.deepEqual(await friends(BEN), []);
  assert.deepEqual(await follows(), []);
});

test('a block ends requests both ways, and the dot with them', async () => {
  await reset();
  await send(BEN, ANA);
  await send(ANA, CAL);
  await send(CAL, ANA);       // crossing: Ana and Cal are now friends
  await block(ANA, BEN);
  assert.equal(await dot(ANA), false);
  assert.deepEqual(await friends(ANA), ['accepted Cal Ruiz', 'friend Cal Ruiz']);
  await send(ANA, CAL);
  await block(CAL, ANA);
  assert.deepEqual(await friends(ANA), []);
});

test('neither can find, list or ask the other, whoever blocked', async () => {
  await reset();
  await block(ANA, BEN);
  assert.deepEqual(await stand(ANA, 'ben'), []);
  assert.deepEqual(await stand(BEN, 'ana'), []);
  assert.deepEqual(await stand(BEN, 'a'), []);
  await assert.rejects(send(BEN, ANA));
  await assert.rejects(send(ANA, BEN));
  // A request from before can't be confirmed into a friendship either.
  await reset();
  await send(BEN, ANA);
  await block(BEN, ANA);
  assert.equal(await confirm(ANA, BEN), 'none');
  assert.deepEqual(await friends(ANA), []);
});

test('the Blocked list is yours alone, newest first', async () => {
  await reset();
  await block(ANA, BEN);
  await db.exec(`update private.blocks set created_at = now() - interval '1 hour'`);
  await block(ANA, CAL);
  await block(CAL, BEN);
  assert.deepEqual(await blocked(ANA), ['Cal Ruiz: blocked', 'Ben Ortiz: blocked']);
  assert.deepEqual(await blocked(BEN), []);
  assert.deepEqual(await blocked(CAL), ['Ben Ortiz: blocked']);
});

test('nobody can block themselves', async () => {
  await reset();
  await assert.rejects(block(ANA, ANA));
});

test('blocking someone who blocked you first is fine, and neither block undoes the other', async () => {
  await reset();
  await block(ANA, BEN);
  assert.equal(await block(BEN, ANA), 'blocked');
  assert.equal(await unblock(ANA, BEN), 'none');
  assert.deepEqual(await stand(ANA, 'ben'), []);
  assert.equal(await unblock(BEN, ANA), 'none');
  assert.deepEqual(await stand(ANA, 'ben'), ['Ben Ortiz: none']);
});

test('unblock gives back being findable, and nothing else', async () => {
  await reset();
  await makeFriends(ANA, BEN);
  await send(CAL, ANA);
  await block(ANA, BEN);
  await block(ANA, CAL);
  assert.equal(await unblock(ANA, BEN), 'none');
  assert.equal(await unblock(ANA, CAL), 'none');
  assert.deepEqual(await stand(ANA, 'ben'), ['Ben Ortiz: none']);
  assert.deepEqual(await stand(BEN, 'ana'), ['Ana Lee: none']);
  assert.deepEqual(await friends(ANA), []);
  assert.deepEqual(await blocked(ANA), []);
  assert.deepEqual(await follows(), []);
  // They can start again from Add friend.
  assert.equal(await send(BEN, ANA), 'sent');
});

test('blocking and unblocking can not be used to get round the daily limit', async () => {
  await reset();
  for (let n = 100; n < 141; n++) {
    await db.query('insert into auth.users (id) values ($1)', [id(n)]);
    await db.query('insert into public.town_profiles (user_id, display_name) values ($1, $2)', [id(n), `Neighbor ${n}`]);
  }
  for (let n = 100; n < 140; n++) assert.equal(await send(ANA, id(n)), 'sent');
  for (let n = 100; n < 110; n++) { await block(ANA, id(n)); await unblock(ANA, id(n)); }
  await assert.rejects(send(ANA, id(140)), /friend_limit/);
});

// get_neighbor (follows 05): one neighbour by id, as search_neighbors answers them, for a page opened
// from a list that knows only who they are.
const neighbor = async (who, other, opts) => (await as(who,
  'select display_name, relation from public.get_neighbor($1)', [other], opts))
  .map((r) => `${r.display_name}: ${r.relation}`);

test('get_neighbor answers where you stand with one neighbour', async () => {
  await reset();
  assert.deepEqual(await neighbor(ANA, BEN), ['Ben Ortiz: none']);
  await send(ANA, BEN);
  assert.deepEqual(await neighbor(ANA, BEN), ['Ben Ortiz: sent']);
  assert.deepEqual(await neighbor(BEN, ANA), ['Ana Lee: received']);
  await confirm(BEN, ANA);
  assert.deepEqual(await neighbor(ANA, BEN), ['Ben Ortiz: friends']);
});

test('get_neighbor finds nobody blocked either way, nor yourself', async () => {
  await reset();
  await block(ANA, BEN);
  assert.deepEqual(await neighbor(ANA, BEN), []);
  assert.deepEqual(await neighbor(BEN, ANA), []);
  assert.deepEqual(await neighbor(CAL, CAL), []);
  assert.deepEqual(await neighbor(CAL, ANON), []);
});

test('get_neighbor answers real accounts only', async () => {
  await reset();
  await assert.rejects(neighbor(ANON, BEN, { anonymous: true }));
  await db.exec('set role anon');
  try {
    await assert.rejects(db.query('select * from public.get_neighbor($1)', [BEN]));
  } finally {
    await db.exec('reset role');
  }
});
