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
  create table auth.users (id uuid primary key);
  create function auth.uid() returns uuid language sql stable as
    $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
  create function public.is_admin() returns boolean language sql stable as
    $$ select coalesce(current_setting('test.admin', true), '') = 'on' $$;
  create table public.feed_actions (id uuid primary key default gen_random_uuid(), user_id uuid not null,
    item_id uuid not null, action text not null, at timestamptz not null default now(),
    constraint feed_actions_action_check check (action in ('view', 'open', 'not_interested')));
  create table public.event_rsvps (id uuid primary key default gen_random_uuid(), event_id uuid not null,
    user_id uuid not null, created_at timestamptz not null default now());
  create table public.event_saves (event_id uuid not null, user_id uuid not null,
    created_at timestamptz not null default now(), primary key (event_id, user_id));
`);
for (const f of creating(migrations, ['public.weekly_numbers'])) await db.exec(readFileSync(join(migrations, f), 'utf8'));

const [ANNA, BEN, CAL, DEE] = ['a', 'b', 'c', 'd'].map((x) => `00000000-0000-0000-0000-00000000000${x}`);
await db.query(`insert into auth.users (id) values ($1), ($2), ($3), ($4)`, [ANNA, BEN, CAL, DEE]);
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
// interested to the ride and shares the fair; Cal opens the app but not the feed and goes to
// the quiz; Dee opens the app and does nothing. A view and a Going the week after don't count.
await act(ANNA, FAIR, 'view', '2026-10-19 09:00');
await act(ANNA, QUIZ, 'view', '2026-10-19 09:00');
await act(ANNA, RIDE, 'view', '2026-10-20 18:00');
await db.query(`insert into public.event_rsvps (event_id, user_id, created_at) values ($1, $2, $3)`, [FAIR, ANNA, at('2026-10-19 09:05')]);
await db.query(`insert into public.event_saves (event_id, user_id, created_at) values ($1, $2, $3)`, [RIDE, ANNA, at('2026-10-20 17:00')]);
await act(BEN, FAIR, 'view', '2026-10-21 12:00');
await act(BEN, FAIR, 'view', '2026-10-22 12:00');
await act(BEN, RIDE, 'view', '2026-10-21 12:00');
await act(BEN, RIDE, 'not_interested', '2026-10-21 12:01');
await act(BEN, FAIR, 'share', '2026-10-22 12:05');
for (const [who, day] of [[CAL, '2026-10-21'], [DEE, '2026-10-20'], [DEE, '2026-10-26']])
  await db.query(`insert into public.app_opens (user_id, day) values ($1, $2)`, [who, day]);
await db.query(`insert into public.event_rsvps (event_id, user_id, created_at) values ($1, $2, $3)`, [QUIZ, CAL, at('2026-10-21 08:00')]);
await act(BEN, QUIZ, 'view', '2026-10-26 10:00');
await db.query(`insert into public.event_rsvps (event_id, user_id, created_at) values ($1, $2, $3)`, [QUIZ, BEN, at('2026-10-26 10:05')]);

test('a fixed week gives its three numbers', async () => {
  const [w] = await numbers('2026-10-21');
  assert.deepEqual({ ...w, week_start: w.week_start.toISOString().slice(0, 10) }, {
    week_start: '2026-10-19',
    // Anna's three and Ben's two; Ben's second fair view is the same Event shown.
    shown: 5,
    // Anna's fair and Ben's shared fair: Anna's ride was saved before she saw it in the feed.
    acted_on: 2,
    action_rate: '0.4000',
    views: 6,
    not_interested: 1,
    bad_rate: '166.67',
    // Anna and Ben saw the feed, Cal and Dee opened the app; Anna, Ben and Cal acted.
    openers: 4,
    actors: 3,
    reach: '0.7500',
    shares: 1,
    viewers: 2,
  });
});

test("the next week counts only its own: Ben's Going after his view", async () => {
  const [w] = await numbers('2026-10-26');
  // Ben's view and Going, and Dee's open.
  assert.deepEqual([w.shown, w.acted_on, w.views, w.openers, w.actors], [1, 1, 1, 2, 1]);
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

test('an open is recorded once per person per Town day, never for nobody', async () => {
  await db.exec(`reset role; delete from public.app_opens; set role authenticated; set request.jwt.claim.sub = '${DEE}'`);
  await db.exec('select public.record_open(); select public.record_open();');
  await db.exec('reset request.jwt.claim.sub; select public.record_open(); reset role');
  const { rows } = await db.query(`select user_id, day = (now() at time zone 'America/Chicago')::date as today from public.app_opens`);
  assert.deepEqual(rows, [{ user_id: DEE, today: true }]);
  await db.exec('set role anon');
  await assert.rejects(db.query('select public.record_open()'), /permission denied/);
  await assert.rejects(db.query('select * from public.app_opens'), /permission denied/);
  await db.exec('reset role');
});
