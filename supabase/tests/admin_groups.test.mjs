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
  const { check, ...fields } = e;
  assert.equal(typeof check, 'number', 'its check\'s number, which apply asks for');
  assert.deepEqual(fields, { name: 'Joetown Quilters', kind: null, about: 'Quilts too.', photo: PHOTO(SAM, club, 'a1') });
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

test('a new edit over one still waiting hands its photo to the check to take down', async () => {
  const club = group(10);
  await live(club, 'Joetown Sewing Circle');
  await edit(SAM, club, { name: 'Joetown Quilters', photo: PHOTO(SAM, club, 'a1') });
  await edit(SAM, club, { name: 'Joetown Quilters', photo: PHOTO(SAM, club, 'b2') });
  const e = await claim(club, SAM);
  assert.equal(e.photo, PHOTO(SAM, club, 'b2'));
  assert.deepEqual(e.drop, [PHOTO(SAM, club, 'a1')], 'the first upload, which nothing shows now');
  // Taken back to the Group as it is: nothing to check but the waiting photo to take down.
  await edit(SAM, club, { name: 'Joetown Quilters', photo: PHOTO(SAM, club, 'c3') });
  const [{ checks }] = await edit(SAM, club, { name: 'Joetown Sewing Circle' });
  assert.equal(checks, true, 'the app asks the check, which takes the photo down');
  assert.deepEqual(await claim(club, SAM), { drop: [PHOTO(SAM, club, 'c3')] });
  assert.equal(await apply(club, SAM, { drop: [PHOTO(SAM, club, 'c3')] }), false, 'and changes nothing');
  assert.equal((await seen(ANA, club)).name, 'Joetown Sewing Circle');
  await db.exec('delete from private.group_edit_checks');
  await reset();
});

test('a Group started under 18 stays private when an adult runs it', async () => {
  const [club, adults] = [group(11), group(12)];
  await db.query(`update public.town_profiles set birthday = (now() - interval '15 years')::date where user_id = $1`, [BO]);
  await as(BO, 'select public.start_group($1, $2)', [club, 'Teen Chess Club']);
  await db.query(`update public.clubs set status = 'approved' where id = $1`, [club]);
  await db.query('insert into public.club_members (club_id, user_id) values ($1, $2)', [club, ANA]);
  assert.equal((await seen(BO, club)).always_private, true);
  await as(BO, 'select public.hand_over_group($1, $2)', [club, ANA]);
  await edit(ANA, club, { name: 'Teen Chess Club', about: null, private: false });
  const row = await seen(ANA, club);
  assert.deepEqual([row.private, row.always_private], [true, true], 'Private stays on');
  await live(adults, 'Joetown Sewing Circle');
  assert.equal((await seen(SAM, adults)).always_private, false, 'an adult\'s Group turns Private off');
  await db.query(`update public.town_profiles set birthday = '1980-01-01' where user_id = $1`, [BO]);
  await reset();
});

test('a deleted Admin\'s Group skips a member nobody can find', async () => {
  const club = group(13);
  await live(club, 'Joetown Sewing Circle', [BO, ANA]);
  await db.query(`update auth.users set banned_until = now() + interval '1 year' where id = $1`, [BO]);
  await as(SAM, 'select public.delete_my_account()');
  assert.equal((await seen(ANA, club)).requests, 0, 'Bo joined first but is banned: Ana runs it');
  await db.query(`update auth.users set banned_until = null where id = $1`, [BO]);
  await db.query('insert into auth.users (id) values ($1)', [SAM]);
  await db.query('insert into public.town_profiles (user_id, display_name, birthday) values ($1, $2, $3)',
                 [SAM, 'Sam Rivera', '1980-01-01']);
  await reset();
});

test('private.runs_group is not for anyone signed out', async () => {
  const [{ ok }] = (await db.query(
    `select has_function_privilege('anon', 'private.runs_group(uuid, uuid)', 'execute') as ok`)).rows;
  assert.equal(ok, false);
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
  await comeBack(SAM, 'Sam Rivera');
});

