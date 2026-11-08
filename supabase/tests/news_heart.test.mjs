// News gets a heart (BP app docs/plans/inside-cards/issues/22-news-heart.md, Jesse's yes in 05): a heart on a
// story is kept in news_likes, as an Event's is in event_likes; the Town feed and Following say whether you
// hearted each story and how many have; You's Liked lists it until it leaves the feed; and Jesse's weekly
// numbers count it as a heart, never as acting on an Event. Run: `npm install && npm test` in this folder.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { realDatabase, people, adminClaims } from './fixture.mjs';

const db = await realDatabase();
const ME = '00000000-0000-0000-0000-00000000000a';
const NEIGHBOUR = '00000000-0000-0000-0000-00000000000b';

async function reset() {
  await db.exec(`reset role; reset request.jwt.claim.sub; reset request.jwt.claims;
                 delete from public.news_likes; delete from public.news_views; delete from public.board_items;
                 delete from public.event_likes; delete from public.club_events; delete from public.town_follows;
                 delete from public.places; delete from auth.users;`);
  await people(db, ME, NEIGHBOUR);
}

// A story as the morning job publishes it, at a Town time ("2026-10-08 09:00").
async function story(title, published, more = {}) {
  const row = { source_name: 'The Wandering Cow', status: 'published', ends_on: null, place_entry_id: null, ...more };
  const { rows } = await db.query(
    `insert into public.board_items (title, blurb, category, source_name, source_url, status, published_at, ends_on,
       place_entry_id)
     values ($1, $1 || ', in a line.', 'business', $2, 'https://www.instagram.com/p/x/', $3,
             $4::timestamp at time zone 'America/Chicago', $5, $6)
     returning id`,
    [title, row.source_name, row.status, published, row.ends_on, row.place_entry_id]);
  return rows[0].id;
}

async function as(who) {
  await db.exec(who ? `set role authenticated; set request.jwt.claim.sub = '${who}'`
                    : 'set role anon; reset request.jwt.claim.sub');
}

async function heart(who, item) {
  await db.exec('reset role');
  await db.query('insert into public.news_likes (user_id, item_id) values ($1, $2)', [who, item]);
}

const count = async () => (await db.query('select count(*)::int as n from public.news_likes')).rows[0].n;

test('a heart on a story is your own: you give and take back yours, never a neighbour\'s, and signed out can\'t', async () => {
  await reset();
  const cow = await story('Flight Friday', '2026-10-08 09:00');
  await as(ME);
  // As the app writes it: presence only, a second tap changes nothing.
  for (let i = 0; i < 2; i++) {
    await db.query('insert into public.news_likes (user_id, item_id) values ($1, $2) on conflict (user_id, item_id) do nothing',
                   [ME, cow]);
  }
  await assert.rejects(db.query('insert into public.news_likes (user_id, item_id) values ($1, $2)', [NEIGHBOUR, cow]),
                       /row-level security/, 'never as someone else');
  await heart(NEIGHBOUR, cow);
  await as(ME);
  assert.deepEqual((await db.query('select user_id from public.news_likes')).rows.map((r) => r.user_id), [ME],
                   "nobody reads who else hearted it");
  await db.query('delete from public.news_likes where item_id = $1', [cow]);
  await as(null);
  await assert.rejects(db.query('insert into public.news_likes (user_id, item_id) values ($1, $2)', [ME, cow]),
                       /permission denied/, 'signed out gives none');
  await assert.rejects(db.query('delete from public.news_likes'), /permission denied/, 'and takes none back');
  await db.exec('reset role');
  assert.equal(await count(), 1, "your delete took back yours alone: the neighbour's stays");
  await db.query('delete from public.board_items where id = $1', [cow]);
  assert.equal(await count(), 0, 'a story deleted takes its hearts with it');
});

