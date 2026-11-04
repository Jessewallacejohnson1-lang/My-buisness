// Fixed stories for the 8:00 bad-morning email (supabase/migrations/*_morning_check.sql, BP app docs/plans/loopholes,
// ticket 03), run in PGlite with the fixture's stand-ins for pgsql-http, pg_cron's run log and Vault. A normal morning sends
// nothing; each kind of bad morning is one line in one email. Run: `npm test` in this folder.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { realDatabase, people } from './fixture.mjs';

const POSTER = '00000000-0000-0000-0000-00000000000a';
const db = await realDatabase();
await people(db, POSTER);
await db.exec(`
  insert into vault.decrypted_secrets values
    ('morning_check', '{"headers":{"x-user-api-key":"test-key","x-org-id":"ok_test"},"account":"ca_test",
      "user":"consumer-test","to":"jesse@example.com"}');
  insert into cron.job values (4, 'game-finals'), (5, 'live-scores');
  delete from public.clubs;
`);
// Monday Nov 2, 8:00 in Chicago (winter time, UTC-6).
const NOW = '2026-11-02 14:00:00+00';
const report = ({ pages = 242, failed = 2, events = 54, extra = '' } = {}) => [
  'Morning watch, 2026-11-02',
  `- Pages: ${pages} fetched, 36 changed, 27 read by the cheap model`,
  `- Events: ${events} new, 1165 already listed`,
  '- News: 2 new, 37 repeats left out',
  `- Failed today: ${failed}`,
  'New Events:',
  '- Sat Nov 28 · 1 PM · Girls Hockey vs Rogers · Municipal Athletic Complex',
  extra,
  '[morning] tagged 55 events (0 with no interest)',
  '[morning] standouts: 9 of 25 events today',
].join('\n');
const story = async (text = report()) => {
  await db.exec(`delete from fake.calls; delete from fake.answer; delete from public.morning_reports;
    delete from public.club_events; delete from cron.job_run_details;
    insert into fake.answer values (200, '{"successful":true,"error":null}');`);
  if (text) await db.query(`insert into public.morning_reports (day, report) values ('2026-11-02', $1)`, [text]);
};
const problems = async (now = NOW) =>
  (await db.query('select private.morning_problems($1) p', [now])).rows.map((r) => r.p);
const check = (now = NOW) => db.query('select private.morning_check($1)', [now]);
const sent = async () => (await db.query('select uri, headers, content from fake.calls')).rows;

test('a normal morning sends no email', async () => {
  await story();
  assert.deepEqual(await problems(), []);
  await check();
  assert.equal((await sent()).length, 0);
});

test('no report today: one email through Composio, to the address, with the headers and account in Vault', async () => {
  await story(null);
  await check();
  const calls = await sent();
  assert.equal(calls.length, 1);
  assert.equal(calls[0].uri, 'https://backend.composio.dev/api/v3.1/tools/execute/GMAIL_SEND_EMAIL');
  assert.equal(calls[0].headers, '{"(x-org-id,ok_test)","(x-user-api-key,test-key)"}');
  const body = JSON.parse(calls[0].content);
  assert.equal(body.connected_account_id, 'ca_test');
  assert.equal(body.user_id, 'consumer-test');
  assert.equal(body.arguments.recipient_email, 'jesse@example.com');
  assert.equal(body.arguments.subject, "Block Party: No morning report today: the morning run didn't finish.");
  assert.equal(body.arguments.body,
    "- No morning report today: the morning run didn't finish.\n\nNo email means all is well.");
});

test('a failed step, 0 Events and too many failing pages are one line each in one email', async () => {
  await story(report({ events: 0, failed: 25, extra: '[morning] tags failed: Supabase 500: upstream timeout' }));
  assert.deepEqual(await problems(), [
    'A morning step failed: tags failed: Supabase 500: upstream timeout',
    'The morning run added 0 Events.',
    '25 of 242 pages failed this morning.',
  ]);
  await check();
  const calls = await sent();
  assert.equal(calls.length, 1);
  assert.equal(JSON.parse(calls[0].content).arguments.subject, 'Block Party: 3 things wrong this morning');
});

