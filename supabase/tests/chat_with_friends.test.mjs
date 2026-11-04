// Fixed stories for chat (supabase/migrations/*_chat_with_friends.sql, BP app five-tabs 05), run in PGlite: friends
// message freely, a stranger reaches Requests with one text, Delete and under-18 keep a message with its sender, no
// direct writes, the read rules say Block, Hide and Leave, group rules, reports, and Seen.
// Run: `npm install && npm test` in this folder.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { PGlite } from '@electric-sql/pglite';

const here = dirname(fileURLToPath(import.meta.url));
const migrations = process.env.MIGRATIONS ?? join(here, '..', 'migrations');
const read = (suffix) => readdirSync(migrations).filter((f) => f.endsWith(suffix)).sort()
  .map((f) => readFileSync(join(migrations, f), 'utf8'));
const realAccount = read('_anonymous_accounts.sql')[0]
  .match(/create or replace function public\.is_real_account\(\)[\s\S]*?\$\$;/)[0];

const db = await PGlite.create();
await db.exec(`
  create role anon; create role authenticated;
  create schema auth; create schema storage; create schema realtime; create schema private;
  grant usage on schema auth, storage, realtime, private to anon, authenticated;
  create function auth.jwt() returns jsonb language sql stable as
    $$ select coalesce(nullif(current_setting('request.jwt.claims', true), ''), '{}')::jsonb $$;
  create function auth.uid() returns uuid language sql stable as
    $$ select nullif(auth.jwt() ->> 'sub', '')::uuid $$;
  create table auth.users (id uuid primary key, is_anonymous boolean not null default false,
    banned_until timestamptz);
  create table public.town_profiles (
    user_id uuid primary key references auth.users (id) on delete cascade, display_name text, avatar_url text,
    birthday date, onboarded_at timestamptz, created_at timestamptz not null default now());
  create table public.town_follows (
    id uuid primary key default gen_random_uuid(), follower_id uuid not null,
    target_type text not null, target_id uuid not null, created_at timestamptz not null default now(),
    unique (follower_id, target_type, target_id));
  create function public.get_feed_postings(limit_n integer default 30) returns int
    language sql as $$ select 0 $$;
  create table public.club_events (id uuid primary key, title text, description text, status text, kind text,
    place_entry_id text, club_id uuid);
  create function public.is_admin() returns boolean language sql stable as
    $$ select coalesce((auth.jwt() ->> 'admin')::boolean, false) $$;
  grant execute on function public.is_admin() to authenticated;
  create table storage.buckets (id text primary key, name text, public boolean, file_size_limit bigint,
    allowed_mime_types text[]);
  create table storage.objects (id uuid primary key default gen_random_uuid(), bucket_id text, name text);
  alter table storage.objects enable row level security;
  create function storage.foldername(name text) returns text[] language sql immutable as
    $$ select (string_to_array(name, '/'))[1:array_length(string_to_array(name, '/'), 1) - 1] $$;
  create table realtime.messages (id uuid primary key default gen_random_uuid(), extension text, topic text);
  alter table realtime.messages enable row level security;
  create function realtime.topic() returns text language sql stable as
    $$ select current_setting('realtime.topic', true) $$;
  create publication supabase_realtime;
  grant select, insert on storage.objects, realtime.messages to authenticated;
  grant execute on function realtime.topic(), storage.foldername(text) to authenticated;
`);
await db.exec(realAccount);
for (const sql of [...read('_find_neighbors.sql'), ...read('_friend_requests.sql'), ...read('_unfriend_and_block.sql')]) {
  await db.exec(sql);
}
// The card's own stories are event_card's; here it says only which Event, and adults_only reads the title's 21+.
await db.exec(`
  create function private.event_cards(p_events uuid[]) returns table (id uuid, card jsonb) language sql stable as
    $$ select e.id, jsonb_build_object('id', e.id, 'title', e.title) from public.club_events e where e.id = any (p_events) $$;
  create function private.adults_only(p_place text, p_club uuid, p_words text) returns boolean language sql stable as
    $$ select p_words like '%21+%' $$;
`);
await db.exec(read('_chat_with_friends.sql')[0]);

const id = (n) => `00000000-0000-0000-0000-${String(n).padStart(12, '0')}`;
const [ANA, BEN, CAL, DEE, KID, ANON, NOBIRTH] = [1, 2, 3, 4, 5, 6, 7].map(id);
const [EVENT, BAR, OFF] = [901, 902, 903].map(id);
let clients = 0;
const client = () => id(1000 + ++clients);