// The News rows of the Town feed and of Following, as the app reads them: the heart is right on the first frame.
async function newsRows(read, who) {
  await as(who);
  const call = read === 'feed' ? 'public.get_town_feed($1::timestamp at time zone \'America/Chicago\', true)'
                               : 'public.get_following_news($1::timestamp at time zone \'America/Chicago\')';
  const { rows } = await db.query(`select title, heart_count, hearted from ${call} where kind = 'news' order by title`,
                                  ['2026-10-08 12:00']);
  await db.exec('reset role');
  return rows.map((r) => [r.title, r.heart_count, r.hearted]);
}

test("the Town feed's News says whether you hearted it and how many have, signed out too", async () => {
  await reset();
  const cow = await story('Flight Friday', '2026-10-08 09:00');
  await story('Taco Tuesday', '2026-10-08 10:00', { source_name: 'Neighbors Route 75' });
  await heart(ME, cow);
  await heart(NEIGHBOUR, cow);
  assert.deepEqual(await newsRows('feed', ME), [['Flight Friday', 2, true], ['Taco Tuesday', 0, false]]);
  assert.deepEqual(await newsRows('feed', null), [['Flight Friday', 2, false], ['Taco Tuesday', 0, false]]);
});

test("Following's News says the same, a story you've seen too", async () => {
  await reset();
  const { rows: [{ id: place }] } = await db.query(
    `insert into public.places (lat, lon, family, name, entry_id) values (45.5, -94.3, 'business', 'White Peony', 'white-peony')
     returning id`);
  await db.query(`insert into public.town_follows (follower_id, target_type, target_id) values ($1, 'place', $2)`, [ME, place]);
  const peony = { source_name: 'White Peony', place_entry_id: 'white-peony' };
  const arrivals = await story('Fall arrivals', '2026-10-08 09:00', peony);
  await story('Layer up', '2026-10-08 08:00', peony);
  await heart(ME, arrivals);
  await heart(NEIGHBOUR, arrivals);
  await db.query('insert into public.news_views (user_id, item_id) values ($1, $2)', [ME, arrivals]);
  assert.deepEqual(await newsRows('following', ME), [['Fall arrivals', 2, true], ['Layer up', 0, false]]);
});

// You's Liked as the app reads it (PostgREST's rows, json_agg), at a Town time, from that Town day on.
async function liked(at, who = ME) {
  await as(who);
  const { rows } = await db.query(
    `select coalesce(json_agg(t), '[]')::text as body
     from (select * from public.get_my_likes(($1::timestamp)::date, $1::timestamp at time zone 'America/Chicago')) t`, [at]);
  await db.exec('reset role');
  return JSON.parse(rows[0].body);
}
const likedNews = async (at) => (await liked(at)).filter((r) => r.news).map((r) => r.news.title);

test('Liked lists the stories you hearted after the Events, newest first, as the feed sends a News row', async () => {
  await reset();
  const { rows: [{ id: trivia }] } = await db.query(
    `insert into public.club_events (title, event_date, source_name, status, kind)
     values ('Trivia night', '2026-10-13', 'City of St. Joseph', 'approved', 'event') returning id`);
  await db.query('insert into public.event_likes (event_id, user_id) values ($1, $2)', [trivia, ME]);
  const cow = await story('Flight Friday', '2026-10-08 09:00');
  const taco = await story('Taco Tuesday', '2026-10-07 10:00', { source_name: 'Neighbors Route 75' });
  await story('Not yours', '2026-10-08 10:00');
  await heart(ME, taco);
  await heart(ME, cow);
  await heart(NEIGHBOUR, cow);
  await heart(NEIGHBOUR, (await db.query(`select id from public.board_items where title = 'Not yours'`)).rows[0].id);
  const rows = await liked('2026-10-08 12:00');
  assert.deepEqual(rows.map((r) => r.card?.title ?? r.news.title), ['Trivia night', 'Flight Friday', 'Taco Tuesday']);
  assert.deepEqual(rows.map((r) => Object.keys(r)), [['card', 'news'], ['card', 'news'], ['card', 'news']]);
  assert.equal(rows[0].news, null, 'an Event is its card alone');
  assert.equal(rows[1].card, null, 'a story has no Event card, so a build from before this leaves it out');
  const { news } = rows[1];
  assert.deepEqual(Object.keys(news).sort(), ['created_at', 'description', 'heart_count', 'hearted', 'id', 'image_url',
    'kind', 'leaves_at', 'place_picture', 'poster', 'source_name', 'source_url', 'title']);
  assert.deepEqual([news.id, news.kind, news.source_name, news.description, news.source_url, news.heart_count, news.hearted],
                   [cow, 'news', 'The Wandering Cow', 'Flight Friday, in a line.', 'https://www.instagram.com/p/x/', 2, true]);
  assert.equal(Date.parse(news.created_at), Date.parse('2026-10-08T14:00:00Z'), 'published, as the feed says it');
  // The moment it leaves is the Town feed's own.
  await as(ME);
  const { rows: [feed] } = await db.query(
    `select leaves_at from public.get_town_feed('2026-10-08 12:00'::timestamp at time zone 'America/Chicago', true)
     where id = $1`, [cow]);
  await db.exec('reset role');
  assert.equal(Date.parse(news.leaves_at), feed.leaves_at.getTime());
  await db.query('delete from public.news_likes where item_id = $1 and user_id = $2', [taco, ME]);
  assert.deepEqual(await likedNews('2026-10-08 12:00'), ['Flight Friday'], 'a heart taken back leaves it');
});

