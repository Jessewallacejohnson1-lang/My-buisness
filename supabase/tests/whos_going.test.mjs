// Fixed stories for who's going (supabase/migrations/*_whos_going.sql, BP app inside-cards 36), run in PGlite: a minor is
// never named to anyone but a friend, nobody blocked, banned, anonymous or switched off is, four names until you're Going,
// and nothing for an Event that is over, called off, hidden, kept to adults or a Group's you can't see.
// Run: `npm install && npm test` in this folder.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { realDatabase } from './fixture.mjs';

const db = await realDatabase();
const id = (n) => `00000000-0000-0000-0000-${String(n).padStart(12, '0')}`;
const [ME, SAM, KIT, ALEX, AVA, TEEN, BLANK, QUIET, ZOE, BO] = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10].map(id);
const [EVENT, OVER, OFF, HIDDEN, BAR, NEWS] = [901, 902, 903, 904, 905, 906].map(id);
const CLUB = '00000000-0000-0000-0009-000000000001';

async function reset() {
  await db.exec(`reset role; reset request.jwt.claims;
    delete from private.blocks; delete from private.friendships; delete from public.event_rsvps;
    delete from public.town_profiles; delete from public.club_events; delete from public.clubs; delete from auth.users;`);
  for (const [who, name, birthday, anonymous] of [
    [ME, 'Me Myself', '1990-01-01'], [SAM, 'Sam Lee', '1988-01-01'], [KIT, 'Kit Young', '2010-05-01'],
    [ALEX, 'Alex Moss', '1992-01-01'], [AVA, 'Ava Ruiz', '2004-01-01'], [TEEN, 'Tess Teen', '2011-01-01'],
    [BLANK, 'Nia Blank', null], [QUIET, 'Anon Ymous', '1980-01-01', true], [ZOE, 'Zoe Hart', '1970-01-01'],
    [BO, 'bo Ortiz', '1971-01-01']]) {
    await db.query('insert into auth.users (id, is_anonymous) values ($1, $2)', [who, !!anonymous]);
    await db.query('insert into public.town_profiles (user_id, display_name, birthday) values ($1, $2, $3)', [who, name, birthday]);
  }
  for (const friend of [SAM, KIT]) {
    await db.query('insert into private.friendships (a, b, requested_by) values ($1, $2, $1)', [ME, friend].sort());
  }
  await db.query(`insert into public.club_events (id, title, status, kind, event_date, cancelled_at) values
    ($1, 'Market', 'approved', 'event', current_date + 9, null), ($2, 'Long over', 'approved', 'event', current_date - 9, null),
    ($3, 'Called off', 'approved', 'event', current_date + 9, now()), ($4, 'Hidden', 'rejected', 'event', current_date + 9, null),
    ($5, 'Trivia 21+', 'approved', 'event', current_date + 9, null), ($6, 'A post', 'approved', 'post', current_date + 9, null)`,
    [EVENT, OVER, OFF, HIDDEN, BAR, NEWS]);
}
async function as(who, sql, params = [], anonymous = false) {
  if (who) await db.exec(`set role authenticated; set request.jwt.claims = '${JSON.stringify({ sub: who, is_anonymous: anonymous })}'`);
  else await db.exec('set role anon');
  try {
    return (await db.query(sql, params)).rows;
  } finally {
    await db.exec('reset role; reset request.jwt.claims');
  }
}
const going = async (event, ...who) => {
  for (const w of who) await db.query('insert into public.event_rsvps (event_id, user_id) values ($1, $2)', [event, w]);
};
const rows = (who, event = EVENT) => as(who, 'select * from public.get_event_going($1)', [event]);
const names = async (who, event) => (await rows(who, event)).map((r) => r.display_name.split(' ')[0]);
const refused = (run, word) => assert.rejects(run, (e) => { assert.match(e.message, word); return true; });

test('Going: friends first, then neighbours by name, never yourself', async () => {
  await reset();
  await going(EVENT, ME, ZOE, SAM, BO, ALEX, AVA);
  assert.deepEqual(await names(ME), ['Sam', 'Alex', 'Ava', 'bo', 'Zoe']);
  const [sam, alex] = await rows(ME);
  assert.equal(sam.relation, 'friends');
  assert.equal(alex.relation, 'none');
});

test('not Going: four at most, the same four every time', async () => {
  await reset();
  await going(EVENT, ZOE, SAM, BO, ALEX, AVA);
  assert.deepEqual(await names(ME), ['Sam', 'Alex', 'Ava', 'bo']);
  await going(EVENT, ME);
  assert.equal((await names(ME)).length, 5);
  await db.query('delete from public.event_rsvps where user_id = $1', [ME]);
  assert.equal((await names(ME)).length, 4, 'leaving takes the list back');
});

