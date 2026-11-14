// Fixed stories for a school closing from WJON's list (supabase/migrations/*_weather_tracker.sql, BP app
// docs/plans/school-activities, ticket 08): which Events it calls off (Jesse, 2026-11-13: District 742's own rule),
// the town's own schools' News, a change of kind, a closing taken back, and the 8:00 email's tracker lines.
// PGlite, like the others: `npm install && npm test` in this folder.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { realDatabase, people } from './fixture.mjs';
import { townDay } from './town_day.mjs';

const ME = '00000000-0000-0000-0000-00000000000a';
const NEIGHBOUR = '00000000-0000-0000-0000-00000000000b';
const db = await realDatabase();
await people(db, ME, NEIGHBOUR);
const DAY = townDay(2);
const POST = 'https://wjon.com/minnesota-school-delay-announcement/';

// What the edge function sends for a line (supabase/functions/weather/index.ts, DISTRICTS).
const ST_CLOUD = { district: 'st-cloud', teams: ['apollo', 'tech', 'kennedy', 'apollo-cathedral'],
  sources: ['Apollo High School', 'Tech High School', 'Kennedy Community School'],
  news: { source_name: 'Kennedy Community School', place_entry_id: 'kennedy-community-school' } };
const SARTELL = { district: 'sartell', teams: ['sartell'], sources: ['Sartell High School'], news: null };
const line = (d, kind, title) => ({ ...d, kind, title, words: `${d.district} ${kind}` });
const apply = async (closings, day = DAY) =>
  (await db.query('select public.apply_school_closings($1, $2, $3) r', [day, POST, JSON.stringify(closings)])).rows[0].r;

const event = async (title, f = {}) => (await db.query(
  `insert into public.club_events (title, status, event_date, start_time, source_name, team_ids, submitted_by, all_day)
   values ($1, 'approved', $2, $3, $4, $5, $6, $7) returning id`,
  [title, f.day ?? DAY, 'time' in f ? f.time : '7 PM', f.source ?? null, f.teams ?? null, f.by ?? null, f.allDay ?? false])).rows[0].id;
const off = async (ids) => (await db.query(
  `select id from public.club_events where id = any($1) and cancelled_at is not null`, [ids])).rows.map((r) => r.id);
const news = async () => (await db.query(`select title, blurb, category, source_name, place_entry_id, status,
  starts_at = ($1::date)::timestamp at time zone 'America/Chicago' as on_its_day, ends_on = $1::date as ends_on_its_day
  from public.board_items where source_url = $2 order by title`, [DAY, POST])).rows;
const clean = () => db.exec(`delete from private.school_closings; delete from public.club_events;
  delete from public.board_items; delete from public.event_rsvps;`);

test("closed: the district's Events that day, home, away, co-op and all-day; nobody else's, no other day's", async () => {
  await clean();
  const club = await event('Kennedy Chess Club', { source: 'Kennedy Community School', time: '3 PM' });
  const fair = await event('Kennedy Book Fair', { source: 'Kennedy Community School', time: null, allDay: true });
  const away = await event('Sartell Girls Hockey vs Tech', { source: 'Sartell High School', teams: ['sartell', 'tech'] });
  const coop = await event('Apollo-Cathedral Boys Swim vs Brainerd', { teams: ['apollo-cathedral', 'brainerd'] });
  const other = await event('Sartell Girls Hockey vs Sauk Rapids-Rice', { source: 'Sartell High School',
                                                                          teams: ['sartell', 'sauk-rapids-rice'] });
  const tomorrow = await event('Kennedy Chess Club', { source: 'Kennedy Community School', day: townDay(3) });
  const own = await event('Pickup basketball at Kennedy', { source: 'Kennedy Community School', by: NEIGHBOUR });

  const r = await apply([line(ST_CLOUD, 'closed', 'No School')]);
  assert.deepEqual((await off([club, fair, away, coop, other, tomorrow, own])).sort(), [club, fair, away, coop].sort());
  assert.deepEqual(r, { closings: 1, news: 1, called_off: 4, brought_back: 0 });
  const { rows } = await db.query('select distinct called_off_by from public.club_events where cancelled_at is not null');
  assert.deepEqual(rows, [{ called_off_by: 'st-cloud' }]);
  const dayName = new Date(`${DAY}T12:00:00Z`).toLocaleDateString('en-US', { weekday: 'long', month: 'short', day: 'numeric', timeZone: 'UTC' });
  assert.deepEqual(await news(), [{ title: 'No School', blurb: dayName,
    category: 'school', source_name: 'Kennedy Community School', place_entry_id: 'kennedy-community-school',
    status: 'published', on_its_day: true, ends_on_its_day: true }], 'one News card on its day, with the day');
});

