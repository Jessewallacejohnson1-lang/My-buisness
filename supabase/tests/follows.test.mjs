// Fixed stories for following Places and people (supabase/migrations/*_follow_places_and_people.sql,
// BP app docs/plans/follows, ticket 02): who may follow and be followed, the real count, the friends
// line that names only your friends, nobody listing a target's followers, the Following list, an
// Event's host, and Join group needing a signed-up account. Run in PGlite like the others:
// `npm install && npm test` in this folder.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { realDatabase } from './fixture.mjs';

const db = await realDatabase();
const id = (n) => `00000000-0000-0000-0000-${String(n).padStart(12, '0')}`;
const [ANA, BEN, CAL, DEE, EVE, NAMELESS, ANON] = [1, 2, 3, 4, 5, 6, 7].map(id);
const [KREWE, BLEND, RUNNERS] = [id(800), id(801), id(900)];
const [AT_KREWE, BY_BEN, BY_GROUP, NOWHERE] = [id(700), id(701), id(702), id(703)];
const people = [[ANA, 'Ana Lee'], [BEN, 'Ben Ortiz'], [CAL, 'Cal Ruiz'], [DEE, 'Dee Moss'], [EVE, 'Eve Park'],
                [NAMELESS, '  ']];

async function reset() {
  await db.exec(`reset role; reset request.jwt.claims;
    delete from private.blocks; delete from private.friend_requests; delete from private.friendships;
    delete from public.town_follows; delete from public.club_members; delete from public.clubs;
    delete from public.club_events; delete from public.places; delete from public.town_profiles;
    delete from auth.users;`);
  for (const [who, name] of people) {
    await db.query('insert into auth.users (id) values ($1)', [who]);
    await db.query('insert into public.town_profiles (user_id, display_name, avatar_url) values ($1, $2, $3)',
                   [who, name, `https://face/${name.trim()}`]);
  }
  await db.query('insert into auth.users (id, is_anonymous) values ($1, true)', [ANON]);
  await db.query(`insert into public.places (id, name, lat, lon, family, primary_type, entry_id) values
                  ($1, 'Krewe', 45.5, -94.3, 'food', 'restaurant', 'krewe'),
                  ($2, 'The Local Blend', 45.5, -94.3, 'food', 'coffee_shop', 'local-blend')`, [KREWE, BLEND]);
  await db.exec(`delete from public.place_photos;
    insert into public.place_photos (entry_id, url, source_url, kind, status) values
      ('krewe', 'https://pic/krewe', 'https://krewemn.com/', 'logo', 'live'),
      ('local-blend', 'https://pic/local-blend', 'https://localblend.com/', 'logo', 'live')`);
  await db.query(`insert into public.clubs (id, name, status) values ($1, 'Running Club', 'approved')`, [RUNNERS]);
  await db.query(`insert into public.club_events (id, status, title, submitted_by, club_id, place_entry_id) values
                  ($1, 'approved', 'Mardi Gras Night', null, null, 'krewe'), ($2, 'approved', 'Porch sale', $5, null, 'krewe'),
                  ($3, 'approved', 'Long run', $5, $6, null), ($4, 'approved', 'Somewhere', null, null, 'gone')`,
                 [AT_KREWE, BY_BEN, BY_GROUP, NOWHERE, BEN, RUNNERS]);
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
const card = async (who, type, target, o) => (await as(who, 'select * from public.follow_card($1, $2)', [type, target], o))[0];
const makeFriends = async (a, b) => {
  await as(a, 'select public.send_friend_request($1)', [b]);
  await as(b, 'select public.confirm_friend_request($1)', [a]);
};

test('an Anonymous account follows nothing and joins no group', async () => {
  await reset();
  await assert.rejects(follow(ANON, 'place', KREWE, { anonymous: true }), /real account/);
  await assert.rejects(follow(ANON, 'profile', ANA, { anonymous: true }), /real account/);
  await assert.rejects(as(ANON, 'insert into public.club_members (club_id) values ($1)', [RUNNERS], { anonymous: true }),
                       /row-level security/);
  // A real account still joins.
  await as(ANA, 'insert into public.club_members (club_id) values ($1)', [RUNNERS]);
  assert.equal((await db.query('select count(*)::int as n from public.club_members')).rows[0].n, 1);
});

test('nobody writes follows straight into the table, nor for anyone else', async () => {
  await reset();
  await assert.rejects(as(ANA, `insert into public.town_follows (follower_id, target_type, target_id)
                                values ($1, 'place', $2)`, [ANA, KREWE]), /row-level security/);
  await follow(ANA, 'place', KREWE);
  await as(BEN, `delete from public.town_follows`);
  await as(ANA, `delete from public.town_follows`);
  assert.equal((await db.query('select count(*)::int as n from public.town_follows')).rows[0].n, 1,
               'a delete matches nothing, your own included: unfollow goes through unfollow_target');
});

test('follow and unfollow a Place, twice each, and the count is real', async () => {
  await reset();
  assert.equal(await follow(ANA, 'place', KREWE), true);
  assert.equal(await follow(ANA, 'place', KREWE), true);
  await follow(BEN, 'place', KREWE);
  assert.deepEqual(await card(CAL, 'place', KREWE), { following: false, followers: 2, friends: [], friends_count: 0 });
  assert.equal((await card(ANA, 'place', KREWE)).following, true);
  assert.equal(await unfollow(ANA, 'place', KREWE), false);
  assert.equal(await unfollow(ANA, 'place', KREWE), false);
  assert.equal((await card(ANA, 'place', KREWE)).followers, 1);
  assert.equal((await card(ANA, 'place', BLEND)).followers, 0);
});

test('a Place that does not exist, or another kind of target, cannot be followed', async () => {
  await reset();
  await assert.rejects(follow(ANA, 'place', id(999)), /not_followable/);
  await assert.rejects(follow(ANA, 'club', RUNNERS), /not_followable/, 'a Group has Join only');
  await assert.rejects(follow(ANA, 'board', KREWE), /not_followable/);
});

test('people: nameless, Anonymous, blocked either way and yourself cannot be followed', async () => {
  await reset();
  assert.equal(await follow(ANA, 'profile', BEN), true);
  await assert.rejects(follow(ANA, 'profile', NAMELESS), /not_followable/);
  await assert.rejects(follow(ANA, 'profile', ANON), /not_followable/);
  await assert.rejects(follow(ANA, 'profile', ANA), /not_followable/);
  await as(CAL, 'select public.block_neighbor($1)', [ANA]);
  await assert.rejects(follow(ANA, 'profile', CAL), /not_followable/, 'Cal blocked Ana');
  await as(ANA, 'select public.block_neighbor($1)', [DEE]);
  await assert.rejects(follow(ANA, 'profile', DEE), /not_followable/, 'Ana blocked Dee');
});

test('a person shows no count, and blocking ends the follow', async () => {
  await reset();
  await follow(ANA, 'profile', BEN);
  await follow(CAL, 'profile', BEN);
  assert.deepEqual(await card(ANA, 'profile', BEN), { following: true, followers: null, friends: [], friends_count: 0 });
  await as(BEN, 'select public.block_neighbor($1)', [ANA]);
  assert.equal((await card(ANA, 'profile', BEN)).following, false);
});

test("a friend's Unfollow keeps the friendship; Unfriend still ends both follows", async () => {
  await reset();
  await makeFriends(ANA, BEN);
  assert.equal((await card(ANA, 'profile', BEN)).following, true, 'friends follow each other');
  await unfollow(ANA, 'profile', BEN);
  assert.equal((await card(ANA, 'profile', BEN)).following, false);
  assert.equal((await card(BEN, 'profile', ANA)).following, true, 'Ben still follows Ana');
  assert.equal((await as(ANA, 'select public.unfriend($1) as r', [BEN]))[0].r, 'none');
  await follow(ANA, 'profile', BEN);
  await makeFriends(ANA, BEN);
  await as(ANA, 'select public.unfriend($1)', [BEN]);
  assert.equal((await card(ANA, 'profile', BEN)).following, false);
  assert.equal((await card(BEN, 'profile', ANA)).following, false);
});

test("the friends line names only the caller's friends who follow, A to Z, three at most", async () => {
  await reset();
  await makeFriends(ANA, BEN);
  await makeFriends(ANA, CAL);
  await makeFriends(ANA, DEE);
  await makeFriends(ANA, EVE);
  for (const who of [EVE, DEE, BEN, CAL]) await follow(who, 'place', KREWE);
  const c = await card(ANA, 'place', KREWE);
  assert.equal(c.followers, 4);
  assert.equal(c.friends_count, 4);
  assert.deepEqual(c.friends.map((f) => f.name), ['Ben Ortiz', 'Cal Ruiz', 'Dee Moss']);
  assert.equal(c.friends[0].avatar_url, 'https://face/Ben Ortiz');
  // Ben's friends are only Ana: Cal, Dee and Eve are nobody to him.
  assert.deepEqual(await card(BEN, 'place', KREWE), { following: true, followers: 4, friends: [], friends_count: 0 });
  // Signed out or Anonymous: the count alone.
  await db.exec('set role anon');
  assert.deepEqual((await db.query('select * from public.follow_card($1, $2)', ['place', KREWE])).rows[0],
                   { following: false, followers: 4, friends: [], friends_count: 0 });
  await db.exec('reset role');
  assert.equal((await card(ANON, 'place', KREWE, { anonymous: true })).friends_count, 0);
});

test("nobody can list a target's followers", async () => {
  await reset();
  await follow(BEN, 'place', KREWE);
  await follow(CAL, 'profile', ANA);
  assert.deepEqual(await as(ANA, 'select follower_id from public.town_follows'), [], 'only your own rows read');
  await db.exec('set role anon');
  assert.deepEqual((await db.query('select follower_id from public.town_follows')).rows, []);
  await db.exec('reset role');
  await assert.rejects(as(ANON, 'select * from public.my_follows()', [], { anonymous: true }), /real account/);
});

test('the Following list: people and Places, A to Z, without anyone who went out of reach', async () => {
  await reset();
  await follow(ANA, 'place', BLEND);
  await follow(ANA, 'profile', EVE);
  await follow(ANA, 'place', KREWE);
  await follow(ANA, 'profile', BEN);
  await as(ANA, 'insert into public.club_members (club_id) values ($1)', [RUNNERS]);
  const rows = await as(ANA, 'select * from public.my_follows()');
  assert.deepEqual(rows.map((r) => `${r.target_type}:${r.name}:${r.kind ?? ''}:${r.picture_kind}`),
                   ['profile:Ben Ortiz::photo', 'profile:Eve Park::photo', 'place:Krewe:restaurant:logo',
                    'place:The Local Blend:coffee_shop:logo']);
  assert.equal(rows[2].picture, 'https://pic/krewe');
  await db.query("update auth.users set banned_until = now() + interval '1 day' where id = $1", [EVE]);
  assert.deepEqual((await as(ANA, 'select name from public.my_follows()')).map((r) => r.name),
                   ['Ben Ortiz', 'Krewe', 'The Local Blend']);
  assert.deepEqual(await as(BEN, 'select * from public.my_follows()'), [], 'a brand-new list is empty');
});

test("an Event's host: who posted it if they may be found, else its Place, never a Group's", async () => {
  await reset();
  const host = async (event, who = ANA) => (await as(who, 'select * from public.event_host($1)', [event]))
    .map((r) => `${r.target_type}:${r.name}`);
  assert.deepEqual(await host(AT_KREWE), ['place:Krewe']);
  assert.deepEqual(await host(BY_BEN), ['profile:Ben Ortiz']);
  assert.deepEqual(await host(BY_BEN, BEN), ['place:Krewe'], 'your own Event names its Place');
  assert.deepEqual(await host(BY_GROUP), [], "a Group's Event has Join");
  assert.deepEqual(await host(NOWHERE), []);
  assert.equal((await as(ANA, 'select friend from public.event_host($1)', [BY_BEN]))[0].friend, false);
  await makeFriends(ANA, BEN);
  assert.equal((await as(ANA, 'select friend from public.event_host($1)', [BY_BEN]))[0].friend, true,
               'a friend already follows: no Follow');
  await as(BEN, 'select public.block_neighbor($1)', [ANA]);
  assert.deepEqual(await host(BY_BEN), ['place:Krewe']);
  await db.exec('set role anon');
  assert.deepEqual((await db.query('select name from public.event_host($1)', [AT_KREWE])).rows, [{ name: 'Krewe' }]);
  await db.exec('reset role');
});

test("the Following list draws a person's photo only from their own folder of our avatars bucket", async () => {
  await reset();
  const own = `https://lxdgwhvqjqmqliobwjpi.supabase.co/storage/v1/object/public/avatars/${BEN}/face.jpg`;
  const theirs = `https://lxdgwhvqjqmqliobwjpi.supabase.co/storage/v1/object/public/avatars/${CAL}/face.jpg`;
  await db.query('update public.town_profiles set avatar_url = $2 where user_id = $1', [BEN, own]);
  await db.query('update public.town_profiles set avatar_url = $2 where user_id = $1', [DEE, theirs]);
  await follow(ANA, 'profile', BEN);
  await follow(ANA, 'profile', DEE);
  await follow(ANA, 'profile', EVE);
  const rows = await as(ANA, 'select name, picture from public.my_follows()');
  assert.deepEqual(rows.map((r) => [r.name, r.picture]),
                   [['Ben Ortiz', own], ['Dee Moss', null], ['Eve Park', null]]);
});
