// Fixed stories for the City and Joetown pages (supabase/migrations/*_city_pages.sql, BP app
// docs/plans/follows, ticket 04): a page and a board each round-trip as a follow, the count is real,
// an Anonymous caller can't follow, the City's page lists its boards with each one's next meeting, a
// board's meetings, the Following list, and a meeting's Event page naming its board. PGlite, like the
// others: `npm install && npm test` in this folder.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { realDatabase } from './fixture.mjs';
import { townDay } from './town_day.mjs';
import { CARD_KEYS } from './event_card.mjs';

const db = await realDatabase();
const id = (n) => `00000000-0000-0000-0000-${String(n).padStart(12, '0')}`;
const [ANA, BEN, CAL, ANON] = [1, 2, 3, 4].map(id);
const soon = townDay;
const page = async (slug) => (await db.query(`select id from public.town_pages where town = 'st-joseph-mn' and slug = $1`,
                                             [slug])).rows[0].id;
const board = async (name) => (await db.query(`select id from public.city_boards where name = $1`, [name])).rows[0].id;
const [CITY, JOETOWN] = [await page('city'), await page('town')];
const [COUNCIL, PARKS] = [await board('City Council'), await board('Park Board')];

async function reset() {
  await db.exec(`reset role; reset request.jwt.claims;
    delete from private.friend_requests; delete from private.friendships;
    delete from public.town_follows; delete from public.club_events; delete from public.town_profiles;
    delete from auth.users;`);
  for (const [who, name] of [[ANA, 'Ana Lee'], [BEN, 'Ben Ortiz'], [CAL, 'Cal Ruiz']]) {
    await db.query('insert into auth.users (id) values ($1)', [who]);
    await db.query('insert into public.town_profiles (user_id, display_name) values ($1, $2)', [who, name]);
  }
  await db.query('insert into auth.users (id, is_anonymous) values ($1, true)', [ANON]);
}

async function as(who, sql, params = [], { anonymous = false } = {}) {
  await db.exec(`set role authenticated; set request.jwt.claims = '${JSON.stringify({ sub: who, is_anonymous: anonymous })}'`);
  try {
    return (await db.query(sql, params)).rows;
  } finally {
    await db.exec('reset role; reset request.jwt.claims');
  }
}
const follow = async (who, type, target, o) => (await as(who, 'select public.follow_target($1, $2) as r', [type, target], o))[0].r;
const unfollow = async (who, type, target) => (await as(who, 'select public.unfollow_target($1, $2) as r', [type, target]))[0].r;
const card = async (who, type, target) => (await as(who, 'select * from public.follow_card($1, $2)', [type, target]))[0];
const event = (title, source, days, o = {}) => db.query(
  `insert into public.club_events (title, status, source_name, draw, event_date, start_time, location, cancelled_at)
   values ($1, 'approved', $2, $3, $4, $5, $6, $7) returning id`,
  [title, source, o.draw ?? 1, soon(days), o.time ?? '18:00', o.location ?? null, o.cancelled ?? null])
  .then((r) => r.rows[0].id);

test('the City, Joetown and a board each round-trip as a follow, twice each way', async () => {
  await reset();
  for (const [type, target] of [['page', CITY], ['page', JOETOWN], ['board', COUNCIL]]) {
    assert.equal(await follow(ANA, type, target), true);
    assert.equal(await follow(ANA, type, target), true);
    assert.equal((await card(ANA, type, target)).following, true);
    assert.equal(await unfollow(ANA, type, target), false);
    assert.equal(await unfollow(ANA, type, target), false);
    assert.equal((await card(ANA, type, target)).following, false);
  }
  await assert.rejects(follow(ANA, 'page', COUNCIL), /not_followable/, "a board's id is no page");
  await assert.rejects(follow(ANA, 'board', id(999)), /not_followable/);
});

test('the count is real: only those who follow, and never the people', async () => {
  await reset();
  await follow(ANA, 'page', CITY);
  await follow(BEN, 'page', CITY);
  await follow(BEN, 'board', PARKS);
  assert.deepEqual(await card(CAL, 'page', CITY), { following: false, followers: 2, friends: [], friends_count: 0 });
  assert.equal((await card(CAL, 'page', JOETOWN)).followers, 0);
  assert.equal((await card(CAL, 'board', PARKS)).followers, 1);
  assert.equal((await card(CAL, 'board', COUNCIL)).followers, 0, "a board's follow is that board's alone");
});

