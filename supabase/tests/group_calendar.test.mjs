// Fixed stories for a Group's Calendar (supabase/migrations/*_group_calendar.sql, BP app docs/plans/start-a-group,
// ticket 05): who may add an Event to a Group (its Admin, and whoever Edit group's Who can add events lets in), a
// private Group's Events reaching only those in it, and Add when you meet writing the repeats its Calendar reads.
// Run in PGlite: `npm install && npm test` in this folder.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { realDatabase } from './fixture.mjs';

const db = await realDatabase();
const id = (n) => `00000000-0000-0000-0000-${String(n).padStart(12, '0')}`;
const group = (n) => `00000000-0000-0000-0009-${String(n).padStart(12, '0')}`;
const [SAM, ANA, BO, STAN] = [1, 2, 3, 4].map(id);

for (const [who, name] of [[SAM, 'Sam Rivera'], [ANA, 'Ana Lee'], [BO, 'Bo Dale'], [STAN, 'Stan Ger']]) {
  await db.query('insert into auth.users (id) values ($1)', [who]);
  await db.query('insert into public.town_profiles (user_id, display_name, birthday) values ($1, $2, $3)',
                 [who, name, '1980-01-01']);
}

async function as(who, sql, params = []) {
  if (who === null) await db.exec('set role anon');
  else await db.exec(`set role authenticated; set request.jwt.claims = '${JSON.stringify({ sub: who, is_anonymous: false })}'`);
  try {
    return (await db.query(sql, params)).rows;
  } finally {
    await db.exec('reset role; reset request.jwt.claims');
  }
}
const [today, tomorrow] = (await db.query(`select (now() at time zone 'America/Chicago')::date::text as t,
  ((now() at time zone 'America/Chicago')::date + 1)::text as m`)).rows.map((r) => [r.t, r.m])[0];

// A live Group Sam runs, with these members, Who can add events and these picked.
async function live(club, { members = [], eventsBy = 'admin', picked = [], priv = false, status = 'approved' } = {}) {
  await as(SAM, 'select public.start_group($1, $2, null, null, $3)', [club, 'Joetown Sewing Circle', priv]);
  // Started days ago, so start_group's 3 a day never counts it.
  await db.query(`update public.clubs set status = $2, events_by = $3, created_at = now() - interval '2 days'
                  where id = $1`, [club, status, eventsBy]);
  for (const m of members) await db.query('insert into public.club_members (club_id, user_id) values ($1, $2)', [club, m]);
  for (const m of picked) await db.query('insert into private.club_editors (club_id, user_id) values ($1, $2)', [club, m]);
}
let n = 0;
// New post's New event with the Group as host, as the app sends it.
async function added(who, club, title = 'Holiday quilt swap') {
  const event = `00000000-0000-0000-0008-${String(++n).padStart(12, '0')}`;
  await as(who, `insert into public.club_events (id, submitted_by, title, event_date, start_time, location, club_id)
                 values ($1, $2, $3, $4, '10:00', 'Resurrection Lutheran', $5)`, [event, who, title, tomorrow, club]);
  return event;
}
const claim = async (event, who) =>
  (await db.query('select public.claim_submit($1, $2) as ok', [event, who])).rows[0].ok;
const approve = (event) => db.query(`update public.club_events set status = 'approved' where id = $1`, [event]);
const reset = () => db.exec('delete from public.club_events; delete from public.clubs where submitted_by is not null');

test('the Admin adds an Event to the Group; a member only when Who can add events lets them', async () => {
  const club = group(1);
  await live(club, { members: [ANA, BO] });
  assert.equal(await claim(await added(SAM, club), SAM), true, 'the Admin');
  await assert.rejects(added(ANA, club), /row-level security/, 'Only me: a member is refused');

  await db.query(`update public.clubs set events_by = 'picked' where id = $1`, [club]);
  await db.query('insert into private.club_editors (club_id, user_id) values ($1, $2)', [club, ANA]);
  assert.equal(await claim(await added(ANA, club), ANA), true, 'Members I pick: Ana is picked');
  await assert.rejects(added(BO, club), /row-level security/, 'Bo isn\'t');

  await db.query(`update public.clubs set events_by = 'members' where id = $1`, [club]);
  assert.equal(await claim(await added(BO, club), BO), true, 'All members');
  await reset();
});

