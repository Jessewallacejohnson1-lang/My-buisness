// Failure drills for live scores (supabase/migrations/*_never_blind.sql, BP app docs/plans/game-card/issues/
// 22-never-blind-quietly.md), each one a thing that already happened, run in PGlite on files saved from real games:
// the card keeps moving from the next source in order, and the marks say which source carried it. Then the alarm:
// one push to Jesse for a dark game, no more until it comes back. Run: `npm test` in this folder.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { realDatabase } from './fixture.mjs';

const file = (name) => JSON.parse(readFileSync(new URL(name, import.meta.url), 'utf8'));
// The school's file as the live-scores function writes it: the Game, every play so far as its LastPlays.
const whole = (f, game = {}) => ({ Game: { ...f.Game, LastPlays: f.Plays, ...game } });
// CSB hockey vs Lake Forest at 2:28 PM on 2026-11-07, read from gobennies.com: 1-0, 0:37 left in the 1st.
const hockey = file('sidearm-live-csb-whockey.json');
const score = (host, other) => ({ HomeTeam: { ...hockey.Game.HomeTeam, Score: String(host) },
                                  VisitingTeam: { ...hockey.Game.VisitingTeam, Score: String(other) } });
const live = whole(hockey);

const db = await realDatabase();
await db.exec(`insert into vault.decrypted_secrets values ('live_alarm', 'bp-test-topic')`);
const add = async (title, sport) => (await db.query(`insert into public.club_events
  (title, status, team_ids, source_name, sport, event_date, start_time)
  values ($1, 'approved', '{saint-benedict,lake-forest}', 'CSB Athletics', $2, '2026-11-07', '2 PM') returning id`,
  [title, sport])).rows[0].id;
const GAME = await add('CSB Hockey vs Lake Forest', 'Hockey');
await db.query(`insert into private.live_feeds (event_id, url) values ($1, 'https://gobennies.com/api/livestats?game_id=10289')`, [GAME]);

// 2:28 PM in St. Joseph (winter time, UTC-6), and n minutes on.
const at = (n = 0) => new Date(Date.parse('2026-11-07T20:28:00Z') + n * 60_000).toISOString();
const story = () => db.exec(`delete from private.live_reads; delete from private.live_alerts; delete from fake.calls;
  delete from fake.answer; insert into fake.answer values (200, '{"id":"x"}');
  update public.club_events set live_score = null, final_score = null, scoring_plays = null;`);
const read = async (source, game, minute, why = null, event = GAME) =>
  (await db.query('select public.record_live_read($1, $2, $3, $4, $5) r', [event, source, game, why, at(minute)])).rows[0].r;
const card = async () => (await db.query(`select live_score->'score' as score, (live_score->>'clock_s')::int as clock,
  final_score from public.club_events where id = $1`, [GAME])).rows[0];
const marks = async () => Object.fromEntries((await db.query(
  'select source, reads, failed, wrote, why from private.live_reads where event_id = $1', [GAME])).rows
  .map((r) => [r.source, { reads: r.reads, failed: r.failed, wrote: r.wrote, why: r.why }]));

test('expired certificate, push host moved: each failed push leaves its reason, and the school file carries', async () => {
  await story();
  assert.equal(await read('push', null, 0, 'certificate expired'), 'failed');
  assert.equal(await read('push', null, 0, 'push pointed at api-realtime-stats.example.com'), 'failed');
  assert.equal(await read('school', live, 0), 'live');
  assert.deepEqual((await card()).score, [1, 0]);
  assert.deepEqual(await marks(), {
    push: { reads: 2, failed: 2, wrote: 0, why: 'push pointed at api-realtime-stats.example.com' },
    school: { reads: 1, failed: 0, wrote: 1, why: null } });
});

test('cached old file: the backup waits while the school file has scored in the last 3 minutes', async () => {
  await story();
  await read('school', live, 0);
  const older = whole(hockey, { ClockSeconds: 900 });
  assert.equal(await read('backup', older, 2), 'held');
  assert.equal(await read('push', older, 2.9), 'held', 'the push waits too');
  assert.equal((await card()).clock, 37, "the school's clock stays on the card");
});

