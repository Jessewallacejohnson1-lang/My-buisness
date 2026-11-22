// Fixed stories for a Group's Admin and Edit group (supabase/migrations/*_admin_and_edit_group.sql, BP app
// docs/plans/start-a-group, ticket 04): only the Admin edits, hands over or closes; a changed name, kind, About or
// photo waits on moderate-post's `group` check; Who adds Events; the Admin can't just leave; a deleted Admin's Group.
// Run in PGlite: `npm install && npm test` in this folder.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { realDatabase } from './fixture.mjs';

const db = await realDatabase();
const id = (n) => `00000000-0000-0000-0000-${String(n).padStart(12, '0')}`;
const group = (n) => `00000000-0000-0000-0009-${String(n).padStart(12, '0')}`;
const [SAM, ANA, STAN, BO] = [1, 2, 3, 4].map(id);

for (const [who, name] of [[SAM, 'Sam Rivera'], [ANA, 'Ana Lee'], [STAN, 'Stan Ger'], [BO, 'Bo Dale']]) {
  await db.query('insert into auth.users (id) values ($1)', [who]);
  await db.query('insert into public.town_profiles (user_id, display_name, birthday) values ($1, $2, $3)',
                 [who, name, '1980-01-01']);
}

async function as(who, sql, params = []) {
  if (who === 'service') await db.exec('set role service_role');
  else await db.exec(`set role authenticated; set request.jwt.claims = '${JSON.stringify({ sub: who, is_anonymous: false })}'`);
  try {
    return (await db.query(sql, params)).rows;
  } finally {
    await db.exec('reset role; reset request.jwt.claims');
  }
}
const PHOTO = (who, club, n) =>
  `https://lxdgwhvqjqmqliobwjpi.supabase.co/storage/v1/object/public/event-images/${who}/group-${club}-${n}.jpg`;
// A live Group Sam started, with these members joined in this order (a second apart).
async function live(club, name, members = []) {
  await as(SAM, 'select public.start_group($1, $2)', [club, name]);
  await db.query(`update public.clubs set status = 'approved', description = 'We sew.' where id = $1`, [club]);
  for (const [i, m] of members.entries()) {
    await db.query(`insert into public.club_members (club_id, user_id, created_at) values ($1, $2, now() + $3::interval)`,
                   [club, m, `${i + 1} second`]);
  }
}
const edit = (who, club, f = {}) => as(who,
  'select public.edit_group($1, $2, $3, $4, $5, $6, $7, $8) as checks',
  [club, f.name ?? 'Joetown Sewing Circle', f.kind ?? null, f.about ?? 'We sew.', f.photo ?? null,
   f.private ?? false, f.eventsBy ?? 'admin', 'editors' in f ? f.editors : []]);
const seen = async (who, club) => (await as(who, 'select * from public.get_groups()')).find((g) => g.id === club);
const reset = () => db.exec('delete from public.clubs where submitted_by is not null or status = \'closed\'');

test('only the Admin edits; Private and Who adds Events land at once, a new name waits on the check', async () => {
  const club = group(1);
  await live(club, 'Joetown Sewing Circle', [ANA]);
  await assert.rejects(edit(ANA, club, { name: 'Ana\'s Circle' }), /only the Admin/);
  await assert.rejects(edit(STAN, club), /only the Admin/);
  const [{ checks }] = await edit(SAM, club, { name: 'Joetown Quilters', private: true, eventsBy: 'members' });
  assert.equal(checks, true, 'the new name goes to the check');
  const row = await seen(SAM, club);
  assert.deepEqual([row.name, row.private, row.events_by], ['Joetown Sewing Circle', true, 'members'],
                   'the old name shows until the check says yes');
  const [{ checks: none }] = await edit(SAM, club, { private: false, eventsBy: 'members' });
  assert.equal(none, false, 'nothing for the check');
  await reset();
});

const claim = (club, who) => as('service', 'select public.claim_group_edit($1, $2) as e', [club, who]).then((r) => r[0].e);
const apply = (club, who, e) => as('service', 'select public.apply_group_edit($1, $2, $3) as ok', [club, who, e]).then((r) => r[0].ok);

test('the check\'s two yeses put the new name, About and photo live; a no leaves the old ones', async () => {
  const club = group(2);
  await live(club, 'Joetown Sewing Circle');
  await edit(SAM, club, { name: 'Joetown Quilters', about: 'Quilts too.', photo: PHOTO(SAM, club, 'a1') });
  assert.equal(await claim(club, ANA), null, 'only the Admin\'s own edit is claimed');
  const e = await claim(club, SAM);
  assert.deepEqual(e, { name: 'Joetown Quilters', kind: null, about: 'Quilts too.', photo: PHOTO(SAM, club, 'a1') });
  assert.equal(await claim(club, SAM), null, 'read once');
  assert.equal(await apply(club, SAM, e), true);
  const row = await seen(ANA, club);
  assert.deepEqual([row.name, row.about, row.image_url], ['Joetown Quilters', 'Quilts too.', PHOTO(SAM, club, 'a1')]);

  // A name the check says no to: moderate-post never applies it, and the Group keeps its name.
  await edit(SAM, club, { name: 'Buy Followers Cheap', about: 'Quilts too.', photo: PHOTO(SAM, club, 'a1') });
  assert.equal((await claim(club, SAM)).name, 'Buy Followers Cheap');
  assert.equal((await seen(ANA, club)).name, 'Joetown Quilters', 'held');
  assert.equal(await claim(club, SAM), null, 'and gone, so it isn\'t read again');
  await reset();
});

