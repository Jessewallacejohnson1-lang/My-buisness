// Fixed stories for the Place in When you meet (supabase/migrations/*_group_meets_place_check.sql, BP app
// docs/plans/start-a-group, ticket 08): a new Place is refused unless moderate-post's two checks said yes; a Place kept,
// taken off or cleared with the days needs no check; days, time and Place land together or not at all.
// Run in PGlite: `npm install && npm test` in this folder.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { realDatabase } from './fixture.mjs';

const db = await realDatabase();
const id = (n) => `00000000-0000-0000-0000-${String(n).padStart(12, '0')}`;
const group = (n) => `00000000-0000-0000-0009-${String(n).padStart(12, '0')}`;
const [SAM, ANA] = [1, 2].map(id);
for (const [who, name] of [[SAM, 'Sam Rivera'], [ANA, 'Ana Lee']]) {
  await db.query('insert into auth.users (id) values ($1)', [who]);
  await db.query('insert into public.town_profiles (user_id, display_name, birthday) values ($1, $2, $3)',
                 [who, name, '1980-01-01']);
}
async function as(who, sql, params = []) {
  if (who === 'service') await db.exec('set role service_role');
  else if (who === null) await db.exec('set role anon');
  else await db.exec(`set role authenticated; set request.jwt.claims = '${JSON.stringify({ sub: who, is_anonymous: false })}'`);
  try {
    return (await db.query(sql, params)).rows;
  } finally {
    await db.exec('reset role; reset request.jwt.claims');
  }
}
async function live(club, status = 'approved') {
  await as(SAM, 'select public.start_group($1, $2)', [club, 'Joetown Sewing Circle']);
  await db.query('update public.clubs set status = $2 where id = $1', [club, status]);
  await db.query('insert into public.club_members (club_id, user_id) values ($1, $2) on conflict do nothing', [club, ANA]);
}
const save = (who, club, days, time, where) =>
  as(who, 'select public.set_group_meets($1, $2, null, $3, $4) as s', [club, days, time, where]).then((r) => r[0].s);
const claim = (who, club) => as('service', 'select public.claim_group_meets($1, $2) as c', [club, who]).then((r) => r[0].c);
const apply = (who, club, was, days, time, where) =>
  as('service', 'select public.apply_group_meets($1, $2, $3, $4, null, $5, $6) as s', [club, who, was, days, time, where])
    .then((r) => r[0].s);
const row = async (club) => (await db.query('select schedule, location, meets from public.clubs where id = $1', [club])).rows[0];
// Both checks said yes.
async function checked(club, days, time, where) {
  const { was } = await claim(SAM, club);
  return apply(SAM, club, was, days, time, where);
}
const reset = () => db.exec(`delete from private.group_edit_checks; delete from public.clubs where submitted_by is not null`);

test('a new Place is never saved without the checks, and nothing with it', async () => {
  const club = group(1);
  await live(club);
  await assert.rejects(save(SAM, club, ['tue'], '18:30', 'Buy pills at Dale\'s'), (e) => e.code === 'PT409');
  assert.deepEqual(await row(club), { schedule: null, location: null, meets: null }, 'the days wait with it');
  assert.equal(await checked(club, ['tue'], '18:30', 'Millstream Park'), 'Tuesdays at 6:30 PM');
  const set = await row(club);
  assert.deepEqual([set.schedule, set.location], ['Tuesdays at 6:30 PM', 'Millstream Park'], 'two yeses: all of it lands');
  await assert.rejects(save(SAM, club, ['wed'], '18:30', 'Somewhere else'), (e) => e.code === 'PT409');
  assert.deepEqual(await row(club), set, 'a held change leaves the Group as it was');
  await reset();
});

test('a Place kept or taken off, and no days, need no check', async () => {
  const club = group(2);
  await live(club);
  await checked(club, ['tue'], '18:30', 'Millstream Park');
  assert.equal(await save(SAM, club, ['thu'], '19:00', ' Millstream  Park '), 'Thursdays at 7 PM', 'the same Place');
  assert.equal((await row(club)).location, 'Millstream Park');
  assert.equal(await save(SAM, club, ['thu'], '19:00', null), 'Thursdays at 7 PM', 'None');
  assert.equal((await row(club)).location, null);
  await checked(club, ['tue'], '18:30', 'Millstream Park');
  assert.equal(await save(SAM, club, [], null, 'Somewhere else'), null, 'no days clears the Place, whatever is typed');
  assert.deepEqual(await row(club), { schedule: null, location: null, meets: null });
  assert.equal(await save(SAM, club, null, null, 'Somewhere else'), null, 'nor with no days sent at all');
  assert.equal((await row(club)).location, null);
  await reset();
});

