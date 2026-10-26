// Fixed stories for Jesse's three weekly numbers (supabase/migrations/*_weekly_numbers.sql, BP app
// docs/plans/town-feed, ticket 26), run in PGlite. Run: `npm test` in this folder.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { PGlite } from '@electric-sql/pglite';
import { creating } from './migrations.mjs';

const migrations = process.env.MIGRATIONS ?? new URL('../migrations', import.meta.url).pathname;
const db = await PGlite.create();
await db.exec(`
  set timezone = 'UTC';
  create role anon; create role authenticated;
  create schema auth;
  create function auth.uid() returns uuid language sql stable as
    $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
  create function public.is_admin() returns boolean language sql stable as
    $$ select coalesce(current_setting('test.admin', true), '') = 'on' $$;
  create table public.feed_actions (id uuid primary key default gen_random_uuid(), user_id uuid not null,
    item_id uuid not null, action text not null, at timestamptz not null default now());
  create table public.event_rsvps (id uuid primary key default gen_random_uuid(), event_id uuid not null,
    user_id uuid not null, created_at timestamptz not null default now());
  create table public.event_saves (event_id uuid not null, user_id uuid not null,
    created_at timestamptz not null default now(), primary key (event_id, user_id));
`);
for (const f of creating(migrations, ['public.weekly_numbers'])) await db.exec(readFileSync(join(migrations, f), 'utf8'));

const [ANNA, BEN, CAL] = ['a', 'b', 'c'].map((x) => `00000000-0000-0000-0000-00000000000${x}`);
const [FAIR, QUIZ, RIDE] = ['1', '2', '3'].map((x) => `00000000-0000-0000-0000-00000000010${x}`);
// Town time, Central.
const at = (s) => `${s}-05`;
async function act(who, item, action, when) {
  await db.query(`insert into public.feed_actions (user_id, item_id, action, at) values ($1, $2, $3, $4)`,
    [who, item, action, at(when)]);
}
async function numbers(week, admin = true) {
  await db.exec(`reset role; ${admin ? "set test.admin = 'on'" : 'reset test.admin'}; set role authenticated`);
  const { rows } = await db.query(`select * from public.weekly_numbers($1::date)`, [week]);
  await db.exec('reset role');
  return rows;
}

// The week of Monday Oct 19, 2026. Anna sees three Events, goes to one after seeing it and
// saves one she saw only after saving it; Ben sees two, sees the fair again, says Not
// interested to the ride and does nothing else; Cal never opens the feed but goes to the
// quiz. A view and a Going the week after don't count.
await act(ANNA, FAIR, 'view', '2026-10-19 09:00');
await act(ANNA, QUIZ, 'view', '2026-10-19 09:00');
await act(ANNA, RIDE, 'view', '2026-10-20 18:00');
await db.query(`insert into public.event_rsvps (event_id, user_id, created_at) values ($1, $2, $3)`, [FAIR, ANNA, at('2026-10-19 09:05')]);
await db.query(`insert into public.event_saves (event_id, user_id, created_at) values ($1, $2, $3)`, [RIDE, ANNA, at('2026-10-20 17:00')]);
await act(BEN, FAIR, 'view', '2026-10-21 12:00');
await act(BEN, FAIR, 'view', '2026-10-22 12:00');
await act(BEN, RIDE, 'view', '2026-10-21 12:00');
await act(BEN, RIDE, 'not_interested', '2026-10-21 12:01');
await db.query(`insert into public.event_rsvps (event_id, user_id, created_at) values ($1, $2, $3)`, [QUIZ, CAL, at('2026-10-21 08:00')]);
await act(BEN, QUIZ, 'view', '2026-10-26 10:00');
await db.query(`insert into public.event_rsvps (event_id, user_id, created_at) values ($1, $2, $3)`, [QUIZ, BEN, at('2026-10-26 10:05')]);

test('a fixed week gives its three numbers', async () => {
  const [w] = await numbers('2026-10-21');
  assert.deepEqual({ ...w, week_start: w.week_start.toISOString().slice(0, 10) }, {
    week_start: '2026-10-19',
    // Anna's three and Ben's two; Ben's second fair view is the same Event shown.
    shown: 5,
    // Only Anna's fair: her ride was saved before she saw it in the feed.
    acted_on: 1,
    action_rate: '0.2000',
    views: 6,
    not_interested: 1,
    bad_rate: '166.67',
    // Anna and Ben saw the feed; Anna acted. Cal acted without the feed, so counts in neither.
    viewers: 2,
    actors: 1,
    reach: '0.5000',
  });
});

test("the next week counts only its own: Ben's Going after his view", async () => {
  const [w] = await numbers('2026-10-26');
  assert.deepEqual([w.shown, w.acted_on, w.views, w.viewers, w.actors], [1, 1, 1, 1, 1]);
});

test('an empty week has no rates, not zero divided by zero', async () => {
  const [w] = await numbers('2026-09-07');
  assert.deepEqual([w.shown, w.action_rate, w.bad_rate, w.reach], [0, null, null, null]);
});

test('nobody but the admin gets a row, and the public role cannot call it', async () => {
  assert.deepEqual(await numbers('2026-10-21', false), []);
  await db.exec('set role anon');
  await assert.rejects(db.query(`select * from public.weekly_numbers()`), /permission denied/);
  await db.exec('reset role');
});
