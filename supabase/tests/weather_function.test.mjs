// The weather edge function itself (supabase/functions/weather/index.ts, BP app docs/plans/school-activities,
// ticket 08): WJON's lists from last winter read to the right schools and kinds, the feeds' days, when it reads, and
// one wake with the database and the web faked. Node 24 imports the TypeScript as it is. Run: `npm test` here.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { parseList, dayOf, feedPosts, listDue, stormy, alertsDue, readAlerts, run } from '../functions/weather/index.ts';

const wjon = JSON.parse(readFileSync(new URL('wjon-lists.json', import.meta.url), 'utf8'));
const read = (day) => Object.fromEntries(parseList(wjon.posts[day]).lines.map((l) => [l.district, `${l.kind}: ${l.title}`]));

test("last winter's lists: each of our schools with its kind, and nobody else's", () => {
  assert.deepEqual(read('2025-11-26'), { sartell: 'closed: No School', 'sauk-rapids-rice': 'closed: No School' });
  assert.deepEqual(read('2025-12-09'), {
    sartell: 'early: Out 2 Hours Early', 'st-cloud': 'early: Out 2 Hours Early',
    'sauk-rapids-rice': 'early: Out 2 Hours Early', 'catholic-community-schools': 'early: Out 2 Hours Early',
    holdingford: 'early: Out Early', rocori: 'early: Out Early', 'eden-valley-watkins': 'early: Out Early',
  }, '"closing at 12:30 p.m.", "closing early today", "closing at Noon" are out early, not closed');
  assert.deepEqual(read('2025-12-10'), {
    royalton: 'closed: No School', 'catholic-community-schools': 'late: 2 Hours Late',
    'eden-valley-watkins': 'late: 2 Hours Late', rocori: 'late: 2 Hours Late', 'st-johns-prep': 'late: 2 Hours Late',
    'st-cloud': 'late: 2 Hours Late', sartell: 'late: 2 Hours Late', 'sauk-rapids-rice': 'late: 2 Hours Late',
  }, 'Royalton\'s "It is not an E-learning day" is closed; the hours come from the heading');
  assert.deepEqual(read('2025-12-18'), { 'eden-valley-watkins': 'early: Out Early' }, 'Paynesville is not ours');
  assert.deepEqual(read('2026-01-06 5:49 AM'), {
    'sauk-rapids-rice': 'late: 2 Hours Late', sartell: 'late: 2 Hours Late', 'st-cloud': 'late: 2 Hours Late',
  });
  assert.deepEqual(read('2026-01-06'), {
    'catholic-community-schools': 'closed: No School', 'sauk-rapids-rice': 'elearning: E-Learning Day',
    sartell: 'elearning: E-Learning Day', 'st-cloud': 'closed: No School',
  }, '"St. Cloud Area" under Closed; "(e-learning)" under Closed is e-learning');
  assert.deepEqual(read('2026-01-23'), {
    'catholic-community-schools': 'closed: No School', 'eden-valley-watkins': 'elearning: E-Learning Day',
    holdingford: 'elearning: E-Learning Day', kimball: 'elearning: E-Learning Day', rocori: 'elearning: E-Learning Day',
    'st-cloud': 'elearning: E-Learning Day', 'sauk-rapids-rice': 'elearning: E-Learning Day',
    sartell: 'elearning: E-Learning Day',
  }, '"will be closed. Cathedral will move to an e-learning day" is closed; St. Cloud Technical College is not ours');
  assert.deepEqual(read('2026-01-26'), {
    'eden-valley-watkins': 'late: 2 Hours Late', 'st-johns-prep': 'late: 2 Hours Late',
    'sauk-rapids-rice': 'late: 2 Hours Late', sartell: 'late: 2 Hours Late', 'st-cloud': 'late: 2 Hours Late',
  });
  assert.deepEqual(read('2026-02-19'), { 'eden-valley-watkins': 'late: 2 Hours Late', rocori: 'late: 2 Hours Late' });
  assert.deepEqual(read('2026-04-02'), {
    'eden-valley-watkins': 'early: Out Early', 'catholic-community-schools': 'late: 2 Hours Late',
    'st-cloud': 'late: 2 Hours Late', sartell: 'late: 2 Hours Late', 'sauk-rapids-rice': 'late: 2 Hours Late',
  });
  for (const day of Object.keys(wjon.posts)) assert.deepEqual(parseList(wjon.posts[day]).unread, [], day);
});

