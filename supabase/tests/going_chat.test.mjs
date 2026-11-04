// Fixed stories for the Going chat (supabase/migrations/*_going_chat.sql, BP app five-tabs 06), run in PGlite: who is in
// it is worked out from Going, under 18 and no birthday stay out, the host's words are updates and only they light the
// dot, it takes words only, and it closes a week after the Event.
// Run: `npm install && npm test` in this folder.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { realDatabase } from './fixture.mjs';

const db = await realDatabase();
const id = (n) => `00000000-0000-0000-0000-${String(n).padStart(12, '0')}`;
const [HOST, ANA, BEN, CAL, KID, BLANK, QUIET] = [1, 2, 3, 4, 5, 6, 7].map(id);
const [EVENT, FOUND, OLD, HIDDEN] = [901, 902, 903, 904].map(id);
let clients = 0;
const client = () => id(1000 + ++clients);

async function reset() {
  await db.exec(`reset role; reset request.jwt.claims;
    delete from public.chat_reads; delete from public.chat_messages; delete from private.chat_members;
    delete from private.chats; delete from private.blocks; delete from public.event_rsvps;
    delete from public.town_profiles; delete from public.club_events; delete from auth.users;`);
  for (const [who, name, anonymous, birthday] of [
    [HOST, 'Sam Lee', false, '1980-01-01'], [ANA, 'Ana Moss', false, '1980-01-01'], [BEN, 'Ben Ortiz', false, '1990-02-02'],
    [CAL, 'Cal Ruiz', false, '1985-03-03'], [KID, 'Kit Young', false, '2012-05-01'], [BLANK, 'Nia Blank', false, null],
    [QUIET, 'Anon Ymous', true, '1980-01-01']]) {
    await db.query('insert into auth.users (id, is_anonymous) values ($1, $2)', [who, anonymous]);
    await db.query('insert into public.town_profiles (user_id, display_name, birthday) values ($1, $2, $3)', [who, name, birthday]);
  }
  await db.query(`insert into public.club_events (id, title, status, kind, event_date, submitted_by) values
    ($1, 'Holiday Market', 'approved', 'event', current_date + 30, $5),
    ($2, 'Found Event', 'approved', 'event', current_date + 30, null),
    ($3, 'Long over', 'approved', 'event', current_date - 9, $5),
    ($4, 'Hidden', 'rejected', 'event', current_date + 30, $5)`, [EVENT, FOUND, OLD, HIDDEN, HOST]);
}

async function as(who, sql, params = [], { anonymous = false } = {}) {
  await db.exec(`set role authenticated; set request.jwt.claims = '${JSON.stringify({ sub: who, is_anonymous: anonymous })}';`);
  try {
    return (await db.query(sql, params)).rows;
  } finally {
    await db.exec('reset role; reset request.jwt.claims');
  }
}
const going = (who, event = EVENT) => db.query('insert into public.event_rsvps (event_id, user_id) values ($1, $2)', [event, who]);
const notGoing = (who, event = EVENT) => db.query('delete from public.event_rsvps where event_id = $1 and user_id = $2', [event, who]);
const join = async (who, event = EVENT) => (await as(who, 'select public.join_going_chat($1) as c', [event]))[0].c;
const say = async (who, chat, words) => {
  const rows = await as(who, 'select * from public.send_chat_message($1, null, $2, $3)', [chat, client(), words]);
  // PGlite's clock moves in milliseconds: two sends a tick apart keep their order.
  await new Promise((r) => setTimeout(r, 2));
  return rows[0];
};
const read = (who, chat) => as(who, 'select * from public.get_chat_messages($1)', [chat]);
const list = (who) => as(who, 'select * from public.get_chats()');
const refused = (run, word) => assert.rejects(run, (e) => { assert.match(e.message, word); return true; });

