// Fixed stories for the waitlist's limits (supabase/migrations/*_waitlist_limits.sql, BP app
// docs/plans/loopholes, ticket 06), run in PGlite as the website's public key would. Run: `npm test`
// in this folder.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { PGlite } from '@electric-sql/pglite';
import { creating } from './migrations.mjs';

const migrations = process.env.MIGRATIONS ?? new URL('../migrations', import.meta.url).pathname;
const db = await PGlite.create();
// public.waitlist as live: its unique email, its insert rule, and anon's insert on every column.
await db.exec(`
  create role anon; create role authenticated;
  create schema private;
  create table public.waitlist (id uuid primary key default gen_random_uuid(), email text not null,
    first_name text not null, town text not null, created_at timestamptz not null default now(),
    business_name text, business_kind text);
  create unique index waitlist_email_lower_idx on public.waitlist (lower(email));
  alter table public.waitlist enable row level security;
  create policy "anon can join the waitlist" on public.waitlist for insert to anon
    with check (char_length(email) between 6 and 254 and position('@' in email) > 1
      and char_length(first_name) between 1 and 80 and char_length(town) between 1 and 120);
  grant insert on public.waitlist to anon;
`);
for (const f of creating(migrations, ['private.waitlist_per_minute'])) await db.exec(readFileSync(join(migrations, f), 'utf8'));

const TOWN = 'St. Joseph, MN';
// The website's insert: its five fields, the business two only on an owner's path.
async function signUp(email, extra = {}) {
  const row = { email, first_name: 'Neighbor', town: TOWN, ...extra };
  const cols = Object.keys(row);
  await db.exec('set role anon');
  try {
    await db.query(`insert into public.waitlist (${cols}) values (${cols.map((_, i) => `$${i + 1}`)})`, Object.values(row));
    return 'joined';
  } catch (e) {
    return e.code;
  } finally {
    await db.exec('reset role');
  }
}
const count = async () => Number((await db.query('select count(*) from public.waitlist')).rows[0].count);
// Moves every saved signup back past the minute, as the clock would.
const aMinuteLater = () => db.exec(`update public.waitlist set created_at = created_at - interval '61 seconds'`);

test('ten signups a minute join; the eleventh is refused and not counted', async () => {
  for (let i = 1; i <= 9; i++) assert.equal(await signUp(`n${i}@example.com`), 'joined');
  assert.equal(await signUp('owner@example.com', { business_name: 'Bad Habit', business_kind: 'coffee shop' }), 'joined');
  assert.equal(await signUp('n11@example.com'), 'PT429');
  assert.equal(await count(), 10);
  await aMinuteLater();
  assert.equal(await signUp('n11@example.com'), 'joined');
});

test('a burst sent as one request is capped too', async () => {
  await aMinuteLater();
  await db.exec('set role anon');
  const burst = db.query(`insert into public.waitlist (email, first_name, town)
    select 'burst' || g || '@example.com', 'Bot', $1 from generate_series(1, 11) g`, [TOWN]);
  await assert.rejects(burst, { code: 'PT429' });
  await db.exec('reset role');
  assert.equal(await count(), 11);
});

test('a signup cannot be backdated past the cap', async () => {
  assert.equal(await signUp('old@example.com', { created_at: '2026-01-01' }), '42501');
  assert.equal(await signUp('mine@example.com', { id: '00000000-0000-0000-0000-000000000001' }), '42501');
});

test('each email joins once, whatever its case', async () => {
  await aMinuteLater();
  assert.equal(await signUp('Twice@Example.com'), 'joined');
  assert.equal(await signUp('twice@example.com'), '23505');
});
