// Fixed stories for the Group chat (supabase/migrations/*_group_chat.sql, BP app five-tabs 07), run in PGlite: who is in
// it is worked out from the Group's members, under 18 and no birthday stay out, every message lights the dot, it takes
// words and Events but no photos, and it closes when the Group is hidden.
// Run: `npm install && npm test` in this folder.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { realDatabase } from './fixture.mjs';

const db = await realDatabase();
const id = (n) => `00000000-0000-0000-0000-${String(n).padStart(12, '0')}`;
const [ANA, BEN, CAL, KID, BLANK, QUIET] = [1, 2, 3, 4, 5, 6].map(id);
const [GROUP, HIDDEN, OTHER, EVENT] = [901, 902, 903, 904].map(id);
let clients = 0;
const client = () => id(1000 + ++clients);

async function reset() {
  await db.exec(`reset role; reset request.jwt.claims;
    delete from public.chat_reads; delete from public.chat_messages; delete from private.chat_members;
    delete from private.chats; delete from private.chat_reports; delete from private.blocks; delete from private.friendships; delete from public.club_members;
    delete from public.clubs; delete from public.town_profiles; delete from public.club_events; delete from auth.users;`);
  for (const [who, name, anonymous, birthday] of [
    [ANA, 'Ana Moss', false, '1980-01-01'], [BEN, 'Ben Ortiz', false, '1990-02-02'], [CAL, 'Cal Ruiz', false, '1985-03-03'],
    [KID, 'Kit Young', false, '2012-05-01'], [BLANK, 'Nia Blank', false, null], [QUIET, 'Anon Ymous', true, '1980-01-01']]) {
    await db.query('insert into auth.users (id, is_anonymous) values ($1, $2)', [who, anonymous]);
    await db.query('insert into public.town_profiles (user_id, display_name, birthday) values ($1, $2, $3)', [who, name, birthday]);
  }
  await db.query(`insert into public.clubs (id, name, status) values
    ($1, 'Rod and Gun Club', 'approved'), ($2, 'Hidden Group', 'rejected'), ($3, 'Yarnovers', 'approved')`, [GROUP, HIDDEN, OTHER]);
  await db.query(`insert into public.club_events (id, title, status, kind, event_date) values
    ($1, 'Ice Fishing Contest', 'approved', 'event', current_date + 30)`, [EVENT]);
}

async function as(who, sql, params = [], { anonymous = false } = {}) {
  await db.exec(`set role authenticated; set request.jwt.claims = '${JSON.stringify({ sub: who, is_anonymous: anonymous })}';`);
  try {
    return (await db.query(sql, params)).rows;
  } finally {
    await db.exec('reset role; reset request.jwt.claims');
  }
}
const member = (who, group = GROUP) => db.query('insert into public.club_members (club_id, user_id) values ($1, $2)', [group, who]);
const notMember = (who, group = GROUP) => db.query('delete from public.club_members where club_id = $1 and user_id = $2', [group, who]);
const join = async (who, group = GROUP) => (await as(who, 'select public.join_group_chat($1) as c', [group]))[0].c;
const say = async (who, chat, words) => {
  const rows = await as(who, 'select * from public.send_chat_message($1, null, $2, $3)', [chat, client(), words]);
  // PGlite's clock moves in milliseconds: two sends a tick apart keep their order.
  await new Promise((r) => setTimeout(r, 2));
  return rows[0];
};
const read = (who, chat) => as(who, 'select * from public.get_chat_messages($1)', [chat]);
const list = (who) => as(who, 'select * from public.get_chats()');
const table = (who, chat) => as(who, 'select id from public.chat_messages where chat_id = $1', [chat]);
const refused = (run, word) => assert.rejects(run, (e) => { assert.match(e.message, word); return true; });

test('Members read and write, and see who wrote', async () => {
  await reset();
  await member(ANA); await member(BEN);
  const chat = await join(ANA);
  assert.equal(await join(BEN), chat, 'one chat per Group');
  await say(ANA, chat, 'Anyone out on Watab?');
  const rows = await read(BEN, chat);
  assert.equal(rows.length, 1);
  assert.equal(rows[0].sender.display_name, 'Ana Moss');
  assert.equal(rows[0].host, false, 'a Group has no host');
  assert.equal((await table(BEN, chat)).length, 1, 'the table itself obeys, as Realtime does');
});

test('A neighbour who has not joined sees nothing and can write nothing, through the function or the table', async () => {
  await reset();
  await member(ANA);
  const chat = await join(ANA);
  await say(ANA, chat, 'hello');
  assert.equal((await read(CAL, chat)).length, 0);
  assert.equal((await table(CAL, chat)).length, 0);
  await refused(() => say(CAL, chat, 'let me in'), /chat_not_going/);
  await refused(() => join(CAL), /chat_not_going/);
  await refused(() => as(CAL, 'select * from private.chats'), /permission denied/);
  assert.equal((await list(CAL)).length, 0);
});

