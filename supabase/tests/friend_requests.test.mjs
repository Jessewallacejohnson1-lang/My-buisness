// Fixed stories for friend requests (supabase/migrations/*_friend_requests.sql, as
// *_unfriend_and_block.sql re-made search, the Friends page and send): send, cancel,
// confirm, delete, the dot and the accepted line, the daily limit, and who can read what
// (BP app docs/plans/friends, ticket 03). Run in PGlite like the Town feed's: `npm install &&
// npm test` in this folder. The schema below is the subset of schema.sql the functions read,
// with is_real_account() taken from its own migration.
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
  -- The old feed read whose follower count would count friends; only its grant matters here.
  create function public.get_feed_postings(limit_n integer default 30) returns int
    language sql as $$ select 0 $$;
  revoke execute on function public.get_feed_postings(integer) from public, anon;
  grant execute on function public.get_feed_postings(integer) to authenticated;

  -- The live rules (schema.sql): your own profile row, your own follows.
  alter table public.town_profiles enable row level security;
  create policy "town_profiles_select_own" on public.town_profiles for select to public
    using (auth.uid() = user_id);
  alter table public.town_follows enable row level security;
  create policy "own follows select" on public.town_follows for select to public
    using (auth.uid() = follower_id);
  grant select on all tables in schema public to anon, authenticated;
