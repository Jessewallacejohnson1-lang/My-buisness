// Fixed stories for starting a Group (supabase/migrations/*_start_a_group.sql, BP app docs/plans/start-a-group,
// ticket 02): start_group makes a pending Group with its starter in it, who sees it while a stranger doesn't, invites
// reach friends only and light the Friends dot, the invited may join, the check is claimed once, 3 a day.
// Run in PGlite: `npm install && npm test` in this folder.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { realDatabase } from './fixture.mjs';

const db = await realDatabase();
const id = (n) => `00000000-0000-0000-0000-${String(n).padStart(12, '0')}`;
const group = (n) => `00000000-0000-0000-0009-${String(n).padStart(12, '0')}`;
const [SAM, ANA, STRANGER, ANON] = [1, 2, 3, 4].map(id);
const photo = (who, club) =>
  `https://lxdgwhvqjqmqliobwjpi.supabase.co/storage/v1/object/public/event-images/${who}/group-${club}.jpg`;

for (const [who, name, anonymous] of [[SAM, 'Sam Rivera', false], [ANA, 'Ana Lee', false],
                                      [STRANGER, 'Stan Ger', false], [ANON, 'Anon Ymous', true]]) {
  await db.query('insert into auth.users (id, is_anonymous) values ($1, $2)', [who, anonymous]);
  // Adults: an account with no birthday counts as under 18, whose Groups are private (start-a-group 03).
  await db.query("insert into public.town_profiles (user_id, display_name, birthday) values ($1, $2, '1990-01-01')", [who, name]);
}
await db.query('insert into private.friendships (a, b, requested_by) values ($1, $2, $1)', [SAM, ANA].sort());

async function as(who, sql, params = [], { anonymous = false } = {}) {
  await db.exec(`set role authenticated; set request.jwt.claims = '${JSON.stringify({ sub: who, is_anonymous: anonymous })}'`);
  try {
    return (await db.query(sql, params)).rows;
  } finally {
    await db.exec('reset role; reset request.jwt.claims');
  }
}
const start = (who, club, name, { kind = null, pic = null, anonymous = false } = {}) =>
  as(who, 'select public.start_group($1, $2, $3, $4) as id', [club, name, kind, pic], { anonymous });
const seen = async (who, club) => (await as(who, 'select * from public.get_groups()')).find((g) => g.id === club);
const invite = (who, club, users) => as(who, 'select public.invite_to_group($1, $2::uuid[]) as n', [club, users]);
const dot = async (who) => (await as(who, 'select public.friends_dot() as d'))[0].d;
const join_ = (who, club) => as(who, 'insert into public.club_members (club_id, user_id) values ($1, $2)', [club, who]);
const reset = () => db.exec(`delete from public.clubs where submitted_by is not null; delete from private.friends_seen`);

test('start_group makes a pending Group with its starter in it, its photo and kind', async () => {
  const club = group(1);
  await start(SAM, club, '  Joetown   Knitters ', { kind: 'Crafts', pic: photo(SAM, club) });
  const row = await seen(SAM, club);
  assert.deepEqual([row.name, row.kind, row.status, row.joined, row.member_count, row.image_url],
    ['Joetown Knitters', 'Crafts', 'pending', true, 1, photo(SAM, club)], 'spaces tidied');
  assert.deepEqual(row.photos, [{ url: photo(SAM, club), kind: 'photo' }], 'its photo is its page\'s photo too');
  assert.equal(row.invited_by, null);
  await reset();
});

test('a stranger neither sees nor joins a pending Group; the table can\'t be written straight', async () => {
  const club = group(2);
  await start(SAM, club, 'Book Nook');
  assert.equal(await seen(STRANGER, club), undefined);
  assert.equal((await as(STRANGER, 'select id from public.clubs where id = $1', [club])).length, 0, 'not by the table either');
  await assert.rejects(join_(STRANGER, club), /row-level security/);
  await assert.rejects(as(STRANGER, "insert into public.clubs (name, status, submitted_by) values ('Mine', 'pending', $1)", [STRANGER]),
    /row-level security/, 'start_group is the only way in');
  await assert.rejects(as(SAM, "update public.clubs set name = 'Changed' where id = $1 returning id", [club])
    .then((r) => { if (!r.length) throw new Error('row-level security: no row'); }), /row-level security/,
  'the starter can\'t change it after the check');
  await reset();
});

