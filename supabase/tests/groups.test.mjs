// Fixed stories for get_groups and group_meetings (supabase/migrations/*_groups.sql), the Search
// tab's Groups shelf and a Group page's one read, on the groups the migrations load, run in PGlite under the live read rules (BP app docs/plans/rsvp-and-groups,
// ticket 05). Run: `npm install && npm test` in this folder.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { realDatabase, people } from './fixture.mjs';

const db = await realDatabase();
await db.exec(`insert into vault.decrypted_secrets values ('google_calendar_key', 'test-key')`);
const ME = '00000000-0000-0000-0000-00000000000a';
const NEIGHBOUR = '00000000-0000-0000-0000-00000000000b';
await people(db, ME, NEIGHBOUR);
// A calendar a migration gave a group would answer the stories' fake Google too.
await db.exec('update public.clubs set calendar_id = null');
const GROUPS = (await db.query(`select count(*)::int as n from public.clubs where status = 'approved'`)).rows[0].n;

async function groups(as) {
  await db.exec(as ? `set role authenticated; set request.jwt.claim.sub = '${as}'` : 'set role anon; reset request.jwt.claim.sub');
  const { rows } = await db.query('select * from public.get_groups()');
  await db.exec('reset role; reset request.jwt.claim.sub');
  return rows;
}
const idOf = async (name) => (await db.query('select id from public.clubs where name = $1', [name])).rows[0].id;
const join_ = (club, user) => db.query('insert into public.club_members (club_id, user_id) values ($1, $2)', [club, user]);
const meetings = async (meets, from) =>
  (await db.query('select public.group_meetings($1::jsonb, $2::date) as m', [JSON.stringify(meets), from])).rows[0].m;

test('only approved groups come back', async () => {
  await db.query("insert into public.clubs (name, status, submitted_by) values ('Waiting', 'pending', $1), ('Turned down', 'rejected', $1)", [ME]);
  const names = (await groups(ME)).map((g) => g.name);
  assert.equal(names.length, GROUPS);
  assert.ok(!names.includes('Waiting') && !names.includes('Turned down'), 'not even the caller\'s own pending one');
  await db.exec("delete from public.clubs where status <> 'approved'");
});

test('the member count counts everyone; joined is the caller\'s own', async () => {
  const lions = await idOf('St. Joseph Lions Club'), book = await idOf('Book Discussion Group');
  await join_(lions, ME);
  await join_(lions, NEIGHBOUR);
  await join_(book, NEIGHBOUR);
  const mine = await groups(ME);
  const lionsRow = mine.find((g) => g.name === 'St. Joseph Lions Club'), bookRow = mine.find((g) => g.name === 'Book Discussion Group');
  assert.deepEqual([lionsRow.member_count, lionsRow.joined], [2, true]);
  assert.deepEqual([bookRow.member_count, bookRow.joined], [1, false]);
  assert.equal(mine[0].name, 'St. Joseph Lions Club', 'most members first');
  await db.exec('delete from public.club_members');
});

test('the public key reads it too: counts, never joined', async () => {
  await join_(await idOf('Laundry Love'), NEIGHBOUR);
  const rows = await groups(null);
  assert.equal(rows.length, GROUPS);
  assert.equal(rows.find((g) => g.name === 'Laundry Love').member_count, 1, 'counted though anon can\'t read memberships');
  assert.ok(rows.every((g) => g.joined === false));
  await db.exec('delete from public.club_members');
});