test('nobody outside it adds to a Group, nor to one turned down', async () => {
  const club = group(2);
  await live(club, { eventsBy: 'members' });
  await assert.rejects(added(STAN, club), /row-level security/, 'a stranger can\'t even save one');
  const turnedDown = group(3);
  await live(turnedDown, { status: 'rejected' });
  await assert.rejects(added(SAM, turnedDown), /row-level security/, 'a Group its checks said no to');
  // One saved before the rules said no (an older build, a Group closed meanwhile) never passes the check.
  const old = await added(SAM, club);
  await db.query(`update public.clubs set status = 'closed' where id = $1`, [club]);
  assert.equal(await claim(old, SAM), false, 'a closed Group');
  await reset();
});

test('a private Group\'s Event reaches only those in it; a public Group\'s goes to the Town feed', async () => {
  const [priv, pub] = [group(4), group(5)];
  await live(priv, { members: [ANA], priv: true });
  await live(pub, { members: [ANA] });
  const secret = await added(SAM, priv, 'Members quilt night');
  const open = await added(SAM, pub, 'Holiday quilt swap');
  for (const e of [secret, open]) { assert.equal(await claim(e, SAM), true); await approve(e); }

  const feed = async (who) => (await as(who, 'select id, club_id, in_club from public.get_town_feed(now(), false)'));
  const calendar = async (who, club) => (await as(who, 'select card->>\'id\' as id from public.get_group_events($1)', [club])).map((r) => r.id);

  assert.deepEqual(await calendar(ANA, priv), [secret], 'a member sees it on the Calendar');
  assert.ok((await feed(ANA)).some((r) => r.id === secret && r.club_id === priv && r.in_club), 'and in the Town feed');
  for (const who of [STAN, null]) {
    assert.deepEqual(await calendar(who, priv), [], 'not a stranger, nor signed out');
    assert.ok(!(await feed(who)).some((r) => r.id === secret), 'nor in their Town feed');
    assert.equal((await as(who, 'select id from public.club_events where id = $1', [secret])).length, 0, 'nor from the table');
  }
  assert.deepEqual(await calendar(STAN, pub), [open], 'a public Group\'s shows to anyone');
  assert.ok((await feed(STAN)).some((r) => r.id === open && r.club_id === pub && !r.in_club), 'with its Group and Join');
  await reset();
});

test('a found Event of a private Group shows a stranger no Group to join', async () => {
  const club = group(6);
  await live(club, { members: [ANA], priv: true });
  await db.query(`update public.clubs set place_entry_id = 'resurrection-lutheran' where id = $1`, [club]);
  const found = id(900);
  await db.query(`insert into public.club_events (id, title, event_date, start_time, location, source_name, place_entry_id, status)
                  values ($1, 'Joetown Sewing Circle', $2, '18:30', 'Resurrection Lutheran', 'Resurrection Lutheran',
                          'resurrection-lutheran', 'approved')`, [found, tomorrow]);
  const card = async (who) => (await as(who, 'select club_id from public.get_town_feed(now(), false) where id = $1', [found]))[0];
  assert.equal((await card(ANA)).club_id, club, 'a member sees its Group');
  assert.equal((await card(STAN)).club_id, null, 'a stranger sees the Event, no Group');
  assert.deepEqual(await as(STAN, 'select card from public.get_group_events($1)', [club]), [], 'and nothing on its Calendar');
  await reset();
});

