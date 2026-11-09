// Fixed stories for get_my_going (supabase/migrations/*_my_going.sql), the You tab's read of
// the caller's Going, and get_my_likes (*_heart_replaces_save.sql), You's Liked list (its stories in
// news_heart.test.mjs), run in PGlite like the Town feed's. Run: `npm install && npm test` in this folder.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { realDatabase, people } from './fixture.mjs';
import { townDay } from './town_day.mjs';
import { CARD_KEYS } from './event_card.mjs';

const db = await realDatabase();
const CITY = 'City of St. Joseph';
const ME = '00000000-0000-0000-0000-00000000000a';
const NEIGHBOUR = '00000000-0000-0000-0000-00000000000b';

async function reset() {
  await db.exec(`reset role; delete from public.event_rsvps; delete from public.event_likes;
                 delete from public.club_events; delete from private.friendships;
                 delete from public.town_profiles; delete from auth.users;
                 delete from public.clubs; delete from public.sources;
                 delete from public.place_photos; reset request.jwt.claim.sub;`);
  await people(db, ME, NEIGHBOUR);
}

async function add(title, date, more = {}) {
  const row = { source_name: CITY, status: 'approved', kind: 'event', submitted_by: null,
                club_id: null, end_at: null, ...more };
  const { rows } = await db.query(
    `insert into public.club_events (title, event_date, source_name, status, kind, submitted_by, club_id, end_at)
     values ($1, $2, $3, $4, $5, $6, $7, $8) returning id`,
    [title, date, row.source_name, row.status, row.kind, row.submitted_by, row.club_id, row.end_at]);
  return rows[0].id;
}

async function going(user, eventId) {
  await db.query('insert into public.event_rsvps (event_id, user_id) values ($1, $2)', [eventId, user]);
}