test('site down: after 3 quiet minutes the backup carries, and the school file takes back over', async () => {
  await story();
  await read('school', live, 0);
  for (const m of [1, 2, 3]) assert.equal(await read('school', null, m, 'HTTP 503'), 'failed');
  assert.equal(await read('backup', whole(hockey, score(2, 0)), 3.5), 'live');
  assert.deepEqual((await card()).score, [2, 0]);
  assert.equal(await read('school', whole(hockey, score(2, 1)), 4), 'live', 'back up: nothing holds the school');
  assert.deepEqual((await card()).score, [2, 1]);
  const m = await marks();
  assert.deepEqual(m.school, { reads: 5, failed: 3, wrote: 2, why: 'HTTP 503' });
  assert.deepEqual(m.backup, { reads: 1, failed: 0, wrote: 1, why: null });
});

test('the backup never moves the score backward', async () => {
  await story();
  await read('school', live, 0);
  assert.equal(await read('backup', whole(hockey, score(0, 0)), 5), 'held');
  assert.deepEqual((await card()).score, [1, 0]);
});

test("last week's game still in the file: a failed read, and the next source writes", async () => {
  await story();
  const friday = file('sidearm-final-csb-whockey.json');
  assert.equal(await read('school', whole(friday), 0), 'failed');
  assert.equal((await marks()).school.why, 'holds the game of 11/6/2026');
  assert.equal(await read('push', live, 0.2), 'live');
  assert.deepEqual((await card()).score, [1, 0]);
});

test("the gym's earlier game still in the file: a failed read, and nothing of it reaches the card", async () => {
  await story();
  const gym = whole(hockey, { HomeTeam: { ...hockey.Game.HomeTeam, Name: 'Hamline' },
                              VisitingTeam: { ...hockey.Game.VisitingTeam, Name: 'Minnesota Morris' } });
  assert.equal(await read('school', gym, 0), 'failed');
  assert.equal((await marks()).school.why, 'holds Minnesota Morris vs Hamline');
  assert.equal((await card()).score, null);
});

test('a final flickering on and off is written only after two complete reads in a row', async () => {
  await story();
  const done = (complete) => whole(hockey, { ...score(4, 1), IsComplete: complete, Period: 3, ClockSeconds: 0 });
  for (const c of [true, false, true]) await read('school', done(c), 0);
  assert.equal((await card()).final_score, null);
  assert.equal(await read('school', done(true), 0.5), 'final');
  assert.deepEqual((await card()).final_score, [4, 1]);
});

test("a plays push isn't a failed read, nor a score: it holds nothing below it", async () => {
  await story();
  await read('push', null, 0, 'certificate expired');
  assert.notEqual(await read('push', hockey.Plays.slice(-5), 1), 'failed');
  assert.deepEqual((await marks()).push, { reads: 2, failed: 1, wrote: 0, why: 'certificate expired' });
  assert.equal(await read('backup', live, 2), 'live', 'the backup still carries the score');
});

test('the backup takes the quiet game it tried longest ago, never one the school file is carrying', async () => {
  await story();
  const other = await add('CSB Basketball vs Loras', 'Basketball');
  const turn = async (m) => (await db.query('select public.live_backup_turn($1, $2) id', [[GAME, other], at(m)])).rows[0].id;
  try {
    await read('school', live, 0);
    assert.equal(await turn(1), other, 'hockey is carried by its school file');
    await read('backup', null, 1, 'HTTP 503', other);
    assert.equal(await turn(2), other, 'still the only quiet one');
    assert.equal(await turn(10), GAME, 'both quiet: hockey, never tried by the backup');
    await read('backup', whole(hockey, score(2, 0)), 10);
    assert.equal(await turn(20), other, 'then basketball, tried longest ago');
  } finally {
    await db.query('delete from public.club_events where id = $1', [other]);
  }
});

const alarm = (m) => db.query('select private.live_dark_alarm($1)', [at(m)]);
const pushes = async () => (await db.query('select uri, content from fake.calls')).rows
  .map((c) => ({ uri: c.uri, ...JSON.parse(c.content) }));
const lastScore = (m) => db.query(`update public.club_events set live_score = jsonb_build_object('score', '[1,0]'::jsonb, 'at', $2::timestamptz)
  where id = $1`, [GAME, at(m)]);

test('a game reading fine sends nothing', async () => {
  await story();
  await lastScore(-1);
  await alarm(0);
  assert.deepEqual(await pushes(), []);
});