test("an Anonymous caller can't follow a page or a board", async () => {
  await reset();
  await assert.rejects(follow(ANON, 'page', CITY, { anonymous: true }), /real account/);
  await assert.rejects(follow(ANON, 'board', COUNCIL, { anonymous: true }), /real account/);
  assert.equal((await db.query('select count(*)::int n from public.town_follows')).rows[0].n, 0);
});

test("the City's page lists its boards A to Z, each with its next meeting and your Follow", async () => {
  await reset();
  await event('City Council Meeting', 'City of St. Joseph', 9);
  await event('City Council Work Session', 'City of St. Joseph', 2, { time: '17:00' });
  await event('City Council Meeting', 'City of St. Joseph', -3);
  await event('City Council Meeting', 'City of St. Joseph', 1, { cancelled: new Date().toISOString() });
  await event('Park Board Meeting', 'City of St. Joseph', 5);
  await event('Board of Appeal and Equalization', 'City of St. Joseph', 4);
  await event('Winterwalk', 'JoeTown', 6, { draw: 2, location: 'Downtown' });
  await follow(ANA, 'board', PARKS);

  const [{ p: city }] = await as(ANA, `select public.town_page('st-joseph-mn', 'city') p`);
  assert.equal(city.id, CITY);
  assert.equal(city.name, 'City of St. Joseph');
  assert.deepEqual(city.boards.map((b) => [b.name, b.next?.date ?? null, b.following]), [
    ['City Council', soon(2), false],
    ['Economic Development Authority', null, false],
    ['Joint Planning Board', null, false],
    ['Park Board', soon(5), true],
    ['Planning Commission', null, false],
  ]);
  assert.equal(city.boards[0].next.time, '17:00');
  assert.deepEqual(city.events.map((e) => e.title),
                   ['City Council Work Session', 'Board of Appeal and Equalization', 'Park Board Meeting',
                    'City Council Meeting'], "its own coming Events, soonest first, none past or canceled");

  const [{ p: joetown }] = await as(ANA, `select public.town_page('st-joseph-mn', 'town') p`);
  assert.equal(joetown.name, 'Joetown');
  assert.equal(joetown.picture_kind, 'town');
  assert.deepEqual(joetown.boards, [], 'Joetown has no boards');
  assert.deepEqual(joetown.events.map((e) => [e.title, e.location]), [['Winterwalk', 'Downtown']]);

  await db.exec('set role anon');
  const signedOut = (await db.query(`select public.town_page('st-joseph-mn', 'city') p`)).rows[0].p;
  await db.exec('reset role');
  assert.equal(signedOut.boards.find((b) => b.name === 'Park Board').following, false, 'signed out follows nothing');
});

test("a board's meetings: its own, coming, soonest first", async () => {
  await reset();
  await event('City Council Meeting', 'City of St. Joseph', 9, { location: 'City Hall' });
  await event('City Council Work Session', 'City of St. Joseph', 2);
  await event('City Council Meeting', 'City of St. Joseph', -1);
  await event('Park Board Meeting', 'City of St. Joseph', 3);
  await db.exec('set role anon');
  const meetings = (await db.query('select public.board_meetings($1) m', [COUNCIL])).rows[0].m;
  await db.exec('reset role');
  assert.deepEqual(meetings.map((m) => [m.title, m.date, m.location]), [
    ['City Council Work Session', soon(2), null],
    ['City Council Meeting', soon(9), 'City Hall'],
  ]);
});

test('the Following list names pages and boards, and a meeting names its board, else the City', async () => {
  await reset();
  await follow(ANA, 'page', JOETOWN);
  await follow(ANA, 'board', COUNCIL);
  assert.deepEqual((await as(ANA, 'select target_type, name, kind, picture_kind from public.my_follows()')), [
    { target_type: 'board', name: 'City Council', kind: 'City of St. Joseph', picture_kind: null },
    { target_type: 'page', name: 'Joetown', kind: "St. Joseph's events", picture_kind: 'town' },
  ]);

  const council = await event('City Council Meeting', 'City of St. Joseph', 3);
  const appeal = await event('Board of Appeal and Equalization', 'City of St. Joseph', 4);
  const host = async (e) => (await as(CAL, 'select target_type, target_id, name, kind from public.event_host($1)', [e]))[0];
  assert.deepEqual(await host(council), { target_type: 'board', target_id: COUNCIL, name: 'City Council',
                                          kind: 'City of St. Joseph' });
  assert.deepEqual(await host(appeal), { target_type: 'page', target_id: CITY, name: 'City of St. Joseph',
                                         kind: 'City government' });
});