test('a line for one of ours with no kind fails the read; a school only named inside a line is not ours', () => {
  const page = (lines) => `<article id="post-1"><p>UNDATED ( WJON News ) -- We have some announcements:</p>${lines}
    <p>If you have a weather-related announcement, call our cancellations line.</p></article>`;
  assert.deepEqual(parseList(page('<p>SCHOOLS:</p><p>-- St. Cloud Area Schools</p>')).unread, ['St. Cloud Area Schools']);
  const r = parseList(page('<p>SCHOOLS (CLOSED):</p><p>-- Prince of Peace Lutheran School in St. Cloud</p>' +
    '<p>-- The St. Cloud Area School District</p><p>MISC:</p><p>-- Sartell VFW bingo is cancelled</p>'));
  assert.deepEqual(r.lines.map((l) => [l.district, l.kind]), [['st-cloud', 'closed']]);
  assert.deepEqual(r.unread, []);
});

test("the feeds' days: today's and tomorrow's posts by their titles, the year from when they went up", () => {
  const all = [...feedPosts(wjon.feeds.closings), ...feedPosts(wjon.feeds.weather)];
  const day = (slug) => { const p = all.find((x) => x.link.includes(slug)); return dayOf(p.title, p.posted); };
  assert.equal(day('/local-school-weather-announcements-2/'), '2026-01-26', 'posted 9 PM the night before');
  assert.equal(day('/weather-announcements/'), '2026-02-18', '"For Wednesday, February 18th", no year');
  assert.equal(day('/weather-impacts-local-schools/'), '2025-12-09', 'only in the Weather feed');
  assert.equal(dayOf('Unique Minnesota Restaurant Closing Less Than A Year From Opening', new Date()), null);
  assert.equal(dayOf('Weather Announcements for Thursday, January 1st', new Date('2025-12-31T23:00:00Z')), '2026-01-01');
});

const at = (iso) => new Date(iso);
test('when it reads the list: storm nights and mornings every 15 minutes, otherwise once at 6:15 AM', () => {
  // Nov to Mar is Central Standard Time, UTC-6.
  assert.equal(listDue(at('2026-01-26T02:00:00Z'), true, null), true, '8 PM in a storm');
  assert.equal(listDue(at('2026-01-26T02:10:00Z'), true, '2026-01-26T02:00:00Z'), false, 'not within 13 minutes');
  assert.equal(listDue(at('2026-01-26T02:15:00Z'), true, '2026-01-26T02:00:00Z'), true, '15 minutes on');
  assert.equal(listDue(at('2026-01-26T04:15:00Z'), true, null), false, '10:15 PM: done for the night');
  assert.equal(listDue(at('2026-01-26T11:00:00Z'), true, null), true, '5 AM in a storm');
  assert.equal(listDue(at('2026-01-26T18:00:00Z'), true, null), true, 'noon, for an early dismissal');
  assert.equal(listDue(at('2026-01-26T18:30:00Z'), true, null), false, '12:30 PM');
  assert.equal(listDue(at('2026-01-26T12:00:00Z'), false, null), false, '6 AM with no alert');
  assert.equal(listDue(at('2026-01-26T12:15:00Z'), false, '2026-01-25T12:15:00Z'), true, '6:15 AM, read yesterday');
  assert.equal(listDue(at('2026-01-26T12:30:00Z'), false, '2026-01-26T12:15:00Z'), false, 'read at 6:15 today');
  assert.equal(listDue(at('2026-01-26T12:30:00Z'), false, '2026-01-25T12:15:00Z'), true, '6:15 failed: 6:30 tries');
  assert.equal(listDue(at('2026-01-26T13:00:00Z'), false, null), false, '7 AM with no alert');
  assert.equal(listDue(at('2026-04-02T11:15:00Z'), false, null), true, '6:15 AM in daylight time, UTC-5');
});

test('a storm is a winter alert still out; the alerts are read once an hour', async () => {
  const now = at('2026-01-25T20:00:00Z');
  assert.equal(stormy([{ event: 'Cold Weather Advisory', ends: '2026-01-26T17:00:00Z' }], now), true);
  assert.equal(stormy([{ event: 'Winter Storm Watch', ends: null }], now), true, 'a watch with no end yet');
  assert.equal(stormy([{ event: 'Dense Fog Advisory', ends: '2026-01-26T17:00:00Z' }], now), false);
  assert.equal(stormy([{ event: 'Winter Weather Advisory', ends: '2026-01-25T19:00:00Z' }], now), false, 'over');
  assert.equal(alertsDue(now, { alerts_read_at: '2026-01-25T19:10:00Z' }), false);
  assert.equal(alertsDue(now, { alerts_read_at: '2026-01-25T19:00:00Z' }), true);
  const nws = JSON.stringify({ features: [
    { properties: { event: 'Cold Weather Advisory', status: 'Actual', messageType: 'Alert', onset: 'a', ends: null, expires: 'b' } },
    { properties: { event: 'Winter Storm Watch', status: 'Actual', messageType: 'Cancel', onset: 'a', ends: 'c' } },
    { properties: { event: 'Winter Storm Watch', status: 'Test', messageType: 'Alert', onset: 'a', ends: 'c' } },
  ] });
  let asked;
  const alerts = await readAlerts('MNZ049', async (url) => { asked = url; return nws; });
  assert.equal(asked, 'https://api.weather.gov/alerts/active?zone=MNZ049');
  assert.deepEqual(alerts, [{ event: 'Cold Weather Advisory', onset: 'a', ends: 'b' }], 'a cancel and a test dropped');
});