async function mine(from, to, as = ME) {
  await db.exec(`set role authenticated; set request.jwt.claim.sub = '${as}'`);
  const { rows } = await db.query(`select card from public.get_my_going($1::date, $2::date)`, [from, to]);
  await db.exec('reset role');
  return rows.map((r) => ({ ...r.card, day: r.card.event_date }));
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
  const { rows } = await db.query(`insert into public.clubs (name, status) values ('Bike club', 'approved') returning id`);
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

test('a called-off Event still comes back, saying so: the app tells the people Going', async () => {
  await reset();
  const game = await add('Sartell Volleyball vs ROCORI', '2026-10-20');
  await going(ME, game);
  await going(ME, await add('Trivia night', '2026-10-21'));
  await db.query('update public.club_events set cancelled_at = now() where id = $1', [game]);
  const rows = await mine('2026-10-11', '2026-10-31');
  assert.deepEqual(rows.map((r) => [r.title, r.cancelled]),
                   [['Sartell Volleyball vs ROCORI', true], ['Trivia night', false]]);
});

// get_my_likes: You's Liked list (BP app inside-cards 16), which took over Saved (you-tab 04): what you hearted.

async function heart(user, eventId) {
  await db.query('insert into public.event_likes (event_id, user_id) values ($1, $2)', [eventId, user]);
}

async function liked(from, as = ME) {
  await db.exec(`set role authenticated; set request.jwt.claim.sub = '${as}'`);
  const { rows } = await db.query(`select card from public.get_my_likes($1::date)`, [from]);
  await db.exec('reset role');
  return rows.map((r) => ({ ...r.card, day: r.card.event_date }));
}

test('Liked: only the caller\'s own, with every account\'s Going count', async () => {
  await reset();
  const trivia = await add('Trivia night', '2026-10-13');
  const market = await add('Fall market', '2026-10-24');
  await heart(ME, trivia);
  await heart(NEIGHBOUR, market);
  await going(NEIGHBOUR, trivia);
  const rows = await liked('2026-10-12');
  assert.deepEqual(rows.map((r) => [r.title, r.going_count]), [['Trivia night', 1]]);
});

test('Liked: a heart taken back leaves the list', async () => {
  await reset();
  const trivia = await add('Trivia night', '2026-10-13');
  await heart(ME, trivia);
  assert.deepEqual((await liked('2026-10-12')).map((r) => r.title), ['Trivia night']);
  await db.query('delete from public.event_likes where event_id = $1 and user_id = $2', [trivia, ME]);
  assert.deepEqual(await liked('2026-10-12'), []);
});

test('Liked: from the given day on, with no end; earlier days left out', async () => {
  await reset();
  for (const [title, day] of [['Yesterday', '2026-10-11'], ['Today', '2026-10-12'], ['Next year', '2027-10-12']]) {
    await heart(ME, await add(title, day));
  }
  const rows = await liked('2026-10-12');
  assert.deepEqual(rows.map((r) => r.title), ['Today', 'Next year']);
});

test('Liked: an Event that began before the day and is still running stays', async () => {
  await reset();
  await heart(ME, await add('Festival', '2026-10-10', { end_at: new Date(Date.now() + 86400000).toISOString() }));
  await heart(ME, await add('Over', '2026-10-10', { end_at: new Date(Date.now() - 86400000).toISOString() }));
  const rows = await liked('2026-10-12');
  assert.deepEqual(rows.map((r) => r.title), ['Festival']);
});

test('Liked: says whether the caller is Going', async () => {
  await reset();
  const trivia = await add('Trivia night', '2026-10-13');
  const market = await add('Fall market', '2026-10-24');
  await heart(ME, trivia);
  await heart(ME, market);
  await going(ME, market);
  await going(NEIGHBOUR, trivia);
  const rows = await liked('2026-10-12');
  assert.deepEqual(rows.map((r) => [r.title, r.going]), [['Trivia night', false], ['Fall market', true]]);
});

test('Liked: says whether the Event is called off', async () => {
  await reset();
  const game = await add('Sartell Volleyball vs ROCORI', '2026-10-20');
  await heart(ME, game);
  await heart(ME, await add('Trivia night', '2026-10-21'));
  await db.query('update public.club_events set cancelled_at = now() where id = $1', [game]);
  const rows = await liked('2026-10-12');
  assert.deepEqual(rows.map((r) => [r.title, r.cancelled]),
                   [['Sartell Volleyball vs ROCORI', true], ['Trivia night', false]]);
});

test('Liked: ordered by day, then title', async () => {
  await reset();
  for (const [title, day] of [['Zumba', '2026-10-14'], ['Book club', '2026-10-14'], ['Hike', '2026-10-13']]) {
    await heart(ME, await add(title, day));
  }
  const rows = await liked('2026-10-12');
  assert.deepEqual(rows.map((r) => `${r.day} ${r.title}`),
                   ['2026-10-13 Hike', '2026-10-14 Book club', '2026-10-14 Zumba']);
});

test('Liked: pending, rejected, a hearted post and events with no host are left out', async () => {
  await reset();
  await heart(ME, await add('Pending', '2026-10-13', { status: 'pending', submitted_by: NEIGHBOUR }));
  await heart(ME, await add('Rejected', '2026-10-13', { status: 'rejected' }));
  await heart(ME, await add('A post', '2026-10-13', { kind: 'post' }));
  await heart(ME, await add('Seeded sample', '2026-10-13', { source_name: null }));
  await heart(ME, await add('Posted by a neighbour', '2026-10-13', { source_name: null, submitted_by: NEIGHBOUR }));
  const rows = await liked('2026-10-12');
  assert.deepEqual(rows.map((r) => r.title), ['Posted by a neighbour']);
});

test('Liked: signed out can\'t ask', async () => {
  await reset();
  await heart(ME, await add('Trivia night', '2026-10-13'));
  await db.exec('set role anon');
  await assert.rejects(db.query(`select * from public.get_my_likes('2026-10-12')`), /permission denied/);
  await db.exec('reset role');
});

test("your Going and your Liked carry each event's place picture", async () => {
  await reset();
  await db.exec(`insert into public.place_photos (entry_id, url, source_url, kind, status)
                 values ('krewe', 'https://x/food.webp', 'https://krewemn.com/', 'photo', 'live')`);
  const id = await add('Trivia', '2026-10-09');
  await db.query(`update public.club_events set place_entry_id = 'krewe' where id = $1`, [id]);
  await going(ME, id);
  await db.query('insert into public.event_likes (event_id, user_id) values ($1, $2)', [id, ME]);
  await db.exec(`set role authenticated; set request.jwt.claim.sub = '${ME}'`);
  const g = (await db.query(`select card from public.get_my_going('2026-10-01', '2026-10-31')`)).rows;
  const s = (await db.query(`select card from public.get_my_likes('2026-10-01')`)).rows;
  await db.exec('reset role; delete from public.place_photos;');
  assert.equal(g[0].card.place_picture.url, 'https://x/food.webp');
  assert.equal(s[0].card.place_picture.url, 'https://x/food.webp');
});

// Friends Going (you-tab 07): the Town feed's helper decides who; its rules (plans off, blocked,
// strangers, Events over, newest first) are town_feed.test.mjs's. These check the You tab carries them.
const FRIEND = '00000000-0000-0000-0000-0000000000c1';
const FRIEND_PHOTO = `https://lxdgwhvqjqmqliobwjpi.supabase.co/storage/v1/object/public/avatars/${FRIEND}/me.jpg`;
// A Town day a few days from now, so the Event is never over when the stories run.
const soon = () => townDay(3);

async function friendsOn(day) {
  await db.exec(`set role authenticated; set request.jwt.claim.sub = '${ME}'`);
  const { rows } = await db.query(`select card from public.get_my_going($1::date, $1::date)`, [day]);
  await db.exec('reset role');
  return rows.map((r) => r.card);
}

test('a friend Going to your plan rides it, first name and photo; nobody, an empty list', async () => {
  await reset();
  const day = soon();
  const quiz = await add('Quiz night', day);
  const fair = await add('Craft fair', day);
  await db.query('insert into auth.users (id) values ($1)', [FRIEND]);
  await db.query(`insert into public.town_profiles (user_id, display_name, avatar_url) values ($1, 'Anna Lee', $2)`,
                 [FRIEND, FRIEND_PHOTO]);
  await db.query('insert into private.friendships (a, b, requested_by) values ($1, $2, $1)', [ME, FRIEND]);
  await going(ME, quiz);
  await going(ME, fair);
  await going(FRIEND, quiz);
  assert.deepEqual((await friendsOn(day)).map((r) => [r.title, r.friends_going]),
                   [['Craft fair', []], ['Quiz night', [{ name: 'Anna', photo: FRIEND_PHOTO }]]]);
});

test('a friend who leaves drops off on the next read', async () => {
  await reset();
  const day = soon();
  const quiz = await add('Quiz night', day);
  await db.query('insert into auth.users (id) values ($1)', [FRIEND]);
  await db.query(`insert into public.town_profiles (user_id, display_name) values ($1, 'Anna Lee')`, [FRIEND]);
  await db.query('insert into private.friendships (a, b, requested_by) values ($1, $2, $1)', [ME, FRIEND]);
  await going(ME, quiz);
  await going(FRIEND, quiz);
  assert.equal((await friendsOn(day))[0].friends_going.length, 1);
  await db.query('delete from public.event_rsvps where user_id = $1', [FRIEND]);
  assert.deepEqual((await friendsOn(day))[0].friends_going, []);
});

test('your Liked carries friends Going too, never a stranger or a friend hiding plans (friends-on-event-page)', async () => {
  await reset();
  const day = soon();
  const quiz = await add('Quiz night', day);
  const fair = await add('Craft fair', day);
  const HIDING = '00000000-0000-0000-0000-0000000000c2';
  await people(db, FRIEND, HIDING);
  await db.query(`insert into public.town_profiles (user_id, display_name, avatar_url, plans_to_friends)
                  values ($1, 'Anna Lee', $2, true), ($3, 'Hal Moe', null, false), ($4, 'Ned Nu', null, true)`,
                 [FRIEND, FRIEND_PHOTO, HIDING, NEIGHBOUR]);
  await db.query('insert into private.friendships (a, b, requested_by) values ($1, $2, $1), ($1, $3, $1)',
                 [ME, FRIEND, HIDING]);
  await heart(ME, quiz);
  await heart(ME, fair);
  for (const who of [FRIEND, HIDING, NEIGHBOUR]) await going(who, quiz);
  await db.exec(`set role authenticated; set request.jwt.claim.sub = '${ME}'`);
  const { rows } = await db.query(`select card from public.get_my_likes($1::date)`, [day]);
  await db.exec('reset role');
  assert.deepEqual(rows.map(({ card: r }) => [r.title, r.friends_going]),
                   [['Craft fair', []], ['Quiz night', [{ name: 'Anna', photo: FRIEND_PHOTO }]]]);
});

test('your Going and your Liked carry each event\'s description', async () => {
  await reset();
  const id = await add('Trivia', '2026-10-09');
  await db.query(`update public.club_events set description = 'Teams of up to six.' where id = $1`, [id]);
  await going(ME, id);
  await db.query('insert into public.event_likes (event_id, user_id) values ($1, $2)', [id, ME]);
  await db.exec(`set role authenticated; set request.jwt.claim.sub = '${ME}'`);
  const g = (await db.query(`select card from public.get_my_going('2026-10-01', '2026-10-31')`)).rows;
  const s = (await db.query(`select card from public.get_my_likes('2026-10-01')`)).rows;
  await db.exec('reset role');
  assert.equal(g[0].card.description, 'Teams of up to six.');
  assert.equal(s[0].card.description, 'Teams of up to six.');
});

// The Event card (BP app codebase-health-2, tickets 01 to 03): get_my_going and get_my_likes send each Event's
// card whole, as one nested value and nothing else, read here as PostgREST hands an RPC's rows to the app
// (json_agg).
async function asTheAppReads(read, day) {
  await db.exec(`set role authenticated; set request.jwt.claim.sub = '${ME}'`);
  const call = read === 'going' ? 'public.get_my_going($1::date, $1::date)' : 'public.get_my_likes($1::date)';
  // From a subquery, so a one-column answer stays an object per row, as PostgREST sends it (its "single-column
  // TABLE return" spec), never the bare value Postgres gives `json_agg` of the function itself.
  const { rows } = await db.query(`select coalesce(json_agg(t), '[]')::text as body from (select * from ${call}) t`, [day]);
  await db.exec('reset role');
  return JSON.parse(rows[0].body);
}

// A found game, called off, whose page names the group it was found for, at a place with a photo, that you
// and a friend are Going to.
async function fullEvent(day) {
  await db.query(`insert into public.clubs (name, status, own_entry_id) values ('Johnnie Football Boosters', 'approved', 'sju-athletics')`);
  await db.exec(`insert into public.sources (entry_id, url, town, name, status, method) values
      ('sju-athletics', 'https://gojohnnies.com/', 'st-joseph-mn', 'SJU Athletics', 'active', 'fetch');
    insert into public.place_photos (entry_id, url, source_url, kind, status) values
      ('activities-athletic-sju', 'https://x/sju-logo.webp', 'https://gojohnnies.com/', 'logo', 'live'),
      ('clemens-field', 'https://x/field.webp', 'https://csbsju.edu/', 'photo', 'live');
    insert into public.teams (id, name, short_name, logo_url) values
      ('saint-johns', 'Saint John''s', 'SJU', 'https://x/sju.png'), ('concordia', 'Concordia', 'Concordia', null)
    on conflict (id) do nothing;`);
  const id = await add('SJU Football vs Concordia', day, { source_name: 'SJU Athletics' });
  await db.query(`update public.club_events set start_time = '1 PM', location = 'Clemens Field', category = 'sports',
      image_url = 'https://x/flyer.jpg', end_at = $2::date + time '21:00', place_entry_id = 'clemens-field',
      description = 'Homecoming against the Cobbers.', what = 'Football game',
      source_url = 'https://gojohnnies.com/sports/football/schedule', sport = 'Football',
      team_ids = '{saint-johns,concordia}', occasion = 'Homecoming', cancelled_at = now()
    where id = $1`, [id, day]);
  await db.query('insert into auth.users (id) values ($1)', [FRIEND]);
  await db.query(`insert into public.town_profiles (user_id, display_name, avatar_url) values ($1, 'Anna Lee', $2)`,
                 [FRIEND, FRIEND_PHOTO]);
  await db.query('insert into private.friendships (a, b, requested_by) values ($1, $2, $1)', [ME, FRIEND]);
  await going(ME, id);
  await going(FRIEND, id);
  return id;
}

function isFullCard(card, id, day) {
  assert.equal(typeof card, 'object', 'one nested value, never a string the app has to parse again');
  assert.deepEqual(Object.keys(card).sort(), CARD_KEYS);
  assert.equal(card.id, id);
  assert.deepEqual([card.title, card.event_date, card.start_time, card.location, card.image_url, card.category],
                   ['SJU Football vs Concordia', day, '1 PM', 'Clemens Field', 'https://x/flyer.jpg', 'sports']);
  assert.equal(new Date(card.end_at).toISOString(), `${day}T21:00:00.000Z`);
  assert.equal(card.club_name, 'Johnnie Football Boosters', 'the group it was found for, as the Town feed names it');
  assert.equal(card.source_name, 'SJU Athletics');
  assert.deepEqual([card.going_count, card.going, card.cancelled, card.all_day], [2, true, true, false]);
  assert.equal(card.place_picture.url, 'https://x/field.webp');
  assert.deepEqual(card.host_picture, { url: 'https://x/sju-logo.webp', kind: 'logo', hue: null });
  assert.equal(card.description, 'Homecoming against the Cobbers.');
  assert.equal(card.what, 'Football game');
  assert.equal(card.source_url, 'https://gojohnnies.com/sports/football/schedule');
  assert.deepEqual([card.game.sport, card.game.occasion, card.game.teams.map((t) => t.name), card.game.final],
                   ['Football', 'Homecoming', ["Saint John's", 'Concordia'], null]);
  assert.deepEqual(card.friends_going, [{ name: 'Anna', photo: FRIEND_PHOTO }]);
}

// A neighbour's own posting with nothing else: Going, or else Hearted, by you alone.
const bareCard = (card, id, day, going) => ({
  id, title: 'Porch jam', event_date: day, start_time: null, location: null, image_url: null, category: null,
  club_name: null, source_name: null, end_at: null, all_day: false, created_at: card.created_at,
  going_count: going ? 1 : 0, going, heart_count: going ? 0 : 1, hearted: !going, cancelled: false, place_picture: null, host_picture: null, description: null, price: null, ages: null, lat: null, lng: null, no_place: false,
  what: null, source_url: null, game: null, friends_going: [], live_kind: false, friends_going_at: null, recurrence: null,
});

test('the Going read sends a full Event card: photo, found link, about, host, game, friends, called off', async () => {
  await reset();
  const day = soon();
  const id = await fullEvent(day);
  const [row] = await asTheAppReads('going', day);
  isFullCard(row.card, id, day);
  assert.deepEqual([row.card.heart_count, row.card.hearted], [0, false]);
  assert.deepEqual(Object.keys(row), ['card'], 'the card alone: no Event column copied beside it (ticket 03)');
});

test('the Going read sends a bare Event card with empties, never a missing key', async () => {
  await reset();
  const day = soon();
  const id = await add('Porch jam', day, { source_name: null, submitted_by: NEIGHBOUR });
  await going(ME, id);
  const [row] = await asTheAppReads('going', day);
  const { card } = row;
  assert.deepEqual(Object.keys(row), ['card']);
  assert.deepEqual(Object.keys(card).sort(), CARD_KEYS);
  assert.deepEqual(card, bareCard(card, id, day, true));
  assert.ok(!Number.isNaN(Date.parse(card.created_at)));
});

test('Liked sends the same full Event card, saying you hearted it (codebase-health-2 02, inside-cards 16)', async () => {
  await reset();
  const day = soon();
  const id = await fullEvent(day);
  await heart(ME, id);
  await heart(FRIEND, id);
  const [row] = await asTheAppReads('likes', day);
  isFullCard(row.card, id, day);
  assert.deepEqual([row.card.heart_count, row.card.hearted], [2, true], "every account's hearts, and yours");
  // The card alone: no Event column copied beside it (ticket 03); `news` is a hearted story's (inside-cards 22).
  assert.deepEqual([Object.keys(row), row.news], [['card', 'news'], null]);
});

test("a priced Event's card carries its price as words, for the Event page's line (inside-cards 14)", async () => {
  await reset();
  const day = soon();
  const id = await add("Christmas at Saint John's", day);
  await db.query('update public.club_events set price = $2 where id = $1', [id, '$22, $20 seniors, $15 students']);
  await going(ME, id);
  const [row] = await asTheAppReads('going', day);
  assert.equal(row.card.price, '$22, $20 seniors, $15 students', 'free text, as the source says it');
  await db.query('update public.club_events set ages = $2 where id = $1', [id, 'Ages 6–14']);
  const [aged] = await asTheAppReads('going', day);
  assert.equal(aged.card.ages, 'Ages 6–14', 'who it is for by age rides the same card (inside-cards 30)');
});

test("an Event's card says where it is, or that it is at no one place, for its Map (inside-cards 19 review)", async () => {
  await reset();
  const day = soon();
  const park = await add('Music in Millstream Park', day);
  const online = await add('City Council', day);
  await db.query('update public.club_events set lat = 45.57007, lng = -94.32874 where id = $1', [park]);
  await db.query('update public.club_events set no_place = true where id = $1', [online]);
  await going(ME, park);
  await going(ME, online);
  const cards = Object.fromEntries((await asTheAppReads('going', day)).map((r) => [r.card.title, r.card]));
  const where = (c) => [c.lat, c.lng, c.no_place];
  assert.deepEqual(where(cards['Music in Millstream Park']), [45.57007, -94.32874, false]);
  assert.deepEqual(where(cards['City Council']), [null, null, true], 'Online: no Map, known before any read');
});

test('Liked sends a bare Event card with empties, saying you are not Going (codebase-health-2 02)', async () => {
  await reset();
  const day = soon();
  const id = await add('Porch jam', day, { source_name: null, submitted_by: NEIGHBOUR });
  await heart(ME, id);
  const [row] = await asTheAppReads('likes', day);
  assert.deepEqual(Object.keys(row.card).sort(), CARD_KEYS);
  assert.deepEqual(row.card, bareCard(row.card, id, day, false));
  assert.deepEqual([Object.keys(row), row.news], [['card', 'news'], null]);
});
