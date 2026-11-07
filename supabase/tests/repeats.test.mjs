// Fixed stories for how an Event repeats from every door (supabase/migrations/*_repeat_from_every_door.sql, BP app
// docs/plans/inside-cards, ticket 23): the Event card says it ("Every Tuesday") as the Town feed words it, so the You
// tab, the bell and a chat do, and so do a Town page's and a City board's Event rows. PGlite, like the others:
// `npm install && npm test` in this folder.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { realDatabase } from './fixture.mjs';
import { townDay } from './town_day.mjs';

const db = await realDatabase();
const CITY = 'City of St. Joseph';
const PLANNING = (await db.query(`select id from public.city_boards where name = 'Planning Commission'`)).rows[0].id;

/// "Every Tuesday" for the weekday of a Town day.
const every = (day) => `Every ${new Date(`${day}T12:00:00Z`).toLocaleDateString('en-US', { weekday: 'long', timeZone: 'UTC' })}`;

async function reset() {
  await db.exec('reset role; delete from public.club_events;');
}

const event = (title, days, o = {}) => db.query(
  `insert into public.club_events (title, status, kind, source_name, draw, event_date, start_time, cancelled_at)
   values ($1, $2, 'event', $3, $4, $5, '6 PM', $6) returning id`,
  [title, o.status ?? 'approved', o.source ?? CITY, o.draw ?? 2, townDay(days), o.cancelled ?? null])
  .then((r) => r.rows[0].id);

/// Each Event's card's repeat, read signed out, as the app reads the Town feed.
async function repeats(ids) {
  await db.exec('set role anon');
  try {
    const { rows } = await db.query('select id, card from private.event_cards($1::uuid[])', [ids]);
    return Object.fromEntries(rows.map((r) => [r.id, r.card.recurrence]));
  } finally {
    await db.exec('reset role');
  }
}

test("every week of a weekly series says how it repeats; a one-off, two dates and a called-off week don't", async () => {
  await reset();
  const weeks = [await event('Trivia Night', 1), await event('trivia night ', 8), await event('Trivia Night', 15)];
  const off = await event('Trivia Night', 22, { cancelled: new Date().toISOString() });
  const once = await event('Fall Market', 3);
  const twice = [await event('Book Club', 2), await event('Book Club', 9)];
  const elsewhere = await event('Trivia Night', 4, { source: "Sal's Bar and Grill" });
  const waiting = [await event('Yoga', 2), await event('Yoga', 9), await event('Yoga', 16, { status: 'pending' })];
  const got = await repeats([...weeks, off, once, ...twice, elsewhere, ...waiting]);
  for (const id of weeks) assert.equal(got[id], every(townDay(1)), 'title case and spaces are one series');
  assert.equal(got[off], null, "called off: it isn't happening that week");
  assert.equal(got[once], null);
  assert.deepEqual(twice.map((id) => got[id]), [null, null], 'two dates are no pattern yet');
  assert.equal(got[elsewhere], null, "another host's Trivia Night is its own series");
  assert.deepEqual(waiting.slice(0, 2).map((id) => got[id]), [null, null], 'a date waiting for Review is no week of it');
});

test('only the last 60 days count, as in the Town feed', async () => {
  await reset();
  await event('Rod and Gun Club', -70);
  await event('Rod and Gun Club', -63);
  const next = await event('Rod and Gun Club', 1);
  const kept = [await event('Ladies Night', -56), await event('Ladies Night', -49), await event('Ladies Night', -42)];
  const got = await repeats([next, ...kept]);
  assert.equal(got[next], null, 'weeks past the window are gone');
  assert.equal(got[kept[0]], every(townDay(-56)), 'past weeks inside it still say it');
});

test("a Town page's and a City board's Event rows say how they repeat", async () => {
  await reset();
  for (const days of [1, 8, 15]) await event('Planning Commission', days, { draw: 1 });
  await event('Park Board Meeting', 3, { draw: 1 });
  await db.exec('set role anon');
  const city = (await db.query(`select public.town_page('st-joseph-mn', 'city') p`)).rows[0].p;
  const meetings = (await db.query('select public.board_meetings($1) m', [PLANNING])).rows[0].m;
  await db.exec('reset role');
  assert.deepEqual(city.events.map((e) => [e.title, e.recurrence]), [
    ['Planning Commission', every(townDay(1))],
    ['Park Board Meeting', null],
    ['Planning Commission', every(townDay(1))],
    ['Planning Commission', every(townDay(1))],
  ]);
  assert.deepEqual(meetings.map((m) => [m.date, m.recurrence]),
                   [1, 8, 15].map((days) => [townDay(days), every(townDay(1))]));
});
