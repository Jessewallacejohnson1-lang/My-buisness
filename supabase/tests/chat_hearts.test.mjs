// Fixed stories for hearts and replies in a chat (supabase/migrations/*_chat_hearts_and_replies.sql, BP app messages 03),
// run in PGlite: one emoji per person per message, taken back with null, never lighting the dot, never from a request
// not yet accepted or from outside the chat, hidden across a block; a reply quotes the message it answers, only from
// the same chat, and says it's gone once that message is hidden.
// Run: `npm install && npm test` in this folder.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { realDatabase } from './fixture.mjs';

const db = await realDatabase();
const id = (n) => `00000000-0000-0000-0000-${String(n).padStart(12, '0')}`;
const [ANA, BEN, CAL, DEE] = [1, 2, 3, 4].map(id);
const EVENT = id(901);
let clients = 0;
const client = () => id(1000 + ++clients);

async function reset() {
  await db.exec(`reset role; reset request.jwt.claims;
    delete from public.chat_reactions; delete from private.chat_reports; delete from public.chat_reads;
    delete from public.chat_messages; delete from private.chat_members; delete from private.chats;
    delete from private.blocks; delete from private.friend_requests; delete from private.friendships;
    delete from public.town_profiles; delete from auth.users; delete from public.club_events;`);
  for (const [who, name] of [[ANA, 'Ana Lee'], [BEN, 'Ben Ortiz'], [CAL, 'Cal Ruiz'], [DEE, 'Dee Moss']]) {
    await db.query('insert into auth.users (id, is_anonymous) values ($1, false)', [who]);
    await db.query(`insert into public.town_profiles (user_id, display_name, birthday) values ($1, $2, '1980-01-01')`,
      [who, name]);
  }
  await db.query(`insert into public.club_events (id, title, status, kind) values ($1, 'Bingo Night', 'approved', 'event')`,
    [EVENT]);
}

async function as(who, sql, params = []) {
  await db.exec(`set role authenticated; set request.jwt.claims = '${JSON.stringify({ sub: who, is_anonymous: false })}';`);
  try {
    return (await db.query(sql, params)).rows;
  } finally {
    await db.exec('reset role; reset request.jwt.claims');
  }
}
const friends = async (a, b) => {
  await as(a, 'select public.send_friend_request($1)', [b]);
  await as(b, 'select public.confirm_friend_request($1)', [a]);
};
const tick = () => new Promise((r) => setTimeout(r, 2));
const sendTo = async (who, to, body) => (await tick(), await as(who,
  'select * from public.send_chat_message(null, $1, $2, $3)', [to, client(), body]))[0];
const sendIn = async (who, chat, body, { reply = null, event = null } = {}) => (await tick(), await as(who,
  'select * from public.send_chat_message($1, null, $2, $3, null, null, null, $4, $5)',
  [chat, client(), body, event, reply]))[0];
const react = (who, message, emoji) => as(who, 'select public.react_chat_message($1, $2)', [message, emoji]);
const messages = (who, chat) => as(who, 'select * from public.get_chat_messages($1)', [chat]);
const one = async (who, chat, message) => (await messages(who, chat)).find((m) => m.id === message);
const refused = (promise, code) => assert.rejects(promise, (e) => e.message.includes(code));

test('one emoji per person: a new one takes its place, null takes it back, both sides see it', async () => {
  await reset();
  await friends(ANA, BEN);
  const sent = await sendTo(ANA, BEN, 'Bingo tonight?');
  await react(BEN, sent.id, '❤️');
  assert.deepEqual((await one(ANA, sent.chat_id, sent.id)).reactions, [{ user_id: BEN, emoji: '❤️' }]);
  await react(BEN, sent.id, '😂');
  await react(ANA, sent.id, '👍');
  assert.deepEqual((await one(BEN, sent.chat_id, sent.id)).reactions,
    [{ user_id: BEN, emoji: '😂' }, { user_id: ANA, emoji: '👍' }]);
  await react(BEN, sent.id, null);
  assert.deepEqual((await one(ANA, sent.chat_id, sent.id)).reactions, [{ user_id: ANA, emoji: '👍' }]);
  await react(BEN, sent.id, null);
  const rows = await db.query('select count(*)::int as n from public.chat_reactions');
  assert.equal(rows.rows[0].n, 1, 'taken back: gone, and a second take-back changes nothing');
});