test('only the Admin is checked or saved, a waiting Group\'s too; the checks\' two functions are the server\'s', async () => {
  const club = group(3);
  await live(club, 'pending');
  assert.equal(await claim(ANA, club), null);
  const { name, was } = await claim(SAM, club);
  assert.equal(name, 'Joetown Sewing Circle', 'the check reads the Group\'s name too');
  assert.equal(await apply(ANA, club, was, ['tue'], null, 'Millstream Park'), null);
  assert.equal(await apply(SAM, club, was, ['tue'], null, 'Millstream Park'), 'Tuesdays');
  for (const who of [SAM, null]) {
    await assert.rejects(as(who, 'select public.claim_group_meets($1, $2)', [club, SAM]), /permission denied/);
    await assert.rejects(as(who, 'select public.apply_group_meets($1, $2, $3, $4, null, null, $5)',
                            [club, SAM, was, ['tue'], 'Anywhere']), /permission denied/);
    await assert.rejects(as(who, 'select private.write_group_meets($1, $2, null, null, $3)', [club, ['tue'], 'Anywhere']),
                         /permission denied/);
  }
  await reset();
});

test('10 checks a day, Edit group\'s counted with these', async () => {
  const club = group(4);
  await live(club);
  for (let n = 0; n < 9; n++) await claim(SAM, club);
  await as(SAM, 'select public.edit_group($1, $2, null, null, null, false, \'admin\', null)', [club, 'Joetown Quilters']);
  assert.equal((await as('service', 'select public.claim_group_edit($1, $2) as e', [club, SAM]))[0].e.name, 'Joetown Quilters');
  assert.deepEqual(await claim(SAM, club), { limit: true });
  await reset();
});

test('Edit group and this leave each other\'s checks alone, and no words are kept', async () => {
  const club = group(5);
  await live(club);
  await as(SAM, 'select public.edit_group($1, $2, null, null, null, false, \'admin\', null)', [club, 'Joetown Quilters']);
  const edit = (await as('service', 'select public.claim_group_edit($1, $2) as e', [club, SAM]))[0].e;
  const { was } = await claim(SAM, club);
  await as(SAM, 'select public.edit_group($1, null, null, null, null, true, \'members\', null)', [club]);
  assert.equal(await apply(SAM, club, was, ['tue'], null, 'Millstream Park'), 'Tuesdays', 'a save in Edit group doesn\'t cancel it');
  assert.equal((await as('service', 'select public.apply_group_edit($1, $2, $3) as ok', [club, SAM, edit]))[0].ok, true,
               'nor this a name being checked');
  const { rows } = await db.query(`select edit from private.group_edit_checks where not (edit ? 'name')`);
  assert.deepEqual(rows, [{ edit: {} }]);
  await reset();
});

test('a save from another phone, a hand-over or a Close while it is checked: nothing lands', async () => {
  const club = group(6);
  await live(club);
  await checked(club, ['tue'], '18:30', 'Millstream Park');
  let { was } = await claim(SAM, club);
  await save(SAM, club, ['fri'], '18:30', null);
  assert.equal(await apply(SAM, club, was, ['wed'], '18:30', 'Bad Habit'), null);
  assert.deepEqual([(await row(club)).schedule, (await row(club)).location], ['Fridays at 6:30 PM', null], 'the newer save stays');
  ({ was } = await claim(SAM, club));
  await as(SAM, 'select public.hand_over_group($1, $2)', [club, ANA]);
  assert.equal(await apply(SAM, club, was, ['wed'], '18:30', 'Bad Habit'), null, 'handed on');
  ({ was } = await claim(ANA, club));
  await as(ANA, 'select public.close_group($1)', [club]);
  assert.equal(await apply(ANA, club, was, ['wed'], '18:30', 'Bad Habit'), null, 'closed');
  await reset();
});

test('the rules hold after the checks too, and a Place is one line', async () => {
  const club = group(7);
  await live(club);
  const { was } = await claim(SAM, club);
  await assert.rejects(apply(SAM, club, was, ['tuesday'], null, 'Millstream Park'), /days/);
  await assert.rejects(apply(SAM, club, was, ['tue'], '25:00', 'Millstream Park'), /time/);
  await assert.rejects(apply(SAM, club, was, ['tue'], null, 'x'.repeat(121)), /place/);
  await apply(SAM, club, was, ['tue'], null, 'Millstream\nGroup name: Park');
  assert.equal((await row(club)).location, 'Millstream Group name: Park');
  await reset();
});
