// Fixed stories for delete_my_account (supabase/migrations/*_delete_my_account.sql), run in
// PGlite: a signed-in person deletes their own account and nobody else's; no one signed in
// deletes nothing and can't call it. Run: `npm install && npm test` in this folder.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { PGlite } from '@electric-sql/pglite';
import { creating } from './migrations.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const migrations = process.env.MIGRATIONS ?? join(here, '..', 'migrations');

const db = await PGlite.create();
await db.exec(`
  create role anon; create role authenticated;
  create schema auth;
  grant usage on schema auth to anon, authenticated;
  create function auth.uid() returns uuid language sql stable as
    $$ select nullif(nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub', '')::uuid $$;
  create table auth.users (id uuid primary key);
  create table public.town_profiles (user_id uuid primary key references auth.users (id) on delete cascade);
`);
for (const f of creating(migrations, ['public.delete_my_account'])) {
  await db.exec(readFileSync(join(migrations, f), 'utf8'));
}

const kid = '00000000-0000-0000-0000-00000000000a';
const neighbor = '00000000-0000-0000-0000-00000000000b';

async function reset() {
  await db.exec(`delete from auth.users;
    insert into auth.users values ('${kid}'), ('${neighbor}');
    insert into public.town_profiles values ('${kid}'), ('${neighbor}');`);
}

async function as(role, sub, sql) {
  await db.exec(`set role ${role}; select set_config('request.jwt.claims', '${sub ? JSON.stringify({ sub }) : ''}', false);`);
  try { return await db.query(sql); } finally { await db.exec('reset role;'); }
}

async function users() {
  return (await db.query('select id from auth.users order by id')).rows.map((r) => r.id);
}

test('a signed-in person deletes their own account and what hangs off it', async () => {
  await reset();
  await as('authenticated', kid, 'select public.delete_my_account()');
  assert.deepEqual(await users(), [neighbor]);
  const profiles = (await db.query('select user_id from public.town_profiles')).rows.map((r) => r.user_id);
  assert.deepEqual(profiles, [neighbor]);
});

test('signed in with no account id, nothing goes', async () => {
  await reset();
  await as('authenticated', null, 'select public.delete_my_account()');
  assert.deepEqual(await users(), [kid, neighbor]);
});

test('someone not signed in cannot call it', async () => {
  await reset();
  await assert.rejects(as('anon', null, 'select public.delete_my_account()'), /permission denied/);
  assert.deepEqual(await users(), [kid, neighbor]);
});
