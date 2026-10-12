// Fixed stories for get_my_going (supabase/migrations/*_my_going.sql), the You tab's read of
// the caller's Going, run in PGlite like the Town feed's. Run: `npm install && npm test` in
// this folder. The schema below is the subset of schema.sql the function reads.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { PGlite } from '@electric-sql/pglite';

const here = dirname(fileURLToPath(import.meta.url));
const migrations = process.env.MIGRATIONS ?? join(here, '..', 'migrations');
// The function, then its re-creation with counts from the private helpers (town-feed ticket 19).
const files = readdirSync(migrations)
  .filter((f) => /_(my_going(_[a-z]+)?|action_counts)\.sql$/.test(f)).sort();

const db = await PGlite.create();
await db.exec(`
  set timezone = 'UTC';
  create role anon; create role authenticated;
  create schema auth;
  grant usage on schema auth to anon, authenticated;
  create function auth.uid() returns uuid language sql stable as
    $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
  create function public.is_admin() returns boolean language sql stable as $$ select false $$;
  create table public.clubs (id uuid primary key default gen_random_uuid(), name text not null);
  create table public.club_events (
    id uuid primary key default gen_random_uuid(), club_id uuid, submitted_by uuid,
    status text not null default 'approved', title text not null, event_date date,
    start_time text, created_at timestamptz not null default now(), location text,
    image_url text, kind text not null default 'event', category text,
    end_at timestamptz, all_day boolean not null default false, source_name text);
  create table public.event_rsvps (
    id uuid primary key default gen_random_uuid(), event_id uuid not null,
    user_id uuid not null, created_at timestamptz not null default now());
  create table public.event_likes (
    id uuid primary key default gen_random_uuid(), event_id uuid not null,
    user_id uuid not null, created_at timestamptz not null default now());

  -- The live read rules (schema.sql; Going readable only as your own rows since ticket 19).
  alter table public.club_events enable row level security;
  alter table public.event_rsvps enable row level security;
  alter table public.clubs enable row level security;
  create policy "read events" on public.club_events for select to public
    using (status = 'approved' or submitted_by = auth.uid() or is_admin());
  create policy "own rsvps select" on public.event_rsvps for select to public
    using ((select auth.uid()) = user_id);
  create policy "read clubs" on public.clubs for select to public using (true);
  grant select on all tables in schema public to anon, authenticated;
`);
for (const f of files) await db.exec(readFileSync(join(migrations, f), 'utf8'));

const CITY = 'City of St. Joseph';
const ME = '00000000-0000-0000-0000-00000000000a';
const NEIGHBOUR = '00000000-0000-0000-0000-00000000000b';

async function reset() {
  await db.exec(`reset role; delete from public.event_rsvps; delete from public.club_events;
                 delete from public.clubs; reset request.jwt.claim.sub;`);
}

async function add(title, date, more = {}) {
  const row = { source_name: CITY, status: 'approved', kind: 'event', submitted_by: null,
                club_id: null, ...more };
  const { rows } = await db.query(
    `insert into public.club_events (title, event_date, source_name, status, kind, submitted_by, club_id)
     values ($1, $2, $3, $4, $5, $6, $7) returning id`,
    [title, date, row.source_name, row.status, row.kind, row.submitted_by, row.club_id]);
  return rows[0].id;
}

async function going(user, eventId) {
  await db.query('insert into public.event_rsvps (event_id, user_id) values ($1, $2)', [eventId, user]);
}

async function mine(from, to, as = ME) {
  await db.exec(`set role authenticated; set request.jwt.claim.sub = '${as}'`);
  const { rows } = await db.query(
    `select title, event_date::text as day, club_name, going_count
     from public.get_my_going($1::date, $2::date)`, [from, to]);
  await db.exec('reset role');
  return rows;
}

test('only the caller\'s own Going, with every account\'s count', async () => {
  await reset();
  const trivia = await add('Trivia night', '2026-10-13');
  const market = await add('Fall market', '2026-10-24');
  await going(ME, trivia);
  await going(NEIGHBOUR, trivia);
  await going(NEIGHBOUR, market);
  const rows = await mine('2026-10-11', '2026-10-31');
  assert.deepEqual(rows.map((r) => [r.title, r.going_count]), [['Trivia night', 2]]);
});

test('both ends of the range are in, the days outside are not, past days included', async () => {
  await reset();
  for (const [title, day] of [['Before', '2026-10-10'], ['First day', '2026-10-11'],
                              ['Last day', '2026-10-31'], ['After', '2026-11-01']]) {
    await going(ME, await add(title, day));
  }
  const rows = await mine('2026-10-11', '2026-10-31');
  assert.deepEqual(rows.map((r) => r.title), ['First day', 'Last day']);
});

test('ordered by day, then title', async () => {
  await reset();
  for (const [title, day] of [['Zumba', '2026-10-14'], ['Book club', '2026-10-14'], ['Hike', '2026-10-11']]) {
    await going(ME, await add(title, day));
  }
  const rows = await mine('2026-10-11', '2026-10-31');
  assert.deepEqual(rows.map((r) => `${r.day} ${r.title}`),
                   ['2026-10-11 Hike', '2026-10-14 Book club', '2026-10-14 Zumba']);
});

test('pending, rejected, non-events and events with no host are left out', async () => {
  await reset();
  await going(ME, await add('Pending', '2026-10-12', { status: 'pending', submitted_by: NEIGHBOUR }));
  await going(ME, await add('Rejected', '2026-10-12', { status: 'rejected' }));
  await going(ME, await add('A post', '2026-10-12', { kind: 'post' }));
  await going(ME, await add('Seeded sample', '2026-10-12', { source_name: null }));
  await going(ME, await add('Posted by a neighbour', '2026-10-12', { source_name: null, submitted_by: NEIGHBOUR }));
  const rows = await mine('2026-10-11', '2026-10-31');
  assert.deepEqual(rows.map((r) => r.title), ['Posted by a neighbour']);
});

test('a club\'s event carries the club\'s name', async () => {
  await reset();
  const { rows } = await db.query(`insert into public.clubs (name) values ('Bike club') returning id`);
  await going(ME, await add('Bike club ride', '2026-10-20', { club_id: rows[0].id }));
  const got = await mine('2026-10-11', '2026-10-31');
  assert.equal(got[0].club_name, 'Bike club');
});

test('signed out reads nothing', async () => {
  await reset();
  await going(ME, await add('Trivia night', '2026-10-13'));
  await db.exec('set role anon');
  const { rows } = await db.query(`select * from public.get_my_going('2026-10-11', '2026-10-31')`);
  await db.exec('reset role');
  assert.equal(rows.length, 0);
});
