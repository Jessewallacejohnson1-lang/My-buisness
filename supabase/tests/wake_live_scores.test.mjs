// Fixed stories for the every-minute live-scores job (supabase/migrations/*_live_scores_fail_out_loud.sql, BP app
// docs/plans/loopholes, ticket 05), run in PGlite with the fixture's stand-in for pgsql-http. A refused call has to
// fail the run, so pg_cron records it. Run: `npm test` in this folder.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { realDatabase } from './fixture.mjs';

const db = await realDatabase();
const wake = () => db.query('select private.wake_live_scores()');
const story = async (game, status, content) => {
  await db.exec('delete from fake.calls; delete from fake.answer; delete from public.club_events;');
  // A game that kicked off an hour ago, in the Town's time: right now reads an hour ahead for one hour on the night
  // the clocks fall back, past the 15 minutes' lead the job allows.
  if (game) await db.exec(`insert into public.club_events (title, status, team_ids, source_name, sport, event_date, start_time)
    values ('SJU Football vs Concordia', 'approved', '{saint-johns,concordia}', 'SJU Athletics', 'Football',
            ((now() - interval '1 hour') at time zone 'America/Chicago')::date,
            to_char((now() - interval '1 hour') at time zone 'America/Chicago', 'FMHH12:MI am'))`);
  await db.query('insert into fake.answer (status, content) values ($1, $2)', [status, content]);
};

test('no game on: the function is not called', async () => {
  await story(false, 401, 'nope');
  await wake();
  assert.equal((await db.query('select count(*)::int n from fake.calls')).rows[0].n, 0);
});

test('a game on and the function listening: the run succeeds', async () => {
  await story(true, 202, '{"games":1}');
  await wake();
  assert.equal((await db.query('select count(*)::int n from fake.calls')).rows[0].n, 1);
});

test('the login check back on: the run fails with the status and what the function said', async () => {
  await story(true, 401, '{"code":401,"message":"Missing authorization header"}');
  await assert.rejects(wake(), /live-scores answered 401: \{"code":401,"message":"Missing authorization header"\}/);
});

test('the function erroring: the run fails', async () => {
  await story(true, 500, '{"error":"misconfigured"}');
  await assert.rejects(wake(), /live-scores answered 500/);
});