const meets = (who, club, days, weeks, time, where) =>
  as(who, 'select public.set_group_meets($1, $2, $3, $4, $5) as schedule', [club, days, weeks, time, where]);
const calendar = async (who, club) => (await as(who, 'select public.get_group_calendar($1) as c', [club]))[0].c;

test('Add when you meet writes the repeats the Calendar reads, 4 months ahead', async () => {
  const club = group(7);
  await live(club, { members: [ANA] });
  await assert.rejects(meets(ANA, club, ['tue'], null, '18:30', 'Resurrection Lutheran'), /only the Admin/);
  const [{ schedule }] = await meets(SAM, club, ['tue'], null, '18:30', 'Resurrection Lutheran');
  assert.equal(schedule, 'Tuesdays at 6:30 PM');
  const { meetings, adds } = await calendar(ANA, club);
  assert.equal(adds, false, 'Only me: Ana can\'t add');
  assert.ok(meetings.length >= 17, `every Tuesday for 120 days, not get_groups' 10 (${meetings.length})`);
  assert.ok(meetings.every((m) => m.what === 'Get-together' && m.time === '18:30' && m.day >= today));
  const [row] = await as(ANA, 'select schedule, location from public.get_groups() where id = $1', [club]);
  assert.deepEqual(row, { schedule: 'Tuesdays at 6:30 PM', location: 'Resurrection Lutheran' }, 'the when line');
  assert.equal((await calendar(SAM, club)).adds, true, 'the Admin adds');

  const [{ schedule: twice }] = await meets(SAM, club, ['tue', 'thu'], [1, 3], '09:00', null);
  assert.equal(twice, '1st & 3rd Tuesdays & Thursdays at 9 AM');
  assert.ok((await calendar(ANA, club)).meetings.every((m) => Number(m.day.slice(8)) <= 7
    || (Number(m.day.slice(8)) >= 15 && Number(m.day.slice(8)) <= 21)), 'only the 1st and 3rd weeks');
  const [{ schedule: monthly }] = await meets(SAM, club, ['mon'], [2], null, null);
  assert.equal(monthly, '2nd Mondays');
  await meets(SAM, club, ['mon'], null, '18:30', 'Resurrection Lutheran');
  const [{ schedule: none }] = await meets(SAM, club, [], null, null, 'Resurrection Lutheran');
  assert.equal(none, null);
  assert.deepEqual((await calendar(ANA, club)).meetings, [], 'no days: no repeats');
  const [cleared] = await as(ANA, 'select schedule, location from public.get_groups() where id = $1', [club]);
  assert.deepEqual(cleared, { schedule: null, location: null }, 'nor the Place they were at');
  await reset();
});

test('Add when you meet takes only real days, weeks and times', async () => {
  const club = group(8);
  await live(club);
  await assert.rejects(meets(SAM, club, ['tuesday'], null, null, null), /days/);
  await assert.rejects(meets(SAM, club, ['tue'], [6], null, null), /weeks/);
  await assert.rejects(meets(SAM, club, ['tue'], null, '25:00', null), /time/);
  await assert.rejects(meets(SAM, club, ['tue'], null, null, 'x'.repeat(121)), /place/);
  await reset();
});

test('a private Group\'s Calendar stays inside it', async () => {
  const club = group(9);
  await live(club, { members: [ANA], priv: true, eventsBy: 'members' });
  await meets(SAM, club, ['tue'], null, '18:30', null);
  assert.ok((await calendar(ANA, club)).meetings.length > 0);
  assert.equal((await calendar(ANA, club)).adds, true, 'All members');
  assert.deepEqual(await calendar(STAN, club), { meetings: [], adds: false, meets: null }, 'a stranger: none');
  assert.deepEqual(await calendar(null, club), { meetings: [], adds: false, meets: null }, 'signed out: none');
  await reset();
});

