// Fixed stories for comments on posts (supabase/migrations/*_comments_work.sql, BP app backlog 38): who may write
// and read them, what the check's claim keeps, what the pill counts, who deletes, and the bell's grouped rows.
// Run in PGlite: `npm install && npm test` in this folder.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { realDatabase, people } from './fixture.mjs';

const db = await realDatabase();
const POSTER = '00000000-0000-0000-0000-0000000000a1';
const ANA = '00000000-0000-0000-0000-0000000000a2';
const SAM = '00000000-0000-0000-0000-0000000000a3';
const BLOCKED = '00000000-0000-0000-0000-0000000000a4';
const ANON = '00000000-0000-0000-0000-0000000000a5';
const STRANGER = '00000000-0000-0000-0000-0000000000a6';
const BUSY = '00000000-0000-0000-0000-0000000000a7';
await people(db, POSTER, ANA, SAM, BLOCKED, ANON, STRANGER, BUSY);
await db.query(`update auth.users set is_anonymous = true where id = $1`, [ANON]);
await db.query(`insert into public.town_profiles (user_id, display_name) values
  ($1, 'Marlene Ostendorf'), ($2, 'Ana Nguyen'), ($3, 'Sam Rivera'), ($4, 'Blake Doe'), ($5, 'Guest'), ($6, 'Tom Hanson'), ($7, 'Pat Busy')`,
  [POSTER, ANA, SAM, BLOCKED, ANON, STRANGER, BUSY]);
// Ana is the poster's friend; Blake blocked the poster.
await db.exec(`insert into private.friendships (a, b, requested_by) values ('${[POSTER, ANA].sort().join("', '")}', '${POSTER}')`);
await db.query(`insert into private.blocks (blocker_id, blocked_id) values ($1, $2)`, [BLOCKED, POSTER]);

let n = 0;
const id = () => `00000000-0000-0000-0000-${String(++n).padStart(12, '0')}`;

async function as(sub, anonymous = false) {
  await db.exec('reset role; set role authenticated;');
  await db.query(`select set_config('request.jwt.claims', $1, false)`, [JSON.stringify({ sub, role: 'authenticated', is_anonymous: anonymous })]);
}
async function asAdmin() { await db.exec('reset role'); }

/** A live post of `who`'s. */
async function post(who, extra = {}) {
  await asAdmin();
  const row = { id: id(), submitted_by: who, category: 'other', kind: 'post', title: 'Sledding at the park', status: 'approved', ...extra };
  const cols = Object.keys(row);
  await db.query(`insert into public.club_events (${cols.join(', ')}) values (${cols.map((_, i) => `$${i + 1}`).join(', ')})`,
                 Object.values(row));
  return row.id;
}
/** `who` writes a comment, as the app does: an insert under the read rules, then the check's claim and its yes. */
async function comment(who, postId, body, { names = null, verdict = 'shown' } = {}) {
  await as(who);
  const cid = id();
  await db.query(`insert into public.event_comments (id, event_id, user_id, body, at_names) values ($1, $2, $3, $4, $5)`,
                 [cid, postId, who, body, names && JSON.stringify(names)]);
  await asAdmin();
  const claimed = (await db.query(`select public.claim_comment($1, $2) as ok`, [cid, who])).rows[0].ok;
  if (claimed && verdict) await db.query(`update public.event_comments set status = $2 where id = $1`, [cid, verdict]);
  return { cid, claimed };
}
const read = async (who, postId) => { await as(who);
  return (await db.query(`select * from public.get_post_comments($1)`, [postId])).rows; };
const count = async (who, postId) => { await as(who);
  return (await db.query(`select private.comment_count($1) as n`, [postId])).rows[0].n; };
const denied = (p) => assert.rejects(p, /row-level security|permission denied/);

test('a neighbour reads every shown comment, oldest first, and the pill counts the same', async () => {
  const p = await post(POSTER);
  await comment(ANA, p, 'So fun!');
  await comment(SAM, p, 'Which hill?');
  const rows = await read(STRANGER, p);
  assert.deepEqual(rows.map((r) => r.body), ['So fun!', 'Which hill?']);
  assert.equal(rows[0].author.name, 'Ana Nguyen');
  assert.equal(rows[0].can_delete, false);
  assert.equal(await count(STRANGER, p), 2);
});

