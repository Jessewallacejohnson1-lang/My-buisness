// Each live game's own file on its school's site (supabase/migrations/*_school_file_first.sql, BP app
// docs/plans/game-card/issues/21-school-file-first.md). Run: `npm test` in this folder.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { realDatabase } from './fixture.mjs';

const db = await realDatabase();
const game = (await db.query(`insert into public.club_events (title, status, team_ids, source_name, sport, event_date, start_time)
  values ('CSB Hockey vs Lake Forest', 'approved', '{saint-benedict,lake-forest}', 'CSB Athletics', 'Hockey',
          current_date, '2 PM') returning id`)).rows[0].id;
const feeds = async () => (await db.query('select url from public.live_feeds($1)', [[game]])).rows.map((r) => r.url);
const save = (url) => db.query('select public.save_live_feed($1, $2)', [game, url]);

test('a found file is kept for the game', async () => {
  await save('https://gobennies.com/api/livestats?game_id=10289');
  assert.deepEqual(await feeds(), ['https://gobennies.com/api/livestats?game_id=10289']);
});

test('a game not in the list is looked for again after 10 minutes', async () => {
  await save(null);
  assert.deepEqual(await feeds(), [null], 'just looked: not again yet');
  await db.query(`update private.live_feeds set found_at = now() - interval '11 minutes'`);
  assert.deepEqual(await feeds(), [], 'look again');
});

test('only a file on SJU or CSB own site is kept', async () => {
  for (const url of ['https://example.com/api/livestats?game_id=1', 'https://gobennies.com/services/x?game_id=1',
                     'http://gojohnnies.com/api/livestats?game_id=1', 'https://gobennies.com.evil.com/api/livestats?game_id=1'])
    await assert.rejects(save(url), /live_feeds_url_check/, url);
  await save('https://gojohnnies.com/api/livestats?game_id=17791');
  assert.deepEqual(await feeds(), ['https://gojohnnies.com/api/livestats?game_id=17791']);
});

test('the service role only', async () => {
  for (const fn of ['public.live_feeds(uuid[])', 'public.save_live_feed(uuid, text)'])
    for (const role of ['anon', 'authenticated'])
      assert.equal((await db.query(`select has_function_privilege($1, $2, 'execute') as ok`, [role, fn])).rows[0].ok, false,
                   `${fn}: not ${role}`);
});