test('failing pages: 24 of 242 is within 1 in 10, 25 is not', async () => {
  await story(report({ failed: 24 }));
  assert.deepEqual(await problems(), []);
  await story(report({ failed: 25 }));
  assert.deepEqual(await problems(), ['25 of 242 pages failed this morning.']);
});

test('a report without its numbers says it could not be checked', async () => {
  await story('Morning watch, 2026-11-02\n- Events: 12 new, 1165 already listed');
  assert.deepEqual(await problems(),
    ["The morning report has no Pages, Failed today or Events line, so it couldn't be checked."]);
});

test("a neighbour's post waiting over a day is named; a newer one or a found Event waiting is not", async () => {
  await story();
  await db.exec(`insert into public.club_events (title, status, submitted_by, created_at) values
    ('Farmers market', 'pending', '${POSTER}', '2026-11-01 13:00+00'),
    ('Bake sale', 'pending', '${POSTER}', '2026-11-01 15:00+00'),
    ('Pancake breakfast', 'approved', '${POSTER}', '2026-10-20 15:00+00'),
    ('Dave''s Hot Chicken opening', 'pending', null, '2026-10-22 11:00+00')`);
  assert.deepEqual(await problems(),
    ['A neighbour\'s post has waited over a day for your approval: "Farmers market" (since Nov 1).']);
});

test('live scores: failures in the last day are counted by reason; a startup timeout or an older one is not', async () => {
  await story();
  const refused = 'ERROR:  live-scores answered 401: {"code":401}\nCONTEXT:  PL/pgSQL function private.wake_live_scores()';
  await db.query(`insert into cron.job_run_details values
    (5, 'failed', $1, '2026-11-01 23:00+00'), (5, 'failed', $1, '2026-11-01 23:01+00'),
    (5, 'failed', 'job startup timeout', '2026-11-02 01:00+00'),
    (5, 'failed', $1, '2026-11-01 12:00+00'),
    (5, 'succeeded', '1 row', '2026-11-02 02:00+00'),
    (4, 'failed', 'ERROR:  finals', '2026-11-02 03:00+00')`, [refused]);
  assert.deepEqual(await problems(),
    ['Live scores failed 2 times since yesterday: ERROR:  live-scores answered 401: {"code":401}']);
});

test('a game listened to with no score saved is named, final in or not; a scored one or one just begun is not', async () => {
  await story();
  await db.exec(`insert into public.club_events (title, event_date, start_time, team_ids, final_score, live_score,
      source_name, sport, status) values
    ('SJU Football vs Gustavus Adolphus', '2026-11-01', '1 PM', '{sju,gustavus}', '{28,14}', null, 'SJU Athletics', 'Football', 'approved'),
    ('CSB Volleyball vs Augsburg', '2026-11-01', '5 PM', '{csb,augsburg}', null, '{"home":2}', 'CSB Athletics', 'Volleyball', 'approved'),
    ('SJU Basketball vs St. Cloud State', '2026-11-02', '7:50 AM', '{sju,scsu}', null, null, 'SJU Athletics', 'Basketball', 'approved'),
    ('Sartell Football vs Apollo', '2026-11-01', '7 PM', '{sartell,apollo}', null, null, 'Sartell High School', 'Football', 'approved'),
    ('SJU Soccer vs Carleton', '2026-10-31', '1 PM', '{sju,carleton}', null, null, 'SJU Athletics', 'Soccer', 'approved')`);
  assert.deepEqual(await problems(), ['Live scores heard nothing from SJU Football vs Gustavus Adolphus (Sun 1:00 PM).']);
  // The same game private.live_games listened to: 30 minutes in, before its final came.
  await db.exec(`update public.club_events set final_score = null where sport = 'Football'`);
  const listened = await db.query(`select e.title from private.live_games('2026-11-01 19:30+00') g
    join public.club_events e on e.id = g.id`);
  assert.deepEqual(listened.rows.map((r) => r.title), ['SJU Football vs Gustavus Adolphus']);
});