test('Going reads and writes, and sees who wrote', async () => {
  await reset();
  await going(ANA); await going(BEN);
  const chat = await join(ANA);
  assert.equal(await join(BEN), chat, 'one chat per Event');
  await say(ANA, chat, 'Is parking okay?');
  const rows = await read(BEN, chat);
  assert.equal(rows.length, 1);
  assert.equal(rows[0].sender.display_name, 'Ana Moss');
  assert.equal(rows[0].host, false);
  // The table itself obeys, as Realtime does.
  assert.equal((await as(BEN, 'select id from public.chat_messages where chat_id = $1', [chat])).length, 1);
});

test('Not Going sees nothing and can write nothing, through the function or the table', async () => {
  await reset();
  await going(ANA);
  const chat = await join(ANA);
  await say(ANA, chat, 'hello');
  assert.equal((await read(CAL, chat)).length, 0);
  assert.equal((await as(CAL, 'select id from public.chat_messages where chat_id = $1', [chat])).length, 0);
  await refused(() => say(CAL, chat, 'let me in'), /chat_not_going/);
  await refused(() => join(CAL), /chat_not_going/);
  await refused(() => as(CAL, 'select * from private.chats'), /permission denied/);
});

test('Leaving Going leaves the chat at once; Going again returns', async () => {
  await reset();
  await going(ANA); await going(BEN);
  const chat = await join(ANA);
  await join(BEN);
  await say(ANA, chat, 'first');
  await notGoing(BEN);
  assert.equal((await read(BEN, chat)).length, 0);
  assert.equal((await list(BEN)).length, 0, 'gone from Messages though its member row stays');
  await refused(() => say(BEN, chat, 'still here'), /chat_not_going/);
  await going(BEN);
  assert.equal((await read(BEN, chat)).length, 1);
  assert.equal((await list(BEN)).length, 1);
});

test('A member row alone admits no one', async () => {
  await reset();
  await going(ANA);
  const chat = await join(ANA);
  await say(ANA, chat, 'hi');
  await db.query('insert into private.chat_members (chat_id, user_id, accepted_at) values ($1, $2, now())', [chat, CAL]);
  assert.equal((await read(CAL, chat)).length, 0);
  assert.equal((await list(CAL)).length, 0);
});

test('The host is in without Going, and their words are updates', async () => {
  await reset();
  await going(ANA);
  const chat = await join(HOST);
  await say(HOST, chat, 'Moved inside, it is raining');
  const rows = await read(ANA, chat);
  assert.equal(rows[0].host, true);
  assert.equal(rows[0].sender.display_name, 'Sam Lee');
  const [mine] = await list(HOST);
  assert.equal(mine.is_host, true);
  assert.equal(mine.lights, false, 'your own updates light nothing');
  const [theirs] = await list(ANA);
  assert.equal(theirs.is_host, false);
  assert.equal(theirs.last_host, true);
});

test('Under 18, no birthday and a quiet account are out, even when Going', async () => {
  await reset();
  await going(ANA); await going(KID); await going(BLANK); await going(QUIET);
  const chat = await join(ANA);
  await say(ANA, chat, 'hello all');
  for (const who of [KID, BLANK]) {
    assert.equal((await read(who, chat)).length, 0);
    assert.equal((await list(who)).length, 0);
    await refused(() => join(who), /chat_not_going/);
    await refused(() => say(who, chat, 'hi'), /chat_not_going/);
  }
  await refused(() => as(QUIET, 'select public.join_going_chat($1)', [EVENT], { anonymous: true }), /real account/);
  assert.equal((await as(QUIET, 'select id from public.chat_messages where chat_id = $1', [chat], { anonymous: true })).length, 0);
});

