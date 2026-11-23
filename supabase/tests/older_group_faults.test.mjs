// Fixed stories for the older Group faults (supabase/migrations/*_older_group_faults.sql, BP app docs/plans/start-a-group,
// ticket 09): a Group's live photo can't be swapped, its Admin can't delete its members' Events with it, a waiting Event
// can't be moved to someone else's Group, the watch never takes a members-only Event for a repeat, a Private-only save
// leaves a name being checked alone, joining ends your ask, and the morning's pick of a members-only Event shows a stranger nothing.
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
await db.query('insert into private.friendships (a, b, requested_by) values ($1, $2, $1)', [SAM, STAN].sort());
await db.exec(`insert into storage.buckets (id, name, public) values ('event-images', 'event-images', true) on conflict (id) do nothing`);

const roles = { service: 'service_role', watch: 'watch' };
async function as(who, sql, params = []) {
  if (roles[who]) await db.exec(`discard plans; set role ${roles[who]}; set request.jwt.claims = '{"role": "${roles[who]}"}'`);
  else if (who === null) await db.exec('set role anon');
  else await db.exec(`set role authenticated; set request.jwt.claims = '${JSON.stringify({ sub: who, is_anonymous: false })}'`);
  try {
    return (await db.query(sql, params)).rows;
  } finally {
    await db.exec('reset role; reset request.jwt.claims');
  }
}
const tomorrow = (await db.query(`select ((now() at time zone 'America/Chicago')::date + 1)::text as d`)).rows[0].d;
const URL_ = 'https://lxdgwhvqjqmqliobwjpi.supabase.co/storage/v1/object/public/event-images/';
const first = (who, club) => `${who}/group-${club}.jpg`;
const later = (who, club, k) => `${who}/group-${club}-${k}.jpg`;

// A Group of Sam's in this state, with these members and Who can add events.
async function made(club, { members = [], eventsBy = 'members', priv = false, status = 'approved', photo = false } = {}) {
  if (photo) await upload(first(SAM, club));
  await as(SAM, 'select public.start_group($1, $2, null, $3, $4)',
           [club, 'Joetown Sewing Circle', photo ? URL_ + first(SAM, club) : null, priv]);
  await db.query(`update public.clubs set status = $2, events_by = $3, created_at = now() - interval '2 days' where id = $1`,
                 [club, status, eventsBy]);
  for (const m of members) await db.query('insert into public.club_members (club_id, user_id) values ($1, $2)', [club, m]);
}
let n = 0;
async function added(who, club, title = 'Holiday quilt swap') {
  const event = `00000000-0000-0000-0008-${String(++n).padStart(12, '0')}`;
  await as(who, `insert into public.club_events (id, submitted_by, title, event_date, start_time, location, club_id)
                 values ($1, $2, $3, $4, '10:00', 'Resurrection Lutheran', $5)`, [event, who, title, tomorrow, club]);
  return event;
}
const upload = (name) => db.query(`insert into storage.objects (bucket_id, name) values ('event-images', $1)`, [name]);
async function del(who, name) {
  await as(who, 'delete from storage.objects where name = $1', [name]);
  return (await db.query('select 1 from storage.objects where name = $1', [name])).rows.length === 0;
}
const edit = (who, club, f = {}) => as(who, 'select public.edit_group($1, $2, $3, $4, $5, $6, $7, $8) as checks',
  [club, 'name' in f ? f.name : 'Joetown Sewing Circle', null, f.about ?? null, f.photo ?? null, f.private ?? false,
   f.eventsBy ?? 'members', null]).then((r) => r[0].checks);
const claim = (club, who) => as('service', 'select public.claim_group_edit($1, $2) as e', [club, who]).then((r) => r[0].e);
const apply = (club, who, e) => as('service', 'select public.apply_group_edit($1, $2, $3) as ok', [club, who, e]).then((r) => r[0].ok);
const seen = async (who, club) => (await as(who, 'select * from public.get_groups()')).find((g) => g.id === club);
const reset = () => db.exec(`delete from public.club_events; delete from public.clubs where submitted_by is not null or status = 'closed';
                             delete from storage.objects; delete from private.group_edit_checks`);