test('an invite reaches a friend: they see it with who asked, the dot lights, and they may join', async () => {
  const club = group(3);
  await start(SAM, club, 'Sunday Runners');
  assert.equal(await dot(ANA), false);
  assert.equal((await invite(SAM, club, [ANA, STRANGER, ANA]))[0].n, 1, 'a friend once; a stranger never');
  const row = await seen(ANA, club);
  assert.deepEqual([row.status, row.invited_by, row.joined], ['pending', 'Sam', false]);
  assert.equal(await seen(STRANGER, club), undefined);
  assert.equal(await dot(ANA), true, 'the invite lights the Friends dot');
  await join_(ANA, club);
  assert.deepEqual([(await seen(ANA, club)).invited_by, (await seen(ANA, club)).joined], [null, true], 'in it: no invite line');
  assert.equal(await dot(ANA), false, 'nor the dot');
  await assert.rejects(invite(STRANGER, club, [ANA]), /only a member invites/);
  await reset();
});

test('the Friends dot goes once the Friends tab has been seen', async () => {
  const club = group(4);
  await start(SAM, club, 'Puzzle Club');
  await invite(SAM, club, [ANA]);
  await as(ANA, 'select public.mark_friends_seen()');
  assert.equal(await dot(ANA), false);
  await reset();
});

test('approved: the whole town sees and joins it; rejected: only its starter sees it', async () => {
  const [open, no] = [group(5), group(6)];
  await start(SAM, open, 'Garden Club');
  await start(SAM, no, 'Bad Club');
  await db.query("update public.clubs set status = 'approved' where id = $1", [open]);
  await db.query("update public.clubs set status = 'rejected' where id = $1", [no]);
  assert.equal((await seen(STRANGER, open)).status, 'approved');
  await join_(STRANGER, open);
  assert.equal(await seen(STRANGER, no), undefined);
  assert.equal((await seen(SAM, no)).status, 'rejected');
  await assert.rejects(invite(SAM, no, [ANA]), /only a member invites/, 'a rejected Group invites nobody');
  await reset();
});

test('3 new Groups a day; a 4th is refused', async () => {
  for (const n of [7, 8, 9]) await start(SAM, group(n), `Club number ${n}`);
  await assert.rejects(start(SAM, group(10), 'One too many'), /3 new groups a day/);
  await reset();
});

test('refused: a short or letterless name, someone else\'s photo, an anonymous account', async () => {
  await assert.rejects(start(SAM, group(11), 'ab'), /3 to 60/);
  await assert.rejects(start(SAM, group(11), '1234'), /3 to 60/);
  await assert.rejects(start(SAM, group(11), 'x'.repeat(61)), /3 to 60/);
  await assert.rejects(start(SAM, group(11), 'Fine name', { pic: photo(ANA, group(11)) }), /own upload/);
  await assert.rejects(start(SAM, group(11), 'Fine name', { pic: photo(SAM, group(12)) }), /own upload/);
  await assert.rejects(start(ANON, group(11), 'Fine name', { anonymous: true }), /real account/);
  await reset();
});

test('the check is claimed once, only by its starter, only while pending', async () => {
  const club = group(13);
  await start(SAM, club, 'Chess Club');
  const claim = async (who) => (await db.query('select public.claim_group_check($1, $2) as c', [club, who])).rows[0].c;
  assert.equal(await claim(ANA), false, 'not another\'s');
  assert.equal(await claim(SAM), true);
  assert.equal(await claim(SAM), false, 'never twice');
  await assert.rejects(as(SAM, 'select public.claim_group_check($1, $2)', [club, SAM]), /permission denied/,
    'the server\'s alone');
  await reset();
});
