// Fixed stories for get_town_calendar (supabase/migrations/*_town_calendar.sql), Search's Event calendar
// (BP app five-tabs 10, 11): a year of public Events from the 1st of this month, every date of a series, months
// before the show-from day.
// Run in PGlite like the Town feed's: `npm install && npm test` in this folder.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { realDatabase, people } from './fixture.mjs';
import { CARD_KEYS } from './event_card.mjs';

const db = await realDatabase();
const CITY = 'City of St. Joseph';
const ME = '00000000-0000-0000-0000-00000000000a';
const NEIGHBOUR = '00000000-0000-0000-0000-00000000000b';
const GROUP = '00000000-0000-0000-0000-00000000c001';
// Friday Nov 13 2026, noon in the Town: the calendar runs from Nov 1 2026 to Oct 31 2027.
const NOW = `('2026-11-13 12:00'::timestamp at time zone 'America/Chicago')`;

async function reset() {
  await db.exec(`reset role; delete from public.event_rsvps; delete from public.event_likes;
                 delete from public.feed_actions; delete from public.feed_mutes;
                 delete from public.club_events; delete from public.clubs; delete from private.friendships;
                 delete from public.town_profiles; delete from auth.users;
                 delete from public.place_photos; reset request.jwt.claim.sub;`);
  await people(db, ME, NEIGHBOUR);
  await db.query(`insert into public.clubs (id, name) values ($1, 'Book Club')`, [GROUP]);
}

async function add(title, date, more = {}) {
  const row = { source_name: CITY, status: 'approved', kind: 'event', submitted_by: null, club_id: null,
                end_at: null, followers_only: false, friends_only: false, cancelled_at: null, shows_from: null, ...more };
  const { rows } = await db.query(
    `insert into public.club_events (title, event_date, source_name, status, kind, submitted_by, club_id, end_at,
                                     followers_only, friends_only, cancelled_at, shows_from)
     values ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12) returning id`,
    [title, date, row.source_name, row.status, row.kind, row.submitted_by, row.club_id, row.end_at,
     row.followers_only, row.friends_only, row.cancelled_at, row.shows_from]);
  return rows[0].id;
}

async function calendar(as = ME) {
  await db.exec(as ? `set role authenticated; set request.jwt.claim.sub = '${as}'` : 'set role anon');
  const { rows } = await db.query(`select card from public.get_town_calendar(${NOW})`);
  await db.exec('reset role; reset request.jwt.claim.sub');
  return rows.map((r) => r.card);
}

const titles = async (as) => (await calendar(as)).map((c) => `${c.event_date} ${c.title}`);

test('public Events only: no Group post, nothing for followers or friends alone, nothing called off, no post', async () => {
  await reset();
  await add('Bake sale', '2026-11-20');
  await add('Book club meets', '2026-11-20', { club_id: GROUP, source_name: null, submitted_by: NEIGHBOUR });
  await add('JV game', '2026-11-20', { followers_only: true });
  await add('Friends dinner', '2026-11-20', { friends_only: true, source_name: null, submitted_by: NEIGHBOUR });
  await add('Called off', '2026-11-20', { cancelled_at: '2026-11-10 12:00+00' });
  await add('A post', '2026-11-20', { kind: 'post' });
  await add('Pending', '2026-11-20', { status: 'pending' });
  assert.deepEqual(await titles(), ['2026-11-20 Bake sale']);
});

test('the whole year from the first of this month, every earlier day of it too, every date of a series, past its show-from day', async () => {
  await reset();
  await add('Last month', '2026-10-31');
  await add('First of the month', '2026-11-01', { end_at: '2026-11-14 05:00+00' });
  await add('Earlier this month', '2026-11-05');
  for (const day of ['2026-11-17', '2026-11-24', '2026-12-01']) await add('Bingo night', day);
  await add('Spring gala', '2027-04-09', { shows_from: '2027-02-12' });
  await add('Last day', '2027-10-31');
  await add('A year on', '2027-11-01');
  assert.deepEqual(await titles(), ['2026-11-01 First of the month', '2026-11-05 Earlier this month',
                                    '2026-11-17 Bingo night',
                                    '2026-11-24 Bingo night', '2026-12-01 Bingo night',
                                    '2027-04-09 Spring gala', '2027-10-31 Last day']);
});

test('Not interested keeps out every date of the series, Mute its host; only for the one who asked', async () => {
  await reset();
  const bingo = await add('Bingo night', '2026-11-17', { source_name: 'Legion' });
  await add('Bingo night', '2026-11-24', { source_name: 'Legion' });
  const raffle = await add('Meat raffle', '2026-11-20', { source_name: 'Sals' });
  await add('Trivia', '2026-11-21', { source_name: 'Sals' });
  await add('Bake sale', '2026-11-22');
  await db.exec(`set role authenticated; set request.jwt.claim.sub = '${ME}'`);
  await db.query('select public.set_not_interested($1)', [bingo]);
  await db.query('select public.mute_host($1)', [raffle]);
  await db.exec('reset role; reset request.jwt.claim.sub');
  assert.deepEqual(await titles(ME), ['2026-11-22 Bake sale']);
  assert.equal((await titles(NEIGHBOUR)).length, 5);
});

test('signed out reads the same public Events, each with every card key', async () => {
  await reset();
  const id = await add('Bake sale', '2026-11-20');
  await db.query('insert into public.event_rsvps (event_id, user_id) values ($1, $2)', [id, NEIGHBOUR]);
  const cards = await calendar(null);
  assert.deepEqual(cards.map((c) => [c.title, c.going_count, c.going]), [['Bake sale', 1, false]]);
  assert.deepEqual(Object.keys(cards[0]).sort(), [...CARD_KEYS].sort());
});

test('in day order, then by title', async () => {
  await reset();
  await add('Zumba', '2026-11-20');
  await add('Book swap', '2026-11-20');
  await add('Hike', '2026-11-15');
  assert.deepEqual(await titles(), ['2026-11-15 Hike', '2026-11-20 Book swap', '2026-11-20 Zumba']);
});