test("pictures: the group's own first, else where it meets", async () => {
  await db.exec(`
    insert into public.place_photos (entry_id, url, source_url, position, kind, status, hue) values
      ('group-st-joseph-lions-club', 'https://x/lions-2.webp', 'https://e-clubhouse.org/', 1, 'photo', 'live', null),
      ('group-st-joseph-lions-club', 'https://x/lions-1.webp', 'https://e-clubhouse.org/', 0, 'photo', 'live', null),
      ('group-st-joseph-lions-club', 'https://x/old.webp', 'https://e-clubhouse.org/', 2, 'photo', 'retired', null),
      ('group-st-joe-rod-and-gun-club', 'https://x/deer.webp', 'https://stjoerodandgunclub.org/', 0, 'logo', 'live', 31),
      ('resurrection-lutheran-church', 'https://x/church.webp', 'https://rlcstjoe.com/', 0, 'photo', 'live', null);
    insert into public.places (name, lat, lon, family, entry_id, search_logo) values
      ('Legion', 45.5, -94.3, 'business', '328-american-legion-post', '{"url": "https://x/legion.webp", "hue": 25, "chroma": true}');`);
  const rows = Object.fromEntries((await groups(null)).map((g) => [g.name, g]));
  assert.deepEqual(rows['St. Joseph Lions Club'].photos.map((p) => p.url), ['https://x/lions-1.webp', 'https://x/lions-2.webp'],
    'its own live photos, cover first');
  assert.equal(rows['St. Joseph Lions Club'].logo, null);
  assert.deepEqual(rows['St. Joe Rod and Gun Club'].photos, [], 'its place, the Legion, has only a logo');
  assert.deepEqual(rows['St. Joe Rod and Gun Club'].logo, { url: 'https://x/deer.webp', kind: 'logo', hue: 31 }, 'its own logo over the Legion\'s');
  assert.equal(rows['Sons of the American Legion'].logo.url, 'https://x/legion.webp', 'no logo of its own: where it meets');
  assert.deepEqual(rows['Book Discussion Group'].photos.map((p) => [p.url, p.site]), [['https://x/church.webp', 'https://rlcstjoe.com/']]);
  assert.deepEqual([rows['St. Joseph Women of Today'].photos, rows['St. Joseph Women of Today'].logo], [[], null], 'nothing to show: nothing');
  const order = (await groups(null)).map((g) => g.name);
  assert.ok(order.indexOf('St. Joseph Lions Club') < order.indexOf('St. Joe Rod and Gun Club'), 'photos before logos');
  assert.ok(order.indexOf('St. Joe Rod and Gun Club') < order.indexOf('St. Joseph Women of Today'), 'logos before nothing');
  await db.exec('delete from public.place_photos; delete from public.places');
});

test("meetings: the Lions' 1st and 3rd Tuesdays", async () => {
  const m = await meetings([{ what: 'Meeting', days: ['tue'], weeks: [1, 3], time: '18:00' }], '2026-10-18');
  assert.deepEqual(m.map((x) => x.day), ['2026-10-20', '2026-11-03', '2026-11-17'], 'their calendar\'s dates');
  assert.deepEqual(m[0], { what: 'Meeting', day: '2026-10-20', time: '18:00', where: null });
});

test('meetings: rules mixed, soonest first, today counts', async () => {
  const m = await meetings([
    { what: 'Membership meeting', days: ['tue'], weeks: [4], time: '19:00' },
    { what: '500 cards', days: ['wed'], time: '13:30' },
    { what: 'Bingo', days: ['mon'], weeks: [2, 4], time: '18:30' }], '2026-10-21');
  assert.deepEqual(m.map((x) => `${x.day} ${x.what}`),
    ['2026-10-21 500 cards', '2026-10-26 Bingo', '2026-10-27 Membership meeting']);
});

test('meetings: months off, no time, where, and nothing for no rules', async () => {
  const bee = await meetings([{ what: 'Crafting Bee', days: ['sat'], weeks: [1], time: '13:00', months_off: [5, 6, 7, 8, 9, 10] }], '2026-10-18');
  assert.deepEqual(bee.map((x) => x.day), ['2026-11-07', '2026-12-05', '2027-01-02']);
  const summer = await meetings([{ what: 'Stitch and Sip', days: ['wed'], weeks: [4], time: '18:00', months_off: [1, 2, 3, 4, 9, 10, 11, 12] }], '2026-10-18');
  assert.deepEqual(summer, [], 'nothing within 120 days');
  const knights = await meetings([{ what: 'Meeting', days: ['mon'], weeks: [2] },
    { what: 'Parish breakfast', days: ['sun'], weeks: [1], time: '08:30', months_off: [6, 7, 8, 9], where: 'Heritage Hall' }], '2026-10-18');
  assert.deepEqual(knights.map((x) => [x.day, x.time, x.where]),
    [['2026-11-01', '08:30', 'Heritage Hall'], ['2026-11-09', null, null], ['2026-12-06', '08:30', 'Heritage Hall']]);
  assert.deepEqual(await meetings(null, '2026-10-18'), []);
});