async function reset() {
  await db.exec(`reset role; reset request.jwt.claims;
    delete from private.chat_reports; delete from public.chat_reads; delete from public.chat_messages;
    delete from private.chat_members; delete from private.chats; delete from private.blocks;
    delete from private.friend_requests; delete from private.friendships; delete from public.town_follows;
    delete from public.town_profiles; delete from auth.users; delete from public.club_events;`);
  const grown = '1980-01-01';
  for (const [who, name, anonymous, birthday] of [
    [ANA, 'Ana Lee', false, grown], [BEN, 'Ben Ortiz', false, grown], [CAL, 'Cal Ruiz', false, grown],
    [DEE, 'Dee Moss', false, grown], [KID, 'Kit Young', false, '2012-05-01'], [ANON, 'Anon Ymous', true, grown],
    [NOBIRTH, 'Nia Blank', false, null]]) {
    await db.query('insert into auth.users (id, is_anonymous) values ($1, $2)', [who, anonymous]);
    await db.query('insert into public.town_profiles (user_id, display_name, birthday) values ($1, $2, $3)',
      [who, name, birthday]);
  }
  await db.exec(`insert into public.club_events (id, title, status, kind) values
    ('${EVENT}', 'Bingo Night', 'approved', 'event'), ('${BAR}', 'Pub crawl 21+', 'approved', 'event'),
    ('${OFF}', 'Rejected', 'rejected', 'event');`);
}