// Settings' Delete account: the delete-account edge function's rows half, then its deleteUser.
const deleteAccount = async (who) => {
  await as('service', 'select public.clear_account_rows($1)', [who]);
  await db.query('delete from auth.users where id = $1', [who]);
};
const comeBack = async (who, name) => {
  await db.query('insert into auth.users (id) values ($1)', [who]);
  await db.query('insert into public.town_profiles (user_id, display_name, birthday) values ($1, $2, $3)', [who, name, '1980-01-01']);
};
let next = 20;
for (const [path, leave] of [['Settings\' Delete account', deleteAccount],
                             ['the under-13 exit', (who) => as(who, 'select public.delete_my_account()')]]) {
  test(`${path}: a Group goes to its longest member someone could write to, or closes; its photo goes with the folder`, async () => {
    const [club, alone, theirs] = [group(next++), group(next++), group(next++)];
    await live(club, 'Joetown Sewing Circle', [STAN, BO, ANA]);
    await live(alone, 'Sam\'s Own Club');
    await db.query('update auth.users set banned_until = now() + interval \'1 year\' where id = $1', [STAN]);
    // A block between the two goes with the account that leaves.
    await db.query('insert into private.blocks (blocker_id, blocked_id) values ($1, $2)', [BO, SAM]);
    await db.query('update public.clubs set image_url = $2 where id = $1', [club, PHOTO(SAM, club, 'a1')]);
    // One Sam handed on earlier, its photo still in Sam's folder.
    await live(theirs, 'Joetown Quilters', [ANA]);
    await db.query('update public.clubs set image_url = $2 where id = $1', [theirs, PHOTO(SAM, theirs, 'a1')]);
    await as(SAM, 'select public.hand_over_group($1, $2)', [theirs, ANA]);
    await leave(SAM);
    assert.equal((await seen(BO, club)).requests, 0, 'Bo runs it: Stan joined first but is banned');
    assert.equal((await seen(ANA, club)).requests, null);
    assert.equal(await seen(ANA, alone), undefined, 'no member left: it closes');
    for (const g of [club, theirs]) assert.equal((await seen(ANA, g)).image_url, null, 'no card points at a file that went');
    await edit(BO, club, { eventsBy: 'members' });
    await db.query('update auth.users set banned_until = null where id = $1', [STAN]);
    await comeBack(SAM, 'Sam Rivera');
    await reset();
  });
}

test('a photo a check has read is never on the list to take down', async () => {
  const club = group(30);
  const [A, B, C] = ['a1', 'b2', 'c3'].map((n) => PHOTO(SAM, club, n));
  await live(club, 'Joetown Sewing Circle');
  // A, then A again while its check runs, its check's two yeses, then B.
  await edit(SAM, club, { name: 'Joetown Quilters', photo: A });
  const first = await claim(club, SAM);
  await edit(SAM, club, { name: 'Joetown Quilters', photo: A });
  assert.equal(await apply(club, SAM, first), true);
  await edit(SAM, club, { name: 'Joetown Quilters', photo: B });
  const second = await claim(club, SAM);
  assert.deepEqual([second.photo, second.drop], [B, undefined], 'A is live');
  assert.equal((await seen(ANA, club)).image_url, A);

  // B being read, B again, then C: B is its check's to take down, not the list's.
  await edit(SAM, club, { name: 'Joetown Quilters', photo: B });
  await edit(SAM, club, { name: 'Joetown Quilters', photo: C });
  assert.equal((await claim(club, SAM)).drop, undefined);
  assert.equal(await apply(club, SAM, second), false, 'C replaced it');
  assert.equal((await seen(ANA, club)).image_url, A);

  // A waiting photo put back is no longer one to take down.
  const [D, E] = ['d4', 'e5'].map((n) => PHOTO(SAM, club, n));
  for (const photo of [D, E, D]) await edit(SAM, club, { name: 'Joetown Quilters', photo });
  const third = await claim(club, SAM);
  assert.deepEqual([third.photo, third.drop], [D, [E]]);
  await db.exec('delete from private.group_edit_checks');
  await reset();
});

