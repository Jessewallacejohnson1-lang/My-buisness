// Fixed stories for Jesse's three weekly numbers (supabase/migrations/*_weekly_numbers.sql, BP app
// docs/plans/town-feed, ticket 26), run in PGlite. Run: `npm test` in this folder.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { realDatabase, people, adminClaims } from './fixture.mjs';

const db = await realDatabase();
const ADMIN = await adminClaims(db);
const [ANNA, BEN, CAL, DEE] = ['a', 'b', 'c', 'd'].map((x) => `00000000-0000-0000-0000-00000000000${x}`);
await people(db, ANNA, BEN, CAL, DEE);
const [FAIR, QUIZ, RIDE] = ['1', '2', '3'].map((x) => `00000000-0000-0000-0000-00000000010${x}`);
await db.exec(`insert into public.club_events (id, title) values ('${FAIR}', 'Fair'), ('${QUIZ}', 'Quiz'), ('${RIDE}', 'Ride')`);
// Town time, Central.
const at = (s) => `${s}-05`;
async function act(who, item, action, when) {
  await db.query(`insert into public.feed_actions (user_id, item_id, action, at) values ($1, $2, $3, $4)`,
    [who, item, action, at(when)]);
}
async function numbers(week, admin = true) {
  await db.exec(`reset role; ${admin ? `set request.jwt.claims = '${ADMIN}'` : 'reset request.jwt.claims'}; set role authenticated`);
  const { rows } = await db.query(`select * from public.weekly_numbers($1::date)`, [week]);
  await db.exec('reset role');
  return rows;
}

// The week of Monday Oct 19, 2026. Anna sees three Events, goes to one after seeing it, hearts
// the quiz after seeing it and saves the ride from an older build after seeing it (neither is acting
// on it now: BP app inside-cards 16); Ben sees two, sees the fair again, says Not interested to the
// ride, shares the fair and hearts it; Cal opens the app but not the feed and goes to the quiz; Dee
// opens the app and does nothing. A view, a Going and a heart the week after don't count.
await act(ANNA, FAIR, 'view', '2026-10-19 09:00');
await act(ANNA, QUIZ, 'view', '2026-10-19 09:00');
await act(ANNA, RIDE, 'view', '2026-10-20 18:00');
await db.query(`insert into public.event_rsvps (event_id, user_id, created_at) values ($1, $2, $3)`, [FAIR, ANNA, at('2026-10-19 09:05')]);
await db.query(`insert into public.event_likes (event_id, user_id, created_at) values ($1, $2, $3)`, [QUIZ, ANNA, at('2026-10-19 09:10')]);
await db.query(`insert into public.event_saves (event_id, user_id, created_at) values ($1, $2, $3)`, [RIDE, ANNA, at('2026-10-20 18:30')]);
await act(BEN, FAIR, 'view', '2026-10-21 12:00');
await act(BEN, FAIR, 'view', '2026-10-22 12:00');
await act(BEN, RIDE, 'view', '2026-10-21 12:00');
await act(BEN, RIDE, 'not_interested', '2026-10-21 12:01');
await act(BEN, FAIR, 'share', '2026-10-22 12:05');
await db.query(`insert into public.event_likes (event_id, user_id, created_at) values ($1, $2, $3)`, [FAIR, BEN, at('2026-10-22 12:06')]);
for (const [who, day] of [[CAL, '2026-10-21'], [DEE, '2026-10-20'], [DEE, '2026-10-26']])
  await db.query(`insert into public.app_opens (user_id, day) values ($1, $2)`, [who, day]);
await db.query(`insert into public.event_rsvps (event_id, user_id, created_at) values ($1, $2, $3)`, [QUIZ, CAL, at('2026-10-21 08:00')]);
await act(BEN, QUIZ, 'view', '2026-10-26 10:00');
await db.query(`insert into public.event_rsvps (event_id, user_id, created_at) values ($1, $2, $3)`, [QUIZ, BEN, at('2026-10-26 10:05')]);
await db.query(`insert into public.event_likes (event_id, user_id, created_at) values ($1, $2, $3)`, [QUIZ, BEN, at('2026-10-26 10:06')]);

test('a fixed week gives its three numbers', async () => {
  const [w] = await numbers('2026-10-21');
  assert.deepEqual({ ...w, week_start: w.week_start.toISOString().slice(0, 10) }, {
    week_start: '2026-10-19',
    // Anna's three and Ben's two; Ben's second fair view is the same Event shown.
    shown: 5,
    // Anna's fair and Ben's shared fair: Anna's heart on the quiz and her old build's save on the ride count
    // for nothing here.
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
    // Anna's on the quiz and Ben's on the fair: their own line.
    hearts: 2,
  });
});

test("the next week counts only its own: Ben's Going after his view", async () => {
  const [w] = await numbers('2026-10-26');
  // Ben's view and Going, and Dee's open.
  assert.deepEqual([w.shown, w.acted_on, w.views, w.openers, w.actors, w.hearts], [1, 1, 1, 2, 1, 1]);
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
