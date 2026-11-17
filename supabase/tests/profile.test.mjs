// Fixed stories for a profile's page (supabase/migrations/*_profile_bio_cover.sql, *_profile_following.sql):
// its bio and cover, how many friends, its groups, the Events you're both Going to, only for a friend
// who shows their plans (BP app references/profile-remake; friends spec, 2026-10-13: "you can't track
// people's whole agenda"), and how many they follow, as the Following list lists them (BP app
// references/profile-middle). Run in PGlite like the others: `npm install && npm test` in this folder.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { realDatabase } from './fixture.mjs';

const db = await realDatabase();
const id = (n) => `00000000-0000-0000-0000-${String(n).padStart(12, '0')}`;
const [ANA, BEN, CAL, DEE, ANON] = [1, 2, 3, 4, 6].map(id);
const [LIONS, BOOKS] = [900, 901].map(id);
await db.exec(`insert into public.clubs (id, name) values ('${LIONS}', 'Lions'), ('${BOOKS}', 'Books')`);
const [MARKET, TRIVIA, FISH, OVER, CALLED] = [700, 701, 702, 703, 704].map(id);
const PHOTOS = 'https://lxdgwhvqjqmqliobwjpi.supabase.co/storage/v1/object/public/avatars/';
const KREWE = id(800);
await db.query(`insert into public.places (id, name, lat, lon, family, entry_id) values ($1, 'Krewe', 45.5, -94.3, 'food', 'krewe')`,
  [KREWE]);

async function reset() {
  await db.exec(`reset role; reset request.jwt.claims;
    delete from private.blocks; delete from private.friend_requests; delete from private.friendships;
    delete from public.town_follows; delete from public.club_members; delete from public.event_rsvps;
    delete from public.club_events; delete from public.town_profiles; delete from auth.users;`);
  for (const [who, name, anonymous] of [[ANA, 'Ana Lee', false], [BEN, 'Ben Ortiz', false],
                                        [CAL, 'Cal Ruiz', false], [DEE, 'Dee Park', false],
                                        [ANON, 'Anon Ymous', true]]) {
    await db.query('insert into auth.users (id, is_anonymous) values ($1, $2)', [who, anonymous]);
    await db.query('insert into public.town_profiles (user_id, display_name) values ($1, $2)', [who, name]);
  }
  // Dated on the Town's calendar, as get_profile counts them; current_date is UTC's, a day ahead after 7 PM.
  await db.exec(`insert into public.club_events (id, title, status, event_date, start_time, cancelled_at, end_at)
    select id::uuid, 'An Event', 'approved', (now() at time zone 'America/Chicago')::date + d, t, c, null from (values
    ('${MARKET}', 3, '9:00 AM', null::timestamptz),
    ('${TRIVIA}', 1, '7:00 PM', null),
    ('${FISH}',   5, '5:00 PM', null),
    ('${OVER}',  -2, '6:00 PM', null),
    ('${CALLED}', 2, '6:00 PM', now())) v (id, d, t, c)`);
}

/** Runs one call as `who`: a real account unless `anonymous`. */
async function as(who, sql, params = [], { anonymous = false } = {}) {
  await db.exec(`set role authenticated; set request.jwt.claims = '${JSON.stringify({ sub: who, is_anonymous: anonymous })}'`);
  try {
    return (await db.query(sql, params)).rows;
  } finally {
    await db.exec('reset role; reset request.jwt.claims');
  }
}
const one = async (who, fn, other) => (await as(who, `select public.${fn}($1) as r`, [other]))[0].r;
const makeFriends = async (a, b) => { await one(a, 'send_friend_request', b); await one(b, 'confirm_friend_request', a); };
const profile = async (who, of) => (await as(who, 'select * from public.get_profile($1)', [of]))[0];
const going = (who, events) => Promise.all(events.map((e) =>
  db.query('insert into public.event_rsvps (event_id, user_id) values ($1, $2)', [e, who])));
const follows = (who, targets) => Promise.all(targets.map(([type, target]) =>
  db.query('insert into public.town_follows (follower_id, target_type, target_id) values ($1, $2, $3)', [who, type, target])));

test('a friend sees only the Events you are both Going to, soonest first, not over or called off', async () => {
  await reset();
  await makeFriends(ANA, BEN);
  await going(ANA, [MARKET, TRIVIA, OVER, CALLED]);
  await going(BEN, [MARKET, TRIVIA, FISH, OVER, CALLED]);
  assert.deepEqual((await profile(ANA, BEN)).both_going, [TRIVIA, MARKET]);
  assert.deepEqual((await profile(BEN, ANA)).both_going, [TRIVIA, MARKET]);
});

test('no shared Events when they hide their plans from friends, or you are not friends', async () => {
  await reset();
  await makeFriends(ANA, BEN);
  await going(ANA, [MARKET]);
  await going(BEN, [MARKET]);
  await going(CAL, [MARKET]);
  await db.query('update public.town_profiles set plans_to_friends = false where user_id = $1', [BEN]);
  assert.deepEqual((await profile(ANA, BEN)).both_going, []);
  assert.deepEqual((await profile(ANA, CAL)).both_going, []);
  // Your own profile lists none: You has them.
  assert.deepEqual((await profile(ANA, ANA)).both_going, []);
});

test('friends are counted as the Friends list counts them, the viewer included', async () => {
  await reset();
  await makeFriends(BEN, ANA);
  await makeFriends(BEN, CAL);
  await makeFriends(BEN, DEE);
  assert.equal((await profile(ANA, BEN)).friends, 3);
  await one(ANA, 'block_neighbor', CAL);
  assert.equal((await profile(ANA, BEN)).friends, 2);
  assert.equal((await profile(ANA, ANA)).friends, 1);
});