test('Leaving the Group leaves the chat at once, though its member row stays; joining again returns', async () => {
  await reset();
  await member(ANA); await member(BEN);
  const chat = await join(ANA);
  await join(BEN);
  const { id: words } = await say(ANA, chat, 'first');
  await notMember(BEN);
  assert.equal((await db.query('select 1 from private.chat_members where chat_id = $1 and user_id = $2', [chat, BEN])).rows.length, 1);
  assert.equal((await read(BEN, chat)).length, 0);
  assert.equal((await table(BEN, chat)).length, 0);
  assert.equal((await list(BEN)).length, 0);
  await refused(() => say(BEN, chat, 'still here'), /chat_not_going/);
  await refused(() => as(BEN, 'select public.report_chat_message($1, $2)', [words, 'scam']), /chat_not_member/);
  assert.equal((await as(BEN, 'select private.chat_topic_ok($1) as ok', [`chat:${chat}`]))[0].ok, false, 'the typing channel too');
  await member(BEN);
  assert.equal((await read(BEN, chat)).length, 1);
  assert.equal((await list(BEN)).length, 1);
});

test('A member row alone admits no one', async () => {
  await reset();
  await member(ANA);
  const chat = await join(ANA);
  await say(ANA, chat, 'hi');
  await db.query('insert into private.chat_members (chat_id, user_id, accepted_at) values ($1, $2, now())', [chat, CAL]);
  assert.equal((await read(CAL, chat)).length, 0);
  assert.equal((await list(CAL)).length, 0);
  await refused(() => say(CAL, chat, 'hi'), /chat_not_going/);
});

test('Under 18, no birthday and a quiet account are out, even in the Group', async () => {
  await reset();
  await member(ANA); await member(KID); await member(BLANK); await member(QUIET);
  const chat = await join(ANA);
  await say(ANA, chat, 'hello all');
  for (const who of [KID, BLANK]) {
    assert.equal((await read(who, chat)).length, 0);
    assert.equal((await list(who)).length, 0);
    await refused(() => join(who), /chat_not_going/);
    await refused(() => say(who, chat, 'hi'), /chat_not_going/);
  }
  await refused(() => as(QUIET, 'select public.join_group_chat($1)', [GROUP], { anonymous: true }), /real account/);
  assert.equal((await as(QUIET, 'select id from public.chat_messages where chat_id = $1', [chat], { anonymous: true })).length, 0);
});

test('What the row asks: open, birthday or none, leaving membership to the app', async () => {
  await reset();
  const state = async (who, group = GROUP, o = {}) => (await as(who, 'select * from public.get_group_chat($1)', [group], o))[0].state;
  assert.equal(await state(ANA), 'open', 'says nothing of being in the Group, so it cannot race Join');
  assert.equal(await state(BLANK), 'birthday');
  assert.equal(await state(KID), 'none');
  assert.equal(await state(ANA, HIDDEN), 'none');
  assert.equal(await state(QUIET, GROUP, { anonymous: true }), 'none');
  await db.exec('set role anon');
  try {
    await refused(() => db.query('select * from public.get_group_chat($1)', [GROUP]), /permission denied/);
  } finally {
    await db.exec('reset role');
  }
});

test('Every message lights the dot, nothing from before you joined does, and your own never', async () => {
  await reset();
  await member(ANA);
  const chat = await join(ANA);
  await say(ANA, chat, 'said before Ben joined');
  await new Promise((r) => setTimeout(r, 2));
  await member(BEN);
  let [row] = await list(BEN);
  assert.equal(row.lights, false);
  assert.equal(row.unread, false);
  await say(ANA, chat, 'welcome');
  [row] = await list(BEN);
  assert.equal(row.lights, true);
  assert.equal(row.unread, true);
  assert.equal((await list(ANA))[0].lights, false, 'your own lights nothing');
  await join(BEN);
  await as(BEN, 'select public.mark_chat_read($1)', [chat]);
  [row] = await list(BEN);
  assert.equal(row.lights, false);
  assert.equal(row.unread, false);
  assert.equal((await db.query('select 1 from public.chat_reads')).rows.length, 0, 'no Seen: a read wakes no one and shows no one');
});

test('Block works both ways', async () => {
  await reset();
  await member(ANA); await member(BEN);
  const chat = await join(ANA);
  await join(BEN);
  await say(ANA, chat, 'from Ana');
  await say(BEN, chat, 'from Ben');
  await db.query('insert into private.blocks (blocker_id, blocked_id) values ($1, $2)', [BEN, ANA]);
  assert.deepEqual((await read(BEN, chat)).map((m) => m.body), ['from Ben']);
  assert.deepEqual((await read(ANA, chat)).map((m) => m.body), ['from Ana']);
});