test('an Anonymous account can\'t comment', async () => {
  const p = await post(POSTER);
  await as(ANON, true);
  await denied(db.query(`insert into public.event_comments (event_id, user_id, body) values ($1, $2, 'hi')`, [p, ANON]));
});

test('nobody writes a comment as shown, nor on an Event, nor as someone else', async () => {
  const p = await post(POSTER);
  const ev = await post(POSTER, { kind: 'event', title: 'Fair', event_date: '2026-12-01' });
  await as(SAM);
  await denied(db.query(`insert into public.event_comments (event_id, user_id, body, status) values ($1, $2, 'x', 'shown')`, [p, SAM]));
  await denied(db.query(`insert into public.event_comments (event_id, user_id, body) values ($1, $2, 'x')`, [ev, SAM]));
  await denied(db.query(`insert into public.event_comments (event_id, user_id, body) values ($1, $2, 'x')`, [p, ANA]));
  assert.equal((await db.query(`update public.event_comments set body = 'edited'`)).affectedRows, 0, 'no editing');
});

test('a blocked pair sees none of each other\'s comments and can\'t comment on each other\'s posts', async () => {
  const p = await post(SAM);
  await comment(POSTER, p, 'From the poster');
  await comment(BLOCKED, p, 'From Blake');
  assert.deepEqual((await read(POSTER, p)).map((r) => r.body), ['From the poster']);
  assert.deepEqual((await read(BLOCKED, p)).map((r) => r.body), ['From Blake']);
  assert.equal(await count(POSTER, p), 1);
  assert.equal(await count(STRANGER, p), 2);
  const mine = await post(POSTER);
  await as(BLOCKED);
  await denied(db.query(`insert into public.event_comments (event_id, user_id, body) values ($1, $2, 'x')`, [mine, BLOCKED]));
});

test('a turned-down or unchecked comment is neither shown nor counted', async () => {
  const p = await post(POSTER);
  await comment(ANA, p, 'Rude words', { verdict: 'declined' });
  await comment(SAM, p, 'Still checking', { verdict: null });
  assert.equal((await read(STRANGER, p)).length, 0);
  assert.equal(await count(STRANGER, p), 0);
  assert.equal((await read(ANA, p)).length, 0, 'the writer\'s declined one is gone from the sheet too');
});

test('a Friends-only post\'s comments stay with friends', async () => {
  const p = await post(POSTER, { friends_only: true });
  await comment(ANA, p, 'Friends only');
  assert.equal((await read(STRANGER, p)).length, 0);
  await as(STRANGER);
  await denied(db.query(`insert into public.event_comments (event_id, user_id, body) values ($1, $2, 'x')`, [p, STRANGER]));
  assert.equal((await read(ANA, p)).length, 1);
});

test('the poster deletes any comment on their post; a writer only their own', async () => {
  const p = await post(POSTER);
  const a = (await comment(ANA, p, 'one')).cid;
  const s = (await comment(SAM, p, 'two')).cid;
  await as(ANA);
  await db.query(`delete from public.event_comments where id = $1`, [s]);
  assert.equal(await count(STRANGER, p), 2, 'Ana can\'t delete Sam\'s');
  assert.equal((await read(POSTER, p)).every((r) => r.can_delete), true);
  await as(POSTER);
  await db.query(`delete from public.event_comments where id = any($1)`, [[a, s]]);
  assert.equal(await count(STRANGER, p), 0);
});

test('the claim is once per comment and 50 a day', async () => {
  const p = await post(POSTER);
  const { cid } = await comment(BUSY, p, 'first');
  await asAdmin();
  assert.equal((await db.query(`select public.claim_comment($1, $2) as ok`, [cid, BUSY])).rows[0].ok, false);
  await db.query(`insert into private.comment_checks (user_id) select $1 from generate_series(1, 49)`, [BUSY]);
  assert.equal((await comment(BUSY, p, 'fifty-first')).claimed, false);
});