test('out early: only Events from noon on; late and e-learning call off nothing; only our own schools get News', async () => {
  await clean();
  const morning = await event('Kennedy Coffee with the Principal', { source: 'Kennedy Community School', time: '8:30 AM' });
  const noTime = await event('Kennedy Spirit Day', { source: 'Kennedy Community School', time: null });
  const after = await event('Tech Wrestling vs Rocori', { source: 'Tech High School', teams: ['tech', 'rocori'], time: '5 PM' });
  const sartell = await event('Sartell One Act Play', { source: 'Sartell High School', time: '7 PM' });

  await apply([line(ST_CLOUD, 'early', 'Out 2 Hours Early'), line(SARTELL, 'late', '2 Hours Late')]);
  assert.deepEqual(await off([morning, noTime, after, sartell]), [after]);
  assert.deepEqual((await news()).map((n) => [n.source_name, n.title]),
                   [['Kennedy Community School', 'Out 2 Hours Early']], 'Sartell is not the town\'s own school');

  await clean();
  const game = await event('Apollo Girls Basketball vs Sartell', { source: 'Apollo High School', teams: ['apollo', 'sartell'] });
  await apply([line(ST_CLOUD, 'elearning', 'E-Learning Day'), line(SARTELL, 'late', '2 Hours Late')]);
  assert.deepEqual(await off([game]), []);
  assert.deepEqual((await news()).map((n) => n.title), ['E-Learning Day']);
});

test('a game moved to another day is no longer the closing\'s; one kept on by hand stays on', async () => {
  await clean();
  const moved = await event('Tech Boys Hockey vs Sartell', { source: 'Tech High School', teams: ['tech', 'sartell'] });
  const kept = await event('Kennedy Winter Concert', { source: 'Kennedy Community School' });
  await apply([line(ST_CLOUD, 'closed', 'No School')]);
  // Its schedule moves it to a make-up day, the way apply_judged writes a re-read: new date, cancelled_at = null.
  await db.query(`update public.club_events set event_date = $2, cancelled_at = null where id = $1`, [moved, townDay(5)]);
  await db.query(`update public.club_events set called_off_by = 'kept', cancelled_at = null where id = $1`, [kept]);
  await apply([line(ST_CLOUD, 'closed', 'No School')]);
  assert.deepEqual(await off([moved, kept]), []);
  const { rows } = await db.query('select called_off_by from public.club_events where id = $1', [moved]);
  assert.equal(rows[0].called_off_by, null);
});

test("its own source re-reading it the same morning doesn't bring a called-off Event back", async () => {
  await clean();
  const game = await event('Tech Boys Hockey vs Sartell', { source: 'Tech High School', teams: ['tech', 'sartell'] });
  await apply([line(ST_CLOUD, 'closed', 'No School')]);
  // The 6:05 AM league read still lists it: apply_judged writes cancelled_at = null, and restores a cancelled one.
  await db.query('update public.club_events set cancelled_at = null where id = $1', [game]);
  await db.query(`select public.apply_judged('[]', '[]', '[]', '[]', '[]', $1)`, [JSON.stringify([game])]);
  assert.deepEqual(await off([game]), [game]);
  // The next read of the same list calls off nothing twice.
  assert.equal((await apply([line(ST_CLOUD, 'closed', 'No School')])).called_off, 0);
});

test('Jan 6: a late start that becomes a closing archives its News and calls the day off', async () => {
  await clean();
  const game = await event('Apollo Boys Basketball vs Sauk Rapids-Rice', { teams: ['apollo', 'sauk-rapids-rice'] });
  await apply([line(ST_CLOUD, 'late', '2 Hours Late')]);
  assert.deepEqual(await off([game]), []);
  await apply([line(ST_CLOUD, 'closed', 'No School')]);
  assert.deepEqual(await off([game]), [game]);
  assert.deepEqual((await news()).map((n) => [n.title, n.status]), [['2 Hours Late', 'archived'], ['No School', 'published']]);
});

test('the same kind with new hours: the News says the new ones', async () => {
  await clean();
  await apply([line(ST_CLOUD, 'late', '1 Hour Late')]);
  await apply([line(ST_CLOUD, 'late', '2 Hours Late')]);
  assert.deepEqual((await news()).map((n) => [n.title, n.status]), [['1 Hour Late', 'archived'], ['2 Hours Late', 'published']]);
});