test('nothing at all for someone blocked either way, and an anonymous account may not ask', async () => {
  await reset();
  await one(BEN, 'block_neighbor', ANA);
  assert.equal(await profile(ANA, BEN), undefined);
  assert.equal(await profile(BEN, ANA), undefined);
  assert.equal(await profile(ANA, ANON), undefined);
  await assert.rejects(as(ANON, 'select * from public.get_profile($1)', [ANA], { anonymous: true }));
});

test('groups in the order they joined, the bio trimmed, the cover only from their own folder', async () => {
  await reset();
  await db.query(`insert into public.club_members (club_id, user_id, created_at) values
    ($1, $3, now() - interval '1 day'), ($2, $3, now())`, [BOOKS, LIONS, BEN]);
  await as(BEN, `update public.town_profiles set bio = '  Coach at the rink.  ', cover_url = $1 where user_id = $2`,
    [`${PHOTOS}${BEN}/cover-1.jpg`, BEN]);
  let row = await profile(ANA, BEN);
  assert.deepEqual(row.group_ids, [BOOKS, LIONS]);
  assert.equal(row.bio, 'Coach at the rink.');
  assert.equal(row.cover_url, `${PHOTOS}${BEN}/cover-1.jpg`);
  await as(BEN, 'update public.town_profiles set bio = $1, cover_url = $2 where user_id = $3',
    ['   ', `${PHOTOS}${ANA}/cover-1.jpg`, BEN]);
  row = await profile(ANA, BEN);
  assert.equal(row.bio, null);
  assert.equal(row.cover_url, null);
});

test('a bio is at most 150 letters, and only a real account sets a bio or a cover', async () => {
  await reset();
  await assert.rejects(as(BEN, 'update public.town_profiles set bio = $1 where user_id = $2', ['x'.repeat(151), BEN]));
  await as(BEN, 'update public.town_profiles set bio = $1 where user_id = $2', ['x'.repeat(150), BEN]);
  await assert.rejects(as(ANON, 'update public.town_profiles set bio = $1 where user_id = $2', ['Hi', ANON], { anonymous: true }));
  await assert.rejects(as(ANON, 'update public.town_profiles set cover_url = $1 where user_id = $2',
    [`${PHOTOS}${ANON}/cover-1.jpg`, ANON], { anonymous: true }));
  // Its name is still its own to change.
  await as(ANON, 'update public.town_profiles set display_name = $1 where user_id = $2', ['Anon Two', ANON], { anonymous: true });
});

test('following counts what the Following list lists: Places and people you may find, never groups', async () => {
  await reset();
  await one(BEN, 'block_neighbor', DEE);
  // Written after the block on purpose: a block ends follows, but the count doesn't lean on that.
  await follows(BEN, [['place', KREWE], ['profile', CAL], ['profile', DEE], ['club', LIONS]]);
  assert.equal((await profile(BEN, BEN)).following, 2);
  assert.equal((await as(BEN, 'select * from public.my_follows()')).length, 2, 'the Following list agrees');
});

test('a neighbour reads the count as they may see it, and counts themselves when followed', async () => {
  await reset();
  await one(ANA, 'block_neighbor', CAL);
  await follows(BEN, [['place', KREWE], ['profile', ANA], ['profile', CAL]]);
  // Ana blocked Cal, so Cal isn't counted for her; she is, though nobody may find themselves.
  assert.equal((await profile(ANA, BEN)).following, 2);
  assert.equal((await profile(DEE, BEN)).following, 3);
  assert.equal((await profile(BEN, BEN)).following, 3);
  assert.equal((await profile(ANA, ANA)).following, 0);
});

test('followers counts the people following a profile whom the reader may find (BP app backlog 34)', async () => {
  await reset();
  await one(ANA, 'block_neighbor', DEE);
  // Written after the block on purpose, as the following story: the count doesn't lean on a block ending follows.
  await follows(BEN, [['profile', ANA]]);
  await follows(CAL, [['profile', ANA]]);
  await follows(DEE, [['profile', ANA]]);
  await follows(ANA, [['place', KREWE], ['profile', BEN]]);
  assert.equal((await profile(ANA, ANA)).followers, 2, 'Dee is blocked, so not counted');
  assert.equal((await profile(CAL, ANA)).followers, 3, 'Cal may find all three');
  assert.equal((await profile(BEN, BEN)).followers, 1);
  assert.equal((await profile(CAL, CAL)).followers, 0);
});

test('my_followers lists only your own followers, newest first, as the count counts them', async () => {
  await reset();
  await one(ANA, 'block_neighbor', DEE);
  await follows(BEN, [['profile', ANA]]);
  await db.query(`insert into public.town_follows (follower_id, target_type, target_id, created_at)
    values ($1, 'profile', $2, now() + interval '1 minute'), ($3, 'profile', $2, now())`, [CAL, ANA, DEE]);
  await follows(ANA, [['profile', BEN]]);
  await makeFriends(ANA, CAL);
  const rows = await as(ANA, 'select * from public.my_followers()');
  assert.deepEqual(rows.map((r) => r.display_name), ['Cal Ruiz', 'Ben Ortiz']);
  assert.equal(rows[0].relation, 'friends');
  assert.equal(rows.length, (await profile(ANA, ANA)).followers, 'the list and the number agree');
  assert.deepEqual((await as(BEN, 'select * from public.my_followers()')).map((r) => r.display_name), ['Ana Lee']);
  await assert.rejects(as(ANON, 'select * from public.my_followers()', [], { anonymous: true }));
});
