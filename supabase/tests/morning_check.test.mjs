// Fixed stories for the 8:00 bad-morning email (supabase/migrations/*_morning_check.sql, BP app docs/plans/loopholes,
// ticket 03), run in PGlite with stand-ins for pgsql-http, pg_cron's run log and Vault. A normal morning sends
// nothing; each kind of bad morning is one line in one email. Run: `npm test` in this folder.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import { PGlite } from '@electric-sql/pglite';
import { creating } from './migrations.mjs';

const migrations = process.env.MIGRATIONS ?? new URL('../migrations', import.meta.url).pathname;
const read = (f) => readFileSync(join(migrations, f), 'utf8');
// One function as it is now, cut from the newest file that makes it (that file makes much else too).
const fn = (name) => read(creating(migrations, [name]).at(-1))
  .match(new RegExp(`create or replace function ${name.replace('.', '\\.')}\\([\\s\\S]*?\\$\\$;`))[0];

const db = await PGlite.create();
await db.exec(`
  set timezone = 'UTC';
  create role anon; create role authenticated;
  create schema extensions; create schema private; create schema cron; create schema vault;
  create type extensions.http_header as (field varchar, value varchar);
  create type extensions.http_request as (method text, uri varchar, headers extensions.http_header[],
    content_type varchar, content varchar);
  create type extensions.http_response as (status int, content_type varchar, headers extensions.http_header[],
    content varchar);
  create function extensions.http_header(varchar, varchar) returns extensions.http_header language sql
    as $$ select ($1, $2)::extensions.http_header $$;
  create function extensions.http_set_curlopt(varchar, varchar) returns boolean language sql as $$ select true $$;
  -- Composio's answer, set by each story.
  create table calls (uri text, headers text, content text);
  create table answer (status int, content text);
  create function extensions.http(r extensions.http_request) returns extensions.http_response language plpgsql as $$
  begin
    insert into public.calls values (r.uri, r.headers::text, r.content);
    return (select (a.status, 'application/json', null, a.content)::extensions.http_response from public.answer a);
  end $$;
  create table cron.job (jobid bigint, jobname text);
  create table cron.job_run_details (jobid bigint, status text, return_message text, start_time timestamptz);
  create function cron.schedule(name text, sched text, cmd text) returns bigint language sql as $$ select 1::bigint $$;
  create table vault.decrypted_secrets (name text, decrypted_secret text);
  insert into vault.decrypted_secrets values
    ('morning_check', '{"key":"test-key","account":"ca_test","to":"jesse@example.com"}');
  insert into cron.job values (4, 'game-finals'), (5, 'live-scores');
  create table public.club_events (id uuid primary key default gen_random_uuid(), title text, event_date date,
    start_time text, team_ids text[], final_score int[], live_score jsonb, cancelled_at timestamptz,
    status text default 'approved', source_name text, sport text, submitted_by uuid,
    created_at timestamptz default now());
`);
await db.exec(read(readdirSync(migrations).find((f) => f.endsWith('_morning_reports.sql'))));
await db.exec(fn('private.sidearm_file'));
await db.exec(fn('private.live_games'));
await db.exec(read(creating(migrations, ['private.morning_check']).at(-1)));

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
  await db.exec(`delete from calls; delete from answer; delete from public.morning_reports;
    delete from public.club_events; delete from cron.job_run_details;
    insert into answer values (200, '{"successful":true,"error":null}');`);
  if (text) await db.query(`insert into public.morning_reports (day, report) values ('2026-11-02', $1)`, [text]);
};
const problems = async (now = NOW) =>
  (await db.query('select private.morning_problems($1) p', [now])).rows.map((r) => r.p);
const check = (now = NOW) => db.query('select private.morning_check($1)', [now]);
const sent = async () => (await db.query('select uri, headers, content from calls')).rows;

test('a normal morning sends no email', async () => {
  await story();
  assert.deepEqual(await problems(), []);
  await check();
  assert.equal((await sent()).length, 0);
});

test('no report today: one email through Composio, to the address and with the key in Vault', async () => {
  await story(null);
  await check();
  const calls = await sent();
  assert.equal(calls.length, 1);
  assert.equal(calls[0].uri, 'https://backend.composio.dev/api/v3.1/tools/execute/GMAIL_SEND_EMAIL');
  assert.match(calls[0].headers, /x-api-key,test-key/);
  const body = JSON.parse(calls[0].content);
  assert.equal(body.connected_account_id, 'ca_test');
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
    ('Farmers market', 'pending', gen_random_uuid(), '2026-11-01 13:00+00'),
    ('Bake sale', 'pending', gen_random_uuid(), '2026-11-01 15:00+00'),
    ('Pancake breakfast', 'approved', gen_random_uuid(), '2026-10-20 15:00+00'),
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
      source_name, sport) values
    ('SJU Football vs Gustavus Adolphus', '2026-11-01', '1 PM', '{sju,gustavus}', '{28,14}', null, 'SJU Athletics', 'Football'),
    ('CSB Volleyball vs Augsburg', '2026-11-01', '5 PM', '{csb,augsburg}', null, '{"home":2}', 'CSB Athletics', 'Volleyball'),
    ('SJU Basketball vs St. Cloud State', '2026-11-02', '7:50 AM', '{sju,scsu}', null, null, 'SJU Athletics', 'Basketball'),
    ('Sartell Football vs Apollo', '2026-11-01', '7 PM', '{sartell,apollo}', null, null, 'Sartell High School', 'Football'),
    ('SJU Soccer vs Carleton', '2026-10-31', '1 PM', '{sju,carleton}', null, null, 'SJU Athletics', 'Soccer')`);
  assert.deepEqual(await problems(), ['Live scores heard nothing from SJU Football vs Gustavus Adolphus (Sun 1:00 PM).']);
  // The same game private.live_games listened to: 30 minutes in, before its final came.
  await db.exec(`update public.club_events set final_score = null where sport = 'Football'`);
  const listened = await db.query(`select e.title from private.live_games('2026-11-01 19:30+00') g
    join public.club_events e on e.id = g.id`);
  assert.deepEqual(listened.rows.map((r) => r.title), ['SJU Football vs Gustavus Adolphus']);
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
  await db.exec(`update answer set content = '{"successful":false,"error":"Connected account not found"}'`);
  await assert.rejects(check(), /morning check email not sent: .*Connected account not found/);
  await db.exec(`update answer set status = 401, content = '{"error":{"message":"Invalid API key"}}'`);
  await assert.rejects(check(), /morning check email answered 401/);
});