test('a mistyped rule costs only itself, never the shelf', async () => {
  const m = await meetings([
    { what: 'Days not a list', days: 'tue', time: '18:00' },
    { what: 'Week not a number', days: ['tue'], weeks: ['first'], time: '18:00' },
    { what: 'Month not a number', days: ['wed'], weeks: [1], time: 1800, months_off: ['june'] },
    'not a rule',
    { what: 'Meeting', days: ['tue'], weeks: [1, 3], time: '18:00' }], '2026-10-18');
  assert.deepEqual(m.map((x) => `${x.day} ${x.what} ${x.time}`), [
    '2026-10-20 Meeting 18:00', '2026-11-03 Meeting 18:00', '2026-11-04 Month not a number null'],
    'days not a list and weeks not numbers give nothing; a month not a number is skipped; a time not text is no time');
  await db.query("update public.clubs set meets = '[{\"days\": \"tue\"}]' where name = 'Laundry Love'");
  assert.equal((await groups(null)).length, GROUPS, 'one bad rule, every group still reads');
});

// A group's calendar (*_group_calendars.sql): read each morning, it stands in for the rule.
const CAL = 'abc123@group.calendar.google.com';
const google = async (status, items) => {
  await db.exec('delete from fake.answer');
  await db.query('insert into fake.answer values ($1, $2)', [status, JSON.stringify({ summary: 'St. Cloud River Runners', items })]);
};
const runners = async () => (await db.query(
  "select calendar, calendar_read_at::text as read_at from public.clubs where name = 'Runners'")).rows[0];

test("calendar: the morning read keeps each run, with its place, through Google's API and the key", async () => {
  await db.query(`insert into public.clubs (name, status, meets, calendar_id, calendar_area)
    values ('Runners', 'approved', '[{"what": "Sunday run", "days": ["sun"], "time": "07:30"}]', $1, 'St. Cloud area')`, [CAL]);
  await google(200, [
    { summary: 'Breakfast Run @ TBD', start: { dateTime: '2026-11-07T06:00:00-06:00' } },
    { summary: 'Coffee Run', location: 'The Local Blend, 19 W Minnesota St, St Joseph, MN 56374, USA',
      start: { dateTime: '2026-11-08T07:30:00-06:00' } },
    { summary: 'Track Workout', location: 'Check Facebook and Strava groups weekly', start: { dateTime: '2026-11-12T17:30:00-06:00' } },
    { summary: 'Breakfast Run @ Kitchenette', start: { dateTime: '2026-11-14T06:00:00-06:00' } },
    { summary: 'Breakfast Run @ Home of Jess and Mark', location: 'TBA', start: { dateTime: '2026-11-21T06:00:00-06:00' } },
    { summary: 'Old Timers Run/Walk', location: "Coborn's Grocery Store", start: { dateTime: '2026-11-24T10:00:00-06:00' } },
    { summary: 'Coffee Run', status: 'cancelled', start: { dateTime: '2026-11-15T07:30:00-06:00' } },
    { summary: 'SCRR Banquet and Awards Ceremony', location: 'TBA', start: { date: '2027-01-23' } }]);
  await db.exec("delete from fake.calls; select private.read_group_calendars('2026-11-02 10:30+00')");
  const { calendar, read_at } = await runners();
  assert.deepEqual(calendar, [
    { what: 'Breakfast Run', day: '2026-11-07', time: '06:00', where: 'St. Cloud area', away: true },
    { what: 'Coffee Run', day: '2026-11-08', time: '07:30', where: 'The Local Blend', away: false },
    { what: 'Track Workout', day: '2026-11-12', time: '17:30', where: 'St. Cloud area', away: true },
    { what: 'Breakfast Run', day: '2026-11-14', time: '06:00', where: 'Kitchenette, St. Cloud area', away: true },
    { what: 'Breakfast Run', day: '2026-11-21', time: '06:00', where: 'St. Cloud area', away: true },
    { what: 'Old Timers Run/Walk', day: '2026-11-24', time: '10:00', where: "Coborn's Grocery Store, St. Cloud area", away: true },
    { what: 'SCRR Banquet and Awards Ceremony', day: '2027-01-23', time: null, where: 'St. Cloud area', away: true }],
    'a called-off run left out; TBD, TBA, "Check Facebook" and a member\'s home name no place; only a location '
    + 'naming St. Joseph is in town (that Coborn\'s is Sauk Rapids\')');
  assert.equal(read_at, '2026-11-02 10:30:00+00');
  const [call] = (await db.query('select uri, headers from fake.calls')).rows;
  assert.equal(call.uri, 'https://www.googleapis.com/calendar/v3/calendars/abc123%40group.calendar.google.com/events'
    + '?singleEvents=true&orderBy=startTime&maxResults=250&timeZone=America%2FChicago'
    + '&timeMin=2026-11-02T10:30:00Z&timeMax=2027-03-02T10:30:00Z');
  assert.equal(call.headers, '{"(X-goog-api-key,test-key)"}');
});