test('only the six emoji, only from inside the chat, never from a request not yet accepted', async () => {
  await reset();
  await friends(ANA, BEN);
  const sent = await sendTo(ANA, BEN, 'Hi');
  await refused(react(BEN, sent.id, '🎉'), 'chat_bad_reaction');
  await refused(react(CAL, sent.id, '❤️'), 'chat_not_member');
  const ask = await sendTo(DEE, ANA, 'Hey neighbor');
  await refused(react(ANA, ask.id, '❤️'), 'chat_not_accepted');
  await as(ANA, 'select public.accept_chat($1)', [ask.chat_id]);
  await react(ANA, ask.id, '❤️');
  assert.equal((await one(DEE, ask.chat_id, ask.id)).reactions.length, 1);
  // Friends since the request, never accepted: the chat reads as any other, so a heart goes.
  const later = await sendTo(CAL, BEN, 'Hello?');
  await refused(react(BEN, later.id, '❤️'), 'chat_not_accepted');
  await friends(BEN, CAL);
  await react(BEN, later.id, '❤️');
});

test('a reaction never lights the dot', async () => {
  await reset();
  await friends(ANA, BEN);
  const sent = await sendTo(BEN, ANA, 'See you there');
  await as(ANA, 'select public.mark_chat_read($1)', [sent.chat_id]);
  await as(BEN, 'select public.mark_chat_read($1)', [sent.chat_id]);
  await react(ANA, sent.id, '❤️');
  const [chat] = await as(BEN, 'select * from public.get_chats()');
  assert.equal(chat.unread, false);
  assert.equal(chat.lights ?? false, false);
});

test('no direct writes; the read rule follows the message and a block', async () => {
  await reset();
  await friends(ANA, BEN);
  await friends(ANA, CAL);
  await friends(BEN, CAL);
  const chat = (await as(ANA, 'select public.start_group_chat($1::uuid[]) as id', [[BEN, CAL]]))[0].id;
  const sent = await sendIn(ANA, chat, 'Trivia Thursday');
  await refused(as(BEN, `insert into public.chat_reactions (message_id, user_id, emoji) values ($1, $2, '❤️')`,
    [sent.id, BEN]), 'permission denied');
  await react(CAL, sent.id, '😮');
  assert.equal((await as(BEN, 'select * from public.chat_reactions')).length, 1);
  assert.equal((await as(DEE, 'select * from public.chat_reactions')).length, 0, 'outside the chat: nothing');
  await as(BEN, 'select public.block_neighbor($1)', [CAL]);
  assert.deepEqual((await one(BEN, chat, sent.id)).reactions, [], 'blocked: their reaction goes too');
  assert.equal((await as(BEN, 'select * from public.chat_reactions')).length, 0);
  assert.deepEqual((await one(ANA, chat, sent.id)).reactions, [{ user_id: CAL, emoji: '😮' }]);
});

test('a reply quotes the message it answers, from this chat only, and says when it is gone', async () => {
  await reset();
  await friends(ANA, BEN);
  await friends(ANA, CAL);
  const first = await sendTo(ANA, BEN, 'Last night at Bad Habit');
  const card = await sendIn(ANA, first.chat_id, null, { event: EVENT });
  const elsewhere = await sendTo(ANA, CAL, 'Not for Ben');
  const reply = await sendIn(BEN, first.chat_id, 'Looks fun. Who played?', { reply: first.id });
  const toCard = await sendIn(BEN, first.chat_id, 'In', { reply: card.id });
  const stray = await sendIn(BEN, first.chat_id, 'Huh', { reply: elsewhere.id });
  assert.deepEqual((await one(ANA, first.chat_id, reply.id)).reply,
    { gone: false, sender_id: ANA, kind: 'text', name: 'Ana Lee', body: 'Last night at Bad Habit' });
  assert.equal((await one(ANA, first.chat_id, toCard.id)).reply.body, 'Bingo Night');
  assert.equal((await one(ANA, first.chat_id, stray.id)).reply, null, 'another chat: no quote');
  await db.query('update public.chat_messages set hidden_at = now() where id = $1', [first.id]);
  assert.deepEqual((await one(BEN, first.chat_id, reply.id)).reply, { gone: true });
});
