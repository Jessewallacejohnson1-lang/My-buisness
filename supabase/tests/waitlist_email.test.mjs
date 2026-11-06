// Fixed stories for the daily waitlist email (supabase/migrations/*_waitlist_email.sql, BP app docs/plans/loopholes,
// ticket 07). The expected text is what the website's scripts/waitlist-digest.ts digest() printed for the same rows.
// Run: `npm test` in this folder.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { realDatabase } from './fixture.mjs';

const db = await realDatabase();
await db.exec(`
  insert into vault.decrypted_secrets values
    ('morning_check', '{"headers":{"x-user-api-key":"test-key","x-org-id":"ok_test"},"account":"ca_test",
      "user":"consumer-test","to":"jesse@example.com"}');
`);
// Monday Nov 2, 8:00 in Chicago (winter time, UTC-6).
const NOW = '2026-11-02 14:00:00+00';
const carriedOver = (await db.query(`select sent_at from private.waitlist_email_sent`)).rows;
const story = async (rows, lastSent = '2026-11-01 14:00:00+00') => {
  await db.exec(`delete from fake.calls; delete from fake.answer; delete from public.waitlist;
    insert into fake.answer values (200, '{"successful":true,"error":null}');`);
  await db.query('update private.waitlist_email_sent set sent_at = $1', [lastSent]);
  for (const [i, [first_name, town, business_name, business_kind, created_at]] of rows.entries()) {
    await db.query(`insert into public.waitlist (email, first_name, town, business_name, business_kind, created_at)
      values ($1, $2, $3, $4, $5, $6)`, [`p${i}@example.com`, first_name, town, business_name, business_kind, created_at]);
  }
};
const digest = async (since) =>
  (await db.query('select subject, body from private.waitlist_digest($1)', [since])).rows[0];
const send = (now = NOW) => db.query('select private.waitlist_email($1)', [now]);
const sent = async () => (await db.query('select uri, headers, content from fake.calls')).rows;
const lastSent = async () =>
  (await db.query(`select to_char(sent_at at time zone 'UTC', 'YYYY-MM-DD HH24:MI:SS') t from private.waitlist_email_sent`)).rows[0].t;

const SELF_CHECK = [
  ['Ada', 'St Joseph', 'Bean', 'coffee shop', '2026-09-20T12:00:00Z'],
  ['Bo', 'St Joseph', null, null, '2026-09-20T09:00:00Z'],
  ['Cy', 'Benton Harbor', null, null, '2026-09-01T09:00:00Z'],
];

test("the script's self-check rows make its subject and body, word for word", async () => {
  await story(SELF_CHECK);
  assert.deepEqual(await digest('2026-09-19T08:00:00Z'), {
    subject: 'Block Party waitlist — 2 new, 3 total',
    body: [
      'Since Sep 19: 2 new (1 business, 1 neighbour)',
      'On the list: 3 total (1 business, 2 neighbour)',
      '',
      'New signups',
      '  Ada, St Joseph — Bean (coffee shop)',
      '  Bo, St Joseph',
      '',
      'New by town',
      '  2  St Joseph',
      '',
      'All-time by town',
      '  2  St Joseph',
      '  1  Benton Harbor',
    ].join('\n'),
  });
});

test('the window excludes a row exactly at the cutoff: that row belonged to the last email', async () => {
  await story(SELF_CHECK);
  assert.deepEqual(await digest('2026-09-20T12:00:00Z'), {
    subject: 'Block Party waitlist — 0 new, 3 total',
    body: [
      'Since Sep 20: 0 new (0 business, 0 neighbour)',
      'On the list: 3 total (1 business, 2 neighbour)',
      '',
      'All-time by town',
      '  2  St Joseph',
      '  1  Benton Harbor',
    ].join('\n'),
  });
});

test('owners and neighbours are split; a business with no kind, or a blank one, reads as the script did', async () => {
  await story([
    ['Di', 'St. Joseph, MN', 'Bad Habit', null, '2026-11-02T01:00:00Z'],
    ['Ed', 'St. Joseph, MN', '', 'bakery', '2026-11-02T02:00:00Z'],
    ['Flo', 'St. Joseph, MN', 'Flour', '', '2026-11-02T03:00:00Z'],
    ['Gus', 'St. Joseph, MN', null, null, '2026-10-01T03:00:00Z'],
  ]);
  const { body } = await digest('2026-11-01T14:00:00Z');
  assert.deepEqual(body.split('\n').slice(0, 7), [
    'Since Nov 1: 3 new (2 business, 1 neighbour)',
    'On the list: 4 total (2 business, 2 neighbour)',
    '',
    'New signups',
    '  Flo, St. Joseph, MN — Flour',
    '  Ed, St. Joseph, MN',
    '  Di, St. Joseph, MN — Bad Habit',
  ]);
});

test('towns are tallied and sorted: most first, then by name; the all-time list stops at 10 and the new list does not', async () => {
  const towns = ['Zimmerman', 'albany', 'Albany', 'Avon', 'Cold Spring', 'Foley', 'Rice', 'Sartell', 'Sauk Rapids', 'St Joseph', 'St. Cloud', 'Waite Park'];
  await story([
    ...towns.map((t, i) => [`N${i}`, t, null, null, `2026-11-02T0${i % 10}:0${i % 6}:00Z`]),
    ['Zed', 'Zimmerman', null, null, '2026-10-01T00:00:00Z'],
  ]);
  const body = (await digest('2026-11-01T14:00:00Z')).body;
  const list = (name) => body.split(`${name}\n`)[1].split('\n\n')[0].split('\n');
  assert.deepEqual(list('New by town'), [
    '  1  albany', '  1  Albany', '  1  Avon', '  1  Cold Spring', '  1  Foley', '  1  Rice', '  1  Sartell',
    '  1  Sauk Rapids', '  1  St Joseph', '  1  St. Cloud', '  1  Waite Park', '  1  Zimmerman',
  ]);
  assert.deepEqual(list('All-time by town'), [
    '  2  Zimmerman', '  1  albany', '  1  Albany', '  1  Avon', '  1  Cold Spring', '  1  Foley', '  1  Rice',
    '  1  Sartell', '  1  Sauk Rapids', '  1  St Joseph',
  ]);
});