test('a Group waiting on its checks still works for its members: their Events reach only them', async () => {
  const club = group(10);
  await live(club, { members: [ANA, BO], status: 'pending', eventsBy: 'picked', picked: [ANA] });
  assert.equal((await calendar(SAM, club)).adds, true, 'the Admin sees the +');
  assert.equal((await calendar(ANA, club)).adds, true, 'and a member it picked');
  assert.equal((await calendar(BO, club)).adds, false);
  const swap = await added(ANA, club, 'Holiday quilt swap');
  assert.equal(await claim(swap, ANA), true);
  await approve(swap);
  const events = async (who) => (await as(who, 'select card->>\'id\' as id from public.get_group_events($1)', [club])).map((r) => r.id);
  const feed = async (who) => (await as(who, 'select id from public.get_town_feed(now(), false)')).map((r) => r.id);
  assert.deepEqual(await events(BO), [swap], 'a member sees it on the Calendar');
  assert.ok((await feed(BO)).includes(swap), 'and in their Town feed, as a private Group\'s');
  for (const who of [STAN, null]) {
    assert.deepEqual(await events(who), [], 'not a stranger, nor signed out');
    assert.ok(!(await feed(who)).includes(swap), 'nor the Town feed');
  }
  await db.query(`update public.clubs set status = 'approved' where id = $1`, [club]);
  assert.ok((await feed(STAN)).includes(swap), 'live: the Town sees it');
  await reset();
});

test('a public Group still waiting, or turned down, keeps its get-togethers to those in it', async () => {
  const club = group(11);
  await live(club, { members: [ANA], status: 'pending' });
  await meets(SAM, club, ['tue'], null, '18:30', null);
  assert.ok((await calendar(ANA, club)).meetings.length > 0, 'a member still sees them');
  assert.ok((await calendar(SAM, club)).meetings.length > 0, 'and its Admin');
  for (const who of [STAN, null]) assert.deepEqual((await calendar(who, club)).meetings, [], 'not anyone with its id');
  await db.query(`update public.clubs set status = 'rejected' where id = $1`, [club]);
  assert.deepEqual((await calendar(STAN, club)).meetings, [], 'nor once turned down');
  await reset();
});

test('Edit when you meet reads the rule the Group has', async () => {
  const club = group(12);
  await live(club, { members: [ANA] });
  await meets(SAM, club, ['thu', 'tue'], [1, 3], '18:30', 'Resurrection Lutheran');
  assert.deepEqual((await calendar(SAM, club)).meets,
                   [{ what: 'Get-together', days: ['tue', 'thu'], weeks: [1, 3], time: '18:30' }]);
  await reset();
});

test('the Admin takes any of the Group\'s own Events off; nobody else does', async () => {
  const club = group(13);
  await live(club, { members: [ANA], eventsBy: 'members' });
  const [mine, hers] = [await added(SAM, club, 'Mending clinic'), await added(ANA, club, 'Holiday quilt swap')];
  for (const [e, who] of [[mine, SAM], [hers, ANA]]) { assert.equal(await claim(e, who), true); await approve(e); }
  const found = id(901);
  await db.query(`insert into public.club_events (id, title, event_date, start_time, location, source_name, status)
                  values ($1, 'Town quilt show', $2, '10:00', 'City Hall', 'City of St. Joseph', 'approved')`, [found, tomorrow]);
  assert.deepEqual((await calendar(SAM, club)).takes_off.sort(), [mine, hers].sort(), 'the Admin may take off its own');
  assert.equal((await calendar(ANA, club)).takes_off, undefined, 'a member, none');

  const off = (who, e) => as(who, 'select public.take_off_group_event($1)', [e]);
  await assert.rejects(off(ANA, hers), /only the Admin/, 'not even its poster, a member');
  await assert.rejects(off(SAM, found), /only the Admin/, 'nor an Event the Group didn\'t put on');
  await off(SAM, hers);
  const events = async (who) => (await as(who, 'select card->>\'id\' as id from public.get_group_events($1)', [club])).map((r) => r.id);
  assert.deepEqual(await events(STAN), [mine], 'off its Calendar');
  assert.ok(!(await as(STAN, 'select id from public.get_town_feed(now(), false)')).some((r) => r.id === hers), 'and the Town feed');
  await reset();
});