test('a hearted story leaves Liked when it leaves the Town feed: its date, 7 days, 30 at most, or taken out', async () => {
  await reset();
  for (const [title, published, more] of [
    ['Pumpkin Pie Shake', '2026-10-01 12:00', {}],
    ['Sale ends tomorrow', '2026-10-08 09:00', { ends_on: '2026-10-09' }],
    ['Pass through spring', '2026-10-08 09:00', { ends_on: '2027-04-30' }],
    ['Taken out', '2026-10-08 09:00', { status: 'archived' }],
  ]) await heart(ME, await story(title, published, more));
  assert.deepEqual((await likedNews('2026-10-08 11:59')).sort(),
                   ['Pass through spring', 'Pumpkin Pie Shake', 'Sale ends tomorrow'], 'archived is out from the start');
  assert.deepEqual((await likedNews('2026-10-08 12:01')).sort(), ['Pass through spring', 'Sale ends tomorrow'], 'its 7 days');
  assert.deepEqual(await likedNews('2026-10-10 00:01'), ['Pass through spring'], 'midnight after its date');
  assert.deepEqual(await likedNews('2026-11-07 11:00'), [], 'never past 30 days');
});

test('Liked: signed out still can\'t ask', async () => {
  await reset();
  await as(null);
  await assert.rejects(db.query(`select * from public.get_my_likes('2026-10-08')`), /permission denied/);
  await db.exec('reset role');
});

test("Jesse's weekly numbers count a story's heart as a heart, never as acting on an Event (inside-cards 05)", async () => {
  await reset();
  const { rows: [{ id: quiz }] } = await db.query(`insert into public.club_events (title) values ('Quiz') returning id`);
  await db.query(`insert into public.event_likes (event_id, user_id, created_at) values ($1, $2, '2026-10-20 09:00-05')`, [quiz, ME]);
  const cow = await story('Flight Friday', '2026-10-19 09:00');
  await db.query(`insert into public.news_likes (user_id, item_id, created_at) values ($1, $2, '2026-10-20 10:00-05')`, [ME, cow]);
  await db.query(`insert into public.news_likes (user_id, item_id, created_at) values ($1, $2, '2026-10-26 10:00-05')`, [NEIGHBOUR, cow]);
  await db.exec(`set request.jwt.claims = '${await adminClaims()}'; set role authenticated`);
  const { rows: [w] } = await db.query(`select * from public.weekly_numbers('2026-10-21')`);
  await db.exec('reset role; reset request.jwt.claims');
  assert.deepEqual([w.hearts, w.acted_on, w.actors, w.openers], [2, 0, 0, 0], "the quiz's and the story's; the next week's waits");
});