test('a Group\'s photo can\'t be deleted from under it, by who uploaded it, so no unchecked one takes its name', async () => {
  const club = group(1);
  await made(club, { members: [ANA], photo: true });
  await upload(`${SAM}/stray.jpg`);
  assert.equal(await del(SAM, first(SAM, club)), false, 'the live photo stays');
  assert.equal(await del(SAM, `${SAM}/stray.jpg`), true, 'a file nothing shows goes');
  await as(SAM, 'select public.hand_over_group($1, $2)', [club, ANA]);
  assert.equal(await del(SAM, first(SAM, club)), false, 'nor by its old Admin, whose folder it is in');
  await reset();
});

test('a waiting Group\'s photo and one being checked stay put too; a replaced one may go', async () => {
  const club = group(2);
  await made(club, { photo: true, status: 'pending' });
  assert.equal(await del(SAM, first(SAM, club)), false, 'its starter\'s photo, while its checks run');
  await db.query(`update public.clubs set status = 'approved' where id = $1`, [club]);
  await upload(later(SAM, club, 'a1'));
  await edit(SAM, club, { photo: URL_ + later(SAM, club, 'a1') });
  const e = await claim(club, SAM);
  assert.equal(await del(SAM, later(SAM, club, 'a1')), false, 'a new photo, while it is checked');
  assert.equal(await apply(club, SAM, e), true);
  assert.equal(await del(SAM, later(SAM, club, 'a1')), false, 'and once it is live');
  assert.equal(await del(SAM, first(SAM, club)), true, 'the old one shows nowhere now');
  await reset();
});

test('a new Group takes only a photo that is already up', async () => {
  const club = group(17);
  const start = () => as(SAM, 'select public.start_group($1, $2, null, $3)', [club, 'Joetown Sewing Circle', URL_ + first(SAM, club)]);
  await assert.rejects(start(), /your own upload/);
  await upload(first(SAM, club));
  await start();
  await reset();
});

test('an Admin can\'t delete a waiting Group, and its members\' Events with it', async () => {
  const club = group(3);
  await made(club, { members: [ANA], status: 'pending' });
  const event = await added(ANA, club);
  await as(SAM, 'delete from public.clubs where id = $1', [club]);
  assert.equal((await db.query('select 1 from public.clubs where id = $1', [club])).rows.length, 1, 'the Group stays: Close is the way');
  assert.equal((await db.query('select 1 from public.club_events where id = $1', [event])).rows.length, 1, 'and Ana\'s Event');
  await as(SAM, 'select public.close_group($1)', [club]);
  assert.equal((await db.query('select 1 from public.club_events where id = $1', [event])).rows.length, 1, 'closed, it keeps it');
  await reset();
});

test('a waiting Event can\'t be moved to a Group its poster can\'t add to', async () => {
  const [mine, theirs] = [group(4), group(5)];
  await made(mine, { members: [ANA] });
  await made(theirs, { eventsBy: 'admin' });
  const event = await added(ANA, mine);
  const move = (to) => as(ANA, 'update public.club_events set club_id = $2 where id = $1', [event, to]);
  await assert.rejects(move(theirs), /row-level security/, 'not one of Sam\'s she isn\'t in');
  assert.equal((await db.query('select club_id from public.club_events where id = $1', [event])).rows[0].club_id, mine);
  await as(ANA, `update public.club_events set title = 'Quilt swap' where id = $1`, [event]);
  await move(null);
  await assert.rejects(move(theirs), /row-level security/, 'nor one that had no Group');
  await move(mine);
  await reset();
});

test('the watch takes no Event outside the Town\'s sight for a repeat', async () => {
  const [open, priv, waiting, closed] = [group(6), group(7), group(8), group(9)];
  await made(open, {});
  await made(priv, { priv: true });
  await made(waiting, {});
  await made(closed, {});
  const events = {};
  for (const c of [open, priv, waiting, closed]) events[c] = await added(SAM, c);
  const own = await added(SAM, null);
  await db.exec(`update public.club_events set status = 'approved'`);
  await db.query(`update public.clubs set status = 'pending' where id = $1`, [waiting]);
  await db.query(`update public.clubs set status = 'closed' where id = $1`, [closed]);
  for (const who of ['service', 'watch']) {
    const listed = (await as(who, 'select public.listed_for_writer() as l'))[0].l.map((e) => e.id).sort();
    assert.deepEqual(listed, [events[open], own].sort(), `${who}: the public Group's and the neighbour's own`);
  }
  await reset();
});