test("a campus calendar is a page: a follow round-trips, it lists its own Events, and its Event names it", async () => {
  await reset();
  const LIBRARIES = await page('csbsju-libraries');
  assert.equal(await follow(ANA, 'page', LIBRARIES), true);
  assert.equal((await card(BEN, 'page', LIBRARIES)).followers, 1);
  const clinic = await event('Fix-It Clinic', 'CSB SJU Libraries', 2, { draw: 2, time: '3 PM' });
  await event('Women in Politics', 'CSB SJU Campus Events', 2, { draw: 2 });
  const read = (await as(CAL, `select public.town_page('st-joseph-mn', 'csbsju-libraries') as p`))[0].p;
  assert.deepEqual([read.name, read.kind, read.picture_kind, read.picture_credit, read.events.map((e) => e.title), read.boards],
                   ['CSB SJU Libraries', 'College', 'photo', 'csbsju.edu', ['Fix-It Clinic'], []]);
  assert.deepEqual((await as(CAL, 'select public.town_page_by_id($1) as p', [LIBRARIES]))[0].p, read, 'by its id, the same');
  assert.deepEqual(await as(CAL, 'select target_type, target_id, name from public.event_host($1)', [clinic]),
                   [{ target_type: 'page', target_id: LIBRARIES, name: 'CSB SJU Libraries' }]);
  assert.equal((await db.query(`select count(*)::int n from public.town_pages where kind = 'College'`)).rows[0].n, 5);
});

// Every door to the Event page carries its card (BP app inside-cards 27): a Town page's Events and a board's meetings
// each send the Event card, so a page opened from one shows your heart and its count before any other read, even for
// an Event outside the Town feed's window. The row's own keys stay for apps from before it.
const heart = (who, e) => db.query('insert into public.event_likes (event_id, user_id) values ($1, $2)', [e, who]);

test("a Town page's Events each send the Event card, with your heart and its count", async () => {
  await reset();
  const winterwalk = await event('Winterwalk', 'JoeTown', 40, { draw: 2, location: 'Downtown' });
  await event('Shop Small Crawl', 'JoeTown', 3, { draw: 2 });
  await heart(ANA, winterwalk);
  await heart(BEN, winterwalk);
  const [{ p }] = await as(ANA, `select public.town_page('st-joseph-mn', 'town') p`);
  assert.deepEqual(p.events.map((e) => [e.title, e.card.id === e.id]), [['Shop Small Crawl', true], ['Winterwalk', true]]);
  for (const e of p.events) assert.deepEqual(Object.keys(e.card).sort(), CARD_KEYS);
  assert.deepEqual(p.events.map((e) => [e.card.hearted, e.card.heart_count]), [[false, 0], [true, 2]]);
  assert.deepEqual(Object.keys(p.events[1]).sort(), ['card', 'date', 'id', 'location', 'recurrence', 'time', 'title'],
                   'the row keeps its own keys for apps from before the card');

  await db.exec('set role anon');
  const signedOut = (await db.query(`select public.town_page('st-joseph-mn', 'town') p`)).rows[0].p;
  await db.exec('reset role');
  assert.deepEqual(signedOut.events.map((e) => [e.card.hearted, e.card.heart_count]), [[false, 0], [false, 2]],
                   'signed out: the count, never a heart of its own');
});

test("a board's meetings each send the Event card, with your heart and its count", async () => {
  await reset();
  const far = await event('City Council Meeting', 'City of St. Joseph', 45, { location: 'City Hall' });
  await event('City Council Work Session', 'City of St. Joseph', 2);
  await heart(ANA, far);
  await heart(CAL, far);
  await heart(BEN, far);
  const [{ m }] = await as(ANA, 'select public.board_meetings($1) m', [COUNCIL]);
  assert.deepEqual(m.map((e) => [e.title, e.card.id === e.id]),
                   [['City Council Work Session', true], ['City Council Meeting', true]]);
  for (const e of m) assert.deepEqual(Object.keys(e.card).sort(), CARD_KEYS);
  assert.deepEqual(m.map((e) => [e.card.hearted, e.card.heart_count]), [[false, 0], [true, 3]]);
  assert.deepEqual(Object.keys(m[1]).sort(), ['card', 'date', 'id', 'location', 'recurrence', 'time', 'title'],
                   'the row keeps its own keys for apps from before the card');
});