test('nobody reads an edit that waits on its check', async () => {
  const club = group(31);
  await live(club, 'Joetown Sewing Circle', [ANA]);
  await edit(SAM, club, { name: 'Buy Followers Cheap', about: 'Call 555-0100', photo: PHOTO(SAM, club, 'a1') });
  for (const who of [ANA, STAN]) {
    const rows = JSON.stringify([await as(who, 'select * from public.clubs where id = $1', [club]), await seen(who, club)]);
    assert.match(rows, /Joetown Sewing Circle/, 'the Group itself is read');
    assert.doesNotMatch(rows, /Buy Followers|555-0100|group-00000000/, 'its waiting name, About and photo aren\'t');
  }
  await db.exec('set role anon');
  const rows = JSON.stringify((await db.query('select * from public.clubs where id = $1', [club])).rows);
  await db.exec('reset role');
  assert.doesNotMatch(rows, /Buy Followers|555-0100|group-00000000/, 'nor signed out');
  assert.equal((await claim(club, SAM)).name, 'Buy Followers Cheap', 'the check does');
  await db.exec('delete from private.group_edit_checks');
  await reset();
});

const birthday = (who, day) => db.query('update public.town_profiles set birthday = $2 where user_id = $1', [who, day]);
const years = async (n) => (await db.query(`select ((now() at time zone 'America/Chicago')::date - make_interval(years => $1))::date::text as d`, [n])).rows[0].d;
const switchOff = async (who, club) => {
  await edit(who, club, { name: 'No Day Club', about: 'We sew.', private: false });
  const row = await seen(who, club);
  return row.private ? (row.always_private ? 'fixed on' : 'on') : 'off';
};
async function ageless(club, members = []) {
  await birthday(SAM, null);
  await live(club, 'No Day Club', members);
}

test('a starter with no birthday: private until they add an adult one', async () => {
  const club = group(32);
  await ageless(club);
  assert.equal((await seen(SAM, club)).private, true);
  assert.equal(await switchOff(SAM, club), 'fixed on');
  await birthday(SAM, '1980-01-01');
  assert.equal((await seen(SAM, club)).always_private, false);
  assert.equal(await switchOff(SAM, club), 'off');
  await reset();
});

test('a starter who turns out to have been under 18 when they started it: private for good', async () => {
  const club = group(33);
  await ageless(club);
  // 18 now, 17 the day they started it.
  await db.query(`update public.clubs set created_at = now() - interval '2 months' where id = $1`, [club]);
  await birthday(SAM, (await db.query(`select ((now() at time zone 'America/Chicago')::date - interval '18 years 1 month')::date::text as d`)).rows[0].d);
  assert.equal(await switchOff(SAM, club), 'fixed on');
  await birthday(SAM, '1980-01-01');
  await reset();
});

test('a starter under 18 grows up: still private', async () => {
  const club = group(34);
  await birthday(SAM, await years(17));
  await live(club, 'No Day Club', [ANA]);
  await db.query(`update public.clubs set created_at = created_at - interval '2 years' where id = $1`, [club]);
  await birthday(SAM, await years(19));
  assert.equal(await switchOff(SAM, club), 'fixed on');
  await birthday(SAM, '1980-01-01');
  await reset();
});

test('handed over while the starter\'s age is unknown: stays private, whatever they add later', async () => {
  const club = group(35);
  await ageless(club, [ANA]);
  await as(SAM, 'select public.hand_over_group($1, $2)', [club, ANA]);
  assert.equal(await switchOff(ANA, club), 'fixed on', 'Ana is an adult, but didn\'t start it');
  await birthday(SAM, '1980-01-01');
  assert.equal(await switchOff(ANA, club), 'fixed on');
  await reset();
  const left = group(36);
  await ageless(left, [ANA]);
  await deleteAccount(SAM);
  assert.equal(await switchOff(ANA, left), 'fixed on', 'left behind by a deleted account too');
  await comeBack(SAM, 'Sam Rivera');
  await reset();
});

test('handed over once the starter is known an adult: the new Admin may make it public', async () => {
  const club = group(37);
  await ageless(club, [ANA]);
  await birthday(SAM, '1980-01-01');
  await as(SAM, 'select public.hand_over_group($1, $2)', [club, ANA]);
  assert.equal(await switchOff(ANA, club), 'off');
  await reset();
});