test('What the row asks: open, birthday or none, with who the host is', async () => {
  await reset();
  const state = async (who, event = EVENT, o = {}) => (await as(who, 'select * from public.get_going_chat($1)', [event], o))[0];
  assert.deepEqual(await state(ANA), { state: 'open', is_host: false });
  assert.deepEqual(await state(HOST), { state: 'open', is_host: true });
  assert.deepEqual(await state(KID), { state: 'none', is_host: false });
  assert.deepEqual(await state(BLANK), { state: 'birthday', is_host: false });
  assert.deepEqual(await state(QUIET, EVENT, { anonymous: true }), { state: 'none', is_host: false });
  assert.deepEqual(await state(ANA, OLD), { state: 'none', is_host: false });
  assert.deepEqual(await state(ANA, HIDDEN), { state: 'none', is_host: false });
});

test('A birthday sets once, and then it lets you in or keeps you out', async () => {
  await reset();
  await going(BLANK);
  await as(BLANK, 'update public.town_profiles set birthday = $1 where user_id = $2', ['1999-03-12', BLANK]);
  assert.ok(await join(BLANK));
  await going(KID);
  await as(KID, 'update public.town_profiles set birthday = $1 where user_id = $2', ['1980-01-01', KID]);
  await as(KID, `insert into public.town_profiles (user_id, birthday) values ($1, $2)
                 on conflict (user_id) do update set birthday = excluded.birthday`, [KID, '1980-01-01']);
  await refused(() => join(KID), /chat_not_going/);
  const { rows } = await db.query('select birthday::text as b from public.town_profiles where user_id = $1', [KID]);
  assert.equal(rows[0].b, '2012-05-01');
  // By hand, as the database's owner, a wrong one can be fixed.
  await db.query('update public.town_profiles set birthday = $1 where user_id = $2', ['1981-01-01', KID]);
  assert.equal((await db.query('select birthday::text as b from public.town_profiles where user_id = $1', [KID])).rows[0].b, '1981-01-01');
});

test('Only an update lights the dot, and nothing from before you Went', async () => {
  await reset();
  await going(ANA);
  const chat = await join(ANA);
  await join(HOST);
  await say(HOST, chat, 'Vendors at 8:30');
  await new Promise((r) => setTimeout(r, 2));
  await going(BEN);
  let [row] = await list(BEN);
  assert.equal(row.unread, false, 'old words are not unread');
  assert.equal(row.lights, false, 'and light nothing');
  await say(ANA, chat, 'just chatting');
  [row] = await list(BEN);
  assert.equal(row.unread, true, 'a reply bolds the row');
  assert.equal(row.lights, false, 'and lights no dot');
  await say(HOST, chat, 'Moved inside');
  [row] = await list(BEN);
  assert.equal(row.lights, true);
  assert.equal(row.last_host, true);
  await say(ANA, chat, 'thanks');
  assert.equal((await list(BEN))[0].lights, true, 'a reply after it keeps the update lit');
  await join(BEN);
  await as(BEN, 'select public.mark_chat_read($1)', [chat]);
  [row] = await list(BEN);
  assert.equal(row.lights, false);
  assert.equal(row.unread, false);
  assert.equal((await db.query('select count(*)::int as n from public.chat_reads where chat_id = $1', [chat])).rows[0].n, 0, 'no Seen');
});

test('Block works both ways: their words and their updates', async () => {
  await reset();
  await going(ANA); await going(BEN);
  const chat = await join(ANA);
  await join(HOST);
  await say(HOST, chat, 'Update');
  await db.query('insert into private.blocks (blocker_id, blocked_id) values ($1, $2)', [BEN, HOST]);
  assert.equal((await read(BEN, chat)).length, 0);
  assert.equal((await read(HOST, chat)).length, 1, 'the host still sees their own');
  assert.equal((await list(BEN)).length, 0, 'nothing left to list');
  await say(ANA, chat, 'hello');
  const [row] = await list(BEN);
  assert.equal(row.lights, false);
  assert.equal(row.last_body, 'hello');
});