async function as(who, sql, params = [], { anonymous = false, admin = false, topic = '' } = {}) {
  await db.exec(`set role authenticated; set request.jwt.claims = '${JSON.stringify({ sub: who, is_anonymous: anonymous, admin })}';
    set realtime.topic = '${topic}';`);
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
// PGlite's clock moves in milliseconds: two sends a tick apart keep their order.
const tick = () => new Promise((r) => setTimeout(r, 2));
const sendTo = async (who, to, body, extra = {}) => (await tick(), await as(who,
  'select * from public.send_chat_message(null, $1, $2, $3, $4, $5, $6, $7)',
  [to, extra.client ?? client(), body ?? null, extra.photo ?? null, extra.w ?? null, extra.h ?? null, extra.event ?? null]))[0];
const sendIn = async (who, chat, body, extra = {}) => (await tick(), await as(who,
  'select * from public.send_chat_message($1, null, $2, $3, $4, $5, $6, $7)',
  [chat, extra.client ?? client(), body ?? null, extra.photo ?? null, extra.w ?? null, extra.h ?? null, extra.event ?? null]))[0];
const chats = (who) => as(who, 'select * from public.get_chats()');
const messages = async (who, chat) => (await as(who, 'select * from public.get_chat_messages($1)', [chat]));
const words = async (who, chat) => (await messages(who, chat)).map((m) => m.body).reverse();
const refuses = (promise, message) => assert.rejects(promise, new RegExp(message));

test('friends message freely, both see it, and a retry is the same message', async () => {
  await reset();
  await friends(ANA, BEN);
  const first = await sendTo(ANA, BEN, ' hi Ben ', { client: id(5000) });
  const retried = await sendTo(ANA, BEN, ' hi Ben ', { client: id(5000) });
  assert.equal(retried.id, first.id, 'same client id, same message');
  assert.deepEqual(await words(BEN, first.chat_id), ['hi Ben']);
  await sendIn(BEN, first.chat_id, 'hi Ana');
  assert.deepEqual(await words(ANA, first.chat_id), ['hi Ben', 'hi Ana']);
  const [mine] = await chats(ANA);
  assert.equal(mine.kind, 'direct');
  assert.equal(mine.others[0].display_name, 'Ben Ortiz');
  assert.equal(mine.others[0].relation, 'friends');
  assert.equal(mine.last_body, 'hi Ana');
  assert.equal(mine.unread, true);
  assert.equal(mine.request, false);
  assert.equal(mine.waiting, false);
  assert.equal((await chats(BEN))[0].unread, false, 'your own last message is not unread');
  assert.equal((await sendTo(BEN, ANA, 'same chat either way')).chat_id, first.chat_id);
});

test('no direct writes: every table refuses, and nobody can read who accepted whom', async () => {
  await reset();
  await friends(ANA, BEN);
  const { chat_id: chat } = await sendTo(ANA, BEN, 'hi');
  await refuses(as(ANA, `insert into public.chat_messages (chat_id, sender_id, client_id, kind, body)
                         values ($1, $2, $3, 'text', 'forged')`, [chat, ANA, client()]), 'permission denied');
  await refuses(as(ANA, `update public.chat_messages set body = 'changed'`), 'permission denied');
  await refuses(as(ANA, `delete from public.chat_messages`), 'permission denied');
  await refuses(as(ANA, `insert into public.chat_reads values ($1, $2, now())`, [chat, ANA]), 'permission denied');
  await refuses(as(ANA, `select * from private.chat_members`), 'permission denied');
  await refuses(as(ANA, `select * from private.chats`), 'permission denied');
  await refuses(as(ANA, `select * from private.chat_reports`), 'permission denied');
});

test('a read rule keeps a chat to the people in it, in REST as in the functions', async () => {
  await reset();
  await friends(ANA, BEN);
  const { chat_id: chat } = await sendTo(ANA, BEN, 'just us');
  assert.equal((await as(BEN, 'select * from public.chat_messages')).length, 1);
  assert.equal((await as(CAL, 'select * from public.chat_messages')).length, 0);
  assert.deepEqual(await words(CAL, chat), []);
  await refuses(sendIn(CAL, chat, 'let me in'), 'chat_not_member');
});

test('a stranger reaches Requests with one text, and only Accept lets them write on', async () => {
  await reset();
  const { chat_id: chat } = await sendTo(ANA, BEN, 'hi neighbor');
  const [theirs] = await chats(BEN);
  assert.equal(theirs.request, true);
  assert.equal(theirs.unread, false, 'a request lights no dot');
  assert.deepEqual(await words(BEN, chat), ['hi neighbor']);
  const [mine] = await chats(ANA);
  assert.equal(mine.waiting, true);
  assert.equal(mine.request, false);

  await refuses(sendIn(ANA, chat, 'hello?'), 'chat_waiting');
  await as(BEN, 'select public.mark_chat_read($1)', [chat]);
  assert.equal((await as(ANA, 'select * from public.chat_reads')).length, 0, 'opening a request tells them nothing');

  await as(BEN, 'select public.accept_chat($1)', [chat]);
  assert.equal((await chats(BEN))[0].request, false);
  assert.equal((await chats(ANA))[0].waiting, false);
  assert.equal((await as(ANA, 'select * from public.chat_reads')).length, 1, 'accepting reads it');
  await sendIn(ANA, chat, 'thanks');
  assert.deepEqual(await words(BEN, chat), ['hi neighbor', 'thanks']);
});

test('a stranger sends only words, and 20 new requests a day', async () => {
  await reset();
  await refuses(sendTo(ANA, BEN, null, { photo: `${ANA}/${id(1)}.jpg`, w: 10, h: 10 }), 'chat_text_only');
  await refuses(sendTo(ANA, BEN, null, { event: EVENT }), 'chat_text_only');
  for (let i = 0; i < 20; i++) {
    const other = id(100 + i);
    await db.query('insert into auth.users (id) values ($1)', [other]);
    await db.query(`insert into public.town_profiles (user_id, display_name, birthday) values ($1, 'Nora N', '1980-01-01')`, [other]);
    await sendTo(ANA, other, 'hi');
  }
  await refuses(sendTo(ANA, BEN, 'one more'), 'chat_limit');
  await db.exec(`delete from auth.users where id::text like '00000000-0000-0000-0000-0000000001%'`);
});

test('becoming friends lifts the request; a friend can send a photo and an Event', async () => {
  await reset();
  const { chat_id: chat } = await sendTo(ANA, BEN, 'hi');
  await friends(ANA, BEN);
  assert.equal((await chats(BEN))[0].request, false);
  await sendIn(ANA, chat, null, { photo: `${ANA}/${id(1)}.jpg`, w: 800, h: 600 });
  await sendIn(ANA, chat, null, { event: EVENT });
  const [event, photo] = await messages(BEN, chat);
  assert.equal(event.kind, 'event');
  assert.equal(event.card.title, 'Bingo Night');
  assert.equal(photo.photo_path, `${ANA}/${id(1)}.jpg`);
  assert.equal(photo.photo_w, 800);
});

test('a photo must be in your own folder, and an Event must be live', async () => {
  await reset();
  await friends(ANA, BEN);
  await refuses(sendTo(ANA, BEN, null, { photo: `${BEN}/${id(1)}.jpg`, w: 1, h: 1 }), 'chat_bad_message');
  await refuses(sendTo(ANA, BEN, null, { photo: `${ANA}/../${id(1)}.jpg`, w: 1, h: 1 }), 'chat_bad_message');
  await refuses(sendTo(ANA, BEN, null, { event: OFF }), 'chat_event_gone');
  await refuses(sendTo(ANA, BEN, '   '), 'chat_bad_message');
  await refuses(sendTo(ANA, BEN, 'x'.repeat(2001)), 'chat_bad_message');
});

test('Delete is remembered: their next word stays with them, and they are not told', async () => {
  await reset();
  const { chat_id: chat } = await sendTo(ANA, BEN, 'hi');
  await as(BEN, 'select public.decline_chat($1)', [chat]);
  assert.deepEqual(await chats(BEN), []);
  assert.deepEqual(await words(BEN, chat), []);
  const [mine] = await chats(ANA);
  assert.equal(mine.waiting, true, 'reads the same as waiting');
  assert.deepEqual(await words(ANA, chat), ['hi']);
  await refuses(sendIn(ANA, chat, 'again?'), 'chat_waiting');
  assert.deepEqual(await chats(BEN), [], 'still gone');
});

test('under 18 or no birthday: a stranger\'s message is kept from them, and the sender sees nothing different', async () => {
  for (const young of [KID, NOBIRTH]) {
    await reset();
    const { chat_id: chat } = await sendTo(ANA, young, 'hey');
    assert.deepEqual(await chats(young), [], 'nothing reaches them');
    assert.deepEqual(await words(young, chat), []);
    assert.equal((await as(young, 'select * from public.chat_messages')).length, 0);
    const [mine] = await chats(ANA);
    assert.equal(mine.waiting, true);
    assert.deepEqual(await words(ANA, chat), ['hey']);
    // Friends later: what's new arrives, what was kept stays kept.
    await friends(ANA, young);
    await sendIn(ANA, chat, 'hi, it is Ana');
    assert.deepEqual(await words(young, chat), ['hi, it is Ana']);
    assert.equal((await chats(young))[0].request, false);
  }
});

test('Block stops messages both ways and hides the chat, in REST too; unblocking starts over as a request', async () => {
  await reset();
  await friends(ANA, BEN);
  const { chat_id: chat } = await sendTo(ANA, BEN, 'before');
  await as(BEN, 'select public.block_neighbor($1)', [ANA]);
  assert.deepEqual(await chats(ANA), []);
  assert.deepEqual(await chats(BEN), []);
  await refuses(sendIn(ANA, chat, 'hello'), 'chat_not_available');
  await refuses(sendIn(BEN, chat, 'hello'), 'chat_not_available');
  await refuses(sendTo(ANA, BEN, 'hello'), 'chat_not_available');
  assert.deepEqual((await as(BEN, 'select body from public.chat_messages')), [], 'the rule itself says Block');
  await as(BEN, 'select public.unblock_neighbor($1)', [ANA]);
  await refuses(sendIn(ANA, chat, 'hello?'), 'chat_waiting');
});

test('Unfriend ends the free pass', async () => {
  await reset();
  await friends(ANA, BEN);
  const { chat_id: chat } = await sendTo(ANA, BEN, 'friends');
  await sendIn(BEN, chat, 'yes');
  await as(BEN, 'select public.unfriend($1)', [ANA]);
  await refuses(sendIn(ANA, chat, 'hello?'), 'chat_waiting');
  assert.deepEqual(await words(ANA, chat), ['friends', 'yes'], 'what was said stays');
});

test('anonymous accounts get nothing', async () => {
  await reset();
  await refuses(as(ANON, 'select * from public.get_chats()', [], { anonymous: true }), 'real account');
  await refuses(as(ANON, `select * from public.send_chat_message(null, $1, $2, 'hi')`, [ANA, client()], { anonymous: true }),
    'real account');
  await refuses(sendTo(ANA, ANON, 'hi'), 'chat_not_available');
});

test('a group is your friends; it reaches them with its first message, and anyone can leave', async () => {
  await reset();
  await friends(ANA, BEN);
  await friends(ANA, CAL);
  const chat = (await as(ANA, `select public.start_group_chat($1::uuid[], 'Trivia crew') as id`,
    [[BEN, CAL, DEE]]))[0].id;
  assert.deepEqual(await chats(BEN), [], 'no empty chats');
  await sendIn(ANA, chat, 'Thursday?');
  const [theirs] = await chats(BEN);
  assert.equal(theirs.name, 'Trivia crew');
  assert.deepEqual(theirs.others.map((o) => o.display_name).sort(), ['Ana Lee', 'Cal Ruiz']);
  assert.equal(theirs.unread, true);
  assert.deepEqual(await chats(DEE), [], 'Dee is not Ana\'s friend, so left out');
  await sendIn(BEN, chat, 'in');
  await as(CAL, 'select public.leave_chat($1)', [chat]);
  assert.deepEqual(await chats(CAL), []);
  assert.deepEqual(await words(CAL, chat), []);
  assert.equal((await as(CAL, 'select * from public.chat_messages')).length, 0, 'the rule itself says Leave');
  await refuses(sendIn(CAL, chat, 'back'), 'chat_not_member');
  assert.deepEqual((await chats(BEN))[0].others.map((o) => o.display_name), ['Ana Lee']);
});

test('in a group, a Block hides each other\'s messages and nobody else\'s', async () => {
  await reset();
  await friends(ANA, BEN);
  await friends(ANA, CAL);
  const chat = (await as(ANA, 'select public.start_group_chat($1::uuid[]) as id', [[BEN, CAL]]))[0].id;
  await sendIn(ANA, chat, 'from Ana');
  await sendIn(BEN, chat, 'from Ben');
  await sendIn(CAL, chat, 'from Cal');
  await as(BEN, 'select public.block_neighbor($1)', [CAL]);
  assert.deepEqual(await words(BEN, chat), ['from Ana', 'from Ben']);
  assert.deepEqual(await words(CAL, chat), ['from Ana', 'from Cal']);
  assert.deepEqual(await words(ANA, chat), ['from Ana', 'from Ben', 'from Cal']);
  assert.deepEqual((await chats(BEN))[0].others.map((o) => o.display_name), ['Ana Lee']);
});

test('someone under 18 joins a group only when friends with everyone in it', async () => {
  await reset();
  await friends(ANA, BEN);
  await friends(ANA, KID);
  const left = (await as(ANA, 'select public.start_group_chat($1::uuid[]) as id', [[BEN, KID]]))[0].id;
  await sendIn(ANA, left, 'hi all');
  assert.deepEqual(await chats(KID), [], 'Kit and Ben aren\'t friends');
  await friends(BEN, KID);
  const both = (await as(ANA, 'select public.start_group_chat($1::uuid[]) as id', [[BEN, KID]]))[0].id;
  await sendIn(ANA, both, 'hi again');
  assert.equal((await chats(KID))[0].chat_id, both);
});

test('an Event card is gone when its Event is, and from under-18s when it is kept to adults', async () => {
  await reset();
  await friends(ANA, BEN);
  await friends(ANA, KID);
  const { chat_id: chat } = await sendTo(ANA, KID, null, { event: BAR });
  assert.equal((await messages(ANA, chat))[0].card.title, 'Pub crawl 21+');
  assert.equal((await messages(KID, chat))[0].card, null);
  const { chat_id: other } = await sendTo(ANA, BEN, null, { event: EVENT });
  await db.exec(`update public.club_events set status = 'rejected' where id = '${EVENT}'`);
  assert.equal((await messages(BEN, other))[0].card, null);
  await db.exec(`delete from public.club_events where id = '${EVENT}'`);
  const [gone] = await messages(BEN, other);
  assert.equal(gone.kind, 'event');
  assert.equal(gone.card, null);
});

test('Seen moves only when there is something new from someone else', async () => {
  await reset();
  await friends(ANA, BEN);
  const { chat_id: chat } = await sendTo(ANA, BEN, 'one');
  await as(ANA, 'select public.mark_chat_read($1)', [chat]);
  assert.equal((await as(BEN, 'select * from public.chat_reads')).length, 0, 'nothing new for Ana');
  await as(BEN, 'select public.mark_chat_read($1)', [chat]);
  const [read] = await as(ANA, 'select * from public.chat_reads');
  assert.equal(read.user_id, BEN);
  assert.equal((await chats(BEN))[0].unread, false);
  await as(BEN, 'select public.mark_chat_read($1)', [chat]);
  assert.deepEqual((await as(ANA, 'select read_at from public.chat_reads'))[0].read_at, read.read_at);
  assert.equal((await as(CAL, 'select * from public.chat_reads')).length, 0);
});

test('a report keeps its own copy for the admin, and Hide takes the message out for everyone', async () => {
  await reset();
  await friends(ANA, BEN);
  const { chat_id: chat, id: message } = await sendTo(ANA, BEN, 'rude words');
  await refuses(as(ANA, 'select public.report_chat_message($1, $2)', [message, 'bullying']), 'chat_not_member');
  await refuses(as(CAL, 'select public.report_chat_message($1, $2)', [message, 'bullying']), 'chat_not_member');
  await refuses(as(BEN, 'select public.report_chat_message($1, $2)', [message, 'made_up']), 'check');
  await as(BEN, 'select public.report_chat_message($1, $2)', [message, 'bullying']);
  await refuses(as(BEN, 'select * from public.get_chat_reports()'), 'admins only');
  const [report] = await as(DEE, 'select * from public.get_chat_reports()', [], { admin: true });
  assert.equal(report.body, 'rude words');
  assert.equal(report.sender_name, 'Ana Lee');
  assert.equal(report.reason, 'bullying');
  assert.equal(Object.keys(report).includes('reporter'), false);
  await refuses(as(BEN, 'select public.resolve_chat_report($1, true)', [report.id]), 'admins only');
  await as(DEE, 'select public.resolve_chat_report($1, true)', [report.id], { admin: true });
  assert.deepEqual(await words(BEN, chat), []);
  assert.deepEqual(await words(ANA, chat), []);
  assert.deepEqual(await as(DEE, 'select * from public.get_chat_reports()', [], { admin: true }), []);
});

test('a report outlives the sender\'s account; deleting an account leaves the others\' messages', async () => {
  await reset();
  await friends(ANA, BEN);
  const { chat_id: chat, id: message } = await sendTo(ANA, BEN, 'rude');
  await sendIn(BEN, chat, 'hey');
  await as(BEN, 'select public.report_chat_message($1, $2)', [message, 'scam']);
  await db.query('delete from auth.users where id = $1', [ANA]);
  const [report] = await as(DEE, 'select * from public.get_chat_reports()', [], { admin: true });
  assert.equal(report.sender_name, 'Ana Lee');
  assert.equal(report.message_id, null);
  assert.deepEqual(await words(BEN, chat), ['hey']);
  assert.deepEqual(await chats(BEN), [], 'a direct chat with nobody on the other end leaves the list');
});

test('photos: your own folder to send, and only someone who can see the message to read', async () => {
  await reset();
  await friends(ANA, BEN);
  const photo = `${ANA}/${id(77)}.jpg`;
  await as(ANA, `insert into storage.objects (bucket_id, name) values ('chat-photos', $1)`, [photo]);
  await refuses(as(ANA, `insert into storage.objects (bucket_id, name) values ('chat-photos', $1)`, [`${BEN}/x.jpg`]),
    'row-level security');
  await refuses(as(ANON, `insert into storage.objects (bucket_id, name) values ('chat-photos', $1)`, [`${ANON}/x.jpg`], { anonymous: true }),
    'row-level security');
  const seen = async (who) => (await as(who, `select name from storage.objects where bucket_id = 'chat-photos'`)).length;
  assert.equal(await seen(ANA), 1, 'its sender');
  assert.equal(await seen(BEN), 0, 'not yet in a message');
  await sendTo(ANA, BEN, null, { photo, w: 10, h: 10 });
  assert.equal(await seen(BEN), 1);
  assert.equal(await seen(CAL), 0);
  await as(BEN, 'select public.block_neighbor($1)', [ANA]);
  assert.equal(await seen(BEN), 0, 'Block says no');
  assert.equal(await seen(ANA), 1);
  assert.equal((await db.query(`select public from storage.buckets where id = 'chat-photos'`)).rows[0].public, false);
});

test('typing is a private channel for the people in the chat', async () => {
  await reset();
  await friends(ANA, BEN);
  const { chat_id: chat } = await sendTo(ANA, BEN, 'hi');
  const typing = (who, topic) => as(who, `insert into realtime.messages (extension, topic) values ('broadcast', $1)`,
    [topic], { topic });
  await typing(BEN, `chat:${chat}`);
  await refuses(typing(CAL, `chat:${chat}`), 'row-level security');
  await refuses(typing(BEN, 'chat:not-a-chat'), 'row-level security');
  await refuses(typing(BEN, 'realtime:anything'), 'row-level security');
});