const seesEvent = async (who, club, event) => ({
  calendar: (await as(who, 'select card->>\'id\' as id from public.get_group_events($1)', [club])).some((r) => r.id === event),
  feed: (await as(who, 'select id from public.get_town_feed(now(), false)')).some((r) => r.id === event),
  table: (await as(who, 'select id from public.club_events where id = $1', [event])).length > 0,
});
const NONE = { calendar: false, feed: false, table: false };

for (const [n, status, priv, what] of [[14, 'pending', false, 'a waiting'], [15, 'approved', false, 'a live'], [16, 'approved', true, 'a private']]) {
  test(`closing ${what} Group takes its Events, get-togethers and members away from everyone`, async () => {
    const club = group(n);
    await live(club, { members: [ANA, BO], status, priv, eventsBy: 'members' });
    await meets(SAM, club, ['tue'], null, '18:30', null);
    const swap = await added(ANA, club, 'Holiday quilt swap');
    assert.equal(await claim(swap, ANA), true);
    await approve(swap);
    assert.deepEqual(await seesEvent(BO, club, swap), { calendar: true, feed: true, table: true }, 'a member, while it runs');
    await as(SAM, 'select public.close_group($1)', [club]);
    for (const who of [STAN, BO, SAM, null]) {
      assert.deepEqual(await seesEvent(who, club, swap), NONE, 'nobody sees its Events');
      assert.equal(await calendar(who, club), null, 'nor its Calendar');
    }
    assert.equal((await as(ANA, 'select id from public.club_events where id = $1', [swap])).length, 1, 'only whoever posted one keeps it');
    for (const who of [STAN, SAM]) {
      assert.deepEqual(await as(who, 'select user_id from public.club_members where club_id = $1 and user_id <> $2', [club, who]), [],
                       'nor who was in it');
      assert.deepEqual((await as(who, 'select group_ids from public.get_profile($1)', [BO]))[0].group_ids, [], 'on a Profile either');
    }
    await reset();
  });
}

const friends = (a, b) => db.query(`insert into private.friendships (a, b, requested_by)
  values (least($1::uuid, $2::uuid), greatest($1::uuid, $2::uuid), $1) on conflict do nothing`, [a, b]);
let clients = 0;
const send = async (who, to, { words = null, event = null, reply = null, chat = null } = {}) => (await as(who,
  'select * from public.send_chat_message($1, $2, $3, $4, null, null, null, $5, $6)',
  [chat, chat ? null : to, id(5000 + ++clients), words, event, reply]))[0];
const messages = (who, chat) => as(who, 'select * from public.get_chat_messages($1)', [chat]);
const emptyChats = () => db.exec('delete from public.chat_messages; delete from private.chat_members; delete from private.chats');