`);
await db.exec(realAccount);
for (const sql of [...read('_find_neighbors.sql'), ...read('_friend_requests.sql'), ...read('_unfriend_and_block.sql')]) await db.exec(sql);

const id = (n) => `00000000-0000-0000-0000-${String(n).padStart(12, '0')}`;
const [ANA, BEN, CAL, DEE, NONAME, ANON] = [1, 2, 3, 4, 5, 6].map(id);

async function reset() {
  await db.exec(`reset role; reset request.jwt.claims;
    delete from private.friend_requests; delete from private.friendships; delete from private.friends_seen;
    delete from public.town_follows; delete from public.town_profiles; delete from auth.users;`);
  for (const [who, name, anonymous] of [[ANA, 'Ana Lee', false], [BEN, 'Ben Ortiz', false], [CAL, 'Cal Ruiz', false],
                                        [DEE, 'Dee Park', false], [NONAME, null, false], [ANON, 'Anon Ymous', true]]) {
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
const cancel = (who, to) => one(who, 'cancel_friend_request', to);
const confirm = (who, from) => one(who, 'confirm_friend_request', from);
const remove = (who, from) => one(who, 'delete_friend_request', from);
const page = (who) => as(who, 'select kind, display_name, relation, mutual_friends from public.get_friends()');
const dot = async (who) => (await as(who, 'select public.friends_dot() as d'))[0].d;
const seen = (who) => as(who, 'select public.mark_friends_seen()');
const stand = async (who, words) => (await as(who, 'select display_name, relation from public.search_neighbors($1)', [words]))
  .map((r) => `${r.display_name}: ${r.relation}`);
const follows = async () => (await db.query(
  `select follower_id, target_id from public.town_follows where target_type = 'profile' order by 1, 2`)).rows
  .map((r) => `${r.follower_id.slice(-1)}>${r.target_id.slice(-1)}`);

test('an anonymous account can do none of it', async () => {
  await reset();
  for (const sql of ['select public.send_friend_request($1)', 'select public.cancel_friend_request($1)',
                     'select public.confirm_friend_request($1)', 'select public.delete_friend_request($1)']) {
    await assert.rejects(as(ANON, sql, [BEN], { anonymous: true }));
  }
  for (const sql of ['select * from public.get_friends()', 'select public.friends_dot()', 'select public.mark_friends_seen()']) {
    await assert.rejects(as(ANON, sql, [], { anonymous: true }));
  }
});

test('send: the sender reads Request sent, the recipient a request and the dot', async () => {
  await reset();
  assert.equal(await send(ANA, BEN), 'sent');
  assert.deepEqual(await stand(ANA, 'ben'), ['Ben Ortiz: sent']);
  assert.deepEqual(await stand(BEN, 'ana'), ['Ana Lee: received']);
  assert.deepEqual((await page(BEN)).map((r) => `${r.kind} ${r.display_name}`), ['request Ana Lee']);
  assert.equal(await dot(BEN), true);
  assert.equal(await dot(ANA), false);
});

test('cancel takes it back for both', async () => {
  await reset();
  await send(ANA, BEN);
  assert.equal(await cancel(ANA, BEN), 'none');
  assert.deepEqual(await stand(BEN, 'ana'), ['Ana Lee: none']);
  assert.equal(await dot(BEN), false);
});

test('confirm makes friends, both follows, and one accepted line for the sender', async () => {
  await reset();
  await send(ANA, BEN);
  assert.equal(await confirm(BEN, ANA), 'friends');
  assert.deepEqual(await stand(ANA, 'ben'), ['Ben Ortiz: friends']);
  assert.deepEqual(await follows(), ['1>2', '2>1']);
  assert.deepEqual((await page(ANA)).map((r) => r.kind), ['accepted', 'friend']);
  assert.deepEqual((await page(BEN)).map((r) => r.kind), ['friend']);
  await seen(ANA);
  assert.deepEqual((await page(ANA)).map((r) => r.kind), ['friend']);
});

test('confirm with no request changes nothing', async () => {
  await reset();
  assert.equal(await confirm(BEN, CAL), 'none');
  assert.deepEqual(await page(BEN), []);
  assert.deepEqual(await follows(), []);
});

test('a follow that already exists does not stop a confirm', async () => {
  await reset();
  await db.query(`insert into public.town_follows (follower_id, target_type, target_id) values ($1, 'profile', $2)`, [BEN, ANA]);
  await send(ANA, BEN);
  assert.equal(await confirm(BEN, ANA), 'friends');
  assert.deepEqual(await follows(), ['1>2', '2>1']);
});

test('delete hides it from the recipient only; the sender still reads Request sent', async () => {
  await reset();
  await send(ANA, BEN);
  assert.equal(await remove(BEN, ANA), 'none');
  assert.deepEqual(await stand(ANA, 'ben'), ['Ben Ortiz: sent']);
  assert.deepEqual(await page(BEN), []);
  assert.equal(await dot(BEN), false);
  // Cancelling and sending again never brings it back to them.
  await cancel(ANA, BEN);
  await send(ANA, BEN);
  assert.deepEqual(await page(BEN), []);
  assert.deepEqual(await stand(ANA, 'ben'), ['Ben Ortiz: sent']);
});

test('adding someone whose request you deleted makes friends at once', async () => {
  await reset();
  await send(ANA, BEN);
  await remove(BEN, ANA);
  assert.equal(await send(BEN, ANA), 'friends');
  assert.deepEqual((await page(ANA)).map((r) => r.kind), ['accepted', 'friend']);
});

test('two requests crossing make friends at once', async () => {
  await reset();
  await send(ANA, BEN);
  assert.equal(await send(BEN, ANA), 'friends');
  assert.deepEqual(await stand(ANA, 'ben'), ['Ben Ortiz: friends']);
  const left = await db.query('select count(*)::int as n from private.friend_requests');
  assert.equal(left.rows[0].n, 0);
});

test('the 41st new request in a day is refused, and cancelling does not get round it', async () => {
  await reset();
  for (let n = 100; n < 141; n++) {
    await db.query('insert into auth.users (id) values ($1)', [id(n)]);
    await db.query('insert into public.town_profiles (user_id, display_name) values ($1, $2)', [id(n), `Neighbor ${n}`]);
  }
  for (let n = 100; n < 140; n++) assert.equal(await send(ANA, id(n)), 'sent');
  await assert.rejects(send(ANA, id(140)), /friend_limit/);
  for (let n = 100; n < 110; n++) await cancel(ANA, id(n));
  await assert.rejects(send(ANA, id(140)), /friend_limit/);
  // Yesterday's requests don't count.
  await db.exec(`update private.friend_requests set created_at = now() - interval '25 hours'`);
  assert.equal(await send(ANA, id(140)), 'sent');
});

test('a neighbour with no name is asked for one, and nobody can ask the nameless or anonymous', async () => {
  await reset();
  await assert.rejects(send(NONAME, ANA), /friend_name_needed/);
  await assert.rejects(send(ANA, NONAME));
  await assert.rejects(send(ANA, ANON));
  await assert.rejects(send(ANA, ANA));
});

test('friends come A to Z with the friends you share; requests newest first', async () => {
  await reset();
  for (const [x, y] of [[ANA, CAL], [BEN, CAL], [ANA, DEE], [BEN, DEE], [ANA, BEN]]) { await send(x, y); await confirm(y, x); }
  await seen(ANA);
  const rows = await page(ANA);
  assert.deepEqual(rows.map((r) => `${r.display_name} ${r.mutual_friends}`), ['Ben Ortiz 2', 'Cal Ruiz 1', 'Dee Park 1']);
  await reset();
  await send(CAL, ANA);
  await db.exec(`update private.friend_requests set created_at = now() - interval '1 hour'`);
  await send(BEN, ANA);
  assert.deepEqual((await page(ANA)).map((r) => r.display_name), ['Ben Ortiz', 'Cal Ruiz']);
});

test('the dot clears once Friends has been seen, and comes back for a newer request', async () => {
  await reset();
  await send(ANA, BEN);
  await seen(BEN);
  assert.equal(await dot(BEN), false);
  assert.deepEqual((await page(BEN)).map((r) => r.kind), ['request']);
  await db.exec(`update private.friends_seen set seen_at = now() - interval '1 minute'`);
  await send(CAL, BEN);
  assert.equal(await dot(BEN), true);
});

test('search and the Friends page stay quick with 5,000 neighbours', async () => {
  await reset();
  await db.exec(`
    insert into auth.users (id) select ('00000000-0000-0000-0001-' || lpad(g::text, 12, '0'))::uuid
      from generate_series(1, 5000) g;
    insert into public.town_profiles (user_id, display_name)
      select ('00000000-0000-0000-0001-' || lpad(g::text, 12, '0'))::uuid, 'Neighbor ' || g
      from generate_series(1, 5000) g;
    insert into private.friendships (a, b, requested_by)
      select least(u, '${ANA}'::uuid), greatest(u, '${ANA}'::uuid), u
      from (select ('00000000-0000-0000-0001-' || lpad(g::text, 12, '0'))::uuid as u
            from generate_series(1, 300) g) x;`);
  let t = performance.now();
  assert.equal((await stand(ANA, 'ben')).length, 1);
  const search = performance.now() - t;
  t = performance.now();
  assert.equal((await page(ANA)).length, 300);
  const friends = performance.now() - t;
  assert.ok(search < 1500 && friends < 3000, `search ${search.toFixed(0)} ms, friends ${friends.toFixed(0)} ms`);
});

test("nobody can read the requests, friendships or anyone else's list directly", async () => {
  await reset();
  await send(ANA, BEN);
  for (const table of ['private.friend_requests', 'private.friendships', 'private.friends_seen']) {
    await assert.rejects(as(CAL, `select * from ${table}`));
  }
  assert.deepEqual(await page(CAL), []);
  await assert.rejects(as(CAL, 'select public.get_feed_postings(30)'));
});
