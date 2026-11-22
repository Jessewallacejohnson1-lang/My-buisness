// Fixed stories for private Groups and Ask to join (supabase/migrations/*_private_groups.sql, BP app
// docs/plans/start-a-group, ticket 03): what a stranger sees of a private Group and what stays hidden, asking, the
// Admin's yes and no, the under-18 rule, an invite still letting in, and a profile's Groups.
// Run in PGlite: `npm install && npm test` in this folder.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { realDatabase } from './fixture.mjs';

const db = await realDatabase();
const id = (n) => `00000000-0000-0000-0000-${String(n).padStart(12, '0')}`;
const group = (n) => `00000000-0000-0000-0009-${String(n).padStart(12, '0')}`;
const [SAM, ANA, STAN, TEEN, NOBDAY] = [1, 2, 3, 4, 5].map(id);

for (const [who, name, birthday] of [[SAM, 'Sam Rivera', '1980-01-01'], [ANA, 'Ana Lee', '1990-01-01'],
                                     [STAN, 'Stan Ger', '1985-01-01'], [TEEN, 'Tess Teen', '2012-01-01'],
                                     [NOBDAY, 'No Day', null]]) {
  await db.query('insert into auth.users (id) values ($1)', [who]);
  await db.query('insert into public.town_profiles (user_id, display_name, birthday) values ($1, $2, $3)', [who, name, birthday]);
}
await db.query('insert into private.friendships (a, b, requested_by) values ($1, $2, $1)', [SAM, ANA].sort());

async function as(who, sql, params = []) {
  if (who) await db.exec(`set role authenticated; set request.jwt.claims = '${JSON.stringify({ sub: who, is_anonymous: false })}'`);
  else await db.exec('set role anon');
  try {
    return (await db.query(sql, params)).rows;
  } finally {
    await db.exec('reset role; reset request.jwt.claims');
  }
}
const start = (who, club, name, priv = false) =>
  as(who, 'select public.start_group($1, $2, null, null, $3)', [club, name, priv]);
const seen = async (who, club) => (await as(who, 'select * from public.get_groups()')).find((g) => g.id === club);
const ask = (who, club, on = true) => as(who, 'select public.ask_to_join($1, $2)', [club, on]);
const answer = (who, club, user, yes) => as(who, 'select public.answer_join($1, $2, $3)', [club, user, yes]);
const requests = (who, club) => as(who, 'select display_name from public.get_join_requests($1)', [club]);
const join_ = (who, club) => as(who, 'insert into public.club_members (club_id, user_id) values ($1, $2)', [club, who]);
const live = (club) => db.query(`update public.clubs set status = 'approved', schedule = 'Thursdays 7 PM',
  location = 'Sam''s house', description = 'We read Psalms.',
  meets = '[{"what": "Study", "days": ["thu"], "time": "19:00"}]' where id = $1`, [club]);
const reset = () => db.exec('delete from public.clubs where submitted_by is not null');

test('a stranger sees a private Group\'s name, count and About, never when or where it meets', async () => {
  const club = group(1);
  await start(SAM, club, 'Thursday Bible Study', true);
  await live(club);
  const row = await seen(STAN, club);
  assert.deepEqual([row.name, row.private, row.member_count, row.about, row.asked], ['Thursday Bible Study', true, 1, 'We read Psalms.', false]);
  assert.deepEqual([row.schedule, row.location, row.meetings], [null, null, []], 'no time, place or meetings');
  const mine = await seen(SAM, club);
  assert.equal(mine.location, "Sam's house");
  assert.ok(mine.meetings.length > 0, 'its starter sees them');
  assert.equal((await seen(null, club)).location, null, 'signed out neither');
  assert.equal((await as(STAN, 'select id from public.clubs where id = $1', [club])).length, 0, 'nor its row straight from the table');
  assert.equal((await as(STAN, 'select user_id from public.club_members where club_id = $1', [club])).length, 0, 'nor its members');
  await reset();
});