test('a closing gone from the list brings its Events back, and only those it called off', async () => {
  await clean();
  const club = await event('Kennedy Chess Club', { source: 'Kennedy Community School' });
  const dropped = await event('Apollo Boys Swim vs Willmar', { source: 'Apollo High School', teams: ['apollo', 'willmar'] });
  await db.query('update public.club_events set cancelled_at = now() where id = $1', [dropped]);
  await apply([line(ST_CLOUD, 'closed', 'No School'), line(SARTELL, 'closed', 'No School')]);
  const r = await apply([line(SARTELL, 'closed', 'No School')]);
  assert.equal(r.brought_back, 1);
  assert.deepEqual(await off([club, dropped]), [dropped], 'cancelled by its own source before: still cancelled');
  assert.deepEqual((await news()).map((n) => [n.title, n.status]), [['No School', 'archived']]);
  // Back on the list: the same News comes back, not a second one.
  await apply([line(ST_CLOUD, 'closed', 'No School')]);
  assert.deepEqual((await news()).map((n) => [n.title, n.status]), [['No School', 'published']]);
});

test("someone Going is told in Notifications, as for any cancel", async () => {
  await clean();
  const game = await event('Tech Girls Basketball vs Sartell', { source: 'Tech High School', teams: ['tech', 'sartell'] });
  await db.query('insert into public.event_rsvps (event_id, user_id) values ($1, $2)', [game, ME]);
  await apply([line(ST_CLOUD, 'closed', 'No School')]);
  await db.exec(`set role authenticated; select set_config('request.jwt.claims', '${JSON.stringify({ sub: ME })}', false)`);
  try {
    const rows = (await db.query('select card from public.get_my_changes()')).rows;
    assert.deepEqual(rows.map((r) => [r.card.id, r.card.cancelled]), [[game, true]]);
  } finally {
    await db.exec('reset role; reset request.jwt.claims');
  }
});

test('only the server may call the tracker: a signed-in neighbour is refused', async () => {
  await db.exec(`set role authenticated; select set_config('request.jwt.claims', '${JSON.stringify({ sub: ME })}', false)`);
  try {
    await assert.rejects(db.query(`select public.apply_school_closings($1, 'x', '[]')`, [DAY]), /permission denied/);
    await assert.rejects(db.query(`select public.claim_weather('st-joseph-mn')`), /permission denied/);
    await assert.rejects(db.query(`select public.save_weather('st-joseph-mn')`), /permission denied/);
  } finally {
    await db.exec('reset role; reset request.jwt.claims');
  }
});

test("the tracker's claim and state, and the 8:00 email's lines when it stops reading or fails", async () => {
  const claim = async (now) => (await db.query(`select public.claim_weather('st-joseph-mn', $1) s`, [now])).rows[0].s;
  assert.equal((await claim('2026-11-16 13:30:00+00')).zone, 'MNZ049');
  assert.equal(await claim('2026-11-16 13:34:00+00'), null, 'held by the run 4 minutes ago');
  const state = () => claim('2026-11-16 23:00:00+00');
  const lines = async (now) => (await db.query('select private.morning_problems($1) p', [now])).rows
    .map((r) => r.p).filter((p) => p.includes('weather tracker'));
  await db.exec(`update private.weather set began_at = '2026-11-16 13:00:00+00'`);
  assert.deepEqual(await lines('2026-11-16 14:00:00+00'), [], 'never read yet: it has only just begun');
  assert.deepEqual(await lines('2026-11-16 16:30:00+00'), ['The weather tracker has never read the weather.']);

  await db.query(`select public.save_weather('st-joseph-mn', $1, true, null, '2026-11-16 13:45:00+00')`,
                 [JSON.stringify([{ event: 'Winter Storm Watch', onset: null, ends: null }])]);
  const s = await state();
  assert.equal(s.alerts[0].event, 'Winter Storm Watch');
  await db.exec(`update private.weather set claimed_at = null`);
  assert.equal(s.list_read_at, s.alerts_read_at);
  assert.deepEqual(await lines('2026-11-16 14:00:00+00'), []);

  await db.query(`select public.save_weather('st-joseph-mn', p_error => 'api.weather.gov: HTTP 503',
                                              p_now => '2026-11-16 15:00:00+00')`);
  assert.equal((await state()).alerts[0].event, 'Winter Storm Watch', 'a failure keeps the last alerts');
  await db.exec(`update private.weather set claimed_at = null`);
  assert.deepEqual(await lines('2026-11-16 18:00:00+00'), [
    "The weather tracker hasn't read the weather since Nov 16 7:45 AM.",
    'The weather tracker failed at Nov 16 9:00 AM: api.weather.gov: HTTP 503',
  ]);
  await db.exec(`insert into cron.job values (9, 'weather');
    insert into cron.job_run_details values (9, 'failed', E'weather answered 401: {"msg":"Invalid JWT"}', '2026-11-16 17:30:00+00');`);
  assert.equal((await lines('2026-11-16 18:00:00+00'))[0],
               'The weather tracker failed 1 time since yesterday: weather answered 401: {"msg":"Invalid JWT"}');
});
