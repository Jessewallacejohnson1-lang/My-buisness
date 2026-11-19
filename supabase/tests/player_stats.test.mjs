// Each player's stats on a college basketball game's page (supabase/migrations/*_player_stats.sql, BP app
// docs/plans/game-card/issues/35-player-stats.md), run in PGlite on SIDEARM's own file of CSB 54, Simpson 61
// (2026-11-14, sidearmstats.com/csb/wbball): the whole file's player lines reach club_events.player_stats, the host
// first and most points first, from the school's file and the backup but never from a push. Run: `npm test` here.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { realDatabase } from './fixture.mjs';

const file = JSON.parse(readFileSync(new URL('sidearm-final-csb-wbball-simpson.json', import.meta.url), 'utf8'));
// The school's file as the live-scores function writes it: the Game, and the Stats.
const whole = (game = {}, stats = file.Stats) => ({ Game: { ...file.Game, ...game }, Stats: stats });

const db = await realDatabase();
const GAME = (await db.query(`insert into public.club_events
  (title, status, team_ids, source_name, sport, event_date, start_time)
  values ('CSB Basketball vs Simpson', 'approved', '{saint-benedict,simpson}', 'CSB Athletics', 'Basketball',
          '2026-11-14', '3 PM') returning id`)).rows[0].id;
const at = (n = 0) => new Date(Date.parse('2026-11-14T22:30:00Z') + n * 60_000).toISOString();
const read = async (source, game, minute = 0) =>
  (await db.query('select public.record_live_read($1, $2, $3, null, $4) r', [GAME, source, game, at(minute)])).rows[0].r;
const stats = async () => (await db.query('select player_stats s from public.club_events where id = $1', [GAME])).rows[0].s;
const fresh = () => db.exec(`delete from private.live_reads;
  update public.club_events set live_score = null, final_score = null, scoring_plays = null, player_stats = null`);

test("the school's file: both teams' lines, ours first, most points first, the roster's names, and the totals", async () => {
  await fresh();
  await read('school', whole());
  const [ours, theirs] = await stats();
  assert.equal(ours.rows.length, 9);
  assert.equal(theirs.rows.length, 11);
  assert.deepEqual(ours.rows[0], { uni: '5', name: 'C. Goodman', pos: 'G', pts: 12, reb: ours.rows[0].reb,
                                   ast: ours.rows[0].ast, fg: ours.rows[0].fg, tp: ours.rows[0].tp });
  assert.deepEqual(theirs.rows.slice(0, 2).map((r) => [r.name, r.pts]), [['T. Hansen', 16], ['E. Anderson', 14]]);
  assert.deepEqual(ours.total, { pts: 54, reb: 34, ast: 15, fg: '18-58', tp: '7-29' });
  assert.deepEqual(theirs.total, { pts: 61, reb: 42, ast: 13, fg: '23-56', tp: '6-17' });
  // Points never go up the list.
  for (const t of [ours, theirs]) t.rows.slice(1).forEach((r, i) => assert.ok(r.pts <= t.rows[i].pts));
});

test('a tie keeps the file\'s order: the two 6s, then the three 5s, as SIDEARM lists them', async () => {
  await fresh();
  await read('school', whole());
  const [ours] = await stats();
  assert.deepEqual(ours.rows.filter((r) => r.pts === 6).map((r) => r.uni), ['14', '34']);
  assert.deepEqual(ours.rows.filter((r) => r.pts === 5).map((r) => r.uni), ['1', '10', '25']);
});

test('a visiting game puts ours first all the same', async () => {
  await fresh();
  const swapped = { HomeTeam: file.Game.VisitingTeam, VisitingTeam: file.Game.HomeTeam };
  await read('school', whole(swapped, { HomeTeam: file.Stats.VisitingTeam, VisitingTeam: file.Stats.HomeTeam }));
  assert.equal((await stats())[0].total.pts, 54);
});

test('a blank or a dash before tip-off reads 0, and a missing name falls back to the line\'s own, cased', async () => {
  await fresh();
  const odd = structuredClone(file.Stats);
  const first = odd.HomeTeam.PlayerGroups.Players.Values[0];
  Object.assign(first, { Points: '-', TotalRebounds: '', Fgam: null });
  odd.HomeTeam.Players = [];
  await read('school', whole({}, odd));
  const row = (await stats())[0].rows.find((r) => r.uni === '1');
  assert.deepEqual([row.name, row.pts, row.reb, row.fg], ['L. Arnold', 0, 0, '0-0']);
});

test("another game's file, a push, and a file with no players write nothing", async () => {
  await fresh();
  assert.equal(await read('school', whole({ Date: '11/13/2026' })), 'failed');
  await read('push', { Game: file.Game });
  await read('school', whole({}, { HomeTeam: {}, VisitingTeam: {} }));
  assert.equal(await stats(), null);
});

test("the backup held behind the school's file keeps the school's stats", async () => {
  await fresh();
  await read('school', whole());
  const behind = structuredClone(file.Stats);
  behind.HomeTeam.Totals.Values.Points = '40';
  assert.equal(await read('backup', whole({}, behind), 1), 'held');
  assert.equal((await stats())[0].total.pts, 54);
});

test('stats that can\'t be read never cost the score', async () => {
  await fresh();
  await read('school', whole({}, { HomeTeam: { PlayerGroups: { Players: { Values: 'oops' } } }, VisitingTeam: 7 }));
  const card = (await db.query('select final_score, live_score from public.club_events where id = $1', [GAME])).rows[0];
  assert.ok(card.final_score || card.live_score);
  assert.equal(await stats(), null);
});