test('whether a Group is private for good, which says its starter\'s age, is told only to its Admin', async () => {
  const club = group(38);
  await birthday(SAM, await years(15));
  await live(club, 'Teen Chess Club', [ANA]);
  assert.equal((await seen(SAM, club)).always_private, true);
  for (const who of [ANA, STAN]) assert.equal((await seen(who, club)).always_private, false);
  await birthday(SAM, '1980-01-01');
  await reset();
});

test('a waiting photo goes on the list to take down when the Group is handed over, closed or left', async () => {
  const [over, closed, left] = [39, 40, 41].map(group);
  const waiting = async (club, members) => {
    await live(club, 'Joetown Sewing Circle', members);
    await edit(SAM, club, { name: 'Joetown Quilters', photo: PHOTO(SAM, club, 'a1') });
  };
  await waiting(over, [ANA]);
  const [{ drops }] = await as(SAM, 'select public.hand_over_group($1, $2) as drops', [over, ANA]);
  assert.equal(drops, true, 'the app asks the check, which takes the photo down');
  assert.deepEqual(await claim(over, SAM), { drop: [PHOTO(SAM, over, 'a1')] }, 'the one who handed it over asks');
  assert.equal(await claim(over, SAM), null, 'once');
  assert.equal((await seen(ANA, over)).name, 'Joetown Sewing Circle', 'the edit itself is gone');

  await waiting(closed, []);
  assert.equal((await as(SAM, 'select public.close_group($1) as drops', [closed]))[0].drops, true);
  assert.deepEqual(await claim(closed, SAM), { drop: [PHOTO(SAM, closed, 'a1')] });
  assert.equal((await as(SAM, 'select public.hand_over_group($1, $2) as drops', [over, ANA]).catch(() => [{ drops: 'refused' }]))[0].drops, 'refused');

  // Left by the app before it could ask: the new Admin's next edit carries it.
  await reset();
  await waiting(left, [ANA]);
  await as(SAM, 'select public.hand_over_group($1, $2)', [left, ANA]);
  await edit(ANA, left, { name: 'Quilters of Joetown' });
  assert.deepEqual((await claim(left, ANA)).drop, [PHOTO(SAM, left, 'a1')]);

  const none = group(42);
  await live(none, 'Joetown Sewing Circle', [ANA]);
  assert.equal((await as(SAM, 'select public.hand_over_group($1, $2) as drops', [none, ANA]))[0].drops, false, 'nothing waits: nothing to ask');
  await db.exec('delete from private.group_edit_checks');
  await reset();
});

const joinBy = (who, club, fields = '', values = '') =>
  as(who, `insert into public.club_members (club_id, user_id${fields}) values ($1, $2${values}) on conflict (club_id, user_id) do nothing`, [club, who]);

test('the time someone joined is the server\'s: nobody joins in the past and runs the Group next', async () => {
  const club = group(50);
  await live(club, 'Joetown Sewing Circle', [BO]);
  await db.query(`update public.club_members set created_at = now() - interval '1 day' where club_id = $1`, [club]);
  for (const at of ['2000-01-01', '2100-01-01']) {
    await assert.rejects(joinBy(STAN, club, ', created_at', `, '${at}'`), /row-level security/, at);
  }
  await joinBy(STAN, club);
  assert.equal((await seen(STAN, club)).joined, true, 'an ordinary Join, as every phone sends it');
  await as(STAN, `update public.club_members set created_at = '2000-01-01' where club_id = $1`, [club]);
  await joinBy(STAN, club);
  await deleteAccount(SAM);
  assert.equal((await seen(STAN, club)).requests, null, 'Stan joined last');
  assert.equal((await seen(BO, club)).requests, 0);
  await comeBack(SAM, 'Sam Rivera');
  await reset();
});