test('ask, the Admin sees it, says yes: they are in, and see it all', async () => {
  const club = group(2);
  await start(SAM, club, 'Puzzle Night', true);
  await live(club);
  await assert.rejects(join_(STAN, club), /row-level security/, 'no plain Join');
  await ask(STAN, club);
  assert.equal((await seen(STAN, club)).asked, true);
  assert.equal((await seen(SAM, club)).requests, 1);
  assert.equal((await seen(STAN, club)).requests, null, 'only the Admin gets the count');
  assert.deepEqual(await requests(SAM, club), [{ display_name: 'Stan Ger' }]);
  await assert.rejects(requests(ANA, club), /only the Admin/);
  await assert.rejects(answer(ANA, club, STAN, true), /only the Admin/);
  await answer(SAM, club, STAN, true);
  const row = await seen(STAN, club);
  assert.deepEqual([row.joined, row.asked, row.location], [true, false, "Sam's house"]);
  assert.equal((await seen(SAM, club)).requests, 0);
  await reset();
});

test('a no: they keep "asked", can\'t ask again, and aren\'t in', async () => {
  const club = group(3);
  await start(SAM, club, 'Quilting Bee', true);
  await live(club);
  await ask(STAN, club);
  await answer(SAM, club, STAN, false);
  await ask(STAN, club);
  const row = await seen(STAN, club);
  assert.deepEqual([row.joined, row.asked], [false, true]);
  assert.equal((await seen(SAM, club)).requests, 0, 'asking again after a no comes to nothing');
  await reset();
});

test('taking an ask back before the answer', async () => {
  const club = group(4);
  await start(SAM, club, 'Knit Club', true);
  await live(club);
  await ask(STAN, club);
  await ask(STAN, club, false);
  assert.equal((await seen(STAN, club)).asked, false);
  assert.equal((await seen(SAM, club)).requests, 0);
  await reset();
});

test('an invited friend joins a private Group without asking', async () => {
  const club = group(5);
  await start(SAM, club, 'Sunday Runners', true);
  await live(club);
  await as(SAM, 'select public.invite_to_group($1, $2::uuid[])', [club, [ANA]]);
  assert.equal((await seen(ANA, club)).location, "Sam's house", 'invited: sees it all');
  await join_(ANA, club);
  assert.equal((await seen(ANA, club)).joined, true);
  await reset();
});

test('under 18, or no birthday: always private', async () => {
  await start(TEEN, group(6), 'Teen Chess', false);
  await start(NOBDAY, group(7), 'Mystery Club', false);
  await start(ANA, group(8), 'Open Club', false);
  const priv = async (club) => (await db.query('select private from public.clubs where id = $1', [club])).rows[0].private;
  assert.deepEqual([await priv(group(6)), await priv(group(7)), await priv(group(8))], [true, true, false]);
  const fixed = async (who) => (await as(who, 'select public.groups_always_private() as f'))[0].f;
  assert.deepEqual([await fixed(TEEN), await fixed(NOBDAY), await fixed(ANA)], [true, true, false], 'the switch says so first');
  await db.exec(`delete from public.clubs where id in ('${group(6)}', '${group(7)}', '${group(8)}')`);
});

test('a public Group is as before: anyone joins, sees its meetings and members', async () => {
  const club = group(9);
  await start(SAM, club, 'Garden Club');
  await live(club);
  assert.equal((await seen(STAN, club)).location, "Sam's house");
  await join_(STAN, club);
  assert.equal((await as(STAN, 'select user_id from public.club_members where club_id = $1', [club])).length, 2);
  await assert.rejects(ask(ANA, club), /not a private group/);
  await reset();
});

test('a profile lists a private Group only to someone in it', async () => {
  const [priv, open] = [group(10), group(11)];
  await start(SAM, priv, 'Secret Supper', true);
  await start(SAM, open, 'Open Supper');
  await live(priv);
  await live(open);
  const groups = async (who) => (await as(who, 'select group_ids from public.get_profile($1)', [SAM]))[0].group_ids;
  assert.deepEqual(await groups(STAN), [open]);
  assert.deepEqual((await groups(SAM)).sort(), [priv, open].sort());
  await reset();
});