test("a group's calendar not read in over a day is named; one read this morning is not", async () => {
  await story();
  await db.exec(`insert into public.clubs (name, status, calendar_id, calendar_read_at, calendar) values
    ('St. Cloud River Runners', 'approved', 'a@group.calendar.google.com', '2026-11-01 10:30+00', null),
    ('Quiet club', 'approved', 'q@group.calendar.google.com', '2026-11-02 10:30+00', '[{"what": "Run", "day": "2026-11-03"}]'),
    ('New club', 'approved', 'n@group.calendar.google.com', null, null),
    ('Lions', 'approved', null, null, null)`);
  assert.deepEqual(await problems(), [
    "The New club calendar hasn't been read since it was added.",
    "The St. Cloud River Runners calendar hasn't been read since Nov 1."]);
  await db.exec('delete from public.clubs');
});

test('a calendar read this morning with nothing for 2 weeks is named; one with a run next week is not', async () => {
  await story();
  await db.exec(`insert into public.clubs (name, status, calendar_id, calendar_read_at, calendar) values
    ('St. Cloud River Runners', 'approved', 'a@group.calendar.google.com', '2026-11-02 10:30+00',
     '[{"what": "Run", "day": "2026-11-01"}, {"what": "Banquet", "day": "2026-11-16"}]'),
    ('Quiet club', 'approved', 'q@group.calendar.google.com', '2026-11-02 10:30+00', '[{"what": "Run", "day": "2026-11-15"}]')`);
  assert.deepEqual(await problems(), ['The St. Cloud River Runners calendar has nothing on it for the next 2 weeks.']);
  await db.exec('delete from public.clubs');
});

test("a meeting the page promises that the calendar moved or dropped is named once, with the page's top line", async () => {
  await story();
  const club = (calendar) => db.query(`insert into public.clubs (name, status, calendar_id, calendar_read_at, calendar, meets, schedule, location)
    values ('St. Cloud River Runners', 'approved', 'a@group.calendar.google.com', '2026-11-02 10:30+00', $1,
            '[{"what": "Coffee Run", "days": ["sun"], "time": "07:30"}]', 'Sundays at 7:30 AM', 'The Local Blend')`,
    [JSON.stringify(calendar)]);
  const run = (day, time, where) => ({ what: 'Coffee Run', day, time, where });
  await club([run('2026-11-08', '08:00', 'The Local Blend'), run('2026-11-15', '08:00', 'The Local Blend')]);
  assert.deepEqual(await problems(), ['St. Cloud River Runners: the page says Sundays at 7:30 AM · The Local Blend, '
    + 'but its calendar has no Coffee Run on Sun Nov 8 at 7:30 AM. Check the page\'s top line.']);
  await db.exec('delete from public.clubs');
  await club([run('2026-11-08', '07:30', 'Kitchenette, St. Cloud area')]);
  assert.equal((await problems()).length, 1, 'the right time at another place');
  await db.exec('delete from public.clubs');
  await club([run('2026-11-08', '07:30', 'The Local Blend')]);
  assert.deepEqual(await problems(), [], 'as the page says');
  await db.exec('delete from public.clubs');
});

// Apify's line, as social.py's spend writes it at the end of the report; `before` is the mornings before today, newest first.
const apify = (used, cap = 40) => `Apify: $${used.toFixed(2)} of $${cap} this month${used >= cap - 0.01
  ? '. The cap is reached: Apify has stopped every check until the cycle resets.'
  : used >= cap * 0.75 ? '. Heads-up: past 3/4 of the cap.' : ''} (resets after 2026-11-20)`;