test('Words only, and no one floods it', async () => {
  await reset();
  await going(ANA);
  const chat = await join(ANA);
  await refused(() => as(ANA, 'select * from public.send_chat_message($1, null, $2, null, null, null, null, $3)', [chat, client(), FOUND]), /chat_text_only/);
  await refused(() => as(ANA, 'select * from public.send_chat_message($1, null, $2, null, $3, 10, 10)', [chat, client(), `${ANA}/${id(5)}.jpg`]), /chat_text_only/);
  await db.query(`insert into public.chat_messages (chat_id, sender_id, client_id, kind, body)
                  select $1, $2, gen_random_uuid(), 'text', 'x' from generate_series(1, 30)`, [chat, ANA]);
  await refused(() => say(ANA, chat, 'one more'), /chat_slow_down/);
});

test('Leave chat keeps you Going and out; the row brings you back', async () => {
  await reset();
  await going(ANA); await going(BEN);
  const chat = await join(ANA);
  await join(BEN);
  await say(ANA, chat, 'hello');
  await as(BEN, 'select public.leave_chat($1)', [chat]);
  assert.equal((await read(BEN, chat)).length, 0);
  assert.equal((await list(BEN)).length, 0);
  assert.equal((await db.query('select count(*)::int as n from public.event_rsvps where user_id = $1', [BEN])).rows[0].n, 1);
  assert.equal(await join(BEN), chat);
  assert.equal((await read(BEN, chat)).length, 1);
});

test('It closes a week after the Event and when the Event is hidden', async () => {
  await reset();
  await going(ANA); await going(ANA, OLD);
  await refused(() => join(ANA, OLD), /chat_not_going/);
  const chat = await join(ANA);
  await say(ANA, chat, 'hi');
  assert.equal((await list(ANA)).length, 1);
  await db.query(`update public.club_events set status = 'rejected' where id = $1`, [EVENT]);
  assert.equal((await list(ANA)).length, 0);
  assert.equal((await read(ANA, chat)).length, 0);
  await refused(() => say(ANA, chat, 'hello?'), /chat_not_going/);
  // Six days after is still open, eight is not; an end time counts over the day.
  await db.query(`update public.club_events set status = 'approved', event_date = current_date - 6 where id = $1`, [EVENT]);
  assert.equal((await list(ANA)).length, 1);
  await db.query(`update public.club_events set event_date = current_date + 30, end_at = now() - interval '8 days' where id = $1`, [EVENT]);
  assert.equal((await list(ANA)).length, 0);
});

test('A list row carries its Event and names no one; a banned sender goes unnamed', async () => {
  await reset();
  await going(ANA); await going(BEN);
  const chat = await join(ANA);
  await say(BEN, chat, 'hi');
  const [row] = await list(ANA);
  assert.equal(row.kind, 'going');
  assert.equal(row.event.title, 'Holiday Market');
  assert.equal(row.event.going_count, 2);
  assert.deepEqual(row.others, []);
  await db.query(`update auth.users set banned_until = now() + interval '1 day' where id = $1`, [BEN]);
  assert.equal((await read(ANA, chat))[0].sender, null);
});

test('Friends and groups of friends read as before: no Event, and lights is their unread', async () => {
  await reset();
  await as(ANA, 'select public.send_friend_request($1)', [BEN]);
  await as(BEN, 'select public.confirm_friend_request($1)', [ANA]);
  const [{ chat_id: chat }] = await as(ANA, 'select * from public.send_chat_message(null, $1, $2, $3)', [BEN, client(), 'hey']);
  const [row] = await list(BEN);
  assert.equal(row.event, null);
  assert.equal(row.unread, true);
  assert.equal(row.lights, true);
  assert.equal(row.others.length, 1);
  assert.equal((await read(BEN, chat))[0].sender, null);
  await as(BEN, 'select public.mark_chat_read($1)', [chat]);
  assert.equal((await db.query('select count(*)::int as n from public.chat_reads where chat_id = $1', [chat])).rows[0].n, 1, 'Seen stays');
});
