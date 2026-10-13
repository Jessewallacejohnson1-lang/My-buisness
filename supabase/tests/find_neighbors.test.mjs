// Fixed stories for search_neighbors (supabase/migrations/*_find_neighbors.sql),
// how a neighbour finds another by name (BP app docs/plans/friends, ticket 02), run in PGlite
// like the Town feed's. Run: `npm install && npm test` in this folder. The schema below is the
// subset of schema.sql the functions read, with is_real_account() taken from its own migration.
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
  -- One claims JSON feeds both, as on Supabase.
  create function auth.jwt() returns jsonb language sql stable as
    $$ select coalesce(nullif(current_setting('request.jwt.claims', true), ''), '{}')::jsonb $$;
  create function auth.uid() returns uuid language sql stable as
    $$ select nullif(auth.jwt() ->> 'sub', '')::uuid $$;
  create table auth.users (id uuid primary key, is_anonymous boolean not null default false,
    banned_until timestamptz);
  create table public.town_profiles (
    user_id uuid primary key, display_name text, avatar_url text,
    onboarded_at timestamptz, created_at timestamptz not null default now());

  -- The live rule (schema.sql): each person reads only their own row.
  alter table public.town_profiles enable row level security;
  create policy "town_profiles_select_own" on public.town_profiles for select to public
    using (auth.uid() = user_id);
  grant select on all tables in schema public to anon, authenticated;
`);
await db.exec(realAccount);
for (const sql of read('_find_neighbors.sql')) await db.exec(sql);

const id = (n) => `00000000-0000-0000-0000-${String(n).padStart(12, '0')}`;
const ME = id(1);

async function reset() {
  await db.exec(`reset role; reset request.jwt.claims;
                 delete from public.town_profiles; delete from auth.users;`);
}

async function person(n, name, { anonymous = false, photo = null, since = null } = {}) {
  await db.query('insert into auth.users (id, is_anonymous) values ($1, $2)', [id(n), anonymous]);
  await db.query(`insert into public.town_profiles (user_id, display_name, avatar_url, onboarded_at)
                  values ($1, $2, $3, $4)`, [id(n), name, photo, since]);
}

/** Runs `sql` as an account: real unless `anonymous`, or with no account at all (`as: null`). */
async function as(sql, params, { who = ME, anonymous = false, role = 'authenticated' } = {}) {
  const claims = who ? JSON.stringify({ sub: who, is_anonymous: anonymous }) : '';
  await db.exec(`set role ${role}; set request.jwt.claims = '${claims}'`);
  try {
    return (await db.query(sql, params)).rows;
  } finally {
    await db.exec('reset role; reset request.jwt.claims');
  }
}

const found = (words, opts) => as('select * from public.search_neighbors($1)', [words], opts);
const search = (words, opts) => found(words, opts).then((r) => r.map((x) => x.display_name));
const PHOTOS = 'https://lxdgwhvqjqmqliobwjpi.supabase.co/storage/v1/object/public/avatars/';

async function seed() {
  await reset();
  await person(1, 'Jesse Johnson');
  await person(2, 'Sam Rivera', { photo: `${PHOTOS}${id(2)}/avatar-1.jpg`, since: '2026-03-02T10:00:00Z' });
  await person(3, 'Samantha Ostendorf');
  await person(4, 'Ana Samuels');
  await person(5, 'Sam Anonymous', { anonymous: true });
  await person(6, null);
  await person(7, '   ');
  await person(8, '100%_Real Sam');
  await person(9, '\u200b\u200b');
}

test('an anonymous account and no account at all are refused', async () => {
  await seed();
  for (const opts of [{ anonymous: true }, { who: null }, { who: null, role: 'anon' }]) {
    await assert.rejects(search('sam', opts));
  }
});

test('a word of the name starts with what was typed, whole-name matches first', async () => {
  await seed();
  const sam = await search('sam');
  assert.deepEqual(sam.slice(0, 2).sort(), ['Sam Rivera', 'Samantha Ostendorf']);
  assert.deepEqual(sam.slice(2).sort(), ['100%_Real Sam', 'Ana Samuels']);
  assert.deepEqual(await search('  SAMU '), ['Ana Samuels']);
  assert.deepEqual(await search('amuel'), []);
});

test('anonymous accounts, nameless people and the caller never come back', async () => {
  await seed();
  assert.deepEqual(await search('j'), []);
  assert.ok(!(await search('sam')).includes('Sam Anonymous'));
  assert.deepEqual(await search('\u200b'), []);
});

test('a banned account never comes back, until the ban is over', async () => {
  await seed();
  await db.exec(`update auth.users set banned_until = now() + interval '1 day' where id = '${id(2)}'`);
  assert.ok(!(await search('sam')).includes('Sam Rivera'));
  await db.exec(`update auth.users set banned_until = now() - interval '1 day' where id = '${id(2)}'`);
  assert.ok((await search('sam')).includes('Sam Rivera'));
});

test('typed % and _ match themselves, not everyone', async () => {
  await seed();
  assert.deepEqual(await search('%'), []);
  assert.deepEqual(await search('_'), []);
  assert.deepEqual(await search('100%_'), ['100%_Real Sam']);
});

test('nothing typed finds nobody, and at most 20 come back', async () => {
  await seed();
  assert.deepEqual(await search(''), []);
  assert.deepEqual(await search('   '), []);
  assert.deepEqual(await search(null), []);
  for (let n = 10; n < 40; n++) await person(n, `Kim ${n}`);
  assert.equal((await search('kim')).length, 20);
});

test('a neighbour comes with their photo and Neighbor since', async () => {
  await seed();
  const [sam] = await found('sam riv');
  assert.equal(sam.display_name, 'Sam Rivera');
  assert.equal(sam.avatar_url, `${PHOTOS}${id(2)}/avatar-1.jpg`);
  assert.equal(new Date(sam.since).toISOString(), '2026-03-02T10:00:00.000Z');
});

test('with no onboarding date, Neighbor since is the profile\'s first save', async () => {
  await seed();
  await db.exec(`update public.town_profiles set created_at = '2026-09-01T00:00:00Z' where user_id = '${id(4)}'`);
  const [ana] = await found('ana');
  assert.equal(new Date(ana.since).toISOString(), '2026-09-01T00:00:00.000Z');
});

test('only a photo in their own avatars folder comes back', async () => {
  await seed();
  await person(20, 'Tom Elsewhere', { photo: 'https://tracker.example/pixel.gif' });
  await person(21, 'Tom Borrowed', { photo: `${PHOTOS}${id(2)}/avatar-1.jpg` });
  const toms = await found('tom');
  assert.deepEqual(toms.map((t) => t.avatar_url), [null, null]);
});

test('a curly apostrophe finds a straight one, and the other way', async () => {
  await seed();
  await person(22, "Pat O'Brien");
  await person(23, 'Lou O’Neil');
  assert.deepEqual(await search('o’b'), ["Pat O'Brien"]);
  assert.deepEqual(await search("o'n"), ['Lou O’Neil']);
});

test('town_profiles itself still shows only your own row', async () => {
  await seed();
  const rows = await as('select display_name from public.town_profiles', []);
  assert.deepEqual(rows.map((r) => r.display_name), ['Jesse Johnson']);
});