const mornings = async (today, ...before) => {
  await story(`${report()}\n${today}`);
  for (const [i, line] of before.entries()) {
    await db.query('insert into public.morning_reports (day, report) values ($1, $2)',
      [['2026-11-01', '2026-10-31', '2026-10-30'][i], line === null ? report() : `${report()}\n${line}`]);
  }
};

test('Apify below 3/4 of the cap says nothing', async () => {
  await mornings(apify(29.99), apify(29));
  assert.deepEqual(await problems(), []);
});

test('Apify passing 3/4 of the cap is one line that morning, and not the next', async () => {
  await mornings(apify(30), apify(29.5));
  assert.deepEqual(await problems(), [apify(30)]);
  await mornings(apify(31), apify(30));
  assert.deepEqual(await problems(), []);
});

test('Apify reaching the cap is one line that morning, and not the next', async () => {
  await mornings(apify(40), apify(38));
  assert.deepEqual(await problems(), [apify(40)]);
  await mornings(apify(40), apify(40));
  assert.deepEqual(await problems(), []);
});

test('Apify jumping past 3/4 straight to the cap is only the cap line', async () => {
  await mornings(apify(40), apify(20));
  assert.deepEqual(await problems(), [apify(40)]);
});

test('a new Apify cycle sends nothing, and passing 3/4 again later says so again', async () => {
  await mornings(apify(1), apify(40));
  assert.deepEqual(await problems(), []);
  await mornings(apify(30), apify(29), apify(1), apify(40));
  assert.deepEqual(await problems(), [apify(30)]);
});

test('a raised Apify cap sends nothing, and crossing the new 3/4 later sends one line', async () => {
  await mornings(apify(36, 50), apify(36, 40));
  assert.deepEqual(await problems(), []);
  await mornings(apify(38, 50), apify(36, 50), apify(36, 40));
  assert.deepEqual(await problems(), [apify(38, 50)]);
});

test('a morning with Apify spend unknown says nothing about spend, and the next looks past it', async () => {
  const unknown = "Apify: spend unknown, Apify refused the request (HTTP 401): check the routine's network secret";
  await mornings(unknown, apify(30));
  assert.deepEqual(await problems(), []);
  await mornings(apify(31), unknown, apify(30));
  assert.deepEqual(await problems(), [], 'already past 3/4 before the unknown morning');
  await mornings(apify(31), unknown, apify(29));
  assert.deepEqual(await problems(), [apify(31)], 'it crossed during the unknown morning');
});

test('with no earlier Apify line to compare, a morning already past 3/4 says so', async () => {
  await mornings(apify(35));
  assert.deepEqual(await problems(), [apify(35)]);
  await mornings(apify(35), null);
  assert.deepEqual(await problems(), [apify(35)], 'an earlier report with no Apify line is no comparison');
});

test("Apify's line reaches the email as the report wrote it", async () => {
  await mornings(apify(30), apify(29));
  await check();
  const calls = await sent();
  assert.equal(calls.length, 1);
  assert.equal(JSON.parse(calls[0].content).arguments.subject, `Block Party: ${apify(30)}`);
});

test('only 8:00 in Chicago reads, summer or winter time', async () => {
  await story(null);
  await check('2026-11-02 13:00:00+00'); // 7:00 in winter
  await check('2026-11-02 15:00:00+00'); // 9:00
  assert.equal((await sent()).length, 0);
  await check('2026-10-30 13:00:00+00'); // 8:00 in summer time
  assert.equal((await sent()).length, 1);
});

test('an email Composio refuses fails the run, so pg_cron records it', async () => {
  await story(null);
  await db.exec(`update fake.answer set content = '{"successful":false,"error":"Connected account not found"}'`);
  await assert.rejects(check(), /morning check email not sent: .*Connected account not found/);
  await db.exec(`update fake.answer set status = 401, content = '{"error":{"message":"Invalid API key"}}'`);
  await assert.rejects(check(), /morning check email answered 401/);
});