test('a save that only changes Private leaves a name being checked alone', async () => {
  const club = group(10);
  await made(club, {});
  await edit(SAM, club, { name: 'Joetown Quilters' });
  const e = await claim(club, SAM);
  assert.equal(await edit(SAM, club, { name: null, private: true }), false, 'nothing for the check');
  assert.equal((await seen(SAM, club)).private, true, 'Private lands');
  assert.equal(await apply(club, SAM, e), true, 'and the name still lands');
  assert.equal((await seen(SAM, club)).name, 'Joetown Quilters');
  // A name still waiting (the day's checks used) stays waiting.
  await edit(SAM, club, { name: 'Joetown Stitchers', private: true });
  await edit(SAM, club, { name: null, private: false });
  assert.equal((await claim(club, SAM)).name, 'Joetown Stitchers');
  await reset();
});

test('joining ends your ask, so leaving later leaves no "Asked" behind', async () => {
  const club = group(11);
  await made(club, { priv: true });
  const ask = (on = true) => as(STAN, 'select public.ask_to_join($1, $2)', [club, on]);
  await ask();
  await as(SAM, 'select public.answer_join($1, $2, false)', [club, STAN]);
  assert.equal((await seen(STAN, club)).asked, true, 'turned down: still Asked');
  await as(SAM, 'select public.invite_to_group($1, $2)', [club, [STAN]]);
  await as(STAN, 'insert into public.club_members (club_id, user_id) values ($1, $2)', [club, STAN]);
  await as(STAN, 'delete from public.club_members where club_id = $1 and user_id = $2', [club, STAN]);
  assert.equal((await seen(STAN, club)).asked, false, 'in, then out: may ask again');
  await ask();
  assert.equal((await as(SAM, 'select * from public.get_join_requests($1)', [club])).length, 1, 'and the Admin hears it');
  // Asked, then invited in: no ask is left waiting from someone already in.
  await as(SAM, 'select public.invite_to_group($1, $2)', [club, [STAN]]);
  await as(STAN, 'insert into public.club_members (club_id, user_id) values ($1, $2)', [club, STAN]);
  assert.equal((await as(SAM, 'select * from public.get_join_requests($1)', [club])).length, 0);
  await reset();
});

test('the morning\'s pick of a members-only Event gives a stranger nothing, and their Event of the day is the feed\'s', async () => {
  const [open, priv] = [group(15), group(16)];
  const today = (await db.query(`select (now() at time zone 'America/Chicago')::date::text as d`)).rows[0].d;
  await made(open, { members: [ANA] });
  await made(priv, { members: [ANA], priv: true });
  const [shown, secret] = [await added(ANA, open, 'Holiday quilt swap'), await added(ANA, priv, 'Members quilt night')];
  await db.query(`update public.club_events set status = 'approved', event_date = $1, start_time = '11:59 PM'`, [today]);
  await db.query(`insert into public.daily_standouts (town, day, event_id, rank, why)
                  values ('st-joseph-mn', $1, $2, 1, 'Members quilt night is the one to see')`, [today, secret]);
  const read = (who) => as(who, 'select event_id from public.daily_standouts').then((r) => r.map((x) => x.event_id));
  assert.deepEqual(await read(ANA), [secret], 'a member reads it');
  assert.deepEqual(await read(STAN), [], 'a stranger doesn\'t');
  assert.deepEqual(await read(null), [], 'nor signed out');
  const noon = `${today}T18:00:00Z`;
  const best = (who) => as(who, 'select id from public.get_event_of_the_day($1)', [noon]).then((r) => r.map((x) => x.id));
  assert.deepEqual(await best(STAN), [shown], 'a stranger\'s day isn\'t left empty by it');
  await db.query(`update public.daily_standouts set event_id = $1, why = 'Swap'`, [shown]);
  assert.deepEqual(await read(null), [shown], 'a public one shows to all');
  await reset();
});