for (const [n, priv, status, what] of [[17, false, 'pending', 'a waiting'], [18, true, 'approved', 'a private']]) {
  test(`an Event of ${what} Group shared in a chat shows its card only to those who see the Group`, async () => {
    const club = group(n);
    await friends(ANA, STAN);
    await friends(ANA, BO);
    await live(club, { members: [ANA, BO], priv, status });
    const night = await added(SAM, club, 'Members quilt night');
    assert.equal(await claim(night, SAM), true);
    await approve(night);

    const sent = await send(ANA, STAN, { event: night });
    const toBo = await send(ANA, BO, { event: night });
    const card = async (who, m) => (await messages(who, m.chat_id)).find((r) => r.id === m.id).card;
    assert.equal((await card(ANA, sent)).title, 'Members quilt night', 'its sender, a member');
    assert.equal((await card(BO, toBo)).title, 'Members quilt night', 'another member');
    assert.equal(await card(STAN, sent), null, 'a friend outside the Group gets no title, place or Group');
    const answer = await send(STAN, null, { chat: sent.chat_id, words: 'What is it?', reply: sent.id });
    const quoted = async (who) => (await messages(who, sent.chat_id)).find((r) => r.id === answer.id).reply.body;
    assert.equal(await quoted(STAN), null, 'nor in a quote of it');
    assert.equal(await quoted(ANA), 'Members quilt night');
    await assert.rejects(send(STAN, null, { chat: sent.chat_id, event: night }), /chat_event_gone/, 'nor sends it on');

    await db.query(`update public.clubs set private = false, status = 'approved' where id = $1`, [club]);
    assert.equal((await card(STAN, sent)).title, 'Members quilt night', 'live and public: the Town sees it');
    await as(SAM, 'select public.close_group($1)', [club]);
    assert.equal(await card(BO, toBo), null, 'closed: nobody');
    await emptyChats();
    await reset();
  });
}

test('a Group\'s Event takes Going only from those who see it, and Hide never names its Group to anyone else', async () => {
  const club = group(19);
  await live(club, { members: [ANA], priv: true });
  const night = await added(SAM, club, 'Members quilt night');
  assert.equal(await claim(night, SAM), true);
  await approve(night);
  const going = (who) => as(who, 'insert into public.event_rsvps (event_id, user_id) values ($1, $2)', [night, who]);
  await going(ANA);
  await assert.rejects(going(STAN), /row-level security/, 'whoever gave them the id');
  await assert.rejects(as(STAN, 'select public.mute_host($1)', [night]), /nothing to mute/);
  await reset();
});

test('a Group\'s Event\'s Going chat is only for those who still see it', async () => {
  const club = group(20);
  await live(club, { members: [ANA, BO], priv: true });
  const night = await added(SAM, club, 'Members quilt night');
  assert.equal(await claim(night, SAM), true);
  await approve(night);
  for (const who of [ANA, BO]) await as(who, 'insert into public.event_rsvps (event_id, user_id) values ($1, $2)', [night, who]);
  const [{ chat }] = await as(BO, 'select public.join_going_chat($1) as chat', [night]);
  await as(ANA, 'select public.join_going_chat($1)', [night]);
  await send(ANA, null, { chat, words: 'See you there' });
  const rooms = async (who) => (await as(who, 'select * from public.get_chats()')).filter((c) => c.kind === 'going');
  assert.equal((await rooms(BO))[0].event.title, 'Members quilt night');

  await as(BO, 'delete from public.club_members where club_id = $1 and user_id = $2', [club, BO]);
  assert.deepEqual(await rooms(BO), [], 'left the Group: its Event\'s chat goes');
  assert.deepEqual(await messages(BO, chat), []);
  assert.equal((await as(BO, 'select state from public.get_going_chat($1)', [night]))[0].state, 'none');
  await assert.rejects(as(BO, 'select public.join_going_chat($1)', [night]), /chat_not_going/);
  assert.equal((await rooms(ANA)).length, 1, 'a member keeps it');
  await as(SAM, 'select public.close_group($1)', [club]);
  assert.deepEqual(await rooms(ANA), [], 'closed: it goes');
  await emptyChats();
  await reset();
});

test('any other Event still takes Going from anyone, and a friend\'s share of it shows', async () => {
  await friends(ANA, STAN);
  const event = id(902);
  await db.query(`insert into public.club_events (id, title, event_date, status) values ($1, 'Town quilt show', $2, 'approved')`, [event, tomorrow]);
  await as(STAN, 'insert into public.event_rsvps (event_id, user_id) values ($1, $2)', [event, STAN]);
  const sent = await send(ANA, STAN, { event });
  assert.equal((await messages(STAN, sent.chat_id)).find((r) => r.id === sent.id).card.title, 'Town quilt show');
  await emptyChats();
  await reset();
});