test('a minor is named to a friend and nobody else, and no birthday counts as a minor', async () => {
  await reset();
  await going(EVENT, ME, KIT, TEEN, BLANK, ALEX);
  assert.deepEqual(await names(ME), ['Kit', 'Alex']);
  assert.deepEqual(await names(ALEX), ['Me'], 'not the friend’s friend');
  const all = JSON.stringify(await rows(ME));
  for (const hidden of [TEEN, BLANK]) assert.ok(!all.includes(hidden), 'not even an id');
});

test('18 today is an adult, 18 tomorrow is not', async () => {
  await reset();
  await going(EVENT, ME, TEEN, AVA);
  const born = (who, day) => db.query(`update public.town_profiles set birthday =
    ((now() at time zone 'America/Chicago')::date - interval '18 years')::date + $2::int where user_id = $1`, [who, day]);
  await born(TEEN, 1);
  assert.deepEqual(await names(ME), ['Ava']);
  await born(TEEN, 0);
  assert.deepEqual(await names(ME), ['Ava', 'Tess']);
});

test('someone under 18, or with no birthday, sees friends alone', async () => {
  await reset();
  await going(EVENT, KIT, ME, ALEX, AVA);
  assert.deepEqual(await names(KIT), ['Me']);
  assert.deepEqual(await names(BLANK), []);
});

test('the two switches: plans off hides you from everyone, neighbours off from all but friends', async () => {
  await reset();
  await going(EVENT, ME, SAM, ALEX, AVA);
  await as(ALEX, 'update public.town_profiles set plans_to_neighbors = false where user_id = $1', [ALEX]);
  await as(SAM, 'update public.town_profiles set plans_to_neighbors = false where user_id = $1', [SAM]);
  assert.deepEqual(await names(ME), ['Sam', 'Ava']);
  assert.deepEqual(await names(AVA), ['Me']);
  await as(SAM, 'update public.town_profiles set plans_to_friends = false where user_id = $1', [SAM]);
  assert.deepEqual(await names(ME), ['Ava']);
});

test('blocked either way, banned, anonymous and nameless never show; a banned caller sees nobody', async () => {
  await reset();
  await going(EVENT, ME, SAM, ALEX, AVA, ZOE, BO, QUIET);
  await db.query('insert into private.blocks (blocker_id, blocked_id) values ($1, $2), ($3, $1)', [ME, ALEX, AVA]);
  await db.query(`update auth.users set banned_until = now() + interval '1 day' where id = $1`, [ZOE]);
  await db.query(`update public.town_profiles set display_name = '🎉' where user_id = $1`, [BO]);
  assert.deepEqual(await names(ME), ['Sam']);
  assert.deepEqual(await names(ZOE), []);
});

test('nothing for an Event over, called off, hidden, or a post', async () => {
  await reset();
  for (const event of [OVER, OFF, HIDDEN, NEWS]) {
    await going(event, ME, SAM, ALEX);
    assert.deepEqual(await names(ME, event), []);
  }
});

test('an Event kept to adults: nothing for someone under 18, friends too', async () => {
  await reset();
  await going(BAR, ME, KIT, SAM);
  assert.deepEqual(await names(KIT, BAR), []);
  assert.deepEqual(await names(ME, BAR), ['Kit', 'Sam']);
});

test("a private Group's Event only to its members, an old Going row or not", async () => {
  await reset();
  await as(SAM, 'select public.start_group($1, $2, null, null, true)', [CLUB, 'Book club']);
  await db.query(`update public.clubs set status = 'approved' where id = $1`, [CLUB]);
  await db.query('update public.club_events set club_id = $1, submitted_by = $2 where id = $3', [CLUB, SAM, EVENT]);
  await going(EVENT, ME, SAM, ALEX);
  assert.deepEqual(await names(ME), []);
  await db.query('insert into public.club_members (club_id, user_id) values ($1, $2)', [CLUB, ME]);
  assert.deepEqual(await names(ME), ['Sam', 'Alex']);
});

test('no account, or a quiet one, is refused, and the table still shows your own rows alone', async () => {
  await reset();
  await going(EVENT, ME, SAM);
  await refused(() => rows(null), /permission denied/);
  await refused(() => as(QUIET, 'select * from public.get_event_going($1)', [EVENT], true), /real account/);
  const own = await as(ME, 'select user_id from public.event_rsvps');
  assert.deepEqual(own.map((r) => r.user_id), [ME]);
});