test('the Since day is the day in Chicago, not in UTC', async () => {
  await story(SELF_CHECK);
  assert.match((await digest('2026-11-02T03:00:00Z')).body, /^Since Nov 1: /);
});

test('the time carried over from the Mac starts the window, so the first email covers what the Mac last missed', () => {
  assert.equal(carriedOver.length, 1);
  assert.equal(new Date(carriedOver[0].sent_at).toISOString(), '2026-11-05T14:00:13.182Z');
});

test('the 8:00 run sends one email through Composio, to the address in Vault, and moves the last-sent time', async () => {
  await story(SELF_CHECK, '2026-09-19 08:00:00+00');
  await send();
  const calls = await sent();
  assert.equal(calls.length, 1);
  assert.equal(calls[0].uri, 'https://backend.composio.dev/api/v3.1/tools/execute/GMAIL_SEND_EMAIL');
  assert.equal(calls[0].headers, '{"(x-org-id,ok_test)","(x-user-api-key,test-key)"}');
  const request = JSON.parse(calls[0].content);
  assert.equal(request.connected_account_id, 'ca_test');
  assert.equal(request.user_id, 'consumer-test');
  assert.deepEqual(Object.keys(request.arguments).sort(), ['body', 'is_html', 'recipient_email', 'subject'],
    'no cc or bcc: the email goes only to the one address');
  assert.equal(request.arguments.recipient_email, 'jesse@example.com');
  assert.equal(request.arguments.is_html, false);
  assert.deepEqual({ subject: request.arguments.subject, body: request.arguments.body }, await digest('2026-09-19 08:00:00+00'));
  assert.equal(await lastSent(), '2026-11-02 14:00:00');
});

test("the next morning's window starts where the last email's ended, and a quiet day still sends", async () => {
  await story(SELF_CHECK, '2026-09-19 08:00:00+00');
  await send();
  await send('2026-11-03 14:00:00+00');
  const calls = await sent();
  assert.equal(calls.length, 2);
  const second = JSON.parse(calls[1].content).arguments;
  assert.equal(second.subject, 'Block Party waitlist — 0 new, 3 total');
  assert.match(second.body, /^Since Nov 2: 0 new/);
});

test('a missed day is still reported: the window runs from the last email that really went', async () => {
  await story([['Ida', 'Avon', null, null, '2026-10-31T20:00:00Z'], ['Jo', 'Avon', null, null, '2026-11-02T01:00:00Z']],
    '2026-10-31 13:00:00+00');
  await send();
  const { subject, body } = JSON.parse((await sent())[0].content).arguments;
  assert.equal(subject, 'Block Party waitlist — 2 new, 2 total');
  assert.match(body, /^Since Oct 31: 2 new/);
});

test('a refused or failed send fails the run and keeps the last-sent time, so tomorrow covers today', async () => {
  await story(SELF_CHECK, '2026-09-19 08:00:00+00');
  await db.exec(`update fake.answer set content = '{"successful":false,"error":"Connected account not found"}'`);
  await assert.rejects(send(), /waitlist email not sent: .*Connected account not found/);
  assert.equal(await lastSent(), '2026-09-19 08:00:00');
  await db.exec(`update fake.answer set status = 401, content = '{"error":{"message":"Invalid API key"}}'`);
  await assert.rejects(send(), /waitlist email answered 401/);
  assert.equal(await lastSent(), '2026-09-19 08:00:00');
});

test('only 8:00 in Chicago sends, summer or winter time; the other run moves nothing', async () => {
  await story(SELF_CHECK, '2026-09-19 08:00:00+00');
  await send('2026-11-02 13:00:00+00'); // 7:00 in winter
  await send('2026-10-30 14:00:00+00'); // 9:00 in summer time
  assert.equal((await sent()).length, 0);
  assert.equal(await lastSent(), '2026-09-19 08:00:00');
  await send('2026-10-30 13:00:00+00'); // 8:00 in summer time
  assert.equal((await sent()).length, 1);
  assert.equal(await lastSent(), '2026-10-30 13:00:00');
});

test("the public key can't read the waitlist, the last-sent time, or run any of this", async () => {
  await story(SELF_CHECK);
  for (const role of ['anon', 'authenticated']) {
    for (const sql of [
      'select first_name from public.waitlist',
      'select sent_at from private.waitlist_email_sent',
      `select private.waitlist_towns(now())`,
      `select private.waitlist_digest(now())`,
      `select private.waitlist_email('${NOW}')`,
    ]) {
      await db.exec(`set role ${role}`);
      await assert.rejects(db.query(sql), /permission denied/, `${role}: ${sql}`);
      await db.exec('reset role');
    }
    // By name too: each function runs as its caller, so reading the table would stop an open one anyway.
    for (const fn of ['waitlist_towns', 'waitlist_digest', 'waitlist_email']) {
      const { rows: [{ ok }] } = await db.query(`select has_function_privilege($1, $2, 'execute') ok`,
        [role, `private.${fn}(timestamptz)`]);
      assert.equal(ok, false, `${role} can run ${fn}`);
    }
  }
  assert.equal((await sent()).length, 0);
});