test('no score for 12 minutes: exactly one push, naming the game and where each source stands', async () => {
  await story();
  await lastScore(-13);
  await read('school', null, -0.5, 'HTTP 503');
  await read('push', null, -0.4, 'certificate expired');
  await alarm(0);
  await alarm(1);
  await alarm(2);
  assert.deepEqual(await pushes(), [{
    uri: 'https://ntfy.sh/', topic: 'bp-test-topic', title: 'Live score dark: CSB Hockey vs Lake Forest',
    message: "No score since 2:15 PM. gobennies.com: HTTP 503 (2:27 PM). SIDEARM's push: certificate expired (2:27 PM).",
    priority: 4, tags: ['warning'] }]);
});

test("back from the school's file, then dark again: a second push", async () => {
  await story();
  await lastScore(-13);
  await alarm(0);
  await read('school', live, 2);
  await lastScore(2);
  await alarm(10);
  assert.equal((await pushes()).length, 1, 'fresh again');
  await alarm(15);
  assert.equal((await pushes()).length, 2);
});

test('plays pushes coming while the score is stuck: no second push', async () => {
  await story();
  await lastScore(-13);
  await alarm(0);
  for (const m of [1, 2, 3, 4]) await read('push', hockey.Plays.slice(-5), m);
  await alarm(5);
  assert.equal((await pushes()).length, 1);
});

test('kept going only by the 10-minute backup: no second push', async () => {
  await story();
  await lastScore(-13);
  await alarm(0);
  await read('backup', live, 5);
  await lastScore(5);
  await alarm(18);
  await alarm(40);
  assert.equal((await pushes()).length, 1);
});

test('no score yet: quiet until 30 minutes past the listed start', async () => {
  await story();
  await alarm(1);
  assert.equal((await pushes()).length, 0, '2:29 PM, listed 2 PM: a late start');
  await alarm(3);
  assert.deepEqual((await pushes()).map((p) => p.message), ['No score since 2:00 PM. No source has read it.']);
});

test("a file still saying not started is read fine, and 30 minutes past the start it's dark (CSB vs Loras, 2026-11-07)", async () => {
  await story();
  // The basketball file at 2:46 PM, read for this game: CSB's, today's, not started.
  const loras = { Game: file('sidearm-not-started-csb-wbball.json') };
  assert.equal(await read('school', loras, 2), 'ignored');
  assert.equal((await marks()).school.failed, 0);
  await alarm(3);
  assert.deepEqual((await pushes()).map((p) => p.message), ['No score since 2:00 PM. gobennies.com: no new score (2:30 PM).']);
});

test('a push that fails is kept with its reason and tried again the next minute', async () => {
  await story();
  await lastScore(-13);
  await db.exec(`update fake.answer set status = 503, content = 'busy'`);
  await alarm(0);
  assert.deepEqual((await db.query('select sent_at, why from private.live_alerts')).rows,
                   [{ sent_at: null, why: 'ntfy answered 503: busy' }]);
  await db.exec(`update fake.answer set status = 200, content = '{"id":"x"}'`);
  await alarm(1);
  await alarm(2);
  // The failed call's record goes back with its error here (a real one still went out): this is the sent one alone.
  assert.equal((await pushes()).length, 1, 'sent the next minute, and nothing after');
  const { rows: [a] } = await db.query('select sent_at, why from private.live_alerts');
  assert.deepEqual(a, { sent_at: new Date(at(1)), why: null });
});

test('the morning report gets each source in order, and the alert', async () => {
  await story();
  await read('push', null, 0, 'certificate expired');
  await read('school', live, 0);
  await read('school', null, 1, 'timed out');
  await lastScore(-13);
  await alarm(14);
  const { rows: [m] } = await db.query('select sources, alerted_at, alert_why from public.live_marks($1)', [[GAME]]);
  assert.deepEqual(m.sources, [
    { name: 'gobennies.com', reads: 2, failed: 1, wrote: 1, why: 'timed out' },
    { name: "SIDEARM's push", reads: 1, failed: 1, wrote: 0, why: 'certificate expired' }]);
  assert.equal(m.alerted_at.toISOString(), at(14));
  assert.equal(m.alert_why, null);
});

test('the service role only', async () => {
  for (const fn of ['public.record_live_read(uuid, text, jsonb, text, timestamptz)',
                    'public.live_backup_turn(uuid[], timestamptz)', 'public.live_marks(uuid[])'])
    for (const role of ['anon', 'authenticated'])
      assert.equal((await db.query(`select has_function_privilege($1, $2, 'execute') as ok`, [role, fn])).rows[0].ok, false,
                   `${fn}: not ${role}`);
});