// The web as it was on the night of Jan 25, 2026, and a database that remembers what it was told.
const web = (posts = { 'local-school-weather-announcements-2': wjon.posts['2026-01-26'] }) => {
  const asked = [];
  const get = async (url) => {
    asked.push(url);
    if (url === 'https://wjon.com/category/closings/feed/') return wjon.feeds.closings;
    if (url === 'https://wjon.com/category/weather/feed/') return wjon.feeds.weather;
    const slug = new URL(url).pathname.replaceAll('/', '');
    if (slug in posts) return posts[slug];
    throw new Error(`wjon.com: HTTP 404 ${url}`);
  };
  return { get, asked };
};
const database = (state) => {
  const calls = [];
  const rpc = async (name, body) => {
    calls.push([name, body]);
    return name === 'weather_state' ? state : null;
  };
  return { rpc, calls };
};
const storm = { zone: 'MNZ049', alerts: [{ event: 'Cold Weather Advisory', onset: null, ends: '2026-01-26T17:00:00Z' }],
                alerts_read_at: '2026-01-26T03:20:00Z', list_read_at: '2026-01-26T03:15:00Z' };

test("9:30 PM Sunday, Jan 25, a Cold Weather Advisory out: Monday's late start goes to the database that night", async () => {
  const { rpc, calls } = database(storm);
  const { get, asked } = web();
  await run(rpc, get, at('2026-01-26T03:30:00Z'));
  assert.deepEqual(asked.slice(0, 2), ['https://wjon.com/category/closings/feed/', 'https://wjon.com/category/weather/feed/'],
                   'alerts read 10 minutes ago: not again');
  assert.equal(asked[2], 'https://wjon.com/local-school-weather-announcements-2/');
  const [, apply] = calls.find(([n]) => n === 'apply_school_closings');
  assert.equal(apply.p_day, '2026-01-26');
  const kennedy = apply.p_closings.find((c) => c.district === 'st-cloud');
  assert.equal(kennedy.kind, 'late');
  assert.equal(kennedy.title, '2 Hours Late');
  assert.deepEqual(kennedy.news, { source_name: 'Kennedy Community School', place_entry_id: 'kennedy-community-school' });
  assert.ok(kennedy.teams.includes('apollo') && kennedy.sources.includes('Kennedy Community School'));
  assert.equal(apply.p_closings.find((c) => c.district === 'sartell').news, null, 'only the town\'s own schools get News');
  assert.deepEqual(calls.at(-1), ['save_weather', { p_town: 'st-joseph-mn', p_list_read: true }]);
});

test('a failure is saved with its reason and nothing is applied; failed alerts still leave the list read', async () => {
  const broken = '<article id="post-9"><p>( WJON News )</p><p>SCHOOLS:</p><p>-- St. Cloud Area Schools</p></article>';
  const one = database(storm);
  await run(one.rpc, web({ 'local-school-weather-announcements-2': broken }).get, at('2026-01-26T03:30:00Z'));
  assert.equal(one.calls.some(([n]) => n === 'apply_school_closings'), false);
  assert.match(one.calls.at(-1)[1].p_error, /can't read: St. Cloud Area Schools/);
  assert.equal(one.calls.some(([, b]) => b?.p_list_read), false, 'not saved as read, so 15 minutes on it tries again');

  const two = database({ ...storm, alerts_read_at: '2026-01-26T02:00:00Z' });
  const { get } = web();
  await run(two.rpc, async (url) => {
    if (url.startsWith('https://api.weather.gov/')) throw new Error('api.weather.gov: HTTP 503');
    return get(url);
  }, at('2026-01-26T03:30:00Z'));
  assert.deepEqual(two.calls[1], ['save_weather', { p_town: 'st-joseph-mn', p_error: 'api.weather.gov: HTTP 503' }]);
  assert.ok(two.calls.some(([n]) => n === 'apply_school_closings'), 'the last alerts read still says storm');
});