test('every other way in still works: starting, an invite, an approved ask, leaving and joining again', async () => {
  const [open, priv] = [group(51), group(52)];
  await live(open, 'Joetown Sewing Circle');
  await joinBy(ANA, open);
  await as(ANA, 'delete from public.club_members where club_id = $1 and user_id = $2', [open, ANA]);
  await joinBy(ANA, open);
  assert.equal((await seen(ANA, open)).joined, true);
  await live(priv, 'Thursday Bible Study');
  await db.query('update public.clubs set private = true where id = $1', [priv]);
  await db.query(`insert into private.friendships (a, b, requested_by) values (least($1::uuid, $2::uuid), greatest($1::uuid, $2::uuid), $1)
                  on conflict do nothing`, [SAM, BO]);
  await as(SAM, 'select public.invite_to_group($1, $2)', [priv, [BO]]);
  await joinBy(BO, priv);
  await as(STAN, 'select public.ask_to_join($1)', [priv]);
  await as(SAM, 'select public.answer_join($1, $2, true)', [priv, STAN]);
  for (const who of [SAM, BO, STAN]) assert.equal((await seen(who, priv)).joined, true);
  await reset();
});

test('an edit whose check finishes after a newer edit changes nothing', async () => {
  const club = group(53);
  await live(club, 'Joetown Sewing Circle');
  const named = async () => (await seen(ANA, club)).name;
  await edit(SAM, club, { name: 'First name' });
  const first = await claim(club, SAM);
  await edit(SAM, club, { name: 'Second name' });
  const second = await claim(club, SAM);
  assert.equal(await apply(club, SAM, second), true);
  assert.equal(await apply(club, SAM, first), false, 'the older one finishes last');
  assert.equal(await named(), 'Second name');
  assert.equal(await apply(club, SAM, second), false, 'once');

  await edit(SAM, club, { name: 'Third name' });
  const third = await claim(club, SAM);
  await edit(SAM, club, { name: 'Fourth name' });
  assert.equal(await apply(club, SAM, third), false, 'nor with a newer one still waiting');
  assert.equal(await apply(club, SAM, await claim(club, SAM)), true);

  await edit(SAM, club, { name: 'Fifth name' });
  const fifth = await claim(club, SAM);
  await edit(SAM, club, { name: 'Fourth name' });
  assert.equal(await apply(club, SAM, fifth), false, 'nor once it was taken back to the Group as it is');
  assert.equal(await named(), 'Fourth name');

  // Handed over and back while it is checked.
  await db.query('insert into public.club_members (club_id, user_id) values ($1, $2)', [club, ANA]);
  await edit(SAM, club, { name: 'Sixth name' });
  const sixth = await claim(club, SAM);
  await as(SAM, 'select public.hand_over_group($1, $2)', [club, ANA]);
  await as(ANA, 'select public.hand_over_group($1, $2)', [club, SAM]);
  assert.equal(await apply(club, SAM, sixth), false, 'nor after a hand-over, whoever runs it now');
  assert.equal(await named(), 'Fourth name');
  await db.exec('delete from private.group_edit_checks');
  await reset();
});

test('a photo one check has read goes to no other edit', async () => {
  const club = group(54);
  await live(club, 'Joetown Sewing Circle');
  const A = PHOTO(SAM, club, 'a1');
  await edit(SAM, club, { name: 'Joetown Quilters', photo: A });
  await claim(club, SAM);
  await assert.rejects(edit(SAM, club, { name: 'Another name', photo: A }), /own new upload/);
  await db.exec('delete from private.group_edit_checks');
  await reset();
});

for (const [who, day] of [['no birthday', null], ['a birthday under 18', 15]]) {
  test(`a public Group an adult started stays public when its new Admin has ${who}`, async () => {
    const club = group(next++);
    await live(club, 'Joetown Sewing Circle', [BO]);
    await birthday(BO, day && await years(day));
    await as(SAM, 'select public.hand_over_group($1, $2)', [club, BO]);
    assert.equal((await seen(BO, club)).always_private, false);
    await edit(BO, club, { eventsBy: 'members' });
    const row = await seen(BO, club);
    assert.deepEqual([row.private, row.always_private, row.events_by], [false, false, 'members']);
    await edit(BO, club, { private: true });
    await edit(BO, club, { private: false });
    assert.equal((await seen(BO, club)).private, false, 'theirs to turn on and off');
    await birthday(BO, '1980-01-01');
    await reset();
  });
}