test('Words and Events go in, photos do not, and no one floods it', async () => {
  await reset();
  await member(ANA); await member(BEN);
  const chat = await join(ANA);
  await refused(() => as(ANA, 'select * from public.send_chat_message($1, null, $2, null, $3, 100, 100)',
    [chat, client(), `${ANA}/${client()}.jpg`]), /chat_text_only/);
  await as(ANA, 'select * from public.send_chat_message($1, null, $2, null, null, null, null, $3)', [chat, client(), EVENT]);
  const rows = await read(BEN, chat);
  assert.equal(rows[0].kind, 'event');
  assert.equal(rows[0].card.id, EVENT, 'the same card as everywhere');
  for (let i = 0; i < 29; i += 1) await as(ANA, 'select * from public.send_chat_message($1, null, $2, $3)', [chat, client(), `word ${i}`]);
  await refused(() => say(ANA, chat, 'one too many'), /chat_slow_down/);
  await say(BEN, chat, 'someone else still can');
});

test('Leave chat keeps you in the Group and out of the chat; the row brings you back', async () => {
  await reset();
  await member(ANA); await member(BEN);
  const chat = await join(ANA);
  await join(BEN);
  await say(ANA, chat, 'hello');
  await as(BEN, 'select public.leave_chat($1)', [chat]);
  assert.equal((await read(BEN, chat)).length, 0);
  assert.equal((await list(BEN)).length, 0);
  await refused(() => say(BEN, chat, 'back?'), /chat_not_going/);
  assert.equal((await db.query('select 1 from public.club_members where club_id = $1 and user_id = $2', [GROUP, BEN])).rows.length, 1);
  await join(BEN);
  assert.equal((await read(BEN, chat)).length, 1);
  assert.equal((await list(BEN)).length, 1);
});

test('A hidden Group closes its chat, and a removed one takes it along', async () => {
  await reset();
  await member(ANA);
  const chat = await join(ANA);
  await say(ANA, chat, 'hello');
  await db.query(`update public.clubs set status = 'rejected' where id = $1`, [GROUP]);
  assert.equal((await read(ANA, chat)).length, 0);
  assert.equal((await list(ANA)).length, 0);
  await refused(() => say(ANA, chat, 'hi'), /chat_not_going/);
  await refused(() => join(ANA), /chat_not_going/);
  await db.query('delete from public.clubs where id = $1', [GROUP]);
  assert.equal((await db.query('select 1 from private.chats where id = $1', [chat])).rows.length, 0);
});

test('A list row carries the Group and names no one, once each', async () => {
  await reset();
  await member(ANA); await member(BEN); await member(CAL);
  const chat = await join(ANA);
  await join(BEN);
  await join(CAL);
  await say(BEN, chat, 'Ice is not safe yet');
  const rows = await list(ANA);
  assert.equal(rows.length, 1, 'your member row does not double it');
  assert.equal(rows[0].kind, 'club');
  assert.equal(rows[0].name, 'Rod and Gun Club');
  assert.equal(rows[0].club_id, GROUP);
  assert.deepEqual(rows[0].others, [], 'no member list');
  assert.equal(rows[0].last_sender, 'Ben Ortiz');
  assert.equal(rows[0].event, null);
  assert.equal(rows[0].is_host, false);
  assert.equal(rows[0].request, false);
  assert.equal(rows[0].waiting, false);
  await db.query(`update public.clubs set name = 'St. Joe Rod and Gun Club' where id = $1`, [GROUP]);
  assert.equal((await list(ANA))[0].name, 'St. Joe Rod and Gun Club', 'the Group\'s own name, live');
});

test('A member can report a message', async () => {
  await reset();
  await member(ANA); await member(BEN);
  const chat = await join(ANA);
  const { id: words } = await say(ANA, chat, 'buy my thing');
  await as(BEN, 'select public.report_chat_message($1, $2)', [words, 'scam']);
  const reports = (await db.query('select sender_name, body from private.chat_reports')).rows;
  assert.deepEqual(reports, [{ sender_name: 'Ana Moss', body: 'buy my thing' }]);
});

test('Groups of friends read as before', async () => {
  await reset();
  await db.query('insert into private.friendships (a, b, requested_by) values ($1, $2, $1)', [ANA, BEN]);
  const group = (await as(ANA, 'select public.start_group_chat($1::uuid[], $2) as c', [[BEN], 'Trivia crew']))[0].c;
  await say(ANA, group, 'hello');
  const rows = await list(BEN);
  assert.equal(rows.length, 1);
  assert.equal(rows[0].kind, 'group');
  assert.equal(rows[0].others.length, 1, 'a group of friends still names who is in it');
  assert.equal(rows[0].club_id, null);
  await as(BEN, 'select public.leave_chat($1)', [group]);
  assert.equal((await list(BEN)).length, 0);
  await refused(() => say(BEN, group, 'hi'), /chat_not_member/);
});