test('a name or photo the rules refuse never reaches the check; 10 checks a day', async () => {
  const club = group(3);
  await live(club, 'Joetown Sewing Circle');
  await assert.rejects(edit(SAM, club, { name: 'ab' }), /a name of 3 to 60/);
  await assert.rejects(edit(SAM, club, { photo: PHOTO(ANA, club, 'a1') }), /own new upload/);
  await assert.rejects(edit(SAM, club, { eventsBy: 'anyone' }), /who adds events/);
  for (let n = 0; n < 10; n++) {
    await edit(SAM, club, { name: `Sewing Circle ${'x'.repeat(n + 1)}` });
    await claim(club, SAM);
  }
  await edit(SAM, club, { name: 'Sewing Circle Eleven' });
  assert.deepEqual(await claim(club, SAM), { limit: true });
  await db.exec('delete from private.group_edit_checks');
  await reset();
});

test('Who adds Events is kept, with the members picked (only members, never the Admin)', async () => {
  const club = group(4);
  await live(club, 'Joetown Sewing Circle', [ANA, BO]);
  await edit(SAM, club, { eventsBy: 'picked', editors: [ANA, STAN, SAM] });
  const members = await as(SAM, 'select display_name, editor from public.get_group_members($1)', [club]);
  assert.deepEqual(members, [{ display_name: 'Ana Lee', editor: true }, { display_name: 'Bo Dale', editor: false }],
                   'longest first, the Admin left out; Stan isn\'t a member');
  await assert.rejects(as(ANA, 'select * from public.get_group_members($1)', [club]), /only the Admin/);
  await edit(SAM, club, { eventsBy: 'picked', editors: [ANA], name: 'Joetown Quilters' });
  assert.equal((await seen(BO, club)).events_by, 'picked', 'kept through another edit');
  await edit(SAM, club, { eventsBy: 'picked', editors: null });
  assert.equal((await as(SAM, 'select editor from public.get_group_members($1)', [club]))[0].editor, true,
               'no list sent: the picks stay');
  await as(ANA, 'delete from public.club_members where club_id = $1 and user_id = $2', [club, ANA]);
  assert.deepEqual(await as(SAM, 'select display_name, editor from public.get_group_members($1)', [club]),
                   [{ display_name: 'Bo Dale', editor: false }], 'a member who left is no longer picked');
  await reset();
});

test('only the Admin hands over, and only to a member; the new Admin runs it, the old one is a member', async () => {
  const club = group(5);
  await live(club, 'Joetown Sewing Circle', [ANA]);
  await assert.rejects(as(ANA, 'select public.hand_over_group($1, $2)', [club, ANA]), /only the Admin/);
  await assert.rejects(as(SAM, 'select public.hand_over_group($1, $2)', [club, STAN]), /only to a member/);
  await as(SAM, 'select public.hand_over_group($1, $2)', [club, ANA]);
  assert.equal((await seen(ANA, club)).requests, 0, 'Ana is the Admin now');
  assert.equal((await seen(SAM, club)).requests, null);
  assert.equal((await seen(SAM, club)).joined, true, 'Sam stays in it');
  await assert.rejects(edit(SAM, club), /only the Admin/);
  await edit(ANA, club, { eventsBy: 'members' });
  assert.equal((await seen(SAM, club)).events_by, 'members');
  await reset();
});

test('the Admin can\'t just leave; a member can', async () => {
  const club = group(6);
  await live(club, 'Joetown Sewing Circle', [ANA]);
  await as(SAM, 'delete from public.club_members where club_id = $1 and user_id = $2', [club, SAM]);
  assert.equal((await seen(SAM, club)).joined, true, 'still in: hand over or close first');
  await as(ANA, 'delete from public.club_members where club_id = $1 and user_id = $2', [club, ANA]);
  assert.equal((await seen(ANA, club)).joined, false);
  await reset();
});

test('only the Admin closes; a closed Group leaves every list and can\'t be joined', async () => {
  const club = group(7);
  await live(club, 'Joetown Sewing Circle', [ANA]);
  await assert.rejects(as(ANA, 'select public.close_group($1)', [club]), /only the Admin/);
  await as(SAM, 'select public.close_group($1)', [club]);
  assert.equal(await seen(SAM, club), undefined, 'gone for its Admin');
  assert.equal(await seen(ANA, club), undefined, 'and its members');
  assert.equal(await seen(STAN, club), undefined, 'and the Town');
  await assert.rejects(as(STAN, 'insert into public.club_members (club_id, user_id) values ($1, $2)', [club, STAN]),
                       /row-level security/);
  await assert.rejects(as(SAM, 'select public.close_group($1)', [club]), /only the Admin/, 'closed once');
  await reset();
});

test('a deleted Admin\'s Group goes to the member who joined longest ago; with none left, it closes', async () => {
  const [club, alone] = [group(8), group(9)];
  await live(club, 'Joetown Sewing Circle', [BO, ANA]);
  await live(alone, 'Sam\'s Own Club');
  await as(SAM, 'select public.delete_my_account()');
  assert.equal((await seen(BO, club)).requests, 0, 'Bo joined first: Bo runs it');
  assert.equal((await seen(ANA, club)).requests, null);
  const [{ status }] = (await db.query('select status from public.clubs where id = $1', [alone])).rows;
  assert.equal(status, 'closed');
  assert.equal((await db.query('select 1 from auth.users where id = $1', [SAM])).rows.length, 0, 'the account went');
  await db.exec('delete from public.clubs');
});