test('the check keeps an @ for someone in the thread or a friend, never a blocked one', async () => {
  const p = await post(SAM);
  await comment(STRANGER, p, 'Nice');
  const user = (u, name) => ({ kind: 'user', id: u, name });
  const { cid } = await comment(POSTER, p, '@Tom Hanson @Sam Rivera @Ana Nguyen @Blake Doe hi',
    { names: [user(STRANGER, 'Tom Hanson'), user(SAM, 'Sam Rivera'), user(ANA, 'Ana Nguyen'), user(BLOCKED, 'Blake Doe')] });
  await asAdmin();
  const kept = (await db.query(`select at_names from public.event_comments where id = $1`, [cid])).rows[0].at_names;
  assert.deepEqual(kept.map((k) => k.name), ['Tom Hanson', 'Sam Rivera', 'Ana Nguyen']);
});

test('the bell groups comments by post: "Ana and 1 other commented", "Ana replied to you", newest on top', async () => {
  const mine = await post(POSTER);
  await comment(SAM, mine, 'first');
  await comment(ANA, mine, 'second');
  await comment(ANA, mine, 'third');
  const theirs = await post(STRANGER);
  await comment(ANA, theirs, '@Marlene Ostendorf look', { names: [{ kind: 'user', id: POSTER, name: 'Marlene Ostendorf' }] });
  await as(POSTER);
  const rows = (await db.query(`select id, how, who->>'name' as who, others from public.get_my_comment_notices()
                                where id = any($1)`, [[mine, theirs]])).rows;
  assert.deepEqual(rows.map((r) => [r.id, r.how, r.who, r.others]),
                   [[theirs, 'replied', 'Ana Nguyen', 0], [mine, 'commented', 'Ana Nguyen', 1]]);
});

test('a report keeps a copy for Review, never who sent it; not on your own', async () => {
  const p = await post(POSTER);
  const { cid } = await comment(SAM, p, 'Buy followers at spam.example');
  await as(STRANGER);
  await db.query(`select public.report_comment($1, 'scam')`, [cid]);
  await asAdmin();
  const r = (await db.query(`select * from private.comment_reports where comment_id = $1`, [cid])).rows[0];
  assert.equal(r.writer_name, 'Sam Rivera');
  assert.equal(r.body, 'Buy followers at spam.example');
  await as(SAM);
  await assert.rejects(db.query(`select public.report_comment($1, 'scam')`, [cid]), /comment_not_seen/, 'not your own');
});

test('deleting a comment never gives back a check, and the claim sets the time', async () => {
  const LOOP = '00000000-0000-0000-0000-0000000000a8';
  await asAdmin();
  await people(db, LOOP);
  await db.query(`insert into public.town_profiles (user_id, display_name) values ($1, 'Lou Loop')`, [LOOP]);
  const p = await post(POSTER);
  await asAdmin();
  await db.query(`insert into private.comment_checks (user_id) select $1 from generate_series(1, 49)`, [LOOP]);
  await as(LOOP);
  const cid = id();
  await db.query(`insert into public.event_comments (id, event_id, user_id, body, created_at)
                  values ($1, $2, $3, 'pinned?', '2030-01-01')`, [cid, p, LOOP]);
  await asAdmin();
  assert.equal((await db.query(`select public.claim_comment($1, $2) as ok`, [cid, LOOP])).rows[0].ok, true);
  const at = (await db.query(`select created_at from public.event_comments where id = $1`, [cid])).rows[0].created_at;
  assert.ok(at < new Date('2029-01-01'), 'the claim stamps now');
  await as(LOOP);
  await db.query(`delete from public.event_comments where id = $1`, [cid]);
  assert.equal((await comment(LOOP, p, 'again')).claimed, false, 'the 50th check was used though its comment is gone');
});

test('the bell skips someone you muted', async () => {
  const mine = await post(POSTER);
  await comment(SAM, mine, 'hello');
  await asAdmin();
  await db.query(`insert into public.feed_mutes (user_id, host, name) values ($1, $2, 'Sam Rivera')`, [POSTER, SAM]);
  await as(POSTER);
  assert.equal((await db.query(`select 1 from public.get_my_comment_notices() where id = $1`, [mine])).rows.length, 0);
  await asAdmin();
  await db.query(`delete from public.feed_mutes where user_id = $1`, [POSTER]);
});

test('the Town feed\'s post row carries the pill\'s count', async () => {
  const p = await post(POSTER, { created_at: new Date().toISOString() });
  await comment(ANA, p, 'one');
  await as(STRANGER);
  const row = (await db.query(`select poster from public.get_town_feed(now(), true) where id = $1`, [p])).rows[0];
  assert.equal(row.poster.comments, 1);
});