test('calendar: a failed read keeps the last good copy', async () => {
  const before = await runners();
  await google(403, []);
  await db.exec("select private.read_group_calendars('2026-11-03 10:30+00')");
  assert.deepEqual(await runners(), before);
});

test('Coming up: from now on, the next 3 or every one through this weekday next week; an empty calendar shows none', async () => {
  // Days from today in Chicago, as get_groups counts them. 00:00 today has started; untimed today hasn't ended.
  await db.exec(`update public.clubs set calendar = (
      select jsonb_agg(jsonb_build_object('what', 'Run', 'day', to_char((now() at time zone 'America/Chicago')::date + n, 'YYYY-MM-DD'),
                                          'time', t, 'where', null) order by n, t)
      from (values (-1, '07:30'), (0, '00:00'), (0, null), (1, '07:30'), (2, '07:30'), (3, '07:30'), (5, '07:30'),
                   (6, '07:30'), (7, '07:30'), (9, '07:30'), (12, '07:30')) v (n, t))
    where name = 'Runners';
    insert into public.clubs (name, status, calendar_id, calendar) values
      ('Quiet club', 'approved', 'q@group.calendar.google.com', (
        select jsonb_agg(jsonb_build_object('what', 'Meeting', 'day', to_char((now() at time zone 'America/Chicago')::date + n, 'YYYY-MM-DD'),
                                            'time', null, 'where', null) order by n)
        from unnest(array[10, 20, 30, 40]) n)),
      ('Empty club', 'approved', 'e@group.calendar.google.com', '[]'),
      ('Broken club', 'approved', 'b@group.calendar.google.com', '[{"what": "Bad", "day": "2026-13-45"}, {"what": "No day"},
        {"what": "Bad time", "day": "2099-01-01", "time": "99:99"}, 7, {"what": "Good", "day": "2099-01-02", "time": "09:00"}]');
    insert into public.clubs (name, status, meets) values
      ('Weekly club', 'approved', jsonb_build_array(jsonb_build_object('what', 'Meeting',
        'days', jsonb_build_array(to_char((now() at time zone 'America/Chicago')::date, 'dy')), 'time', '00:00')));`);
  const rows = Object.fromEntries((await groups(null)).map((g) => [g.name, g]));
  const ahead = (g) => rows[g].meetings.map((m) => Math.round((Date.parse(m.day) - Date.parse(rows['Quiet club'].meetings[0].day)) / 864e5) + 10);
  assert.deepEqual(ahead('Runners'), [0, 1, 2, 3, 5, 6, 7],
    'seven this week: all of them, next Sunday too; not yesterday\'s, nor today\'s that has started');
  assert.deepEqual(ahead('Quiet club'), [10, 20, 30], 'one a week or less: the next 3');
  assert.deepEqual(ahead('Weekly club'), [7, 14, 21], 'a rule\'s meeting today that has started is gone too');
  assert.deepEqual(rows['Empty club'].meetings, [], 'read, and nothing on it: no rule stands in');
  assert.deepEqual(rows['Broken club'].meetings.map((m) => m.what), ['Bad time', 'Good'],
    'a broken day costs only itself, never the list; a broken time reads as no time');
  await db.exec("delete from public.clubs where name in ('Runners', 'Quiet club', 'Empty club', 'Broken club', 'Weekly club')");
});
