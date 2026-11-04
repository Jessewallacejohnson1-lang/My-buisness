// Fixed stories for the Town feed function (supabase/migrations/*_town_feed*.sql), run in
// PGlite: Postgres compiled to WASM, so no Docker. Run: `npm install && npm test` in this
// folder.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { realDatabase, migrations, people, adminClaims } from './fixture.mjs';
import { townDay } from './town_day.mjs';
import { CARD_KEYS } from './event_card.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const db = await realDatabase();
const ADMIN = await adminClaims(db);
// The two functions as they were before feed-load (20261102155729_feed_once_per_open.sql), kept under
// other names so the stories can hold the new ones to them: the whole feed with its own body, and the
// Event of the day that worked it all out.
const before = (file, fn, as) => readFileSync(join(migrations, file), 'utf8')
  .match(new RegExp(`create or replace function public\\.${fn}\\([\\s\\S]*?\\n\\$\\$;`))[0]
  .replace(`public.${fn}(`, `public.${as}(`).replaceAll('public.get_town_feed(', 'public.old_town_feed(');
await db.exec(before('20261102005713_post_screen_feed.sql', 'get_town_feed', 'old_town_feed'));
await db.exec(before('20261026132204_activity_follow_lift.sql', 'get_event_of_the_day', 'old_event_of_the_day'));
// The feed and the Event of the day as they read before codebase-health-2 03, for the stories about what an
// Event row says: each read's own answer, its Event card unpacked into the columns the card replaced (news' and
// posts' own as they come, with the old zeros). It reads the answer only; what each read sends beside the card is
// the card stories' (at the end).
const CARD_COLUMNS = `title text, event_date date, start_time text, location text, image_url text, category text,
  club_name text, source_name text, end_at timestamptz, all_day boolean, created_at timestamptz, going_count int,
  going boolean, cancelled boolean, friends_going jsonb, place_picture jsonb, description text, game jsonb, what text,
  source_url text, host_picture jsonb`;
const OLD_COLUMNS = `id uuid, title text, event_date date, start_time text, location text, image_url text, category text,
  club_name text, source_name text, end_at timestamptz, all_day boolean, created_at timestamptz, going_count int,
  rsvpd boolean, recurrence text, leaves_at timestamptz, reason text, reason_name text, score jsonb, heart_count int,
  hearted boolean, saved boolean, cancelled boolean, friends_going jsonb, place_picture jsonb, description text,
  club_id uuid, in_club boolean, game jsonb, what text`;
// An Event's from its card, else (news and posts) the row's own.
const either = (col) => (eotd) => (eotd ? `c.${col}` : `coalesce(c.${col}, f.${col})`);
const oldRow = (eotd) => `f.id, ${either('title')(eotd)}, c.event_date, c.start_time, ${either('location')(eotd)},
  ${either('image_url')(eotd)}, c.category, c.club_name, ${either('source_name')(eotd)}, c.end_at,
  coalesce(c.all_day, false), ${either('created_at')(eotd)}, coalesce(c.going_count, 0), coalesce(c.going, false),
  f.recurrence, f.leaves_at, f.reason, f.reason_name, f.score, f.heart_count, f.hearted, f.saved,
  coalesce(c.cancelled, false), coalesce(c.friends_going, '[]'), ${either('place_picture')(eotd)},
  ${either('description')(eotd)}, f.club_id, f.in_club, c.game, c.what`;
await db.exec(`
  create function public.flat_town_feed(p_now timestamptz default now(), p_news boolean default false,
                                        p_later boolean default false)
  returns table (${OLD_COLUMNS}, kind text, source_url text, host_picture jsonb, poster jsonb)
  language sql stable as $$
    select ${oldRow(false)}, f.kind, coalesce(c.source_url, f.source_url), c.host_picture, f.poster
    from public.get_town_feed(p_now, p_news, p_later) with ordinality f
    left join lateral jsonb_to_record(f.card) as c(${CARD_COLUMNS}) on true
    order by f.ordinality
  $$;
  create function public.flat_event_of_the_day(p_now timestamptz default now())
  returns table (${OLD_COLUMNS})
  language sql stable as $$
    select ${oldRow(true)}
    from public.get_event_of_the_day(p_now) with ordinality f
    left join lateral jsonb_to_record(f.card) as c(${CARD_COLUMNS}) on true
    order by f.ordinality
  $$;`);
const CITY = 'City of St. Joseph';
const ME = '00000000-0000-0000-0000-00000000000a';

async function reset() {
  await db.exec(`reset role; delete from public.feed_actions;
                 refresh materialized view private.feed_item_stats;
                 delete from public.event_rsvps; delete from public.club_events;
                 delete from public.event_saves; delete from public.event_likes;
                 delete from public.town_profiles; delete from private.friendships;
                 delete from private.blocks; delete from public.club_members;
                 delete from public.clubs; delete from public.sources;
                 delete from public.board_items; delete from public.feed_mutes; delete from public.town_follows;
                 -- The stories name their own teams; the activities stay, matched by their ids.
                 set session_replication_role = replica; delete from public.teams; reset session_replication_role;
                 reset request.jwt.claim.sub; reset request.jwt.claims;`);
}

// Created well before the stories' dates, so nothing is new unless a story says so.
async function add(title, date, more = {}) {
  const row = { source_name: CITY, start_time: null, end_at: null, all_day: false,
                shows_from: null, status: 'approved', submitted_by: null, category: null,
                created_at: '2026-09-01 12:00-05', ...more };
  if (row.submitted_by) await people(db, row.submitted_by);
  const { rows } = await db.query(
    `insert into public.club_events (title, event_date, source_name, start_time, end_at,
       all_day, shows_from, status, submitted_by, category, created_at)
     values ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11) returning id`,
    [title, date, row.source_name, row.start_time, row.end_at, row.all_day,
     row.shows_from, row.status, row.submitted_by, row.category, row.created_at]);
  return rows[0].id;
}

async function signIn(id, interests = []) {
  await db.exec('reset role');
  await db.query(`insert into auth.users (id) values ($1) on conflict do nothing`, [id]);
  await db.query(`insert into public.town_profiles (user_id, interests) values ($1, $2)
                  on conflict (user_id) do update set interests = excluded.interests`, [id, interests]);
  await db.exec(`set role authenticated; set request.jwt.claim.sub = '${id}'`);
}

// Rows at a Town time ("2026-10-08 12:00"), Central time either side of DST.
async function feed(at) {
  const { rows } = await db.query(
    `select title, event_date::text as day, recurrence, rsvpd, leaves_at, reason, reason_name, score,
            cancelled, going_count, friends_going
     from public.flat_town_feed(($1::timestamp at time zone 'America/Chicago'))`, [at]);
  return rows;
}
const titles = async (at) => (await feed(at)).map((r) => r.title);
const label = async (...dates) =>
  (await db.query(`select public.town_feed_series_label($1::date[]) as l`, [dates])).rows[0].l;

test('an event with no end leaves two hours after it starts', async () => {
  await reset();
  await add('Bake sale', '2026-10-08', { start_time: '11 AM' });
  assert.deepEqual(await titles('2026-10-08 12:59'), ['Bake sale']);
  assert.deepEqual(await titles('2026-10-08 13:01'), []);
});

test('an event with no start or end leaves at midnight Town time', async () => {
  await reset();
  await add('Garage sale', '2026-10-08');
  await add('Fun run', '2026-10-08', { all_day: true, start_time: '9 AM' });
  assert.deepEqual(await titles('2026-10-08 23:59'), ['Fun run', 'Garage sale']);
  assert.deepEqual(await titles('2026-10-09 00:01'), []);
});

test('an event stays until its end, days after it started', async () => {
  await reset();
  await add('Art fair', '2026-10-06', { start_time: '10 AM', end_at: '2026-10-09 18:00-05' });
  assert.deepEqual(await titles('2026-10-08 12:00'), ['Art fair']);
  assert.deepEqual(await titles('2026-10-09 18:01'), []);
});

test('an exhibit that opened months ago is still there until it closes', async () => {
  await reset();
  await add('Summer exhibit', '2026-06-01', { start_time: '10 AM', end_at: '2026-10-31 17:00-05' });
  await add('Long over', '2026-06-01', { start_time: '10 AM' });
  assert.deepEqual(await titles('2026-10-08 12:00'), ['Summer exhibit']);
});

test('an event shows from its show-from day, or 14 days ahead', async () => {
  await reset();
  await add('Two weeks out', '2026-10-22', { start_time: '6 PM' });
  await add('Fifteen days out', '2026-10-23', { start_time: '6 PM' });
  await add('Big festival', '2026-11-20', { start_time: '6 PM', shows_from: '2026-10-01' });
  await add('Later festival', '2026-11-21', { start_time: '6 PM', shows_from: '2026-10-09' });
  assert.deepEqual(await titles('2026-10-08 12:00'), ['Two weeks out', 'Big festival']);
});

test('only approved events a person posted or a source announced', async () => {
  await reset();
  await add('Pending', '2026-10-10', { status: 'pending' });
  await add('Seed row', '2026-10-10', { source_name: null });
  await add('Posted', '2026-10-10', { source_name: null, submitted_by: ME });
  assert.deepEqual(await titles('2026-10-08 12:00'), ['Posted']);
});

test('soonest first, start times read in the Town, the ones you go to lower', async () => {
  await reset();
  const early = await add('Early', '2026-10-09', { start_time: '7:00 AM' });
  await add('Noon', '2026-10-09', { start_time: 'noon' });
  await add('Evening', '2026-10-09', { start_time: '19:30' });
  await add('Late', '2026-10-09', { start_time: '9pm' });
  assert.deepEqual(await titles('2026-10-08 12:00'), ['Early', 'Noon', 'Evening', 'Late']);

  await db.query(`insert into public.event_rsvps (event_id, user_id) values ($1, $2)`, [early, ME]);
  await db.exec(`set request.jwt.claim.sub = '${ME}'`);
  const rows = await feed('2026-10-08 12:00');
  assert.deepEqual(rows.map((r) => r.title), ['Noon', 'Evening', 'Late', 'Early']);
  assert.equal(rows.at(-1).rsvpd, true);
});

test('a start after the clocks go back is still read in Central time', async () => {
  await reset();
  await add('Council', '2026-11-02', { start_time: '6 PM' });
  const [row] = await feed('2026-11-01 12:00');
  assert.equal(row.leaves_at.toISOString(), '2026-11-03T02:00:00.000Z');
});

test('a series shows once, at its next date, with how it repeats', async () => {
  await reset();
  await add('City Council Meeting', '2026-10-05', { start_time: '6 PM' });
  for (const d of ['2026-10-19', '2026-11-02', '2026-11-16', '2026-12-07', '2026-12-21'])
    await add('City Council Meeting', d, { start_time: '6 PM' });
  for (const d of ['2026-10-13', '2026-10-20', '2026-10-27'])
    await add('Trivia', d, { start_time: '7 PM', source_name: 'Bad Habit' });
  await add('Trivia', '2026-10-13', { start_time: '8 PM', source_name: 'Krewe' });
  const rows = await feed('2026-10-08 12:00');
  assert.deepEqual(rows.map((r) => [r.title, r.day, r.recurrence]), [
    ['Trivia', '2026-10-13', 'Every Tuesday'],
    ['Trivia', '2026-10-13', null],
    ['City Council Meeting', '2026-10-19', 'Every 1st & 3rd Monday'],
  ]);
});

test('how a series repeats, in words', async () => {
  assert.equal(await label('2026-10-10', '2026-10-24', '2026-11-07'), 'Every other Saturday');
  // A weekend festival on three days in a row is not "every day".
  assert.equal(await label('2026-10-09', '2026-10-10', '2026-10-11'), null);
  assert.equal(await label('2026-10-20', '2026-11-17', '2026-12-15'), 'Every 3rd Tuesday');
  assert.equal(await label('2026-10-12', '2026-11-09', '2026-12-14'), 'Every 2nd Monday');
  assert.equal(await label('2026-10-19', '2026-11-02', '2026-11-16', '2026-12-07'),
               'Every 1st & 3rd Monday');
  // A month missing its meeting, an irregular pair, one date: no pattern.
  assert.equal(await label('2026-10-19', '2026-11-02', '2026-11-16', '2026-12-21'), null);
  assert.equal(await label('2026-11-09', '2026-12-07'), null);
  assert.equal(await label('2026-10-20', '2026-12-15'), null);
  assert.equal(await label('2026-10-20'), null);
  // Two dates a week apart could be a two-day class: no label under three dates.
  assert.equal(await label('2026-10-13', '2026-10-20'), null);
});

test('start times written the ways the app reads them', async () => {
  await reset();
  const times = ['6PM', '7:00PM', '8 p.m.', '19:30:00', 'midnight', 'after dark'];
  for (const [i, t] of times.entries()) await add(`T${i}`, '2026-10-09', { start_time: t });
  const leaves = Object.fromEntries((await feed('2026-10-08 12:00'))
    .map((r) => [r.title, r.leaves_at.toISOString()]));
  assert.deepEqual(leaves, {
    T0: '2026-10-10T01:00:00.000Z', T1: '2026-10-10T02:00:00.000Z',
    T2: '2026-10-10T03:00:00.000Z', T3: '2026-10-10T02:30:00.000Z',
    T4: '2026-10-09T07:00:00.000Z', T5: '2026-10-10T05:00:00.000Z',
  });
});

test('signed out, the feed reads as the public role with the same counts', async () => {
  await reset();
  const id = await add('Bake sale', '2026-10-09', { start_time: '11 AM' });
  await add('Hidden draft', '2026-10-09', { status: 'pending', submitted_by: ME });
  await db.query(`insert into public.event_rsvps (event_id, user_id) values ($1, $2)`, [id, ME]);
  const counts = async () => (await db.query(
    `select title, going_count, rsvpd from public.flat_town_feed(
       ('2026-10-08 12:00'::timestamp at time zone 'America/Chicago'))`)).rows;
  await db.exec(`set role anon`);
  assert.deepEqual(await counts(), [{ title: 'Bake sale', going_count: 1, rsvpd: false }]);
  await db.exec(`reset role; set role authenticated; set request.jwt.claim.sub = '${ME}'`);
  // Your own draft is readable to you, but only approved events are in the feed.
  assert.deepEqual(await counts(), [{ title: 'Bake sale', going_count: 1, rsvpd: true }]);
});

test("every account's hearts are counted, and yours says you hearted it", async () => {
  await reset();
  const fair = await add('Fall fair', '2026-10-09', { start_time: '11 AM' });
  const quiz = await add('Quiz night', '2026-10-09', { start_time: '7 PM' });
  const OTHER = '00000000-0000-0000-0000-0000000000c3';
  await people(db, OTHER);
  await db.query(`insert into public.event_likes (event_id, user_id) values ($1, $2), ($1, $3), ($4, $3)`,
                 [fair, ME, OTHER, quiz]);
  const hearts = async () => (await db.query(
    `select title, heart_count, hearted from public.flat_town_feed(
       ('2026-10-08 12:00'::timestamp at time zone 'America/Chicago')) order by title`)).rows;
  await db.exec(`reset role; set role authenticated; set request.jwt.claim.sub = '${ME}'`);
  assert.deepEqual(await hearts(), [{ title: 'Fall fair', heart_count: 2, hearted: true },
                                    { title: 'Quiz night', heart_count: 1, hearted: false }]);
  // Signed out, the public key gets the same counts, and hearted nothing.
  await db.exec(`reset role; reset request.jwt.claim.sub; set role anon`);
  assert.deepEqual(await hearts(), [{ title: 'Fall fair', heart_count: 2, hearted: false },
                                    { title: 'Quiz night', heart_count: 1, hearted: false }]);
});

test('a heart moves nothing: the order is the recipe\'s', async () => {
  await reset();
  await add('Bake sale', '2026-10-09', { start_time: '11 AM' });
  const later = await add('Book swap', '2026-10-10', { start_time: '11 AM' });
  await db.query(`insert into public.event_likes (event_id, user_id) values ($1, $2)`, [later, ME]);
  await signIn(ME);
  assert.deepEqual(await titles('2026-10-08 12:00'), ['Bake sale', 'Book swap']);
});

test('a called-off event leaves the feed unless someone Hearted it, and then is never promoted', async () => {
  await reset();
  await add('Bake sale', '2026-10-09', { start_time: '11 AM' });
  // Today, a picked interest and new: it would lead the feed if it were on.
  const off = await add('Sartell Volleyball vs ROCORI', '2026-10-08',
                        { start_time: '7 PM', source_name: 'ROCORI High School', category: 'watch_sports',
                          created_at: '2026-10-07 12:00-05' });
  await db.query(`update public.club_events set cancelled_at = now() where id = $1`, [off]);
  await signIn(ME, ['watch_sports']);
  assert.deepEqual(await titles('2026-10-08 12:00'), ['Bake sale']);
  await db.exec('reset role');
  await people(db, '00000000-0000-0000-0000-0000000000c4');
  await db.query(`insert into public.event_likes (event_id, user_id) values ($1, $2)`,
                 [off, '00000000-0000-0000-0000-0000000000c4']);
  await signIn(ME, ['watch_sports']);
  // It says it's called off, so the card shows the Canceled tag (ticket 12).
  assert.deepEqual((await feed('2026-10-08 12:00')).map((r) => [r.title, r.reason, r.cancelled]),
                   [['Bake sale', 'tomorrow', false], ['Sartell Volleyball vs ROCORI', 'today', true]]);
  // Back on its schedule, it is an event like any other again.
  await db.exec('reset role');
  await db.query(`update public.club_events set cancelled_at = null where id = $1`, [off]);
  await signIn(ME, ['watch_sports']);
  const [first] = await feed('2026-10-08 12:00');
  assert.deepEqual([first.title, first.cancelled], ['Sartell Volleyball vs ROCORI', false]);
});

test("a Hearted called-off date never stands in for its series' next live one", async () => {
  await reset();
  const off = await add('Trivia night', '2026-10-08', { start_time: '7 PM' });
  await add('Trivia night', '2026-10-15', { start_time: '7 PM' });
  await db.query(`update public.club_events set cancelled_at = now() where id = $1`, [off]);
  await people(db, '00000000-0000-0000-0000-0000000000c4');
  await db.query(`insert into public.event_likes (event_id, user_id) values ($1, $2)`,
                 [off, '00000000-0000-0000-0000-0000000000c4']);
  await signIn(ME);
  assert.deepEqual((await feed('2026-10-08 12:00')).map((r) => [r.day, r.cancelled]),
                   [['2026-10-15', false], ['2026-10-08', true]]);
});

// ---- The recipe (ticket 18): each neighbour's own order, by the playground's weights ----

const YOU = '00000000-0000-0000-0000-00000000000b';

test('a picked interest lifts an event, and only a picked one', async () => {
  await reset();
  await add('Choir concert', '2026-10-12', { start_time: '3 PM', category: 'live_music' });
  await add('Bake sale', '2026-10-09', { start_time: '11 AM', category: 'dining', source_name: 'Parish' });
  // Signed out, or with other picks, sooner wins.
  assert.deepEqual(await titles('2026-10-08 12:00'), ['Bake sale', 'Choir concert']);
  await signIn(YOU, ['lakes_biking']);
  assert.deepEqual(await titles('2026-10-08 12:00'), ['Bake sale', 'Choir concert']);
  await signIn(YOU, ['live_music']);
  const rows = await feed('2026-10-08 12:00');
  assert.deepEqual(rows.map((r) => [r.title, r.reason, r.reason_name]), [
    ['Choir concert', 'interest', 'live_music'],
    ['Bake sale', 'tomorrow', null],
  ]);
});

test('points halve for every 7 days an event is away', async () => {
  await reset();
  await add('Today', '2026-10-08', { start_time: '12 PM' });
  await add('A week out', '2026-10-15', { start_time: '12 PM', source_name: 'A' });
  await add('Two weeks out', '2026-10-22', { start_time: '12 PM', source_name: 'B' });
  await db.exec(`set request.jwt.claims = '${ADMIN}'`);
  const soon = Object.fromEntries((await feed('2026-10-08 12:00')).map((r) => [r.title, r.score.soon]));
  assert.deepEqual(soon, { 'Today': 1, 'A week out': 0.5, 'Two weeks out': 0.25 });
});

test('what you are Going to or saved sits lower, but stays', async () => {
  await reset();
  const going = await add('Going', '2026-10-09', { start_time: '9 AM', source_name: 'A' });
  const saved = await add('Saved', '2026-10-09', { start_time: '10 AM', source_name: 'B' });
  await add('Neither', '2026-10-09', { start_time: '6 PM', source_name: 'C' });
  await db.query(`insert into public.event_rsvps (event_id, user_id) values ($1, $2)`, [going, YOU]);
  await db.query(`insert into public.event_saves (event_id, user_id) values ($1, $2)`, [saved, YOU]);
  assert.deepEqual(await titles('2026-10-08 12:00'), ['Going', 'Saved', 'Neither']);
  await signIn(YOU);
  assert.deepEqual(await titles('2026-10-08 12:00'), ['Neither', 'Going', 'Saved']);
});

test('the feed says whether you saved each event, and only yours', async () => {
  await reset();
  const fair = await add('Fall fair', '2026-10-09', { start_time: '11 AM' });
  await add('Quiz night', '2026-10-09', { start_time: '7 PM' });
  const OTHER = '00000000-0000-0000-0000-0000000000c3';
  await db.query(`insert into public.event_saves (event_id, user_id) values ($1, $2)`, [fair, YOU]);
  const saves = async () => (await db.query(
    `select title, saved from public.flat_town_feed(
       ('2026-10-08 12:00'::timestamp at time zone 'America/Chicago')) order by title`)).rows;
  await signIn(YOU);
  assert.deepEqual(await saves(), [{ title: 'Fall fair', saved: true }, { title: 'Quiz night', saved: false }]);
  await signIn(OTHER);
  assert.deepEqual(await saves(), [{ title: 'Fall fair', saved: false }, { title: 'Quiz night', saved: false }]);
  await db.exec(`reset role; reset request.jwt.claim.sub; set role anon`);
  assert.deepEqual(await saves(), [{ title: 'Fall fair', saved: false }, { title: 'Quiz night', saved: false }]);
});

test("nobody reads who is Going, saved or hearted: only their own rows, and the counts stay", async () => {
  await reset();
  const fair = await add('Fall fair', '2026-10-09', { start_time: '11 AM' });
  const OTHER = '00000000-0000-0000-0000-0000000000c3';
  for (const t of ['event_rsvps', 'event_saves', 'event_likes']) {
    await db.query(`insert into public.${t} (event_id, user_id) values ($1, $2), ($1, $3)`, [fair, YOU, OTHER]);
  }
  const who = async () => {
    const out = {};
    for (const t of ['event_rsvps', 'event_saves', 'event_likes']) {
      out[t] = (await db.query(`select user_id from public.${t}`)).rows.map((r) => r.user_id);
    }
    return out;
  };
  const counts = async () => (await db.query(
    `select going_count, heart_count from public.flat_town_feed(
       ('2026-10-08 12:00'::timestamp at time zone 'America/Chicago'))`)).rows;
  await signIn(OTHER);
  assert.deepEqual(await who(), { event_rsvps: [OTHER], event_saves: [OTHER], event_likes: [OTHER] });
  assert.deepEqual(await counts(), [{ going_count: 2, heart_count: 2 }]);
  await db.exec(`reset role; reset request.jwt.claim.sub; set role anon`);
  assert.deepEqual(await who(), { event_rsvps: [], event_saves: [], event_likes: [] });
  assert.deepEqual(await counts(), [{ going_count: 2, heart_count: 2 }]);
  // The helpers sit in the private schema, which the API doesn't expose.
  await db.exec('reset role');
  const { rows } = await db.query(`select n.nspname from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                                   where p.proname in ('going_count', 'heart_count') order by 1`);
  assert.deepEqual(rows.map((r) => r.nspname), ['private', 'private']);
});

test("every interest the tagger gave an Event matches, two at most; an untagged one matches by its category", async () => {
  await reset();
  const trivia = await add('Trivia at the taproom', '2026-10-09', { start_time: '7 PM' });
  await add('Pancake breakfast', '2026-10-09', { start_time: '8 AM', category: 'dining', source_name: 'Fire hall' });
  const council = await add('Council meeting', '2026-10-09', { start_time: '6 PM', source_name: 'Council' });
  await db.query(`update public.club_events set interests = '{bars,live_music,dining}', category = 'live_music',
                  interests_tagged_at = now() where id = $1`, [trivia]);
  // The writer guessed dining; the tagger said nothing fits, and the tagger wins.
  await db.query(`update public.club_events set category = 'dining', interests_tagged_at = now() where id = $1`, [council]);
  await signIn(YOU, ['bars', 'dining', 'live_music']);
  await db.exec(`set request.jwt.claims = '${ADMIN}'`);
  const rows = await feed('2026-10-08 12:00');
  assert.deepEqual(rows.map((r) => [r.title, r.reason, r.reason_name, r.score.interest]),
                   [['Trivia at the taproom', 'interest', 'bars', 6], ['Pancake breakfast', 'interest', 'dining', 3],
                    ['Council meeting', 'tomorrow', null, 0]]);
});

test("how much an Event draws the town out is everyone's starting point: 0, 1.5 or 3 points, 2 when not rated", async () => {
  await reset();
  const fair = await add('Art fair', '2026-10-09', { start_time: '10 AM', source_name: 'Arts council' });
  const council = await add('Council meeting', '2026-10-09', { start_time: '9 AM', source_name: 'City' });
  await add('Book sale', '2026-10-09', { start_time: '11 AM', source_name: 'Library' });
  await db.query(`update public.club_events set draw = 3 where id = $1`, [fair]);
  await db.query(`update public.club_events set draw = 1 where id = $1`, [council]);
  await db.exec(`set request.jwt.claims = '${ADMIN}'`);
  const rows = await feed('2026-10-08 12:00');
  assert.deepEqual(rows.map((r) => [r.title, r.score.draw]),
                   [['Art fair', 3], ['Book sale', 1.5], ['Council meeting', 0]]);
  assert.ok(rows.every((r) => r.reason !== 'draw'), 'the draw is never the reason a card gives');
});

// Hosts you've been into (ticket 30): your own taps, `at` a Town time, before you sign in.
async function tap(table, event, who, at) {
  await db.exec('reset role');
  await db.query(`insert into public.${table} (event_id, user_id, created_at)
                  values ($1, $2, ($3::timestamp at time zone 'America/Chicago'))`, [event, who, at]);
}

test("a host you've been into lifts its other Events and is named; routine business neither lifts nor rises", async () => {
  await reset();
  const fair = await add('Craft fair', '2026-10-04', { start_time: '10 AM' });
  const zoo = await add('Zoo day', '2026-10-09', { start_time: '10 AM' });
  // Another host's routine business: a City meeting reaches only the City's followers (town-feed 27).
  const council = await add('Council meeting', '2026-10-09', { start_time: '9 AM', source_name: 'School board' });
  const meetingLastWeek = await add('Planning commission', '2026-10-01', { start_time: '6 PM', source_name: 'School board' });
  await add('Bingo', '2026-10-09', { start_time: '11 AM', source_name: "Sal's" });
  await db.query(`update public.club_events set draw = 1 where id in ($1, $2)`, [council, meetingLastWeek]);
  await tap('event_likes', fair, YOU, '2026-10-04 12:00');
  await tap('event_likes', meetingLastWeek, YOU, '2026-10-01 19:00');
  await tap('event_likes', zoo, YOU, '2026-10-07 12:00');
  await tap('event_rsvps', zoo, YOU, '2026-10-07 12:00');
  await signIn(YOU);
  await db.exec(`set request.jwt.claims = '${ADMIN}'`);
  const rows = Object.fromEntries((await feed('2026-10-08 12:00')).map((r) => [r.title, r]));
  // The craft fair you hearted lifts the Zoo day; the Zoo day's own taps don't count for it, and
  // being Going still lowers it as ever.
  assert.deepEqual([rows['Zoo day'].reason, rows['Zoo day'].reason_name, rows['Zoo day'].score.tapped,
                    rows['Zoo day'].score.acted], ['tapped', CITY, 3, 0.4]);
  assert.equal(rows['Council meeting'].score.tapped, 0, 'a council meeting never rises');
  assert.equal(rows['Bingo'].score.tapped, 0, 'a host you never tapped');
});

test('a host you\'ve been into counts once however much you tapped, 90 days back and no further', async () => {
  await reset();
  const zoo = await add('Zoo day', '2026-10-09', { start_time: '10 AM' });
  const market = await add('Market', '2026-07-25', { start_time: '8 AM' });
  const parade = await add('Parade', '2026-08-01', { start_time: '11 AM' });
  const spring = await add('Spring fling', '2026-06-20', { start_time: '1 PM' });
  const OTHER = '00000000-0000-0000-0000-0000000000c9';
  await people(db, OTHER);
  await tap('event_likes', parade, OTHER, '2026-08-01 12:00');
  await tap('event_likes', spring, YOU, '2026-06-20 14:00');
  const tapped = async () => {
    await signIn(YOU);
    await db.exec(`set request.jwt.claims = '${ADMIN}'`);
    return (await feed('2026-10-08 12:00')).find((r) => r.title === 'Zoo day').score.tapped;
  };
  assert.equal(await tapped(), 0, "a neighbour's heart and 110 days back don't count");
  for (const t of ['event_rsvps', 'event_saves', 'event_likes']) await tap(t, market, YOU, '2026-07-25 09:00');
  assert.equal(await tapped(), 3, '75 days back counts');
  await tap('event_likes', parade, YOU, '2026-08-01 12:00');
  assert.equal(await tapped(), 3, 'a second Event of its host adds nothing');
});

// A game's host is its team (town-feed 39): games are made by `game` below, their teams by `teams`.
const [SJU, ROCORI] = ['SJU Athletics', 'ROCORI High School'];
async function teams(...rows) {
  await db.exec('reset role');
  for (const [id, short] of rows)
    await db.query(`insert into public.teams (id, name, short_name) values ($1, $2, $2)`, [id, short]);
}
async function byTitle(at = '2026-10-08 12:00') {
  await signIn(YOU);
  await db.exec(`set request.jwt.claims = '${ADMIN}'`);
  return Object.fromEntries((await feed(at)).map((r) => [r.title, r]));
}

test("a team's games on two days lift its next game in that sport and name it; not its school's other sports", async () => {
  await reset();
  await teams(['saint-johns', "Saint John's"], ['augsburg', 'Augsburg'], ['bethel', 'Bethel'],
              ['st-olaf', 'St. Olaf'], ['concordia', 'Concordia']);
  const a = await game('SJU Soccer vs Augsburg', '2026-10-01', 'Soccer', ['saint-johns', 'augsburg'], { source_name: SJU });
  const b = await game('Bethel vs SJU Soccer', '2026-10-04', 'Soccer', ['bethel', 'saint-johns'], { source_name: SJU });
  await game('SJU Soccer vs St. Olaf', '2026-10-10', 'Soccer', ['saint-johns', 'st-olaf'], { source_name: SJU });
  await game('SJU Football vs Concordia', '2026-10-10', 'Football', ['saint-johns', 'concordia'], { source_name: SJU });
  await game('Augsburg Soccer vs Bethel', '2026-10-10', 'Soccer', ['augsburg', 'bethel'], { source_name: 'Augsburg Athletics' });
  await tap('event_likes', a, YOU, '2026-10-01 18:00');
  await tap('event_saves', b, YOU, '2026-10-04 18:00');
  const rows = await byTitle();
  const olaf = rows['SJU Soccer vs St. Olaf'];
  assert.deepEqual([olaf.reason, olaf.reason_name, olaf.score.tapped], ['tapped', "Saint John's Soccer", 3]);
  assert.equal(rows['SJU Football vs Concordia'].score.tapped, 0, "the school's other sport doesn't rise");
  assert.equal(rows['Augsburg Soccer vs Bethel'].score.tapped, 0, 'Augsburg and Bethel were in one tapped game each');
});

test('one tapped game lifts nothing, and two rows of one day are one game day', async () => {
  await reset();
  await teams(['saint-johns', "Saint John's"], ['augsburg', 'Augsburg'], ['st-olaf', 'St. Olaf']);
  const varsity = await game('SJU Soccer vs Augsburg', '2026-10-04', 'Soccer', ['saint-johns', 'augsburg'], { source_name: SJU });
  const jv = await game('SJU Soccer vs Augsburg (JV)', '2026-10-04', 'Soccer', ['saint-johns', 'augsburg'], { source_name: SJU });
  await game('SJU Soccer vs St. Olaf', '2026-10-10', 'Soccer', ['saint-johns', 'st-olaf'], { source_name: SJU });
  const olafJv = await game('SJU Soccer vs St. Olaf (JV)', '2026-10-10', 'Soccer', ['saint-johns', 'st-olaf'], { source_name: SJU });
  await tap('event_likes', varsity, YOU, '2026-10-04 18:00');
  assert.equal((await byTitle())['SJU Soccer vs St. Olaf'].score.tapped, 0, 'one game');
  await tap('event_likes', jv, YOU, '2026-10-04 18:00');
  assert.equal((await byTitle())['SJU Soccer vs St. Olaf'].score.tapped, 0, 'varsity and JV the same day');
  await tap('event_likes', olafJv, YOU, '2026-10-08 09:00');
  assert.equal((await byTitle())['SJU Soccer vs St. Olaf'].score.tapped, 0, "its own day's JV game is not another day");
});

test("a school's games and its other Events stop lifting each other", async () => {
  await reset();
  await teams(['rocori', 'ROCORI'], ['st-peter', 'St. Peter'], ['albany', 'Albany'], ['sartell', 'Sartell']);
  const g1 = await game('ROCORI Football vs St. Peter', '2026-10-02', 'Football', ['rocori', 'st-peter'], { source_name: ROCORI });
  const g2 = await game('Albany vs ROCORI Football', '2026-10-05', 'Football', ['albany', 'rocori'], { source_name: ROCORI });
  const concert = await add('Band concert', '2026-10-03', { start_time: '7 PM', source_name: ROCORI });
  await add('Fall play', '2026-10-09', { start_time: '7 PM', source_name: ROCORI });
  await game('ROCORI Football vs Sartell', '2026-10-09', 'Football', ['rocori', 'sartell'], { source_name: ROCORI });
  await game('ROCORI Volleyball vs Sartell', '2026-10-10', 'Volleyball', ['rocori', 'sartell'], { source_name: ROCORI });
  await tap('event_rsvps', g1, YOU, '2026-10-02 12:00');
  await tap('event_likes', g2, YOU, '2026-10-05 21:00');
  let rows = await byTitle();
  assert.deepEqual([rows['ROCORI Football vs Sartell'].score.tapped, rows['ROCORI Football vs Sartell'].reason_name],
                   [3, 'ROCORI Football']);
  assert.equal(rows['Fall play'].score.tapped, 0, "the school's games don't lift its play");
  await tap('event_likes', concert, YOU, '2026-10-03 21:00');
  rows = await byTitle();
  assert.deepEqual([rows['Fall play'].score.tapped, rows['Fall play'].reason_name], [3, ROCORI]);
  assert.equal(rows['ROCORI Volleyball vs Sartell'].score.tapped, 0, "the school's concert doesn't lift its games");
});

test("a team's lift is spaced by school, sits under your own Going, and Not interested on the school beats it", async () => {
  await reset();
  await teams(['saint-johns', "Saint John's"], ['augsburg', 'Augsburg'], ['bethel', 'Bethel'],
              ['st-olaf', 'St. Olaf'], ['gustavus', 'Gustavus']);
  const a = await game('SJU Soccer vs Augsburg', '2026-10-01', 'Soccer', ['saint-johns', 'augsburg'], { source_name: SJU });
  const b = await game('SJU Soccer vs Bethel', '2026-10-04', 'Soccer', ['saint-johns', 'bethel'], { source_name: SJU });
  const olaf = await game('SJU Soccer vs St. Olaf', '2026-10-09', 'Soccer', ['saint-johns', 'st-olaf'], { source_name: SJU });
  await game('SJU Soccer vs Gustavus', '2026-10-11', 'Soccer', ['saint-johns', 'gustavus'], { source_name: SJU });
  await tap('event_likes', a, YOU, '2026-10-01 18:00');
  await tap('event_likes', b, YOU, '2026-10-04 18:00');
  let rows = await byTitle();
  assert.deepEqual(['SJU Soccer vs St. Olaf', 'SJU Soccer vs Gustavus'].map((t) => [rows[t].score.tapped, rows[t].score.spacing]),
                   [[3, 1], [3, 0.5]], 'the second from the school counts half');
  await tap('event_rsvps', olaf, YOU, '2026-10-08 09:00');
  rows = await byTitle();
  assert.deepEqual([rows['SJU Soccer vs St. Olaf'].score.tapped, rows['SJU Soccer vs St. Olaf'].score.acted], [3, 0.4],
                   'its own Going is a third day, and the two before still lift it');
  await notInterested(b, YOU, '2026-10-08 10:00');
  rows = await byTitle();
  const gustavus = rows['SJU Soccer vs Gustavus'];
  assert.deepEqual([gustavus.score.tapped, gustavus.score.notInterested], [3, 0.3]);
});

test("a sport spelled two ways is one team's, and a team with no row is named by its calendar", async () => {
  await reset();
  const a = await game('ROCORI Girls Swim vs Sartell', '2026-10-01', 'Girls Swim', ['rocori', 'sartell'], { source_name: ROCORI });
  const b = await game('Sartell vs ROCORI', '2026-10-06', 'Girls Swimming and Diving', ['sartell', 'rocori'], { source_name: 'Sartell High School' });
  await game('ROCORI Girls Swim vs Tech', '2026-10-09', 'Girls Swim', ['rocori', 'tech'], { source_name: ROCORI });
  await tap('event_likes', a, YOU, '2026-10-01 20:00');
  await tap('event_likes', b, YOU, '2026-10-06 20:00');
  const tech = (await byTitle())['ROCORI Girls Swim vs Tech'];
  assert.deepEqual([tech.score.tapped, tech.reason, tech.reason_name], [3, 'tapped', ROCORI]);
});

// Friends shape the feed (ticket 28). The helper names friends only on Events not over by the
// clock, so these stories date their Events from today rather than the fixed week above.
const day = townDay;
const nowTown = () => new Date().toLocaleString('sv-SE', { timeZone: 'America/Chicago' }).slice(0, 16);
const [ANNA, BEN, CAL, DEE] = ['c1', 'c2', 'c3', 'c4'].map((x) => `00000000-0000-0000-0000-0000000000${x}`);
const PHOTO = `https://lxdgwhvqjqmqliobwjpi.supabase.co/storage/v1/object/public/avatars/${ANNA}/me.jpg`;

async function neighbour(id, name, { photo = null, plans = true, anonymous = false } = {}) {
  await db.exec('reset role');
  await db.query(`insert into auth.users (id, is_anonymous) values ($1, $2)
                  on conflict (id) do update set is_anonymous = excluded.is_anonymous`, [id, anonymous]);
  await db.query(`insert into public.town_profiles (user_id, display_name, avatar_url, plans_to_friends)
                  values ($1, $2, $3, $4)`, [id, name, photo, plans]);
}
async function befriend(x, y) {
  await db.exec('reset role');
  const [a, b] = [x, y].sort();
  await db.query(`insert into private.friendships (a, b, requested_by) values ($1, $2, $1)`, [a, b]);
}
async function goes(event, who, at = null) {
  await db.exec('reset role');
  await db.query(`insert into public.event_rsvps (event_id, user_id, created_at)
                  values ($1, $2, coalesce($3::timestamptz, now()))`, [event, who, at]);
}

test('a friend Going lifts an Event and names them, newest Going first; three friends count once', async () => {
  await reset();
  const quiz = await add('Quiz night', day(2), { start_time: '7 PM' });
  await add('Craft fair', day(2), { start_time: '9 AM' });
  await neighbour(ANNA, '🎉 Anna  Lee', { photo: PHOTO });
  await neighbour(BEN, 'Ben Ortiz');
  await neighbour(CAL, 'Cal Ruiz', { photo: 'https://example.com/cal.jpg' });
  for (const f of [ANNA, BEN, CAL]) await befriend(ME, f);
  await goes(quiz, BEN, '2026-10-01 10:00-05');
  await goes(quiz, CAL, '2026-10-02 10:00-05');
  await goes(quiz, ANNA, '2026-10-03 10:00-05');
  await signIn(ME);
  const rows = await feed(nowTown());
  assert.deepEqual(rows.map((r) => r.title), ['Quiz night', 'Craft fair']);
  assert.deepEqual([rows[0].reason, rows[0].reason_name, rows[0].going_count], ['friend', 'Anna', 3]);
  // A photo counts only from the friend's own folder of our bucket.
  assert.deepEqual(rows[0].friends_going, [{ name: 'Anna', photo: PHOTO }, { name: 'Cal', photo: null },
                                           { name: 'Ben', photo: null }]);
  assert.deepEqual(rows[1].friends_going, []);
  await db.exec(`set request.jwt.claims = '${ADMIN}'`);
  assert.deepEqual([(await feed(nowTown()))[0].score.friend, (await feed(nowTown()))[0].score.yours], [3, 3]);
});

test("a friend who hides their plans, a blocked friend and a stranger only count", async () => {
  await reset();
  const quiz = await add('Quiz night', day(3), { start_time: '7 PM' });
  await neighbour(ANNA, 'Anna Lee', { plans: false });
  await neighbour(BEN, 'Ben Ortiz');
  await neighbour(CAL, 'Cal Ruiz', { anonymous: true });
  await neighbour(DEE, 'Dee Park');
  for (const f of [ANNA, BEN, CAL]) await befriend(ME, f);
  await db.query(`insert into private.blocks (blocker_id, blocked_id) values ($1, $2)`, [BEN, ME]);
  for (const who of [ANNA, BEN, CAL, DEE]) await goes(quiz, who);
  await signIn(ME);
  const [row] = await feed(nowTown());
  assert.deepEqual([row.reason === 'friend', row.friends_going, row.going_count], [false, [], 4]);
});

test("a friend's save or Heart lifts nothing", async () => {
  await reset();
  const quiz = await add('Quiz night', day(3), { start_time: '7 PM' });
  await neighbour(ANNA, 'Anna Lee');
  await befriend(ME, ANNA);
  await db.query(`insert into public.event_saves (event_id, user_id) values ($1, $2)`, [quiz, ANNA]);
  await db.query(`insert into public.event_likes (event_id, user_id) values ($1, $2)`, [quiz, ANNA]);
  await signIn(ME);
  await db.exec(`set request.jwt.claims = '${ADMIN}'`);
  const [row] = await feed(nowTown());
  assert.deepEqual([row.reason === 'friend', row.friends_going, row.score.friend], [false, [], 0]);
});

test("a friend's past plans stay theirs, whatever clock the caller gives the feed", async () => {
  await reset();
  const club = await add('Book club', day(-3), { start_time: '7 PM' });
  await neighbour(ANNA, 'Anna Lee');
  await befriend(ME, ANNA);
  await goes(club, ANNA);
  await signIn(ME);
  const rows = await feed(`${day(-4)} 12:00`);
  assert.deepEqual(rows.map((r) => [r.title, r.friends_going, r.reason === 'friend']), [['Book club', [], false]]);
});

test('signed out or Anonymous, nobody has friends', async () => {
  await reset();
  const quiz = await add('Quiz night', day(3), { start_time: '7 PM' });
  await neighbour(ANNA, 'Anna Lee');
  await goes(quiz, ANNA);
  await db.exec(`set role anon`);
  const [row] = await feed(nowTown());
  assert.deepEqual([row.friends_going, row.going_count], [[], 1]);
});

test('the same host is spaced out: each further item from it counts half', async () => {
  await reset();
  await add('Cafe 1', '2026-10-09', { start_time: '8 AM', source_name: 'Cafe' });
  await add('Cafe 2', '2026-10-09', { start_time: '9 AM', source_name: 'Cafe' });
  await add('Cafe 3', '2026-10-09', { start_time: '10 AM', source_name: 'Cafe' });
  await add('Library', '2026-10-09', { start_time: '7 PM', source_name: 'Library' });
  assert.deepEqual(await titles('2026-10-08 12:00'), ['Cafe 1', 'Library', 'Cafe 2', 'Cafe 3']);
});

// New (town-feed 36): a view of yours `at` a Town time, as the app records it.
async function viewed(event, who, at) {
  await db.exec('reset role');
  await db.query(`insert into auth.users (id) values ($1) on conflict do nothing`, [who]);
  await db.query(`insert into public.feed_actions (user_id, item_id, action, at)
                  values ($1, $2, 'view', ($3::timestamp at time zone 'America/Chicago'))`, [who, event, at]);
}

test('posted since your last visit and not yet seen is New: 2 points, under yours', async () => {
  await reset();
  const old = await add('Old', '2026-10-09', { start_time: '10 AM', source_name: 'A' });
  await add('Posted since', '2026-10-09', { start_time: '6 PM', source_name: 'B', created_at: '2026-10-07 09:00-05' });
  const past = await add('Old craft fair', '2026-10-01', { start_time: '10 AM', source_name: 'C' });
  await add('Yours', '2026-10-09', { start_time: '7 PM', source_name: 'C' });
  await tap('event_likes', past, YOU, '2026-10-01 12:00');
  // A first open: no last visit, and nothing came in the last 24 hours, so nothing is New.
  await signIn(YOU);
  await db.exec(`set request.jwt.claims = '${ADMIN}'`);
  assert.ok((await feed('2026-10-08 12:00')).every((r) => r.reason !== 'new'));
  // You last looked on the 6th.
  await viewed(old, YOU, '2026-10-06 09:00');
  await signIn(YOU);
  await db.exec(`set request.jwt.claims = '${ADMIN}'`);
  const rows = await feed('2026-10-08 12:00');
  assert.deepEqual(rows.map((r) => [r.title, r.reason, r.score.new]),
                   [['Yours', 'tapped', 0], ['Posted since', 'new', 2], ['Old', 'tomorrow', 0]]);
  assert.equal(rows[1].score.newSpot, true);
});

test('New ends once you have seen it, and a view in the last 30 minutes is not a last visit', async () => {
  await reset();
  const old = await add('Old', '2026-10-09', { start_time: '10 AM', source_name: 'A' });
  const fresh = await add('Posted since', '2026-10-09', { start_time: '6 PM', source_name: 'B', created_at: '2026-10-07 09:00-05' });
  // Your only view is from this visit: no last visit yet.
  await viewed(old, YOU, '2026-10-08 11:50');
  await signIn(YOU);
  assert.ok((await feed('2026-10-08 12:00')).every((r) => r.reason !== 'new'));
  await viewed(old, YOU, '2026-10-06 09:00');
  await signIn(YOU);
  assert.equal((await feed('2026-10-08 12:00'))[0].reason, 'new');
  await viewed(fresh, YOU, '2026-10-08 11:55');
  await signIn(YOU);
  assert.deepEqual(await titles('2026-10-08 12:00'), ['Old', 'Posted since']);
});

test('your own posting is never New to you, only to everyone else', async () => {
  await reset();
  const old = await add('Old', '2026-10-09', { start_time: '10 AM', source_name: 'A' });
  await add('My yard sale', '2026-10-09', { start_time: '6 PM', source_name: null, submitted_by: YOU,
                                           created_at: '2026-10-07 09:00-05' });
  await viewed(old, YOU, '2026-10-06 09:00');
  await viewed(old, ME, '2026-10-06 09:00');
  await signIn(YOU);
  assert.ok((await feed('2026-10-08 12:00')).every((r) => r.reason !== 'new'), 'yours');
  await signIn(ME);
  assert.equal((await feed('2026-10-08 12:00'))[0].reason, 'new', 'a neighbour');
});

test('an Event is New from its show-from day, posted weeks before', async () => {
  await reset();
  const old = await add('Old', '2026-10-09', { start_time: '10 AM', source_name: 'A' });
  await add('Fall festival', '2026-10-20', { start_time: '10 AM', source_name: 'B', shows_from: '2026-10-07' });
  await viewed(old, YOU, '2026-10-06 09:00');
  await signIn(YOU);
  assert.equal((await feed('2026-10-08 12:00')).find((r) => r.title === 'Fall festival').reason, 'new');
  await db.exec(`reset role; update public.club_events set shows_from = '2026-10-05' where title = 'Fall festival'`);
  await signIn(YOU);
  assert.notEqual((await feed('2026-10-08 12:00')).find((r) => r.title === 'Fall festival').reason, 'new',
                  'in the feed before your last visit');
});

test("someone else's views make nothing New for you, and nobody reads anyone's views", async () => {
  await reset();
  const old = await add('Old', '2026-10-09', { start_time: '10 AM', source_name: 'A' });
  await add('Posted since', '2026-10-09', { start_time: '6 PM', source_name: 'B', created_at: '2026-10-07 09:00-05' });
  await viewed(old, ME, '2026-10-06 09:00');
  await signIn(YOU);
  assert.ok((await feed('2026-10-08 12:00')).every((r) => r.reason !== 'new'));
  await db.exec(`reset role; set role anon; reset request.jwt.claim.sub`);
  assert.deepEqual((await db.query('select * from private.my_views()')).rows, [], 'signed out reads no views');
});

// New lasts a day (town-feed 38): in the feed in the last 24 hours counts even with no last visit,
// or a last visit since it came, until you've seen it.
test('in the feed in the last 24 hours is New with no last visit or a newer one, until you see it', async () => {
  await reset();
  const old = await add('Old', '2026-10-09', { start_time: '10 AM', source_name: 'A' });
  const found = await add('Found this morning', '2026-10-09', { start_time: '6 PM', source_name: 'B',
                                                                created_at: '2026-10-08 06:14-05' });
  await add('Found yesterday morning', '2026-10-09', { start_time: '7 PM', source_name: 'C',
                                                       created_at: '2026-10-07 06:14-05' });
  await add('Shows from today', '2026-10-20', { start_time: '10 AM', source_name: 'D', shows_from: '2026-10-08' });
  // A first open: no last visit.
  await signIn(YOU);
  let reasons = Object.fromEntries((await feed('2026-10-08 19:00')).map((r) => [r.title, r.reason]));
  assert.equal(reasons['Found this morning'], 'new');
  assert.equal(reasons['Shows from today'], 'new');
  assert.notEqual(reasons['Found yesterday morning'], 'new', '37 hours ago');
  // You looked at 1 PM without reaching it: still New at 7 PM.
  await viewed(old, YOU, '2026-10-08 13:00');
  await signIn(YOU);
  reasons = Object.fromEntries((await feed('2026-10-08 19:00')).map((r) => [r.title, r.reason]));
  assert.equal(reasons['Found this morning'], 'new');
  // Once it has been on your screen, it isn't.
  await viewed(found, YOU, '2026-10-08 18:50');
  await signIn(YOU);
  reasons = Object.fromEntries((await feed('2026-10-08 19:00')).map((r) => [r.title, r.reason]));
  assert.notEqual(reasons['Found this morning'], 'new');
});

test('signed out, a found Event in the feed in the last 24 hours is New', async () => {
  await reset();
  await add('Old', '2026-10-09', { start_time: '10 AM', source_name: 'A' });
  await add('Found this morning', '2026-10-09', { start_time: '6 PM', source_name: 'B',
                                                  created_at: '2026-10-08 06:14-05' });
  await add('Found 25 hours ago', '2026-10-09', { start_time: '7 PM', source_name: 'C',
                                                  created_at: '2026-10-07 18:00-05' });
  await db.exec(`reset role; reset request.jwt.claim.sub; set role anon`);
  const rows = await feed('2026-10-08 19:00');
  assert.deepEqual(rows.map((r) => [r.title, r.reason]),
                   [['Found this morning', 'new'], ['Old', 'tomorrow'], ['Found 25 hours ago', 'tomorrow']]);
});

test('the score breakdown is filled for the admin and null for everyone else', async () => {
  await reset();
  await add('Bake sale', '2026-10-09', { start_time: '12 PM', category: 'dining' });
  await signIn(YOU, ['dining']);
  assert.equal((await feed('2026-10-08 12:00'))[0].score, null);
  await db.exec(`set request.jwt.claims = '${ADMIN}'`);
  const { score } = (await feed('2026-10-08 12:00'))[0];
  assert.deepEqual(score, {
    interest: 3, yours: 0, new: 0, friend: 0, follow: 0, tapped: 0, popular: 0, size: 0, sizeStep: 1, draw: 1.5, daysAway: 1,
    soon: 0.9057, acted: 1, notInterested: 1, spacing: 1, newSpot: false, pool: 'discovery', total: 4.9815, spot: 1, of: 1,
  });
});

test('the admin\'s breakdown on a longer feed: same host halves, nothing moved when nothing is new', async () => {
  await reset();
  for (const [i, h] of ['8 AM', '9 AM', '10 AM', '11 AM', '12 PM'].entries())
    await add(`Meeting ${i + 1}`, '2026-10-09', { start_time: h });
  await db.exec(`set request.jwt.claims = '${ADMIN}'`);
  const rows = await feed('2026-10-08 12:00');
  assert.deepEqual(rows.map((r) => [r.score.spot, r.score.spacing, r.score.newSpot]),
                   [[1, 1, false], [2, 0.5, false], [3, 0.25, false], [4, 0.125, false], [5, 0.0625, false]]);
  assert.ok(rows.every((r) => r.score.total > 0));
});

test('signed out, the public key gets the same recipe with no personal terms: how early it shows lifts nothing', async () => {
  await reset();
  await add('Concert', '2026-10-12', { start_time: '3 PM', category: 'live_music' });
  await add('Fair', '2026-10-14', { start_time: '10 AM', source_name: 'Fair board',
                                    shows_from: '2026-08-20' });
  await db.exec(`set role anon`);
  const rows = await feed('2026-10-08 12:00');
  assert.deepEqual(rows.map((r) => [r.title, r.reason, r.score]),
                   [['Concert', 'soon', null], ['Fair', 'soon', null]]);
});

// Views (ticket 20).
const refused = async (sql, params = []) => {
  await assert.rejects(db.query(sql, params));
  await db.exec('rollback').catch(() => {});
};

test('views: a person inserts only their own, and nobody reads them back', async () => {
  await reset();
  const event = await add('Trivia', '2026-10-09', { start_time: '7 PM' });
  await signIn(ME);
  await db.query(`insert into public.feed_actions (item_id, action) values ($1, 'view')`, [event]);
  await db.query(`insert into public.feed_actions (item_id, action) values ($1, 'open')`, [event]);
  await refused(`select * from public.feed_actions`);
  await refused(`insert into public.feed_actions (id, user_id, item_id, action)
                 values (gen_random_uuid(), $1, $2, 'view')`, [YOU, event]);
  await refused(`insert into public.feed_actions (id, item_id, action, at)
                 values (gen_random_uuid(), $1, 'view', now() - interval '1 year')`, [event]);
  await refused(`insert into public.feed_actions (item_id, action) values ($1, 'like')`, [event]);
  await refused(`insert into public.feed_actions (id, item_id, action) values (gen_random_uuid(), $1, 'view')`, [event]);
  await refused(`insert into public.feed_actions (item_id, action)
                 values ('00000000-0000-0000-0009-00000000dead', 'view')`);
  await refused(`update public.feed_actions set action = 'open'`);
  await refused(`delete from public.feed_actions`);
  await db.exec(`set role anon; reset request.jwt.claim.sub`);
  await refused(`insert into public.feed_actions (item_id, action) values ($1, 'view')`, [event]);
  await db.exec('reset role');
  const { rows } = await db.query(`select user_id::text, action from public.feed_actions order by action`);
  assert.deepEqual(rows, [{ user_id: ME, action: 'open' }, { user_id: ME, action: 'view' }]);
});

test('the nightly clean-up deletes only views older than 60 days', async () => {
  await reset();
  const event = await add('Trivia', '2026-10-09', { start_time: '7 PM' });
  await db.exec('reset role');
  await db.query(`insert into auth.users (id) values ($1) on conflict do nothing`, [ME]);
  await db.query(`insert into public.feed_actions (id, user_id, item_id, action, at) values
                    (gen_random_uuid(), $1, $2, 'view', now() - interval '61 days'),
                    (gen_random_uuid(), $1, $2, 'view', now() - interval '59 days'),
                    (gen_random_uuid(), $1, $2, 'open', now() - interval '61 days')`, [ME, event]);
  await db.exec(`select private.feed_clean_up()`);
  const { rows } = await db.query(`select action, (now() - at) < interval '60 days' as recent
                                   from public.feed_actions order by action`);
  assert.deepEqual(rows, [{ action: 'open', recent: false }, { action: 'view', recent: true }]);
});

// The feed's speed is measured in yardsticks: one yardstick is the time this fixed query takes on the
// same machine, hashing, grouping and sorting 60,000 rows on no table. The feed reads 3.8 to 4.9
// yardsticks (Linux cloud box, 2026-11-01, idle or at a load of 11, while its milliseconds swung from
// 156 to 565). 10 keeps the headroom the old 100 ms budget gave the Mac's 40 ms; a feed with its
// indexes gone reads 32.
const YARDSTICK = `select count(*) from (select md5(g::text) h, g % 977 k from generate_series(1, 60000) g) x
  group by k order by count(*) desc, min(h)`;
const FEED_YARDSTICKS = 10;

// A busy Town for the speed stories: about eight weeks, 200 events, 5,000 people, the reader's friends,
// views and follows.
async function fiveThousand() {
  await reset();
  // About eight weeks of a busy Town: 200 events, 5,000 people with three picks each,
  // 50,000 Going, 10,000 saves and 50,000 hearts.
  const picks = ['live_music', 'dining', 'lakes_biking', 'families_kids', 'bars', 'outdoors'];
  await db.query(`
    insert into public.club_events (status, title, event_date, source_name, start_time, category, created_at)
    select 'approved', 'Event ' || g, date '2026-10-08' + (g % 56), 'Host ' || (g % 40), (g % 12 + 1) || ' PM',
           ($1::text[])[g % 6 + 1], timestamptz '2026-09-01 12:00-05'
    from generate_series(1, 200) g`, [picks]);
  await db.exec(`insert into auth.users (id)
    select ('00000000-0000-0000-0001-' || lpad(g::text, 12, '0'))::uuid from generate_series(1, 5000) g on conflict do nothing`);
  await db.query(`
    insert into public.town_profiles (user_id, interests)
    select ('00000000-0000-0000-0001-' || lpad(g::text, 12, '0'))::uuid,
           array[($1::text[])[g % 6 + 1], ($1::text[])[(g + 1) % 6 + 1], ($1::text[])[(g + 2) % 6 + 1]]
    from generate_series(1, 5000) g`, [picks]);
  await db.exec(`
    insert into public.event_rsvps (event_id, user_id)
    select e.id, p.user_id from (select id, row_number() over (order by id) n from public.club_events) e
    join (select user_id, row_number() over (order by user_id) n from public.town_profiles) p
      on (p.n * 7 + e.n) % 20 = 0;
    insert into public.event_saves (event_id, user_id)
    select e.id, p.user_id from (select id, row_number() over (order by id) n from public.club_events) e
    join (select user_id, row_number() over (order by user_id) n from public.town_profiles) p
      on (p.n * 3 + e.n) % 100 = 0
    on conflict do nothing;
    insert into public.event_likes (event_id, user_id)
    select e.id, p.user_id from (select id, row_number() over (order by id) n from public.club_events) e
    join (select user_id, row_number() over (order by user_id) n from public.town_profiles) p
      on (p.n * 11 + e.n) % 20 = 0;
    analyze;`);
  const { rows: [{ n }] } = await db.query(`select count(*)::int n from public.event_rsvps`);
  assert.ok(n >= 45000, `${n} Going rows`);
  const { rows: [{ h }] } = await db.query(`select count(*)::int h from public.event_likes`);
  assert.ok(h >= 45000, `${h} hearts`);
  // The reader has 200 friends, named and Going to things (ticket 28).
  await db.exec(`
    update public.town_profiles set display_name = 'Neighbour ' || right(user_id::text, 4);
    insert into private.friendships (a, b, requested_by)
    select least(r, f), greatest(r, f), r
    from (select '00000000-0000-0000-0001-000000000042'::uuid r) x,
         (select user_id f from public.town_profiles
          where user_id <> '00000000-0000-0000-0001-000000000042' order by user_id limit 200) y;
    -- And 60 days of looking (town-feed 36): every Event seen 30 times, read for what's New.
    insert into public.feed_actions (user_id, item_id, action, at)
    select '00000000-0000-0000-0001-000000000042', e.id, 'view', timestamptz '2026-10-08 12:00-05' - g * interval '2 days'
    from public.club_events e, generate_series(1, 30) g;
    -- And follows (town-feed 37): 20 people who each posted an Event, 5 Places with 8 Events each, and
    -- 3 Groups with about 10 Events each.
    insert into public.town_follows (follower_id, target_type, target_id)
    select '00000000-0000-0000-0001-000000000042', 'profile', user_id from public.town_profiles
    where user_id <> '00000000-0000-0000-0001-000000000042' order by user_id limit 20;
    update public.club_events e set submitted_by = f.target_id, source_name = null
    from (select target_id, row_number() over (order by target_id) n from public.town_follows
          where target_type = 'profile') f
    where e.title = 'Event ' || (f.n * 9);
    insert into public.places (lat, lon, family, name, entry_id) select 45.5, -94.3, 'business', 'Place ' || g, 'speed-place-' || g from generate_series(1, 5) g;
    insert into public.town_follows (follower_id, target_type, target_id)
    select '00000000-0000-0000-0001-000000000042', 'place', id from public.places where entry_id like 'speed-place-%';
    update public.club_events set place_entry_id = 'speed-place-' || (split_part(title, ' ', 2)::int / 5 % 5 + 1)
    where split_part(title, ' ', 2)::int % 5 = 0;
    insert into public.clubs (status, name) select 'approved', 'Group ' || g from generate_series(1, 3) g;
    insert into public.club_members (club_id, user_id)
    select id, '00000000-0000-0000-0001-000000000042' from public.clubs where name like 'Group %';
    update public.club_events e set club_id = c.id
    from (select id, row_number() over (order by id) n from public.clubs where name like 'Group %') c
    where split_part(e.title, ' ', 2)::int % 7 = 0 and split_part(e.title, ' ', 2)::int / 7 % 3 + 1 = c.n;
    -- And games (town-feed 39): a third of the Events are four pairs of teams' soccer, and the reader
    -- hearted 12 of them.
    insert into public.teams (id, name, short_name) select 'team-' || g, 'Team ' || g, 'Team ' || g from generate_series(1, 8) g;
    update public.club_events set sport = 'Soccer', team_ids = array['team-' || (split_part(title, ' ', 2)::int % 4 + 1),
                                                                     'team-' || (split_part(title, ' ', 2)::int % 4 + 5)]
    where split_part(title, ' ', 2)::int % 3 = 1;
    insert into public.event_likes (event_id, user_id)
    select id, '00000000-0000-0000-0001-000000000042' from public.club_events where team_ids is not null order by title limit 12
    on conflict do nothing;
    analyze;`);
}

test('the feed is read in under 10 yardsticks with 5,000 people', async () => {
  await fiveThousand();
  await signIn('00000000-0000-0000-0001-000000000042');
  await feed('2026-10-08 12:00'); // warm up
  await db.query(YARDSTICK);
  // The time is judged against a yardstick read on the same machine in the same seconds: a fixed
  // query that touches none of the feed's tables or functions, so only the machine's speed moves
  // it. A slow or busy machine slows both alike (run 41157284060 read 250.2 ms on a Swift-only
  // change; a building Mac read 489 ms at a load of 90 and 782 at 68, 2026-11-01), so a busy Mac is
  // timed too; a slower feed moves only the feed. Each pair is read back to back, and the median of
  // nine pairs is kept.
  const pairs = [];
  for (let i = 0; i < 9; i++) {
    let t0 = performance.now();
    await db.query(YARDSTICK);
    const yard = performance.now() - t0;
    t0 = performance.now();
    await db.query(`select * from public.get_town_feed(('2026-10-08 12:00'::timestamp at time zone 'America/Chicago'))`);
    pairs.push({ feed: performance.now() - t0, yard });
  }
  const mid = (xs) => xs.sort((a, b) => a - b)[4];
  const ms = mid(pairs.map((p) => p.feed));
  const yard = mid(pairs.map((p) => p.yard));
  const ratio = mid(pairs.map((p) => p.feed / p.yard));
  console.log(`  get_town_feed with 5,000 people: median ${ms.toFixed(1)} ms, yardstick ${yard.toFixed(1)} ms, ` +
              `${ratio.toFixed(2)} yardsticks`);
  assert.ok(ratio < FEED_YARDSTICKS, `median ${ratio.toFixed(2)} yardsticks (${ms.toFixed(1)} ms against ` +
            `${yard.toFixed(1)} ms), budget ${FEED_YARDSTICKS}`);
  const reasons = (await feed('2026-10-08 12:00')).filter((r) => r.reason === 'follow').length;
  assert.ok(reasons > 20, `${reasons} Events lifted by a follow`);
  await db.exec(`reset role; delete from public.places where entry_id like 'speed-place-%'`);
});

test("each event carries its place's picture: a photo before a logo, else the place's Search logo", async () => {
  await reset();
  await db.exec(`delete from public.place_photos; delete from public.places;
    insert into public.place_photos (entry_id, url, source_url, position, kind, status, hue, width, height) values
      ('krewe', 'https://x/logo.webp', 'https://krewemn.com/', 0, 'logo', 'live', 20, 1024, 1024),
      ('krewe', 'https://x/food.webp', 'https://krewemn.com/', 1, 'photo', 'live', null, 1600, 1067),
      ('krewe', 'https://x/bar.webp', 'https://krewemn.com/menu', 2, 'photo', 'live', null, 1200, 1600),
      ('krewe', 'https://x/old.webp', 'https://krewemn.com/', 0, 'photo', 'retired', null, 1600, 900),
      ('kennedy', 'https://x/k.webp', 'https://kennedy.isd742.org/', 0, 'logo', 'live', 220, null, null);
    insert into public.places (lat, lon, family, name, entry_id, logo_url, search_logo) values
      (45.5, -94.3, 'business', 'Sal''s Bar & Grill', 'sals', 'https://x/pin.png', '{"url":"https://x/sals.webp","hue":7,"chroma":true}'),
      (45.5, -94.3, 'business', 'Coborn''s', 'coborns', 'https://x/coborns-pin.png', null),
      (45.5, -94.3, 'business', 'Grey Co', 'grey', null, '{"url":"https://x/grey.webp","hue":40,"chroma":false}');`);
  const pick = async (id) => (await db.query('select public.place_picture($1) as p', [id])).rows[0].p;
  assert.deepEqual(await pick('krewe'), { url: 'https://x/food.webp', kind: 'photo', credit: null,
                                          site: 'https://krewemn.com/', w: 1600, h: 1067,
                                          more: [{ url: 'https://x/bar.webp', kind: 'photo', credit: null,
                                                   site: 'https://krewemn.com/menu', w: 1200, h: 1600 }] },
                   "a photo wins over a logo in an earlier slot, brings its size and the place's other live photos");
  assert.deepEqual(await pick('kennedy'), { url: 'https://x/k.webp', kind: 'logo', hue: 220 });
  assert.deepEqual(await pick('sals'), { url: 'https://x/sals.webp', kind: 'logo', hue: 7 }, "Search's cut-out");
  assert.equal(await pick('coborns'), null, "never the map pin's logo on its white square");
  assert.deepEqual(await pick('grey'), { url: 'https://x/grey.webp', kind: 'logo', hue: null }, 'a grey logo has no hue');
  assert.equal(await pick('nowhere'), null);
  assert.equal(await pick(null), null);

  await db.query(`insert into public.club_events (status, title, event_date, source_name, place_entry_id, created_at)
                  values ('approved', 'Trivia', '2026-10-09', 'Krewe', 'krewe', '2026-09-01 12:00-05'),
                         ('approved', 'Walk', '2026-10-09', $1, null, '2026-09-01 12:00-05')`, [CITY]);
  await db.exec('set role anon');
  const { rows } = await db.query(`select title, place_picture
    from public.flat_town_feed(('2026-10-08 12:00'::timestamp at time zone 'America/Chicago')) order by title`);
  await db.exec('reset role');
  assert.deepEqual(rows.map((r) => [r.title, r.place_picture?.url ?? null]),
                   [['Trivia', 'https://x/food.webp'], ['Walk', null]], 'signed out too');
  await db.exec('delete from public.place_photos; delete from public.places;');
});

test("an event card shows its place's photo of what the event is, in season, taking turns (event-photos 07)", async () => {
  await reset();
  // Fixed photo ids here and fixed Event ids below: an Event's turn is md5(Event id || photo id),
  // and with random ids all 8 fall Events picked one photo about 1 run in 128 (CI run 41114834248).
  await db.exec(`delete from public.place_photos; delete from public.places;
    insert into public.place_photos (id, entry_id, url, source_url, position, kind, status, width, height, subjects, seasons, description)
    overriding system value values
      (701, 'arena', 'https://x/cover.webp', 'https://arena.org/', 0, 'photo', 'live', 1600, 1067, '{}', '{}', null),
      (702, 'arena', 'https://x/hockey-a.webp', 'https://arena.org/g', 1, 'scene', 'live', 1600, 1067, '{hockey}', '{}', 'Hockey game in play'),
      (703, 'arena', 'https://x/hockey-b.webp', 'https://arena.org/g', 2, 'scene', 'live', 1600, 1067, '{hockey}', '{}', 'Fans cheering a goal'),
      (704, 'arena', 'https://x/hockey-snow.webp', 'https://arena.org/g', 3, 'scene', 'live', 1600, 1067, '{hockey}', '{winter}', 'Pond hockey in the snow'),
      (705, 'arena', 'https://x/hoops-fall.webp', 'https://arena.org/g', 4, 'scene', 'live', 1600, 1067, '{basketball}', '{fall}', 'Game in the fall'),
      (706, 'arena', 'https://x/hockey-gone.webp', 'https://arena.org/g', 0, 'scene', 'retired', 1600, 1067, '{hockey}', '{}', 'Taken down');`);
  const subject = async (t, s, c) => (await db.query('select private.event_subject($1, $2, $3) as s', [t, s, c])).rows[0].s;
  assert.equal(await subject('Sauna, Yoga, Ice Bath, Cider', null, 'health'), 'sauna', 'the same list as scenes.py');
  assert.equal(await subject('Cathedral vs Foley · JV', 'Boys Basketball', 'watch_sports'), 'basketball');
  assert.equal(await subject('The Nolan Lecture', null, 'faith'), 'talk');
  assert.equal(await subject('Central Lakes Jazz Festival', null, 'live_music'), 'band');
  assert.equal(await subject('Organic Gardening Workshop', null, null), 'talk', 'organic is no organ: \\y is a word edge');
  assert.equal(await subject('7th Grade', null, 'watch_sports'), 'sports');
  assert.equal(await subject('Fall Picture Retakes', null, null), 'place');
  assert.equal(await subject('Varsity Jazz', null, 'art_theater'), 'dance', "a dance team's jazz meet is dance, not band");
  assert.equal(await subject('Conference Kick', null, 'art_theater'), 'dance');
  assert.equal(await subject('Fare for All', null, 'markets'), 'market', 'food boxes, not a dinner');
  const season = async (d) => (await db.query('select private.season_of($1::date) as s', [d])).rows[0].s;
  assert.deepEqual([await season('2026-11-30'), await season('2026-12-01'), await season('2027-02-28')], ['fall', 'winter', 'winter']);

  const add = async (title, date, sport = null, id = null) => (await db.query(
    `insert into public.club_events (status, id, title, event_date, sport, category, source_name, place_entry_id)
     values ('approved', coalesce($4::uuid, gen_random_uuid()), $1, $2, $3, 'watch_sports', 'Arena', 'arena') returning id`,
    [title, date, sport, id])).rows[0].id;
  const pic = async (id) => (await db.query('select public.event_picture($1) as p', [id])).rows[0].p;
  const winter = await pic(await add('Hockey vs Foley', '2026-12-10', 'Boys Hockey'));
  assert.equal(winter.url, 'https://x/hockey-snow.webp', "a photo made for the event's season before one for any");
  assert.equal(winter.credit, null);
  assert.equal(winter.site, 'https://arena.org/g', 'credited to its page like a place photo');
  assert.deepEqual(winter.more.map((m) => m.url), ['https://x/cover.webp'], "the Event page's more: the place's photos, no scenes");
  const fall = [];
  for (const [i, d] of ['2026-11-02', '2026-11-03', '2026-11-04', '2026-11-05', '2026-11-06', '2026-11-07', '2026-11-08', '2026-11-09'].entries())
    fall.push((await pic(await add(`Hockey vs ${d}`, d, null, `00000000-0000-0000-0007-00000000000${i + 1}`))).url);
  assert.deepEqual([...new Set(fall)].sort(), ['https://x/hockey-a.webp', 'https://x/hockey-b.webp'],
                   'out of season the any-season photos take turns, never the snow one nor a retired one');
  assert.equal((await pic(await add('Hoops vs Albany', '2026-12-12', 'Girls Basketball'))).url, 'https://x/cover.webp',
               'a fall photo never shows in winter: the place picture instead');
  assert.equal((await pic(await add('Fall Picture Retakes', '2026-11-02'))).url, 'https://x/cover.webp', 'no subject: the place picture');
  assert.equal((await db.query("select public.place_picture('arena') as p")).rows[0].p.url, 'https://x/cover.webp',
               'a scene is never the place cover');
  assert.equal(await pic('00000000-0000-0000-0000-000000000000'), null);

  await db.exec(`delete from public.club_events;
                  insert into public.club_events (status, title, event_date, sport, category, source_name, place_entry_id, created_at)
                  values ('approved', 'Hockey vs Sartell', '2026-10-09', 'Boys Hockey', 'watch_sports', 'Arena', 'arena', '2026-09-01 12:00-05')`);
  await db.exec('set role anon');
  const { rows } = await db.query(`select title, place_picture
    from public.flat_town_feed(('2026-10-08 12:00'::timestamp at time zone 'America/Chicago'))`);
  await db.exec('reset role');
  assert.ok(['https://x/hockey-a.webp', 'https://x/hockey-b.webp'].includes(rows[0].place_picture.url),
            'the Town feed card carries the scene, signed out too');
  await db.exec('delete from public.place_photos; delete from public.places;');
});

test("an Event's own photo shows before any scene, credited, and is never its place's cover (event-photos 09)", async () => {
  await reset();
  await db.exec(`delete from public.place_photos; delete from public.places;
    insert into public.place_photos (entry_id, url, source_url, position, kind, status, width, height, subjects, seasons) values
      ('prep', 'https://x/prep.webp', 'https://sjprep.net/', 0, 'photo', 'live', 1600, 1067, '{}', '{}'),
      ('prep', 'https://x/stage.webp', 'https://sjprep.net/t', 1, 'scene', 'live', 1600, 1067, '{theater}', '{}');`);
  const add = async (title) => (await db.query(
    `insert into public.club_events (status, title, event_date, category, source_name, place_entry_id, created_at)
     values ('approved', $1, '2026-10-09', 'art_theater', 'Saint John''s Prep', 'prep', '2026-09-01 12:00-05') returning id`, [title])).rows[0].id;
  const own = (event, url, status = 'live', kind = 'event') => db.query(
    `insert into public.place_photos (entry_id, url, source_url, kind, status, event_id, credit, width, height)
     values ('prep', $2, 'https://www.facebook.com/SaintJohnsPrepMN/posts/1', $4, $3, $1, 'Saint John''s Prep', 1536, 2048)`,
    [event, url, status, kind]);
  const pic = async (id) => (await db.query('select public.event_picture($1) as p', [id])).rows[0].p;
  const fall = await add('Fall Play');
  const spring = await add('Spring Play');
  await own(fall, 'https://x/cast.webp');

  const p = await pic(fall);
  assert.deepEqual([p.url, p.credit, p.site, p.w, p.h], ['https://x/cast.webp', "Saint John's Prep",
    'https://www.facebook.com/SaintJohnsPrepMN/posts/1', 1536, 2048], 'its own photo before the scene, credited to its post');
  assert.deepEqual(p.more.map((m) => m.url), ['https://x/prep.webp'], "the Event page's more: the place's photos");
  assert.equal((await pic(spring)).url, 'https://x/stage.webp', "another Event never shows this one's photo");
  assert.equal((await db.query("select public.place_picture('prep') as p")).rows[0].p.url, 'https://x/prep.webp',
               "an Event's photo is never the place's cover, though it takes the cover's position");
  await assert.rejects(own(fall, 'https://x/second.webp'), /place_photos_one_per_event/, 'one live photo per Event');
  await assert.rejects(own(null, 'https://x/loose.webp'), /place_photos_event_kind/, "an Event's photo names its Event");
  await assert.rejects(own(spring, 'https://x/scene.webp', 'live', 'scene'), /place_photos_event_kind/, 'a scene names none');

  await db.exec('set role anon');
  const { rows } = await db.query(`select title, place_picture
    from public.flat_town_feed(('2026-10-08 12:00'::timestamp at time zone 'America/Chicago')) order by title`);
  await db.exec('reset role');
  assert.deepEqual(rows.map((r) => [r.title, r.place_picture.url]),
                   [['Fall Play', 'https://x/cast.webp'], ['Spring Play', 'https://x/stage.webp']], 'the Town feed card, signed out too');

  await db.query("update public.place_photos set status = 'retired' where event_id = $1", [fall]);
  assert.equal((await pic(fall)).url, 'https://x/stage.webp', 'taken down on request: the scene again');
  await db.query('delete from public.club_events where id = $1', [fall]);
  assert.equal((await db.query('select count(*)::int as n from public.place_photos where event_id is not null')).rows[0].n, 0,
               'an Event deleted takes its photo with it');
  await db.exec('delete from public.place_photos; delete from public.places;');
});

test("an Event's own flyer shows after the scene of what it is, before its place's photo (Jesse, 2026-11-02)", async () => {
  await reset();
  await db.exec(`delete from public.place_photos; delete from public.places;
    insert into public.place_photos (entry_id, url, source_url, position, kind, status, width, height, subjects, seasons) values
      ('bakery', 'https://x/pastry.webp', 'https://bakery.example/', 0, 'photo', 'live', 1307, 1600, '{}', '{}'),
      ('bakery', 'https://x/tasting.webp', 'https://bakery.example/t', 1, 'scene', 'live', 1600, 1067, '{talk}', '{}');`);
  const add = async (title) => (await db.query(
    `insert into public.club_events (status, title, event_date, category, source_name, place_entry_id, created_at)
     values ('approved', $1, '2026-10-09', 'dining', 'Bakery', 'bakery', '2026-09-01 12:00-05') returning id`, [title])).rows[0].id;
  const flyer = (event) => db.query(
    `insert into public.place_photos (entry_id, url, source_url, kind, status, event_id, credit, width, height)
     values ('bakery', 'https://x/flyer.webp', 'https://www.facebook.com/bakery/posts/1', 'flyer', 'live', $1, 'Bakery', 1080, 1080)`,
    [event]);
  const pic = async (id) => (await db.query('select public.event_picture($1) as p', [id])).rows[0].p;
  const pizza = await add('Pizza night');
  const talk = await add('Bread baking workshop');
  await flyer(pizza);
  await flyer(talk);

  const p = await pic(pizza);
  assert.deepEqual([p.url, p.credit, p.site], ['https://x/flyer.webp', 'Bakery', 'https://www.facebook.com/bakery/posts/1'],
                   'no scene fits: its own flyer, credited to its post, not the pastry photo');
  assert.deepEqual(p.more.map((m) => m.url), ['https://x/pastry.webp'], "the Event page's more: the place's photos");
  assert.equal((await pic(talk)).url, 'https://x/tasting.webp', 'a scene of what it is beats its flyer');
  assert.equal((await db.query("select public.place_picture('bakery') as p")).rows[0].p.url, 'https://x/pastry.webp',
               "a flyer is never the place's cover");
  await assert.rejects(flyer(pizza), /place_photos_one_per_event/, 'one live picture per Event, flyer or photo');
  await assert.rejects(db.query(`insert into public.place_photos (entry_id, url, source_url, kind, status) values
    ('bakery', 'https://x/loose.webp', 'https://bakery.example/', 'flyer', 'live')`), /place_photos_event_kind/, 'a flyer names its Event');
  await db.exec('delete from public.place_photos; delete from public.places;');
});

test('a Christmas photo shows on a holiday event from November 1, on any from December 1 to January 6 (event-photos 07)', async () => {
  await reset();
  await db.exec(`delete from public.place_photos;
    insert into public.place_photos (entry_id, url, source_url, position, kind, status, subjects, seasons) values
      ('shop', 'https://x/cover.webp', 'https://shop.com/', 0, 'photo', 'live', '{}', '{}'),
      ('shop', 'https://x/sweaters.webp', 'https://shop.com/', 1, 'scene', 'live', '{shopping}', '{christmas}'),
      ('shop', 'https://x/racks.webp', 'https://shop.com/', 2, 'scene', 'live', '{shopping}', '{}');`);
  const pic = async (title, date) => (await db.query('select public.event_picture($1) as p', [(await db.query(
    `insert into public.club_events (status, title, event_date, source_name, place_entry_id) values ('approved', $1, $2, 'Shop', 'shop')
     returning id`, [title, date])).rows[0].id])).rows[0].p.url;
  assert.equal(await pic('Boo-tique Bash', '2026-10-28'), 'https://x/racks.webp', 'never on a Halloween party');
  assert.equal(await pic('Black Friday', '2026-11-27'), 'https://x/sweaters.webp', 'a holiday event in November: it goes first');
  assert.equal(await pic('Open House', '2026-11-08'), 'https://x/racks.webp', 'not on any November event');
  assert.equal(await pic('Open House', '2026-12-03'), 'https://x/sweaters.webp', 'on any event in December');
  assert.equal(await pic('Pink Friday', '2027-01-06'), 'https://x/sweaters.webp');
  assert.equal(await pic('Black Friday', '2027-01-07'), 'https://x/racks.webp', 'gone after Epiphany');
  await db.exec('delete from public.place_photos;');
});

test("a girls' game never shows a boys' photo, nor the other way (event-photos 07, round 2)", async () => {
  await reset();
  await db.exec(`delete from public.place_photos;
    insert into public.place_photos (entry_id, url, source_url, position, kind, status, subjects, seasons) values
      ('gym', 'https://x/cover.webp', 'https://gym.org/', 0, 'photo', 'live', '{}', '{}'),
      ('gym', 'https://x/boys.webp', 'https://gym.org/', 1, 'scene', 'live', '{basketball,boys}', '{}');`);
  const pic = async (title, sport) => (await db.query('select public.event_picture($1) as p', [(await db.query(
    `insert into public.club_events (status, title, event_date, sport, source_name, place_entry_id) values ('approved', $1, '2026-12-10', $2, 'Gym', 'gym')
     returning id`, [title, sport])).rows[0].id])).rows[0].p.url;
  assert.equal(await pic('Sartell vs Forestview · 7th Grade', 'Girls Basketball'), 'https://x/cover.webp', "a girls' game: the place's picture");
  assert.equal(await pic("Women's Basketball vs Bethel", null), 'https://x/cover.webp', 'women is girls, though it holds "men"');
  assert.equal(await pic('Sartell vs Foley', 'Boys Basketball'), 'https://x/boys.webp');
  assert.equal(await pic('Basketball Tournament', null), 'https://x/boys.webp', 'a game naming neither takes either');
  assert.equal(await pic('CSB Basketball Home Opener', null), 'https://x/cover.webp', "CSB's teams are women's");
  assert.equal(await pic('SJU Basketball', null), 'https://x/boys.webp', "SJU's are men's");
  assert.equal(await pic('CSB/SJU Basketball Night', null), 'https://x/boys.webp', 'naming both names neither');
  await db.exec('delete from public.place_photos;');
});

test('each event carries its own description, for the Event page\'s About', async () => {
  await reset();
  const fair = await add('Fall fair', '2026-10-09');
  await add('Council meeting', '2026-10-09');
  await db.query(`update public.club_events set description = 'Apple cider and a hay ride.' where id = $1`, [fair]);
  await db.exec('set role anon');
  const { rows } = await db.query(`select title, description
    from public.flat_town_feed(('2026-10-08 12:00'::timestamp at time zone 'America/Chicago')) order by title`);
  await db.exec('reset role');
  assert.deepEqual(rows.map((r) => [r.title, r.description]),
                   [['Council meeting', null], ['Fall fair', 'Apple cider and a hay ride.']]);
});

test('each found event carries the page it was found on, for the Event page\'s link (2026-10-27)', async () => {
  await reset();
  const found = await add('Stitch and Sip', '2026-10-09');
  await add('Council meeting', '2026-10-09');
  await db.query(`update public.club_events set source_url = 'https://www.milkandhoneyciders.com/events' where id = $1`, [found]);
  await db.exec('set role anon');
  const { rows } = await db.query(`select title, kind, source_url
    from public.flat_town_feed(('2026-10-08 12:00'::timestamp at time zone 'America/Chicago')) order by title`);
  await db.exec('reset role');
  assert.deepEqual(rows.map((r) => [r.title, r.kind, r.source_url]),
                   [['Council meeting', 'event', null], ['Stitch and Sip', 'event', 'https://www.milkandhoneyciders.com/events']]);
});

test('each event says what it is in a few words, and the Event of the day says it too (event-card 05)', async () => {
  await reset();
  const talk = await add('Rev. Daniel Groody: Koch Chair Lecture', '2026-10-09', { start_time: '7 PM' });
  await add('Fall fair', '2026-10-09', { start_time: '10 AM' });
  await db.query(`update public.club_events set what = 'Lecture' where id = $1`, [talk]);
  await assert.rejects(db.query(`update public.club_events set what = '  ' where id = $1`, [talk]), 'no blank words');
  await assert.rejects(db.query(`update public.club_events set what = 'A very long way to say a lecture' where id = $1`, [talk]),
                       'one to three words, 24 characters at most');
  await db.exec('set role anon');
  const { rows } = await db.query(`select title, what
    from public.flat_town_feed(('2026-10-08 12:00'::timestamp at time zone 'America/Chicago')) order by title`);
  assert.deepEqual(rows.map((r) => [r.title, r.what]), [['Fall fair', null], ['Rev. Daniel Groody: Koch Chair Lecture', 'Lecture']]);
  const day = (await db.query(`select title, what, game
    from public.flat_event_of_the_day(('2026-10-09 18:00'::timestamp at time zone 'America/Chicago'))`)).rows;
  await db.exec('reset role');
  assert.deepEqual(day.map((r) => [r.title, r.what, r.game?.final ?? null]), [['Rev. Daniel Groody: Koch Chair Lecture', 'Lecture', null]]);
});

test('a game carries its sport, special night and both teams, the host first; any other Event none', async () => {
  await reset();
  const game = await add('SJU Football vs Concordia: Homecoming', '2026-10-09');
  const unseen = await add('Albany Volleyball vs Foley', '2026-10-09');
  await add('Fall fair', '2026-10-09');
  await db.exec(`insert into public.teams (id, name, short_name, logo_url, color) values
    ('saint-johns', 'Saint John''s', 'Saint John''s', 'https://x/sju.png', '#C20430'),
    ('concordia', 'Concordia', 'Concordia', null, null)`);
  await db.query(`update public.club_events set sport = 'Football', team_ids = array['saint-johns', 'concordia'],
    occasion = 'Homecoming' where id = $1`, [game]);
  // A team the writer named but no row yet (it always adds one): its id stands in for its name.
  await db.query(`update public.club_events set sport = 'Volleyball', team_ids = array['albany', 'foley'] where id = $1`,
                 [unseen]);
  await db.exec('set role anon');
  const { rows } = await db.query(`select title, game
    from public.flat_town_feed(('2026-10-08 12:00'::timestamp at time zone 'America/Chicago')) order by title`);
  await db.exec('reset role');
  // A team with a row carries its uuid (hello-drop 03); one with none, null. The uuid is random.
  const sju = rows.find((r) => r.title.startsWith('SJU')).game.teams[0];
  assert.match(sju.id, /^[0-9a-f-]{36}$/);
  const games = rows.map((r) => [r.title, r.game && { ...r.game, teams: r.game.teams.map(({ id, ...t }) => t) }]);
  assert.deepEqual(games, [
    ['Albany Volleyball vs Foley', { sport: 'Volleyball', occasion: null, teams: [
      { name: 'albany', short: 'albany', logo: null, color: null, local: false, colors: null, nickname: null },
      { name: 'foley', short: 'foley', logo: null, color: null, local: false, colors: null, nickname: null }], final: null, live: null, plays: null }],
    ['Fall fair', null],
    ['SJU Football vs Concordia: Homecoming', { sport: 'Football', occasion: 'Homecoming', teams: [
      { name: "Saint John's", short: "Saint John's", logo: 'https://x/sju.png', color: '#C20430', local: false, colors: null, nickname: null },
      { name: 'Concordia', short: 'Concordia', logo: null, color: null, local: false, colors: null, nickname: null }], final: null, live: null, plays: null }]]);
});

test("a game's final rides its game, host first, and keeps its card a day past the game", async () => {
  await reset();
  const game = await add('Sartell Girls Soccer vs Sauk Rapids-Rice', '2026-10-06', { start_time: '5 PM' });
  await add('Fall fair', '2026-10-07');
  await db.query(`update public.club_events set sport = 'Girls Soccer', team_ids = array['sartell', 'sauk-rapids-rice']
    where id = $1`, [game]);
  const at = async (t) => (await db.query(`select title, game, leaves_at, reason, reason_name
    from public.flat_town_feed(($1::timestamp at time zone 'America/Chicago')) order by title`, [t])).rows;
  // A game runs three hours, not two (Jesse at Check-in 2): on at 7:59, gone at 8 PM with no final yet.
  assert.deepEqual((await at('2026-10-06 19:59')).map((r) => r.title), ['Fall fair', 'Sartell Girls Soccer vs Sauk Rapids-Rice']);
  assert.deepEqual((await at('2026-10-06 20:30')).map((r) => r.title), ['Fall fair']);
  await db.query(`update public.club_events set final_score = array[6, 0] where id = $1`, [game]);
  const [row] = (await at('2026-10-06 20:30')).filter((r) => r.game);
  assert.deepEqual(row.game.final, [6, 0], 'in team_ids order, the host first');
  assert.deepEqual([row.reason, row.reason_name], ['final', null], 'its menu says Final score, not Happening today');
  assert.equal(row.leaves_at.toISOString(), '2026-10-08T01:00:00.000Z', 'a day past its 8 PM end');
  assert.deepEqual((await at('2026-10-07 19:59')).map((r) => r.title), ['Fall fair', 'Sartell Girls Soccer vs Sauk Rapids-Rice']);
  assert.deepEqual((await at('2026-10-07 20:01')).map((r) => r.title), ['Fall fair']);
  await assert.rejects(db.query(`update public.club_events set final_score = array[1] where id = $1`, [game]),
                       /club_events_final_score_pair/, 'two scores or none');
});

// The readers private.read_finals uses (20261021120000_game_finals.sql), on the sources' own JSON.
const schedules = JSON.parse(readFileSync(join(here, '..', '..', 'sources', 'scripts', 'samples', 'mshsl-schedules.json'), 'utf8'));
const csbHamline = JSON.parse(readFileSync(join(here, 'sidearm-csb-wsoc.json'), 'utf8'));
const leagueFinal = async (rows, uid, day, teams) => (await db.query(
  'select private.league_final($1::jsonb, $2, $3::date, $4::text[]) as f', [JSON.stringify(rows), uid, day, teams])).rows[0].f;
const sidearmFinal = async (file, day, host) => (await db.query(
  'select private.sidearm_final($1::jsonb, $2::date, $3) as f', [JSON.stringify(file), day, host])).rows[0].f;

test("a high school final is read from its lister's schedule: its row that day, the score its W, L or T agrees with", async () => {
  const sartell = schedules.sartell;
  // Sartell 6-0 Sauk Rapids-Rice girls soccer, Oct 6: Sartell's own row, Sartell the host.
  assert.deepEqual(await leagueFinal(sartell, 'mshsl:142:sartell|sauk rapids-rice:2', '2026-10-06',
                                     ['sartell', 'sauk-rapids-rice']), [6, 0]);
  // A loss: Sartell 0-2 Bemidji. The same row with Bemidji the host turns around.
  assert.deepEqual(await leagueFinal(sartell, 'mshsl:142:bemidji|sartell:1', '2026-09-17', ['sartell', 'bemidji']), [0, 2]);
  assert.deepEqual(await leagueFinal(sartell, 'mshsl:142:bemidji|sartell:1', '2026-09-17', ['bemidji', 'sartell']), [2, 0]);
  assert.deepEqual(await leagueFinal(sartell, 'mshsl:142:anoka|sartell:1', '2026-08-27', ['sartell', 'anoka']), [2, 2], 'a tie');
  assert.equal(await leagueFinal(sartell, 'mshsl:142:sartell|sauk rapids-rice:2', '2026-10-07',
                                 ['sartell', 'sauk-rapids-rice']), null, 'another day');
  // Tech's league name for itself is "St. Cloud": its row against Sartell (0-3) reads by the id's names.
  assert.deepEqual(await leagueFinal(schedules.tech, 'mshsl:142:sartell|st. cloud:1', '2026-09-15', ['sartell', 'st-cloud']), [3, 0]);
  const row = sartell.find((r) => r.event_date === '10/6/2026');
  const one = (change) => [{ ...row, ...change }];
  const uid = 'mshsl:142:sartell|sauk rapids-rice:2', teams = ['sartell', 'sauk-rapids-rice'];
  assert.equal(await leagueFinal(one({ scores: '', w_l: '' }), uid, '2026-10-06', teams), null, 'not entered yet');
  assert.equal(await leagueFinal(one({ w_l: 'L' }), uid, '2026-10-06', teams), null, 'a score its result disagrees with');
  assert.equal(await leagueFinal([row, { ...row, scores: '1-0' }], uid, '2026-10-06', teams), null, 'two that day');
  assert.equal(await leagueFinal({ error: 'down' }, uid, '2026-10-06', teams), null, 'not a schedule');
  assert.deepEqual((await db.query(`select array_agg(private.team_slug(n) order by o) as s from unnest(
    array['St. Cloud Apollo', 'Kimball Area', 'Apollo/Cathedral', 'St. John''s Prep', 'Sauk Rapids-Rice', 'St. Cloud'])
    with ordinality u(n, o)`)).rows[0].s, ['apollo', 'kimball', 'apollo-cathedral', 'st-johns-prep', 'sauk-rapids-rice', 'st-cloud'],
                   "the morning writer's team ids");
});

test("a college final is read from SIDEARM's file: complete, that day, the host first wherever it sits", async () => {
  // CSB 3-0 Hamline, Oct 14, as the file read back on 2026-10-20.
  assert.deepEqual(await sidearmFinal(csbHamline, '2026-10-14', 'benedict'), [3, 0]);
  assert.equal(await sidearmFinal(csbHamline, '2026-10-15', 'benedict'), null, 'the next game not played yet');
  const g = csbHamline.Game;
  assert.equal(await sidearmFinal({ Game: { ...g, IsComplete: false } }, '2026-10-14', 'benedict'), null, 'still on');
  assert.deepEqual(await sidearmFinal({ Game: { ...g, HomeTeam: g.VisitingTeam, VisitingTeam: g.HomeTeam } }, '2026-10-14', 'benedict'),
                   [3, 0], 'the host as visitors');
  assert.deepEqual(await sidearmFinal({ Game: { ...g, HomeTeam: { ...g.HomeTeam, Name: "#21 Saint John's", Score: 33 },
                                                VisitingTeam: { ...g.VisitingTeam, Name: 'Concordia', Score: 23 } } },
                                      '2026-10-14', 'john'), [33, 23], 'a ranked host');
  assert.equal(await sidearmFinal(csbHamline, '2026-10-14', 'john'), null, 'neither side ours');
});

// Live scores (game-card 03): SIDEARM's pushed Game to the card's live score, on the 2026-10-24 test's files.
const sjuLive = JSON.parse(readFileSync(join(here, 'sidearm-live-sju-msoc.json'), 'utf8'));
const sjuFinal = JSON.parse(readFileSync(join(here, 'sidearm-final-sju-msoc.json'), 'utf8'));
const csbOld = JSON.parse(readFileSync(join(here, 'sidearm-old-csb-wvball.json'), 'utf8'));
// SJU 27-3 Gustavus, 2026-10-31, as SIDEARM's file held it once the game was over (game-card 08).
const sjuFootball = JSON.parse(readFileSync(join(here, 'sidearm-final-sju-football.json'), 'utf8'));
const sidearmLiveAll = async (game, day, host, file) => (await db.query(
  'select private.sidearm_live($1::jsonb, $2::date, $3, $4) as l', [JSON.stringify(game), day, host, file])).rows[0].l;
// The score, period and clock; the period scores and the host's side have their own checks (game-card 05).
const sidearmLive = async (...args) => {
  const l = await sidearmLiveAll(...args);
  if (!l) return l;
  const { periods, host_home, drive, ...rest } = l;
  return rest;
};

test("a live score is read from SIDEARM's Game: host first, the sport's period and clock, another day's game none", async () => {
  // SJU 0-0 Carleton, 94 s into the first half: soccer's clock counts up, so its minute.
  assert.deepEqual(await sidearmLive(sjuLive, '2026-10-24', 'john', 'csbsju/msoc'),
                   { score: [0, 0], period: '1st half', clock: "2'", clock_s: 94, complete: false });
  assert.deepEqual(await sidearmLive({ Game: sjuFinal }, '2026-10-24', 'john', 'csbsju/msoc'),
                   { score: [2, 1], period: '2nd half', clock: "91'", clock_s: 5400, complete: true }, 'the file form too');
  assert.equal(await sidearmLive(csbOld, '2026-10-24', 'benedict', 'csb/wvball'), null,
               "the file still holding last week's game (Oct 17) before Saturday's began");
  assert.deepEqual(await sidearmLive(csbOld, '2026-10-17', 'benedict', 'csb/wvball'),
                   { score: [3, 0], period: 'Set 3', clock: null, clock_s: null, complete: true }, 'volleyball: the set, no clock');
  const away = { ...sjuLive, HomeTeam: { ...sjuLive.VisitingTeam, Score: 7 }, VisitingTeam: { ...sjuLive.HomeTeam, Score: 14 },
                 Period: 3, ClockSeconds: 252 };
  assert.deepEqual(await sidearmLive(away, '2026-10-24', 'john', 'csbsju/football'),
                   { score: [14, 7], period: 'Q3', clock: '4:12', clock_s: 252, complete: false }, 'the host away, football counting down');
  assert.equal((await sidearmLive({ ...away, Period: 5 }, '2026-10-24', 'john', 'csbsju/football')).period, 'OT');
  assert.equal((await sidearmLive({ ...away, Period: 2 }, '2026-10-24', 'john', 'csbsju/mbball')).period, '2nd half',
               "men's basketball plays halves");
  assert.equal((await sidearmLive({ ...away, Period: 2 }, '2026-10-24', 'john', 'csb/wbball')).period, 'Q2',
               "women's quarters");
  assert.equal(await sidearmLive({ ...sjuLive, HasStarted: false }, '2026-10-24', 'john', 'csbsju/msoc'), null, 'not started');
  assert.equal(await sidearmLive(sjuLive, '2026-10-24', 'benedict', 'csbsju/msoc'), null, 'the host on neither side');
  const sets = await sidearmLiveAll(csbOld, '2026-10-17', 'benedict', 'csb/wvball');
  assert.deepEqual([sets.periods[0], sets.periods[1].length, sets.host_home], [[25, 25, 25], 3, true],
                   "volleyball's sets, the host's first");
  assert.equal((await sidearmLiveAll(away, '2026-10-24', 'john', 'csbsju/football')).host_home, false, 'the host away');
});

test("a live football score carries the down, distance and spot of SIDEARM's newest play, and who has the ball", async () => {
  const drive = async (game, host = 'john') => (await sidearmLiveAll(game, '2026-10-31', host, 'csbsju/football')).drive;
  // The file's newest rows are "End of game." and "End of 4th quarter." (Type #), which name Gustavus; Saint
  // John's ran the last real play, 1st and 10 on the Gustavus 49: 51 yards from its own goal line.
  assert.deepEqual(await drive(sjuFootball), { down: 1, togo: '10', spot: 'GAC49', side: 0, ball: 51 });
  const play = (p) => ({ Game: { ...sjuFootball.Game, LastPlays: [{ ...sjuFootball.Game.LastPlays[2], ...p }] } });
  assert.deepEqual(await drive(play({ Down: 2, ToGo: '7', Spot: 'SJU34', Team: 'VisitingTeam' })),
                   { down: 2, togo: '7', spot: 'SJU34', side: 1, ball: 34 }, "Gustavus's ball in Saint John's half");
  assert.equal((await drive(play({ Spot: '50' }))).ball, 50, 'midfield names neither side');
  assert.equal((await drive(play({ Spot: 'XYZ20' }))).ball, null, "a spot naming neither team: the words, no ball");
  // After a touchdown the newest plays are the extra point and the kickoff, with no down: no bar, never the
  // scorer's last snap before them.
  const snap = { ...sjuFootball.Game.LastPlays[2], Down: 1, ToGo: 'Goal', Spot: 'GAC3', Team: 'HomeTeam' };
  const kick = { ...sjuFootball.Game.LastPlays[2], Type: 'Kickoff', Down: null, ToGo: null, Spot: 'SJU35' };
  assert.equal(await drive({ Game: { ...sjuFootball.Game, LastPlays: [kick, snap] } }), null, 'a kickoff has no down');
  assert.equal(await drive({ Game: { ...sjuFootball.Game, LastPlays: [] } }), null, 'no plays yet');
  const away = { Game: { ...sjuFootball.Game, HomeTeam: sjuFootball.Game.VisitingTeam, VisitingTeam: sjuFootball.Game.HomeTeam,
                         LastPlays: [{ ...sjuFootball.Game.LastPlays[2], Team: 'VisitingTeam' }] } };
  assert.deepEqual(await drive(away), { down: 1, togo: '10', spot: 'GAC49', side: 0, ball: 51 },
                   'the host away: still side 0, and the yards still from its own goal');
  assert.equal((await sidearmLiveAll(sjuFootball, '2026-10-31', 'john', 'csbsju/msoc')).drive, null, 'only football');
});

test('a pushed score lands on its game; two complete reads in a row make the final, and a final clears it', async () => {
  await reset();
  const game = await add('SJU Soccer vs Carleton', '2026-10-24', { start_time: '1 PM', source_name: 'SJU Athletics' });
  await add('SJU Soccer vs Carleton', '2026-10-31', { start_time: '1 PM', source_name: 'SJU Athletics' });
  await db.query(`update public.club_events set sport = 'Soccer', team_ids = array['saint-johns', 'carleton']
    where source_name = 'SJU Athletics'`);
  const record = async (g) => (await db.query('select public.record_live_score($1, $2::jsonb) as r',
                                              [game, JSON.stringify(g)])).rows[0].r;
  const row = async () => (await db.query('select live_score, final_score, final_checked_at from public.club_events where id = $1',
                                          [game])).rows[0];
  // Which games a listener joins: this one from 15 minutes before its start, by its school and sport's channel.
  const on = async (t) => (await db.query(`select id, grp from private.live_games(($1::timestamp at time zone 'America/Chicago'))`,
                                          [t])).rows;
  assert.deepEqual(await on('2026-10-24 12:40'), []);
  assert.deepEqual(await on('2026-10-24 12:50'), [{ id: game, grp: 'livestats/csbsju/msoc/game' }]);
  assert.equal(await record(csbOld), 'ignored', 'not its game');
  assert.equal(await record(sjuLive), 'live');
  const live = (await row()).live_score;
  assert.deepEqual([live.score, live.period, live.complete], [[0, 0], '1st half', false]);
  const at = live.at;
  await record(sjuLive);
  assert.equal((await row()).live_score.at, at, 'a push that changed nothing writes nothing, so realtime stays quiet');
  // A clock standing still (2026-10-31: football's, between plays): once 'at' is a minute old, the same push writes
  // it again, so the app doesn't hide a clock SIDEARM still shows as stale.
  await db.query(`update public.club_events set live_score = jsonb_set(live_score, '{at}', to_jsonb(now() - interval '61 seconds'))
    where id = $1`, [game]);
  const old = (await row()).live_score.at;
  await record(sjuLive);
  assert.ok(new Date((await row()).live_score.at) > new Date(old), 'a minute-old score SIDEARM confirms is written again');
  // The feed sends it in the game and keeps a game being played two more hours: still there at 5:30.
  await db.exec('set role anon');
  const feed = async (t) => (await db.query(`select game from public.flat_town_feed(($1::timestamp at time zone 'America/Chicago'))
    where game is not null`, [t])).rows;
  assert.deepEqual((await feed('2026-10-24 13:05'))[0].game.live.score, [0, 0]);
  assert.equal((await feed('2026-10-24 17:30')).length, 1);
  await db.exec('reset role');
  assert.equal(await record(sjuFinal), 'live', 'complete once is not yet final: the 2026-10-24 volleyball flickered');
  assert.equal((await row()).live_score.complete, true);
  assert.equal((await row()).final_checked_at, null);
  assert.equal(await record(sjuFinal), 'final');
  assert.deepEqual((await row()).final_score, [2, 1]);
  assert.ok((await row()).final_checked_at, "a final read live is read: the hello pill's team finals list it");
  assert.equal((await row()).live_score.complete, true, 'the last live score stays beside the final, for its period scores');
  assert.equal(await record(sjuLive), 'ignored', 'nothing moves a final');
  assert.deepEqual(await on('2026-10-24 13:30'), [], 'a final game is no longer listened to');
  // A doubleheader can't be told apart on one channel: neither is listened to.
  await db.query(`update public.club_events set final_score = null where id = $1`, [game]);
  await add('SJU Soccer vs Augsburg', '2026-10-24', { start_time: '4 PM', source_name: 'SJU Athletics' });
  await db.query(`update public.club_events set sport = 'Soccer', team_ids = array['saint-johns', 'augsburg']
    where title = 'SJU Soccer vs Augsburg'`);
  assert.deepEqual(await on('2026-10-24 13:30'), []);
});

test('scoring plays are kept as SIDEARM lists them: each play that changed the score, once, host first', async () => {
  await reset();
  const game = await add('SJU Football vs Gustavus Adolphus', '2026-10-24', { start_time: '1 PM', source_name: 'SJU Athletics' });
  await db.query(`update public.club_events set sport = 'Football', team_ids = array['saint-johns', 'gustavus-adolphus']
    where id = $1`, [game]);
  const record = async (g) => (await db.query('select public.record_live_score($1, $2::jsonb) as r',
                                              [game, JSON.stringify(g)])).rows[0].r;
  const plays = async () => (await db.query('select scoring_plays from public.club_events where id = $1', [game])).rows[0].scoring_plays;
  const play = (id, text, team, period, cs, home, away) => ({ Id: id, Narrative: text, Team: team, Type: 'TD', Period: period,
    ClockSeconds: cs, Score: home == null ? null : { HomeTeam: home, VisitingTeam: away } });
  // SJU at home, a touchdown in the first quarter; a kickoff that changed nothing stays out.
  const first = { ...sjuLive, Type: 'FootballGame', HomeTeam: { ...sjuLive.HomeTeam, Score: 7 }, VisitingTeam: { ...sjuLive.VisitingTeam, Name: 'Gustavus', Score: 0 },
                  Period: 1, ClockSeconds: 558,
                  LastPlays: [play('9', 'C. Kern 1 yd TD run (M. Olson kick)', 'HomeTeam', 1, 558, 7, 0),
                              play('8', 'Kickoff by Gustavus', 'VisitingTeam', 1, 900, null, null)] };
  assert.equal(await record(first), 'live');
  assert.deepEqual(await plays(), [{ id: '9', text: 'C. Kern 1 yd TD run (M. Olson kick)', period: 'Q1', clock: '9:18', side: 0, score: [7, 0] }]);
  // The same play pushed again, then a plays push (no team names): Gustavus scores, read with the host still home.
  await record(first);
  assert.equal(await record([play('12', 'A. Moen 7 yd TD run (T. Lund kick)', 'VisitingTeam', 1, 175, 7, 7)]), 'live');
  assert.deepEqual((await plays()).map((p) => [p.id, p.side, p.score]), [['9', 0, [7, 0]], ['12', 1, [7, 7]]], 'once each, oldest first');
  // SIDEARM corrects a play it already sent (2026-10-31: a field goal first sent with the score before it): the
  // correction takes the play's place, and a push that changes nothing writes nothing.
  assert.equal(await record([play('14', 'M. Hansen 35 yd FG', 'HomeTeam', 2, 314, 7, 7)]), 'live');
  assert.equal(await record([play('14', 'M. Hansen 35 yd FG', 'HomeTeam', 2, 314, 10, 7)]), 'live');
  assert.deepEqual((await plays()).map((p) => [p.id, p.score]), [['9', [7, 0]], ['12', [7, 7]], ['14', [10, 7]]],
                   'the correction, in its place');
  assert.equal(await record([play('14', 'M. Hansen 35 yd FG', 'HomeTeam', 2, 314, 10, 7)]), 'ignored', 'nothing new');
  // The feed sends them inside the game.
  await db.exec('set role anon');
  const [row] = (await db.query(`select game from public.flat_town_feed(('2026-10-24 13:30'::timestamp at time zone 'America/Chicago'))
    where game is not null`)).rows;
  await db.exec('reset role');
  assert.equal(row.game.plays.length, 3);
  // Volleyball keeps none: every point carries a score; its sets show instead.
  assert.deepEqual((await db.query(`select private.sidearm_scoring($1::jsonb, true, 'csb/wvball') as s`,
                                   [JSON.stringify(csbOld.LastPlays ?? csbOld.Game?.LastPlays ?? [])])).rows[0].s, []);
});

test("a goal SIDEARM rewrites as its words fill in stays one play, the newest words, in its place (game-card 13)", async () => {
  await reset();
  const game = await add('CSB Soccer vs Macalester', '2026-11-03', { start_time: '2 PM', source_name: 'CSB Athletics' });
  await db.query(`update public.club_events set sport = 'Soccer', team_ids = array['saint-benedict', 'macalester'],
    live_score = '{"host_home": true}' where id = $1`, [game]);
  const record = async (g) => (await db.query('select public.record_live_score($1, $2::jsonb) as r',
                                              [game, JSON.stringify(g)])).rows[0].r;
  const plays = async () => (await db.query('select scoring_plays from public.club_events where id = $1', [game])).rows[0].scoring_plays;
  const shot = (id, text, team, home, away) => ({ Id: id, Narrative: text, Team: team, Type: 'SHOT', Period: 1, ClockSeconds: 1740,
    Score: { HomeTeam: home, VisitingTeam: away } });
  // Tuesday's real pushes: Macalester's goal, then CSB's, its words filling in over three pushes.
  assert.equal(await record([shot('45+A54025FA', 'Shot by MAC Arredondo,Ava, low right, GOAL', 'VisitingTeam', 0, 1)]), 'live');
  assert.equal(await record([shot('73+FC3012F3', 'Shot by CSB , GOAL', 'HomeTeam', 1, 1)]), 'live');
  assert.equal(await record([shot('73+BEFCE2EA', 'Shot by CSB Warren,Veronica, high right, GOAL', 'HomeTeam', 1, 1)]), 'live');
  assert.equal(await record([shot('73+385945FD', 'Shot by CSB Warren,Veronica, high right, GOAL; Assist by CSB Fernholz,Gabby', 'HomeTeam', 1, 1)]), 'live');
  assert.deepEqual((await plays()).map((p) => [p.id, p.text]),
                   [['45', 'Shot by MAC Arredondo,Ava, low right, GOAL'],
                    ['73', 'Shot by CSB Warren,Veronica, high right, GOAL; Assist by CSB Fernholz,Gabby']], 'two goals, two plays');
  // A scorer SIDEARM renames (Augsburg's 88th, Casias then Paradiso) takes the place.
  assert.equal(await record([shot('260+F8BFA6D9', 'Shot by AUG Casias,Gio, low right, GOAL', 'VisitingTeam', 1, 2)]), 'live');
  assert.equal(await record([shot('260+1FECA06E', 'Shot by AUG Paradiso,Liam, low right, GOAL', 'VisitingTeam', 1, 2)]), 'live');
  assert.deepEqual((await plays()).map((p) => p.id), ['45', '73', '260']);
  assert.equal((await plays())[2].text, 'Shot by AUG Paradiso,Liam, low right, GOAL');
  assert.equal(await record([shot('260+1FECA06E', 'Shot by AUG Paradiso,Liam, low right, GOAL', 'VisitingTeam', 1, 2)]), 'ignored', 'the same words again');
});

// CSB 79-57 Augsburg, 2026-02-21: SIDEARM's game file once it was over, with every foul and a few baskets from its
// full play list (game-card 09). SIDEARM's own Personal Fouls per quarter: Saint Benedict 3, 3, 6, 5; Augsburg 3, 3, 10, 5.
const csbHoops = JSON.parse(readFileSync(join(here, 'sidearm-final-csb-wbball.json'), 'utf8'));

test("a live basketball score carries the period being played, how many make the game and its length (game-card 09)", async () => {
  const bar = async (game, file = 'csb/wbball') => {
    const l = await sidearmLiveAll(game, '2026-02-21', 'benedict', file);
    return [l.period, l.clock, l.period_n, l.regulation, l.period_s];
  };
  assert.deepEqual(await bar(csbHoops), ['Q4', '0:00', 4, 4, 600], "CSB's women: four 10-minute quarters");
  assert.deepEqual(await bar({ Game: { ...csbHoops.Game, Period: 5, ClockSeconds: 151 } }), ['OT', '2:31', 5, 4, 300],
                   'overtime is 5 minutes');
  const men = { Game: { ...csbHoops.Game, PeriodsRegulation: 2, Period: 2, ClockSeconds: 372,
                        Rules: { ...csbHoops.Game.Rules, PeriodMinutes: 20, PeriodName: 'Half' } } };
  assert.deepEqual(await bar(men, 'csbsju/mbball'), ['2nd half', '6:12', 2, 2, 1200], "SJU's men: two 20-minute halves");
  const l = await sidearmLiveAll(sjuFootball, '2026-10-31', 'john', 'csbsju/football');
  assert.deepEqual([l.period_n, l.regulation, l.period_s], [undefined, undefined, undefined], 'only basketball');
});

test("basketball keeps each team's fouls this quarter by play, as SIDEARM counts them, however the plays come (game-card 09)", async () => {
  await reset();
  const game = await add('CSB Basketball vs Augsburg', '2026-02-21', { start_time: '1 PM', source_name: 'CSB Athletics' });
  await db.query(`update public.club_events set sport = 'Basketball', team_ids = array['saint-benedict', 'augsburg']
    where id = $1`, [game]);
  const record = async (g) => (await db.query('select public.record_live_score($1, $2::jsonb) as r',
                                              [game, JSON.stringify(g)])).rows[0].r;
  const live = async () => (await db.query('select live_score from public.club_events where id = $1', [game])).rows[0].live_score;
  const fouls = async () => { const f = (await live()).fouls; return [f.period, f.ids[0].length, f.ids[1].length]; };
  // A Game push while it's on: that period, the clock mid-quarter, its newest plays.
  const at = (period, plays = []) => ({ Game: { ...csbHoops.Game, IsComplete: false, Period: period, ClockSeconds: 300,
                                                LastPlays: plays } });
  // Game pushes walking the game's plays in order, each with the newest five, as SIDEARM's LastPlays: at each
  // quarter's end the count is SIDEARM's own.
  const plays = csbHoops.Plays, ends = [];
  for (let i = 0; i < plays.length; i++) {
    await record(at(plays[i].Period, plays.slice(Math.max(0, i - 4), i + 1).reverse()));
    if (plays[i + 1]?.Period !== plays[i].Period) ends.push(await fouls());
  }
  assert.deepEqual(ends, [[1, 3, 3], [2, 3, 3], [3, 6, 10], [4, 5, 5]], "the host's and Augsburg's, each quarter");
  // A new quarter starts empty; a plays push of the whole list counts the same, and again changes nothing.
  await record(at(3));
  assert.deepEqual(await fouls(), [4, 5, 5], 'the period never goes back');
  await db.query('update public.club_events set live_score = null, scoring_plays = null where id = $1', [game]);
  assert.equal(await record(plays), 'ignored', 'no score yet: whose side a play is on is unknown');
  assert.equal(await live(), null, 'no score yet: the fouls wait for one');
  await record(at(3));
  assert.deepEqual(await fouls(), [3, 0, 0]);
  // Late in the 3rd: the plays so far.
  const sofar = plays.filter((p) => p.Period <= 3), before = (await live()).at;
  assert.equal(await record(sofar), 'live');
  assert.deepEqual(await fouls(), [3, 6, 10]);
  assert.equal((await live()).at, before, "a plays push keeps the score's time");
  assert.equal(await record({ Plays: sofar }), 'ignored', 'the same fouls again');
  // Overtime counts with the 4th quarter (the NCAA's rule).
  await record(at(4, plays.filter((p) => p.Period === 4)));
  const foul = plays.find((p) => p.Type === 'FOUL' && p.Team === 'VisitingTeam');
  await record(at(5, [{ ...foul, Id: 'ot-1', Period: 5 }]));
  assert.deepEqual(await fouls(), [4, 5, 6]);
  // SIDEARM rewrites a foul's words: the same place in its list, a new hash, still one foul (game-card 13).
  await record(at(5, [{ ...foul, Id: 'ot-1+5A603CF4', Period: 5 }]));
  assert.deepEqual(await fouls(), [4, 5, 6], 'a rewritten foul counts once');
  // The feed sends them inside the live score.
  await db.exec('set role anon');
  const [row] = (await db.query(`select game from public.flat_town_feed(('2026-02-21 14:30'::timestamp at time zone 'America/Chicago'))
    where game is not null`)).rows;
  await db.exec('reset role');
  assert.deepEqual(row.game.live.fouls.ids.map((s) => s.length), [5, 6]);
  assert.deepEqual([row.game.live.period_n, row.game.live.regulation, row.game.live.period_s], [5, 4, 300]);
});

test("a minute-old basketball score SIDEARM confirms is written again with its fouls and bar, so Bonus keeps counting", async () => {
  await reset();
  const game = await add('CSB Basketball vs Augsburg', '2026-02-21', { start_time: '1 PM', source_name: 'CSB Athletics' });
  await db.query(`update public.club_events set sport = 'Basketball', team_ids = array['saint-benedict', 'augsburg']
    where id = $1`, [game]);
  const live = async () => (await db.query('select live_score from public.club_events where id = $1', [game])).rows[0].live_score;
  // Mid-1st, the quarter's fouls so far: the clock then stands still (a timeout), and SIDEARM pushes the same Game.
  const push = { Game: { ...csbHoops.Game, IsComplete: false, Period: 1, ClockSeconds: 300,
                         LastPlays: csbHoops.Plays.filter((p) => p.Period === 1 && p.Type === 'FOUL') } };
  await db.query('select public.record_live_score($1, $2::jsonb)', [game, JSON.stringify(push)]);
  const before = await live();
  assert.deepEqual(before.fouls.ids.map((s) => s.length), [3, 3]);
  await db.query(`update public.club_events set live_score = jsonb_set(live_score, '{at}', to_jsonb(now() - interval '61 seconds'))
    where id = $1`, [game]);
  const old = (await live()).at;
  await db.query('select public.record_live_score($1, $2::jsonb)', [game, JSON.stringify(push)]);
  const after = await live();
  // Against the minute-old time, not the first push's: two pushes can land in the same millisecond.
  assert.ok(new Date(after.at) > new Date(old), 'written again');
  const { at: _a, ...kept } = before, { at: _b, ...now } = after;
  assert.deepEqual(now, kept, 'the fouls, period_n, regulation and period_s all kept');
});

test('one listener at a time: the games are handed out at most once in 50 seconds', async () => {
  await db.exec('delete from private.live_listener');
  const start = async () => (await db.query('select count(*)::int as n from public.start_live_scores()')).rows[0].n;
  const claimed = async () => (await db.query('select count(*)::int as n from private.live_listener')).rows[0].n;
  await start();
  assert.equal(await claimed(), 1);
  const until = (await db.query('select until from private.live_listener')).rows[0].until;
  await start();
  assert.deepEqual((await db.query('select until from private.live_listener')).rows[0].until, until, 'the second start does nothing');
  // Judged against the claim that ran out, a second in the past, never against the first claim: the
  // two claims can be under a millisecond apart on a fast Mac and read back as the same time.
  const ranOut = (await db.query(`update private.live_listener set until = now() - interval '1 second'
                                  returning until`)).rows[0].until;
  await start();
  const fresh = (await db.query('select until from private.live_listener')).rows[0].until;
  assert.ok(fresh - ranOut > 50000, `free again after it runs out: claimed ${fresh - ranOut} ms past the old claim`);
  for (const fn of ['public.start_live_scores()', 'public.record_live_score(uuid, jsonb)'])
    assert.equal((await db.query(`select has_function_privilege('anon', $1, 'execute') as ok`, [fn])).rows[0].ok, false,
                 `${fn}: the service role only`);
});

test("a group's Event names the group and whether you're in it; found ones by its site or its name at its place", async () => {
  await reset();
  const GROUP = '00000000-0000-0000-0000-0000000000c1', QUILTS = '00000000-0000-0000-0000-0000000000c2';
  const PENDING = '00000000-0000-0000-0000-0000000000c3';
  await db.query(`insert into public.clubs (id, name, status, place_entry_id) values
      ($1, 'Rod and Gun Club', 'approved', 'legion'), ($2, 'Stitch and Sip', 'approved', 'cidery'),
      ($3, 'Book Club', 'pending', 'cidery')`, [GROUP, QUILTS, PENDING]);
  // The live migration's own line gives the Rod and Gun Club its website.
  await db.exec(`update public.clubs set entry_id = 'group-st-joe-rod-and-gun-club' where id = '${GROUP}'`);
  await db.exec(readFileSync(join(migrations, '20261019180000_group_join_on_cards.sql'), 'utf8')
    .match(/update public\.clubs set own_entry_id[^;]*;/)[0]);
  await db.query(`insert into public.sources (town, status, method, entry_id, url, name) values
      ('st-joseph-mn', 'active', 'fetch', 'st-joe-rod-gun-club', 'https://stjoerodandgunclub.org/events/?ical=1', 'St Joe Rod and Gun Club'),
      ('st-joseph-mn', 'active', 'fetch', 'cidery', 'https://cidery.example/events', 'Milk & Honey Ciders')`);
  const at = (title, more) => add(title, '2026-10-09', { start_time: '6 PM', ...more });
  await at('Monthly Meeting', { source_name: 'St Joe Rod and Gun Club' });
  const stitch = await at('Stitch and Sip', { source_name: 'Milk & Honey Ciders' });
  const bingo = await at('Plant Bingo', { source_name: 'Milk & Honey Ciders' });
  const posted = await at('Stitch and Sip', { source_name: null, submitted_by: ME });
  const reading = await at('Book Club', { source_name: 'Milk & Honey Ciders' });
  await db.query(`update public.club_events set place_entry_id = 'cidery' where id = any($1)`,
                 [[stitch, bingo, posted, reading]]);
  const posting = await at('Lions pancake breakfast', { source_name: null, submitted_by: ME });
  await db.query('update public.club_events set club_id = $1 where id = $2', [GROUP, posting]);

  const groups = async () => (await db.query(`select title, club_name, source_name, club_id, in_club
    from public.flat_town_feed(('2026-10-08 12:00'::timestamp at time zone 'America/Chicago'))
    order by title, source_name nulls first`)).rows.map((r) => [r.title.trim(), r.club_name, r.club_id, r.in_club]);
  await db.exec('set role anon');
  assert.deepEqual(await groups(), [
    ['Book Club', null, null, false],                 // a pending group is nobody's host
    ['Lions pancake breakfast', 'Rod and Gun Club', GROUP, false],  // posted by the group
    ['Monthly Meeting', 'Rod and Gun Club', GROUP, false],          // from the group's own site
    ['Plant Bingo', null, null, false],               // the place's own Event
    ['Stitch and Sip', null, null, false],            // a neighbour's posting with the name
    ['Stitch and Sip', 'Stitch and Sip', QUILTS, false],            // its name at its place
  ], 'signed out');

  await signIn(ME);
  await db.exec('reset role');
  await db.query('insert into public.club_members (club_id, user_id) values ($1, $2)', [GROUP, ME]);
  await db.exec('set role authenticated');
  const mine = await groups();
  assert.deepEqual(mine.filter((r) => r[2] === GROUP).map((r) => r[3]), [true, true], "you're in it");
  assert.deepEqual(mine.filter((r) => r[2] === QUILTS).map((r) => r[3]), [false]);
});

// Event of the day (BP app daily-tab 14): the morning job's standouts, one per part of the day for
// each person, read from get_event_of_the_day.
async function standouts(day, ids) {
  await db.exec('reset role');
  for (const [i, id] of ids.entries())
    await db.query(`insert into public.daily_standouts (town, day, event_id, rank, why) values ('st-joseph-mn', $1, $2, $3, 'why')`,
                   [day, id, i + 1]);
}
async function tagged(id, interests, draw = 2) {
  await db.exec('reset role');
  await db.query(`update public.club_events set interests = $2, interests_tagged_at = now(), draw = $3 where id = $1`,
                 [id, interests, draw]);
}
const ofTheDay = async (at) => (await db.query(
  `select title, rsvpd from public.flat_event_of_the_day(($1::timestamp at time zone 'America/Chicago'))`, [at])).rows;
const picks = async (at) => (await ofTheDay(at)).map((r) => r.title);

async function busyFriday() {
  await reset();
  const e = {};
  for (const [title, start, interests] of [
    ['Pancake breakfast', '8 AM', ['dining']], ['Bird walk', '9 AM', ['outdoors']],
    ['Fix-It Clinic', '2 PM', ['books']],
    ['Home game', '7 PM', ['watch_sports']], ['Theology on Tap', '8 PM', ['faith']],
    ['Late show', '10 PM', ['live_music']]]) {
    e[title] = await add(title, '2026-10-09', { start_time: start, source_name: title });
    await tagged(e[title], interests);
  }
  // The job's order: the game is the Town's top pick. The late show isn't a standout.
  await standouts('2026-10-09', [e['Home game'], e['Pancake breakfast'], e['Theology on Tap'], e['Bird walk'], e['Fix-It Clinic']]);
  return e;
}

test('Event of the day: each part of the day gets the standout that fits you, else its top pick', async () => {
  await busyFriday();
  await db.exec('set role anon');
  assert.deepEqual(await picks('2026-10-09 07:00'), ['Pancake breakfast', 'Fix-It Clinic', 'Home game'], 'signed out');
  await signIn(ME, []);
  assert.deepEqual(await picks('2026-10-09 07:00'), ['Pancake breakfast', 'Fix-It Clinic', 'Home game'], 'no interests');
  await signIn(YOU, ['faith', 'outdoors']);
  assert.deepEqual(await picks('2026-10-09 07:00'), ['Bird walk', 'Fix-It Clinic', 'Theology on Tap']);
  await signIn(ME, ['watch_sports', 'coffee']);
  assert.deepEqual(await picks('2026-10-09 07:00'), ['Pancake breakfast', 'Fix-It Clinic', 'Home game']);
});

test("Event of the day: Going keeps your pick, and Going to another standout doesn't take its spot", async () => {
  const e = await busyFriday();
  await signIn(YOU, ['faith']);
  await db.exec('reset role');
  await db.query('insert into public.event_rsvps (event_id, user_id) values ($1, $3), ($2, $3)',
                 [e['Theology on Tap'], e['Home game'], YOU]);
  await db.exec('set role authenticated');
  assert.deepEqual(await ofTheDay('2026-10-09 07:00'), [
    { title: 'Pancake breakfast', rsvpd: false }, { title: 'Fix-It Clinic', rsvpd: false },
    { title: 'Theology on Tap', rsvpd: true }]);
});

test('Event of the day: one that is over leaves, the next takes its spot, and none left is none', async () => {
  await busyFriday();
  await db.exec('set role anon');
  // Breakfast leaves at 10; the bird walk is the morning's next best until 11.
  assert.deepEqual(await picks('2026-10-09 10:30'), ['Bird walk', 'Fix-It Clinic', 'Home game']);
  assert.deepEqual(await picks('2026-10-09 15:00'), ['Fix-It Clinic', 'Home game']);
  assert.deepEqual(await picks('2026-10-09 21:30'), ['Theology on Tap']);
  // Every standout is over; the late show is still on but the job didn't pick it.
  assert.deepEqual(await picks('2026-10-09 22:30'), []);
});

test('Event of the day: a standout that repeats every week never shows, picked or not', async () => {
  const e = await busyFriday();
  // Theology on Tap turns out to be every Friday: it leaves the evening to the game, even for faith.
  for (const d of ['2026-10-16', '2026-10-23']) await add('Theology on Tap', d, { start_time: '8 PM', source_name: 'Theology on Tap' });
  await signIn(YOU, ['faith']);
  assert.deepEqual(await picks('2026-10-09 07:00'), ['Pancake breakfast', 'Fix-It Clinic', 'Home game']);
});

test("Event of the day: a day the job wrote nothing is the feed's top Event, never routine business or a weekly regular", async () => {
  await reset();
  const council = await add('Council meeting', '2026-10-09', { start_time: '6 PM', source_name: 'City' });
  await tagged(council, [], 1);
  for (const d of ['2026-10-09', '2026-10-16', '2026-10-23']) await add('Trivia', d, { start_time: '7 PM', source_name: 'Taproom' });
  const fair = await add('Fall fair', '2026-10-09', { start_time: '5 PM', source_name: 'Fair board' });
  await tagged(fair, ['festivals'], 3);
  const bake = await add('Bake sale', '2026-10-09', { start_time: '10 AM', source_name: 'Church' });
  await tagged(bake, ['dining']);
  // Yesterday's standouts don't count for today.
  await standouts('2026-10-08', [bake]);
  await db.exec('set role anon');
  assert.deepEqual(await picks('2026-10-09 07:00'), ['Fall fair']);
  // The feed lowers an Event you're Going to, so yours comes first and keeps the spot.
  await signIn(ME, []);
  await db.exec('reset role');
  await db.query('insert into public.event_rsvps (event_id, user_id) values ($1, $2)', [bake, ME]);
  await db.exec('set role authenticated');
  assert.deepEqual(await picks('2026-10-09 07:00'), ['Bake sale']);
  // Nothing on today but routine business and a regular: no Event of the day.
  await db.exec('reset role');
  await db.query('delete from public.club_events where id = any($1)', [[fair, bake]]);
  await db.exec('set role anon');
  assert.deepEqual(await picks('2026-10-09 07:00'), []);
});

test('Event of the day: neighbours read the standouts and never write them', async () => {
  const e = await busyFriday();
  await signIn(ME, []);
  const { rows } = await db.query('select count(*)::int as n from public.daily_standouts');
  assert.equal(rows[0].n, 5);
  await refused(`insert into public.daily_standouts (town, day, event_id, rank, why) values ('st-joseph-mn', '2026-10-09', $1, 9, 'mine')`,
                [e['Late show']]);
  // A delete under the read rule finds no row it may touch.
  await db.exec('set role authenticated');
  await db.query('delete from public.daily_standouts');
  await db.exec('reset role');
  assert.equal((await db.query('select count(*)::int as n from public.daily_standouts')).rows[0].n, 5);
});

// Town news (town-feed 35): published at a Town time, by a place, with a post to open.
async function news(title, published, more = {}) {
  const row = { category: 'business', source_name: 'The Wandering Cow', source_url: 'https://www.instagram.com/p/x/',
                status: 'published', starts_at: null, interests: null, place_entry_id: null, ...more };
  await db.exec('reset role');
  await db.query(
    `insert into public.board_items (title, blurb, category, source_name, source_url, status, starts_at,
       published_at, interests, place_entry_id)
     values ($1, $1 || ', in a line.', $2, $3, $4, $5, $6::timestamp at time zone 'America/Chicago',
             $7::timestamp at time zone 'America/Chicago', $8, $9)`,
    [title, row.category, row.source_name, row.source_url, row.status, row.starts_at, published,
     row.interests, row.place_entry_id]);
}
// The feed with news, as the app asks for it.
async function withNews(at) {
  const { rows } = await db.query(
    `select title, kind, reason, reason_name, source_url, description, place_picture
     from public.flat_town_feed(($1::timestamp at time zone 'America/Chicago'), true)`, [at]);
  return rows;
}
const newsTitles = async (at) => (await withNews(at)).map((r) => r.title);

test('an app that does not ask for news gets none, and signed out all news sits under the events', async () => {
  await reset();
  await add('Bake sale', '2026-10-09', { start_time: '11 AM' });
  await news('Flight Friday', '2026-10-08 18:00', { interests: ['dining'] });
  await db.exec('set role anon');
  assert.deepEqual(await titles('2026-10-08 20:00'), ['Bake sale']);
  const rows = await withNews('2026-10-08 20:00');
  assert.deepEqual(rows.map((r) => [r.title, r.kind]), [['Bake sale', 'event'], ['Flight Friday', 'news']]);
  assert.equal(rows[1].source_url, 'https://www.instagram.com/p/x/');
  assert.equal(rows[1].description, 'Flight Friday, in a line.');
});

test('news sharing your interests sits below an equal event, above one days off, and the rest goes last', async () => {
  await reset();
  await add('Fish fry dinner', '2026-10-08', { start_time: '7 PM', category: 'dining' });
  await add('Council meeting', '2026-10-20', { start_time: '6 PM' });
  await news('Taco Tuesday', '2026-10-08 17:00', { interests: ['dining'], source_name: 'Neighbors Route 75' });
  await news('Fall arrivals', '2026-10-08 17:50', { source_name: 'White Peony Boutique' });
  await news('Halloween cookies', '2026-10-08 17:40', { interests: ['coffee'], source_name: 'The Local Blend' });
  await signIn(ME, ['dining']);
  const rows = await withNews('2026-10-08 18:00');
  assert.deepEqual(rows.map((r) => r.title),
                   ['Fish fry dinner', 'Taco Tuesday', 'Council meeting', 'Fall arrivals', 'Halloween cookies']);
  assert.deepEqual([rows[1].reason, rows[1].reason_name], ['interest', 'dining']);
  assert.equal(rows[3].reason, null);
});

test('a place\'s news spreads apart at the bottom, newest first', async () => {
  await reset();
  await news('Milkshake Monday', '2026-10-08 17:00');
  await news('Flight Friday', '2026-10-08 17:10');
  await news('Taco Tuesday', '2026-10-08 16:00', { source_name: 'Neighbors Route 75' });
  await db.exec('set role anon');
  assert.deepEqual(await newsTitles('2026-10-08 18:00'), ['Flight Friday', 'Taco Tuesday', 'Milkshake Monday']);
});

test('news leaves after 7 days, or once the day it is about is over', async () => {
  await reset();
  await news('Pumpkin Pie Shake', '2026-10-01 12:00');
  await news('Layer Up drop tonight', '2026-10-08 09:00', { starts_at: '2026-10-08 00:00' });
  await news('Life Saving Awards', '2026-10-08 09:00', { starts_at: '2026-10-05 00:00', category: 'announcement' });
  await db.exec('set role anon');
  assert.deepEqual((await newsTitles('2026-10-08 11:59')).sort(),
                   ['Layer Up drop tonight', 'Life Saving Awards', 'Pumpkin Pie Shake']);
  assert.deepEqual((await newsTitles('2026-10-08 12:01')).sort(), ['Layer Up drop tonight', 'Life Saving Awards']);
  assert.deepEqual(await newsTitles('2026-10-09 00:01'), ['Life Saving Awards']);
  assert.deepEqual(await newsTitles('2026-10-15 09:01'), []);
});

test('road work shows; unpublished news and news with no post to open stay out', async () => {
  await reset();
  await news('Fiber installation underway', '2026-10-08 17:00', { category: 'road', source_name: 'City of St. Joseph' });
  await news('Still being checked', '2026-10-08 17:00', { status: 'staging' });
  await news('No link', '2026-10-08 17:00', { source_url: ' ' });
  await news('Taco Tuesday', '2026-10-08 17:00', { source_name: 'Neighbors Route 75' });
  await db.exec('set role anon');
  assert.deepEqual((await newsTitles('2026-10-08 18:00')).sort(), ['Fiber installation underway', 'Taco Tuesday']);
});

test('a host you muted keeps its news out too', async () => {
  await reset();
  await news('Taco Tuesday', '2026-10-08 17:00', { source_name: 'Neighbors Route 75', interests: ['dining'] });
  await news('Flight Friday', '2026-10-08 17:00', { interests: ['dining'] });
  await signIn(ME, ['dining']);
  await db.exec('reset role');
  await db.query(`insert into public.feed_mutes (user_id, host, name) values ($1, 'Neighbors Route 75', 'Neighbors Route 75')`, [ME]);
  await db.exec('set role authenticated');
  assert.deepEqual(await newsTitles('2026-10-08 18:00'), ['Flight Friday']);
});

test('news takes the ••• too: Not interested hides that item alone, to you only; Mute its place, Events too (news-menu)', async () => {
  await reset();
  await add('Ice cream social', '2026-10-09', { start_time: '6 PM', source_name: 'The Wandering Cow' });
  await news('Flight Friday', '2026-10-08 17:00');
  await news('Milkshake Monday', '2026-10-08 16:00');
  await news('Taco Tuesday', '2026-10-08 17:00', { source_name: 'Neighbors Route 75' });
  const { rows: [{ id: flight }] } = await db.query(`select id from public.board_items where title = 'Flight Friday'`);
  const all = ['Flight Friday', 'Ice cream social', 'Milkshake Monday', 'Taco Tuesday'];
  await signIn(YOU);
  await db.query('select public.set_not_interested($1)', [flight]);
  assert.deepEqual((await newsTitles('2026-10-08 18:00')).sort(), ['Ice cream social', 'Milkshake Monday', 'Taco Tuesday']);
  // Someone else still sees it, and can't read your hide.
  await signIn('00000000-0000-0000-0000-0000000000c9');
  assert.deepEqual((await newsTitles('2026-10-08 18:00')).sort(), all);
  assert.deepEqual((await db.query('select item_id from public.news_hides')).rows, [], "nobody reads another's hides");
  // Undo brings it back.
  await signIn(YOU);
  await db.query('select public.set_not_interested($1, false)', [flight]);
  assert.deepEqual((await newsTitles('2026-10-08 18:00')).sort(), all);
  // Mute names the place as its card does, and takes its news and its Events.
  assert.equal((await db.query('select public.mute_host($1) as host', [flight])).rows[0].host, 'The Wandering Cow');
  assert.deepEqual((await db.query('select name from public.feed_mutes')).rows, [{ name: 'The Wandering Cow' }]);
  assert.deepEqual(await newsTitles('2026-10-08 18:00'), ['Taco Tuesday']);
  await db.exec('reset role; reset request.jwt.claim.sub; set role anon');
  await assert.rejects(db.query('select public.set_not_interested($1)', [flight]));
  await db.exec('reset role');
});

test('a news item shows its place\'s logo before its photo', async () => {
  await reset();
  await db.exec(`delete from public.place_photos; delete from public.places;
    insert into public.place_photos (entry_id, url, source_url, position, kind, status, width, height) values
      ('cow-wandering', 'https://x/cow-photo.webp', 'https://cow', 0, 'photo', 'live', 800, 600);
    insert into public.places (lat, lon, family, name, entry_id, search_logo) values
      (45.5, -94.3, 'business', 'The Wandering Cow', 'cow-wandering', '{"url": "https://x/cow-logo.webp", "hue": 19}');`);
  await news('Flight Friday', '2026-10-08 17:00', { place_entry_id: 'cow-wandering' });
  await news('Taco Tuesday', '2026-10-08 16:00', { source_name: 'Neighbors Route 75' });
  await db.exec('set role anon');
  const rows = await withNews('2026-10-08 18:00');
  assert.deepEqual(rows[0].place_picture, { url: 'https://x/cow-logo.webp', kind: 'logo', hue: 19 });
  assert.equal(rows[1].place_picture, null, 'no place: no picture, and the app shows its first letter');
  await db.exec('reset role; delete from public.place_photos; delete from public.places;');
});

test('an Event shows who puts it on: the logo of the place it was found on, else its group\'s place', async () => {
  await reset();
  await db.exec(`delete from public.place_photos; delete from public.places; delete from public.sources;
    insert into public.places (lat, lon, family, name, entry_id, search_logo) values
      (45.5, -94.3, 'business', 'The Wandering Cow', 'cow-wandering', '{"url": "https://x/cow-logo.webp", "hue": 19}');
    insert into public.sources (town, status, method, entry_id, url, name) values ('st-joseph-mn', 'active', 'fetch', 'cow-wandering', 'https://cow/events', 'The Wandering Cow');`);
  await add('Sundae Social', '2026-10-09', { start_time: '6 PM', source_name: 'The Wandering Cow' });
  await add('Bake sale', '2026-10-09', { start_time: '7 PM', source_name: 'Nobody Known' });
  await db.exec('set role anon');
  const { rows } = await db.query(`select title, host_picture
     from public.flat_town_feed(('2026-10-08 18:00'::timestamp at time zone 'America/Chicago'))`);
  const by = Object.fromEntries(rows.map((r) => [r.title, r.host_picture]));
  assert.deepEqual(by['Sundae Social'], { url: 'https://x/cow-logo.webp', kind: 'logo', hue: 19 },
    'sources has no read rule for neighbours, and the logo still shows');
  assert.equal(by['Bake sale'], null, 'no known host: the app shows its first letter');
  // A host the registry names differently (host-names): its entry, by the name the card shows.
  await db.exec(`reset role; insert into public.host_entries (name, entry_id) values ('Nobody Known', 'cow-wandering')`);
  await db.exec('set role anon');
  const again = await db.query(`select title, host_picture
     from public.flat_town_feed(('2026-10-08 18:00'::timestamp at time zone 'America/Chicago'))`);
  assert.equal(again.rows.find((r) => r.title === 'Bake sale').host_picture.url, 'https://x/cow-logo.webp');
  await db.exec('reset role; delete from public.host_entries;');
  await db.exec('reset role; delete from public.place_photos; delete from public.places; delete from public.sources;');
});

test('there is one get_town_feed, so every app\'s call finds it', async () => {
  // A later `create or replace function public.get_town_feed(p_now timestamptz ...)` with one
  // argument would make a second, and `{}` would fail as ambiguous for every app.
  const { rows } = await db.query(`select count(*)::int as n from pg_proc where proname = 'get_town_feed'`);
  assert.equal(rows[0].n, 1);
});

// Not interested and Mute (ticket 21). A Not interested row `at` a Town time, written as the
// database would; set_not_interested and mute_host as the app calls them.
async function notInterested(event, who, at) {
  await db.exec('reset role');
  await db.query(`insert into public.feed_actions (user_id, item_id, action, at)
                  values ($1, $2, 'not_interested', ($3::timestamp at time zone 'America/Chicago'))`, [who, event, at]);
}

test('Not interested keeps the item and every week of its series out; other hosts stay', async () => {
  await reset();
  const trivia = await add('Trivia', '2026-10-13', { start_time: '7 PM', source_name: "Loso's" });
  await add('Trivia', '2026-10-20', { start_time: '7 PM', source_name: "Loso's" });
  await add('Trivia', '2026-10-13', { start_time: '7 PM', source_name: 'Bad Habit' });
  await add('Bake sale', '2026-10-09', { start_time: '12 PM', source_name: 'Church' });
  await signIn(YOU);
  assert.equal((await titles('2026-10-08 12:00')).length, 3);
  await db.query('select public.set_not_interested($1)', [trivia]);
  const rows = await feed('2026-10-08 12:00');
  assert.deepEqual(rows.map((r) => r.title).sort(), ['Bake sale', 'Trivia']);
  // The next week's Trivia from the same host would take its place; it doesn't.
  assert.ok((await feed('2026-10-15 12:00')).every((r) => r.title !== 'Trivia' || r.day !== '2026-10-20'));
  // Undo takes it back.
  await db.query('select public.set_not_interested($1, false)', [trivia]);
  assert.equal((await titles('2026-10-08 12:00')).length, 3);
});

test("Not interested lowers its host's other Events × 0.3, and nothing else, for as long as it stands", async () => {
  await reset();
  const fair = await add('Craft fair', '2026-10-09', { start_time: '10 AM', source_name: 'Parks', category: 'arts' });
  await add('Zoo day', '2026-10-09', { start_time: '11 AM', source_name: 'Parks', category: 'outdoors' });
  await add('Gallery night', '2026-10-09', { start_time: '6 PM', source_name: 'Gallery', category: 'arts' });
  await add('Bingo', '2026-10-09', { start_time: '7 PM', source_name: "Sal's", category: 'games' });
  await notInterested(fair, YOU, '2026-10-08 12:00');
  const x = async (at) => {
    await signIn(YOU);
    await db.exec(`set request.jwt.claims = '${ADMIN}'`);
    return Object.fromEntries((await feed(at)).map((r) => [r.title, r.score.notInterested]));
  };
  assert.deepEqual(await x('2026-10-08 12:00'), { 'Zoo day': 0.3, 'Gallery night': 1, Bingo: 1 });
  // No fade (town-feed 36): 120 days on it still lowers.
  await db.exec(`reset role; update public.feed_actions set at = at - interval '120 days'`);
  assert.deepEqual(await x('2026-10-08 12:00'), { 'Zoo day': 0.3, 'Gallery night': 1, Bingo: 1 });
});

test('Not interested on a host beats its "been into" lift', async () => {
  await reset();
  const fair = await add('Craft fair', '2026-10-04', { start_time: '10 AM', source_name: 'Parks' });
  const movie = await add('Movie night', '2026-10-07', { start_time: '7 PM', source_name: 'Parks' });
  await add('Zoo day', '2026-10-09', { start_time: '10 AM', source_name: 'Parks' });
  await add('Bingo', '2026-10-09', { start_time: '10 AM', source_name: "Sal's" });
  await tap('event_likes', fair, YOU, '2026-10-04 12:00');
  await tap('event_likes', movie, YOU, '2026-10-07 12:00');
  await notInterested(movie, YOU, '2026-10-08 12:00');
  await signIn(YOU);
  await db.exec(`set request.jwt.claims = '${ADMIN}'`);
  const rows = await feed('2026-10-08 12:00');
  const zoo = rows.find((r) => r.title === 'Zoo day');
  assert.deepEqual([zoo.score.tapped, zoo.score.notInterested], [3, 0.3]);
  assert.deepEqual(rows.map((r) => r.title), ['Bingo', 'Zoo day'], 'the lift (1 + 3) × 0.3 sits under a plain 1');
});

test('a muted host never shows, to the one who muted it only; unmuting brings it back', async () => {
  await reset();
  const zoo = await add('Zoo day', '2026-10-09', { start_time: '10 AM', source_name: 'Parks' });
  await add('Movie night', '2026-10-10', { start_time: '7 PM', source_name: 'Parks' });
  await add('Bingo', '2026-10-09', { start_time: '10 AM', source_name: "Sal's" });
  await signIn(YOU);
  const { rows: [{ host }] } = await db.query('select public.mute_host($1) as host', [zoo]);
  assert.equal(host, 'Parks');
  assert.deepEqual(await titles('2026-10-08 12:00'), ['Bingo']);
  assert.deepEqual((await db.query('select host, name from public.feed_mutes')).rows, [{ host: 'Parks', name: 'Parks' }]);
  // Someone else, and a signed-out read, still see Parks.
  await signIn('00000000-0000-0000-0000-0000000000c9');
  assert.equal((await titles('2026-10-08 12:00')).length, 3);
  assert.deepEqual((await db.query('select host from public.feed_mutes')).rows, [], "nobody reads another's mutes");
  await db.exec('reset role; reset request.jwt.claim.sub; set role anon');
  assert.equal((await titles('2026-10-08 12:00')).length, 3);
  // Unmute from the Muted list: a delete of your own row.
  await signIn(YOU);
  await db.query(`delete from public.feed_mutes where host = 'Parks'`);
  assert.equal((await titles('2026-10-08 12:00')).length, 3);
});

test("a group's Event mutes the group by the name its card shows; signed out can't hide or mute", async () => {
  await reset();
  await db.exec('reset role');
  const { rows: [{ id: club }] } = await db.query(`insert into public.clubs (name, status) values ('Rod and Gun Club', 'approved') returning id`);
  const shoot = await add('Trap shoot', '2026-10-09', { start_time: '10 AM' });
  await db.query('update public.club_events set club_id = $1, source_name = null where id = $2', [club, shoot]);
  await signIn(YOU);
  assert.equal((await db.query('select public.mute_host($1) as host', [shoot])).rows[0].host, club);
  assert.deepEqual((await db.query('select name from public.feed_mutes')).rows, [{ name: 'Rod and Gun Club' }]);
  await db.exec('reset role; reset request.jwt.claim.sub; set role anon');
  await assert.rejects(db.query('select public.set_not_interested($1)', [shoot]));
  await assert.rejects(db.query('select public.mute_host($1)', [shoot]));
  await db.exec('reset role');
});

// Onboarding ticket 19: under 18 never sees what its place keeps to 18+ or 21+.
async function born(id, birthday) {
  await signIn(id);
  await db.exec('reset role');
  await db.query('update public.town_profiles set birthday = $2 where user_id = $1', [id, birthday]);
  await db.exec(`set role authenticated; set request.jwt.claim.sub = '${id}'`);
}

test('under 18 never sees an Event or news its place or host keeps to 18+ or 21+', async () => {
  await reset();
  await db.exec(`delete from public.place_photos; delete from public.places;
    insert into public.places (lat, lon, family, name, entry_id, adults_only) values (45.5, -94.3, 'business', 'The Middy', 'middy', true),
      (45.5, -94.3, 'business', 'Sal''s Bar & Grill', 'bar-grill-sals', false);`);
  const middy = await add('Trivia night', '2026-10-09', { start_time: '7 PM', source_name: 'The Middy' });
  await add('Bingo Night', '2026-10-09', { start_time: '6 PM', source_name: "Sal's Bar and Grill" });
  const label = await add('Comedy show', '2026-10-09', { start_time: '8 PM', source_name: "Sal's Bar and Grill" });
  await add('Bake sale', '2026-10-09', { start_time: '11 AM' });
  await add('Haunted hayride', '2026-10-09', { start_time: '5 PM' });
  await db.exec('reset role');
  await db.query(`update public.club_events set description = 'Tickets $18 and up at the door.' where title = 'Haunted hayride'`);
  await db.query(`update public.club_events set place_entry_id = 'middy' where id = $1`, [middy]);
  await db.query(`update public.club_events set place_entry_id = 'bar-grill-sals', description = 'Ages 21+ only.' where id = $1`, [label]);
  await news('Happy hour', '2026-10-08 17:00', { source_name: 'The Middy', place_entry_id: 'middy' });
  await news('Flight Friday', '2026-10-08 17:00');
  const grown = ['Bake sale', 'Bingo Night', 'Comedy show', 'Haunted hayride', 'Trivia night', 'Flight Friday', 'Happy hour'];

  await db.exec('set role anon');
  assert.deepEqual((await newsTitles('2026-10-08 18:00')).sort(), [...grown].sort());
  await born(ME, '2010-03-01');   // 16
  assert.deepEqual((await newsTitles('2026-10-08 18:00')).sort(), ['Bake sale', 'Bingo Night', 'Flight Friday', 'Haunted hayride']);
  assert.deepEqual((await titles('2026-10-08 18:00')).sort(), ['Bake sale', 'Bingo Night', 'Haunted hayride']);
  await born(ME, '2008-10-08');   // 18 today
  assert.deepEqual((await newsTitles('2026-10-08 18:00')).sort(), [...grown].sort());
  await born(ME, '2008-10-09');   // 18 tomorrow
  assert.equal((await newsTitles('2026-10-08 18:00')).length, 4);
  await db.exec('reset role; update public.town_profiles set birthday = null');
  await db.exec(`set role authenticated; set request.jwt.claim.sub = '${ME}'`);
  assert.equal((await newsTitles('2026-10-08 18:00')).length, 7);
  await db.exec('reset role; delete from public.places');
});

test('a birthday is read by its own account only', async () => {
  await reset();
  const other = '00000000-0000-0000-0000-00000000000b';
  await born(ME, '1990-05-04');
  assert.deepEqual((await db.query('select birthday::text as b from public.town_profiles')).rows, [{ b: '1990-05-04' }]);
  await signIn(other);
  assert.deepEqual((await db.query('select birthday from public.town_profiles where user_id = $1', [ME])).rows, []);
  await db.exec('reset role');
  await assert.rejects(db.query(`update public.town_profiles set birthday = '1899-12-31' where user_id = $1`, [ME]));
});

// Followed activities (school-activities 03): an activity starred on a school's page, or the whole
// school, lifts its Events and says so; a followers-only Event reaches only them.
async function follow(who, type, team, activity) {
  await db.exec('reset role');
  const id = activity
    ? (await db.query(`select id from public.team_activities where team_id = $1 and name = $2`, [team, activity])).rows[0].id
    : (await db.query(`select uuid from public.teams where id = $1`, [team])).rows[0].uuid;
  await people(db, who);
  await db.query(`insert into public.town_follows (follower_id, target_type, target_id) values ($1, $2, $3)`, [who, type, id]);
}
async function schools() {
  await db.exec(`reset role; insert into public.teams (id, name, short_name, local) values
    ('cathedral', 'Cathedral', 'Cathedral', true), ('sartell', 'Sartell', 'Sartell', true),
    ('apollo', 'Apollo', 'Apollo', true) on conflict do nothing`);
}
async function game(title, date, sport, teams, more = {}) {
  const id = await add(title, date, { start_time: '7 PM', ...more });
  await db.query(`update public.club_events set sport = $2, team_ids = $3, followers_only = $4 where id = $1`,
                 [id, sport, teams, more.followersOnly ?? false]);
  return id;
}
const why = async (at) => Object.fromEntries((await feed(at)).map((r) => [r.title, [r.reason, r.reason_name]]));

test('an activity you follow lifts its games and says so; following the whole school covers every activity', async () => {
  await reset();
  await schools();
  await game('Cathedral Volleyball vs Sartell', '2026-10-09', 'Volleyball', ['cathedral', 'sartell']);
  await add('Fall fair', '2026-10-09', { start_time: '7 PM' });
  await follow(ME, 'activity', 'cathedral', 'Volleyball (girls)');
  await signIn(ME);
  await db.exec(`set request.jwt.claims = '${ADMIN}'`);
  const rows = await feed('2026-10-08 12:00');
  assert.deepEqual(rows.map((r) => [r.title, r.reason, r.reason_name, r.score.follow]), [
    ['Cathedral Volleyball vs Sartell', 'follow', 'Cathedral Volleyball (girls)', 3],
    ['Fall fair', 'tomorrow', null, 0]]);
  await db.exec('reset request.jwt.claims');
  await db.exec(`reset role; delete from public.town_follows`);
  await follow(ME, 'team', 'cathedral');
  await signIn(ME);
  assert.deepEqual((await why('2026-10-08 12:00'))['Cathedral Volleyball vs Sartell'], ['follow', 'Cathedral']);
  await db.exec(`reset role; reset request.jwt.claim.sub; set role anon`);
  assert.deepEqual((await why('2026-10-08 12:00'))['Cathedral Volleyball vs Sartell'], ['tomorrow', null]);
});

test('a followers-only Event reaches only those following its activity or its school', async () => {
  await reset();
  await schools();
  await game('Cathedral Volleyball vs Sartell · JV', '2026-10-09', 'Volleyball', ['cathedral', 'sartell'],
             { followersOnly: true });
  await add('Fall fair', '2026-10-09');
  const OTHER = '00000000-0000-0000-0000-00000000000b';
  const SCHOOL = '00000000-0000-0000-0000-00000000000c';
  await follow(ME, 'activity', 'cathedral', 'Volleyball (girls)');
  await follow(OTHER, 'activity', 'cathedral', 'Football');
  await follow(SCHOOL, 'team', 'sartell');
  await db.exec('set role anon');
  assert.deepEqual(await titles('2026-10-08 12:00'), ['Fall fair'], 'signed out never sees it');
  await signIn(OTHER);
  assert.deepEqual(await titles('2026-10-08 12:00'), ['Fall fair'], "another activity's follower doesn't");
  await signIn(ME);
  assert.deepEqual(await titles('2026-10-08 12:00'), ['Cathedral Volleyball vs Sartell · JV', 'Fall fair']);
  await signIn(SCHOOL);
  assert.deepEqual((await why('2026-10-08 12:00'))['Cathedral Volleyball vs Sartell · JV'], ['follow', 'Sartell'],
                   'the other school, followed whole');
});

test("a concert lands on its activity by Bound's name: Choir is never Chamber Choir, Drama is Theatre/Drama", async () => {
  await reset();
  await schools();
  for (const [title, name] of [['Fall Choir Concert', 'Choir'], ['The SpongeBob Musical', 'Drama']]) {
    const id = await add(title, '2026-10-09', { start_time: '7 PM', source_name: 'Apollo High School' });
    await db.query(`update public.club_events set followers_only = true, activity_team = 'apollo', activity_name = $2
                    where id = $1`, [id, name]);
  }
  const CHAMBER = '00000000-0000-0000-0000-00000000000b';
  await follow(ME, 'activity', 'apollo', 'Choir');
  await follow(ME, 'activity', 'apollo', 'Theatre/Drama');
  await follow(CHAMBER, 'activity', 'apollo', 'Chamber Choir');
  await signIn(ME);
  assert.deepEqual(await why('2026-10-08 12:00'), {
    'Fall Choir Concert': ['follow', 'Apollo Choir'], 'The SpongeBob Musical': ['follow', 'Apollo Theatre/Drama'] });
  await signIn(CHAMBER);
  assert.deepEqual(await titles('2026-10-08 12:00'), []);
});

test('what you follow says so before an interest it matches', async () => {
  await reset();
  await schools();
  await game('Cathedral Volleyball vs Sartell', '2026-10-09', 'Volleyball', ['cathedral', 'sartell'],
             { category: 'watch_sports' });
  await follow(ME, 'activity', 'cathedral', 'Volleyball (girls)');
  await signIn(ME, ['watch_sports']);
  assert.deepEqual((await why('2026-10-08 12:00'))['Cathedral Volleyball vs Sartell'],
                   ['follow', 'Cathedral Volleyball (girls)']);
});

test('Event of the day is never a followers-only Event, even for its followers', async () => {
  await reset();
  await schools();
  await game('Cathedral Volleyball vs Sartell · JV', '2026-10-09', 'Volleyball', ['cathedral', 'sartell'],
             { followersOnly: true });
  await follow(ME, 'activity', 'cathedral', 'Volleyball (girls)');
  await signIn(ME);
  assert.deepEqual(await titles('2026-10-09 12:00'), ['Cathedral Volleyball vs Sartell · JV']);
  const { rows } = await db.query(
    `select title from public.flat_event_of_the_day(('2026-10-09 12:00'::timestamp at time zone 'America/Chicago'))`);
  assert.deepEqual(rows, []);
});

// Report (ticket 22). The app calls report_event; the queue calls list_reports and resolve_reports.
const reportAs = async (who, event, reason) => {
  await signIn(who);
  return (await db.query('select public.report_event($1, $2) as recheck', [event, reason])).rows[0].recheck;
};

test('a reported Event never shows to its reporter, lowers nothing, and others still see it', async () => {
  await reset();
  const scam = await add('Free iPhones', '2026-10-09', { start_time: '10 AM', source_name: 'Parks', category: 'arts' });
  await add('Zoo day', '2026-10-09', { start_time: '11 AM', source_name: 'Parks', category: 'arts' });
  await reportAs(YOU, scam, 'scam');
  await db.exec(`set request.jwt.claims = '${ADMIN}'`);
  const rows = await feed('2026-10-08 12:00');
  assert.deepEqual(rows.map((r) => [r.title, r.score.notInterested]), [['Zoo day', 1]]);
  await signIn(ME);
  assert.deepEqual((await titles('2026-10-08 12:00')).sort(), ['Free iPhones', 'Zoo day']);
  // Undo brings it back to its reporter; the report stays.
  await signIn(YOU);
  await db.query('select public.set_not_interested($1, false)', [scam]);
  assert.equal((await titles('2026-10-08 12:00')).length, 2);
  await db.exec('reset role');
  assert.equal((await db.query('select count(*)::int as n from public.reports')).rows[0].n, 1);
});

test('a report holds the Event, the reason and the time only, and no neighbour can read it', async () => {
  await reset();
  const fair = await add('Craft fair', '2026-10-09', { start_time: '10 AM' });
  await reportAs(YOU, fair, 'violence');
  await assert.rejects(db.query('select * from public.reports'), /permission denied/);
  assert.deepEqual((await db.query('select * from public.list_reports()')).rows, []);
  await db.exec('reset role');
  const { rows } = await db.query(`select column_name from information_schema.columns
                                   where table_name = 'reports' order by ordinal_position`);
  assert.deepEqual(rows.map((r) => r.column_name), ['id', 'event_id', 'reason', 'at']);
  await assert.rejects(reportAs(YOU, fair, 'not_a_reason'), /reports_reason_check/);
});

test('Wrong info and Wrong photo hide nothing and only reach the queue', async () => {
  await reset();
  const fair = await add('Craft fair', '2026-10-09', { start_time: '10 AM' });
  assert.equal(await reportAs(YOU, fair, 'wrong_info'), false);
  assert.equal(await reportAs(YOU, fair, 'wrong_photo'), false);
  assert.deepEqual(await titles('2026-10-08 12:00'), ['Craft fair']);
  await db.exec(`set request.jwt.claims = '${ADMIN}'`);
  assert.deepEqual((await db.query('select title, reasons, reports from public.list_reports()')).rows,
    [{ title: 'Craft fair', reasons: ['wrong_info', 'wrong_photo'], reports: 2 }]);
});

test("only a neighbour's posting, reported by a signed-in account, goes back to the AI, and once", async () => {
  await reset();
  const found = await add('City meeting', '2026-10-09', { start_time: '6 PM' });
  const posted = await add('Garage sale', '2026-10-09', { start_time: '8 AM', submitted_by: ME, source_name: null });
  assert.equal(await reportAs(YOU, found, 'scam'), false);
  const ANON = '00000000-0000-0000-0000-0000000000d1';
  await db.exec('reset role');
  await db.query('insert into auth.users (id, is_anonymous) values ($1, true) on conflict do nothing', [ANON]);
  assert.equal(await reportAs(ANON, posted, 'scam'), false);
  assert.equal(await reportAs(YOU, posted, 'scam'), true);
  // The app can't claim the re-check; moderate-post (the service role) claims it once.
  await assert.rejects(db.query('select public.claim_recheck($1)', [posted]), /permission denied/);
  await db.exec('reset role; set role service_role');
  const claim = async (id) => (await db.query('select public.claim_recheck($1) as c', [id])).rows[0].c;
  assert.deepEqual([await claim(posted), await claim(posted), await claim(found)], [true, false, false]);
  await db.exec('reset role');
  assert.equal(await reportAs(ME, posted, 'bullying'), false, 'already re-checked');
});

test('the admin keeps a reported Event or takes it down for everyone', async () => {
  await reset();
  const fair = await add('Craft fair', '2026-10-09', { start_time: '10 AM' });
  const sale = await add('Garage sale', '2026-10-09', { start_time: '8 AM' });
  await reportAs(YOU, fair, 'scam');
  await reportAs(YOU, sale, 'nudity');
  await signIn(ME);
  await assert.rejects(db.query('select public.resolve_reports($1, true)', [fair]), /admin only/);
  await db.exec(`set request.jwt.claims = '${ADMIN}'`);
  await db.query('select public.resolve_reports($1, false)', [fair]);
  await db.query('select public.resolve_reports($1, true)', [sale]);
  assert.deepEqual((await db.query('select * from public.list_reports()')).rows, []);
  assert.deepEqual(await titles('2026-10-08 12:00'), ['Craft fair']);
  await db.exec('reset role');
  assert.deepEqual((await db.query('select status, review_reason from public.club_events where id = $1', [sale])).rows,
    [{ status: 'rejected', review_reason: 'reported' }]);
});

// Places, people and Groups you follow (town-feed 37): each lifts its Events once and says so by name.
// Unfollow stays on the profile or page (Jesse, 2026-10-27).
const PEONY = 'White Peony Boutique';
async function followPlace(who, name = PEONY, entry = 'white-peony') {
  await db.exec('reset role');
  const { rows: [{ id }] } = await db.query(
    `insert into public.places (lat, lon, family, name, entry_id) values (45.5, -94.3, 'business', $1, $2) returning id`, [name, entry]);
  await people(db, who);
  await db.query(`insert into public.town_follows (follower_id, target_type, target_id) values ($1, 'place', $2)`, [who, id]);
}
async function atPlace(title, date, more = {}) {
  const id = await add(title, date, { start_time: '7 PM', source_name: PEONY, ...more });
  await db.query(`update public.club_events set place_entry_id = 'white-peony' where id = $1`, [id]);
  return id;
}
async function lifted(at) {
  const { rows } = await db.query(
    `select title, reason, reason_name, score, friends_going
     from public.flat_town_feed(($1::timestamp at time zone 'America/Chicago'))`, [at]);
  return rows;
}
const noPlaces = () => db.exec('reset role; delete from public.places; delete from public.sources;');

test('a Place you follow lifts its Events and says so', async () => {
  await reset();
  await atPlace('Fall open house', '2026-10-12');
  await add('Fall fair', '2026-10-09', { start_time: '7 PM' });
  await signIn(ME);
  assert.deepEqual(await titles('2026-10-08 12:00'), ['Fall fair', 'Fall open house'], 'not followed: soonest first');
  await followPlace(ME);
  await signIn(ME);
  await db.exec(`set request.jwt.claims = '${ADMIN}'`);
  const [top, next] = await lifted('2026-10-08 12:00');
  assert.deepEqual([top.title, top.reason, top.reason_name, top.score.follow, top.score.pool],
                   ['Fall open house', 'follow', PEONY, 3, 'yours']);
  assert.deepEqual([next.title, next.reason, next.score.follow], ['Fall fair', 'tomorrow', 0]);
  await db.exec('reset request.jwt.claims');
  await db.exec('reset role; reset request.jwt.claim.sub; set role anon');
  assert.deepEqual((await lifted('2026-10-08 12:00')).map((r) => [r.title, r.reason]),
                   [['Fall fair', 'tomorrow'], ['Fall open house', 'soon']], 'signed out follows nothing');
  await noPlaces();
});

test('a followed Place is still spaced out, and a host you have been into lifts it no more', async () => {
  await reset();
  const old = await atPlace('Summer sale', '2026-09-20');
  for (const d of ['2026-10-09', '2026-10-10', '2026-10-11']) await atPlace(`Open house ${d.slice(-2)}`, d);
  await followPlace(ME);
  await db.query(`insert into public.event_likes (event_id, user_id, created_at) values ($1, $2, '2026-09-19')`, [old, ME]);
  await signIn(ME);
  await db.exec(`set request.jwt.claims = '${ADMIN}'`);
  const rows = await lifted('2026-10-08 12:00');
  assert.deepEqual(rows.map((r) => [r.title, r.score.yours, r.score.spacing]), [
    ['Open house 09', 3, 1], ['Open house 10', 3, 0.5], ['Open house 11', 3, 0.25]]);
  await db.exec('reset request.jwt.claims');
  await noPlaces();
});

test('a person you follow lifts what they posted; one who can no longer be found lifts nothing', async () => {
  await reset();
  const SAM = '00000000-0000-0000-0000-0000000000e1';
  await db.query(`insert into auth.users (id) values ($1) on conflict do nothing`, [SAM]);
  await db.query(`insert into public.town_profiles (user_id, display_name) values ($1, 'Sam Lee')`, [SAM]);
  await add('Porch concert', '2026-10-12', { start_time: '7 PM', source_name: null, submitted_by: SAM });
  await add('Fall fair', '2026-10-09', { start_time: '7 PM' });
  await db.query(`insert into public.town_follows (follower_id, target_type, target_id) values ($1, 'profile', $2)`, [ME, SAM]);
  await signIn(ME);
  const [top] = await lifted('2026-10-08 12:00');
  assert.deepEqual([top.title, top.reason, top.reason_name], ['Porch concert', 'follow', 'Sam Lee']);
  await db.exec('reset role');
  await db.query(`update auth.users set banned_until = now() + interval '1 day' where id = $1`, [SAM]);
  await signIn(ME);
  assert.deepEqual((await lifted('2026-10-08 12:00')).map((r) => [r.title, r.reason]),
                   [['Fall fair', 'tomorrow'], ['Porch concert', 'soon']]);
  await db.exec('reset role');
  await db.query('delete from auth.users where id = $1', [SAM]);
});

test("a Group you're in lifts its Events and those found for it", async () => {
  await reset();
  await db.exec('reset role');
  const { rows: [{ id: club }] } = await db.query(
    `insert into public.clubs (name, status, own_entry_id) values ('Book Club', 'approved', 'book-club') returning id`);
  await db.query(`insert into public.sources (town, status, method, entry_id, url, name) values ('st-joseph-mn', 'active', 'fetch', 'book-club', 'https://books', 'Book Club site')`);
  const POSTER = '00000000-0000-0000-0000-0000000000e2';
  const own = await add('Book swap', '2026-10-12', { start_time: '7 PM', source_name: null, submitted_by: POSTER });
  await db.query('update public.club_events set club_id = $1 where id = $2', [club, own]);
  await add('Author talk', '2026-10-13', { start_time: '7 PM', source_name: 'Book Club site' });
  await add('Fall fair', '2026-10-09', { start_time: '7 PM' });
  await signIn(ME);
  assert.equal((await titles('2026-10-08 12:00'))[0], 'Fall fair', 'not in the Group: soonest first');
  await db.exec('reset role');
  await db.query('insert into public.club_members (club_id, user_id) values ($1, $2)', [club, ME]);
  await signIn(ME);
  assert.deepEqual((await lifted('2026-10-08 12:00')).map((r) => [r.title, r.reason, r.reason_name]), [
    ['Book swap', 'follow', 'Book Club'], ['Author talk', 'follow', 'Book Club'], ['Fall fair', 'tomorrow', null]]);
  const { rows } = await db.query(`select title, club_name, in_club
     from public.flat_town_feed(('2026-10-08 12:00'::timestamp at time zone 'America/Chicago'))`);
  assert.deepEqual(rows.filter((r) => r.club_name).map((r) => [r.title, r.club_name, r.in_club]),
                   [['Book swap', 'Book Club', true], ['Author talk', 'Book Club', true]], "the card's Join reads the same Group");
  await noPlaces();
});

test('a muted Place you follow stays out; Not interested still lowers its other Events', async () => {
  await reset();
  const first = await atPlace('Open house', '2026-10-09');
  await atPlace('Trunk show', '2026-10-12');
  await add('Fall fair', '2026-10-12', { start_time: '6 PM' });
  await followPlace(ME);
  await notInterested(first, ME, '2026-10-08 09:00');
  await signIn(ME);
  await db.exec(`set request.jwt.claims = '${ADMIN}'`);
  const by = Object.fromEntries((await lifted('2026-10-08 12:00')).map((r) => [r.title, [r.score.yours, r.score.notInterested]]));
  assert.deepEqual(by, { 'Trunk show': [3, 0.3], 'Fall fair': [0, 1] });
  await db.exec('reset request.jwt.claims');
  await db.query(`select public.mute_host($1)`, [first]);
  assert.deepEqual(await titles('2026-10-08 12:00'), ['Fall fair']);
  await noPlaces();
});

test("an activity you follow names the game before the Place it's at; a Place never opens a followers-only Event", async () => {
  await reset();
  await schools();
  const home = await game('Cathedral Volleyball vs Sartell', '2026-10-09', 'Volleyball', ['cathedral', 'sartell'],
                          { source_name: PEONY });
  await db.query(`update public.club_events set place_entry_id = 'white-peony' where id = $1`, [home]);
  const jv = await game('Cathedral Volleyball vs Sartell · JV', '2026-10-09', 'Volleyball', ['cathedral', 'sartell'],
                        { source_name: PEONY, followersOnly: true });
  await db.query(`update public.club_events set place_entry_id = 'white-peony' where id = $1`, [jv]);
  await followPlace(ME);
  await signIn(ME);
  assert.deepEqual((await lifted('2026-10-08 12:00')).map((r) => [r.title, r.reason_name]),
                   [['Cathedral Volleyball vs Sartell', PEONY]]);
  await follow(ME, 'activity', 'cathedral', 'Volleyball (girls)');
  await signIn(ME);
  assert.deepEqual((await lifted('2026-10-08 12:00')).map((r) => [r.title, r.reason_name]), [
    ['Cathedral Volleyball vs Sartell', 'Cathedral Volleyball (girls)'],
    ['Cathedral Volleyball vs Sartell · JV', 'Cathedral Volleyball (girls)']]);
  await noPlaces();
});

test("your own posting is never lifted by what it's at, and a Group's Event never names who posted it", async () => {
  await reset();
  await db.exec('reset role');
  const { rows: [{ id: club }] } = await db.query(`insert into public.clubs (name, status) values ('Book Club', 'approved') returning id`);
  const SAM = '00000000-0000-0000-0000-0000000000e3';
  await db.query(`insert into auth.users (id) values ($1) on conflict do nothing`, [SAM]);
  await db.query(`insert into public.town_profiles (user_id, display_name) values ($1, 'Sam Lee')`, [SAM]);
  await db.query(`insert into public.town_follows (follower_id, target_type, target_id) values ($1, 'profile', $2)`, [ME, SAM]);
  await db.query('insert into public.club_members (club_id, user_id) values ($1, $2)', [club, ME]);
  const mine = await add('My book swap', '2026-10-12', { start_time: '7 PM', source_name: null, submitted_by: ME });
  const sams = await add("Sam's book swap", '2026-10-13', { start_time: '7 PM', source_name: null, submitted_by: SAM });
  await db.query('update public.club_events set club_id = $1 where id = any($2)', [club, [mine, sams]]);
  await signIn(ME);
  assert.deepEqual(Object.fromEntries((await lifted('2026-10-08 12:00')).map((r) => [r.title, [r.reason, r.reason_name]])), {
    'My book swap': ['soon', null], "Sam's book swap": ['follow', 'Book Club'] });
  await db.exec('reset role');
  await db.query('delete from auth.users where id = $1', [SAM]);
});

test('the Score line gives the follow lift to what the card names, a friend Going or not', async () => {
  await reset();
  // Friends Going counts only Events not over by the real clock, so this one is days from now.
  const show = await atPlace('Trunk show', day(3));
  await followPlace(ME);
  const FRIEND = '00000000-0000-0000-0000-0000000000e4';
  await neighbour(FRIEND, 'Kate Moss');
  await befriend(ME, FRIEND);
  await goes(show, FRIEND);
  await signIn(ME);
  await db.exec(`set request.jwt.claims = '${ADMIN}'`);
  const [row] = await lifted(`${day(0)} 12:00`);
  assert.deepEqual([row.reason, row.score.follow, row.score.friend, row.score.yours, row.friends_going.length],
                   ['follow', 3, 0, 3, 1]);
  await db.exec('reset request.jwt.claims; reset role');
  await db.query('delete from auth.users where id = $1', [FRIEND]);
  await noPlaces();
});

// The City, its boards and Joetown (town-feed 27): a page you follow lifts the Events carrying its name, a
// board its meetings; a City meeting (draw 1) reaches only the City's or that board's followers, lower.
async function followPage(who, slug) {
  await db.exec('reset role');
  await people(db, who);
  await db.query(`insert into public.town_follows (follower_id, target_type, target_id)
                  select $1, 'page', id from public.town_pages where slug = $2`, [who, slug]);
}
async function followBoard(who, name) {
  await db.exec('reset role');
  await people(db, who);
  await db.query(`insert into public.town_follows (follower_id, target_type, target_id)
                  select $1, 'board', id from public.city_boards where name = $2`, [who, name]);
}
async function meeting(title, date) {
  const id = await add(title, date, { start_time: '6 PM' });
  await db.query('update public.club_events set draw = 1 where id = $1', [id]);
  return id;
}
const reasons = async (at) => (await feed(at)).map((r) => [r.title, r.reason, r.reason_name]);

test("a City meeting reaches only those who follow the City or its board, and sits lower for them", async () => {
  await reset();
  await meeting('City Council Meeting', '2026-10-09');
  await add('Fall fair', '2026-10-09', { start_time: '6 PM', source_name: 'Arts council' });
  const [CITYFAN, BOARDFAN, PARKFAN] = ['00000000-0000-0000-0000-0000000000f1', '00000000-0000-0000-0000-0000000000f2',
                                        '00000000-0000-0000-0000-0000000000f3'];
  await followPage(CITYFAN, 'city');
  await followBoard(BOARDFAN, 'City Council');
  await followBoard(PARKFAN, 'Park Board');
  await db.exec('set role anon');
  assert.deepEqual(await titles('2026-10-08 12:00'), ['Fall fair'], 'signed out: no meetings');
  await signIn(PARKFAN);
  assert.deepEqual(await titles('2026-10-08 12:00'), ['Fall fair'], "another board's follower doesn't get it");
  await signIn(BOARDFAN);
  assert.deepEqual(await reasons('2026-10-08 12:00'), [['Fall fair', 'tomorrow', null],
    ['City Council Meeting', 'follow', 'City Council']], 'lifted, and still under the fair at x 0.3');
  await signIn(CITYFAN);
  assert.deepEqual(await reasons('2026-10-08 12:00'), [['Fall fair', 'tomorrow', null],
    ['City Council Meeting', 'follow', CITY]]);
});

test('a City meeting you are Going to or saved stays in your feed, lower, followed or not', async () => {
  await reset();
  const council = await meeting('City Council Meeting', '2026-10-09');
  const parks = await meeting('Park Board', '2026-10-10');
  await goes(council, ME);
  await db.query('insert into public.event_saves (event_id, user_id) values ($1, $2)', [parks, ME]);
  await add('Fall fair', '2026-10-09', { start_time: '6 PM', source_name: 'Arts council' });
  await signIn(ME);
  assert.deepEqual(await titles('2026-10-08 12:00'), ['Fall fair', 'City Council Meeting', 'Park Board']);
  await signIn(YOU);
  assert.deepEqual(await titles('2026-10-08 12:00'), ['Fall fair'], "someone else's Going brings it to nobody else");
});

test("a City meeting that matches no board reaches only the City's followers", async () => {
  await reset();
  await meeting('Special Meeting', '2026-10-09');
  const [CITYFAN, BOARDFAN] = ['00000000-0000-0000-0000-0000000000f1', '00000000-0000-0000-0000-0000000000f2'];
  await followPage(CITYFAN, 'city');
  await followBoard(BOARDFAN, 'City Council');
  await signIn(BOARDFAN);
  assert.deepEqual(await titles('2026-10-08 12:00'), []);
  await signIn(CITYFAN);
  assert.deepEqual(await reasons('2026-10-08 12:00'), [['Special Meeting', 'follow', CITY]]);
});

test('a City meeting reaches those who picked Town meetings, lifted by it, as following the City does (onboarding 21)', async () => {
  await reset();
  const council = await meeting('City Council Meeting', '2026-10-09');
  await db.query(`update public.club_events set interests = '{town_meetings}', interests_tagged_at = now() where id = $1`, [council]);
  const compost = await meeting('Compost site open', '2026-10-09');
  await db.query(`update public.club_events set interests = '{outdoors}', interests_tagged_at = now() where id = $1`, [compost]);
  await add('Fall fair', '2026-10-09', { start_time: '6 PM', source_name: 'Arts council' });
  await signIn(ME, ['town_meetings', 'live_music', 'outdoors']);
  assert.deepEqual(await reasons('2026-10-08 12:00'), [['Fall fair', 'tomorrow', null],
    ['City Council Meeting', 'interest', 'town_meetings']], 'in, under the fair at x 0.3; the compost site hours stay the City\'s');
  await signIn(YOU, ['live_music', 'outdoors', 'dining']);
  assert.deepEqual(await titles('2026-10-08 12:00'), ['Fall fair'], 'not picked and following nothing City: out');
});

test('an Event for college students reaches only those who picked College, or are Going or saved it (onboarding 21)', async () => {
  await reset();
  const dogs = await add('Therapy Dogs', '2026-10-09', { start_time: '7 PM', source_name: 'CSB SJU Libraries' });
  await db.query(`update public.club_events set interests = '{books,campus,college}', interests_tagged_at = now() where id = $1`, [dogs]);
  const choir = await add('Christmas with CSB SJU', '2026-10-09', { start_time: '7 PM', source_name: 'CSB SJU' });
  await db.query(`update public.club_events set interests = '{live_music,campus}', interests_tagged_at = now() where id = $1`, [choir]);
  await signIn(ME, ['college', 'live_music', 'outdoors']);
  assert.deepEqual((await titles('2026-10-08 12:00')).sort(), ['Christmas with CSB SJU', 'Therapy Dogs']);
  await signIn(YOU, ['campus', 'live_music', 'outdoors']);
  assert.deepEqual(await titles('2026-10-08 12:00'), ['Christmas with CSB SJU'], 'Campus alone: the public concert only');
  await db.exec('reset role');
  await db.query('insert into public.event_saves (event_id, user_id) values ($1, $2)', [dogs, YOU]);
  await signIn(YOU, ['campus', 'live_music', 'outdoors']);
  assert.deepEqual((await titles('2026-10-08 12:00')).sort(), ['Christmas with CSB SJU', 'Therapy Dogs'], 'saved, it stays');
  await db.exec('reset role; set role anon; reset request.jwt.claim.sub');
  assert.deepEqual(await titles('2026-10-08 12:00'), ['Christmas with CSB SJU'], 'signed out: the public concert only');
});

test("Campus lifts CSB and SJU's Events, spaced as one host's so a dozen campus calendars can't fill the top (onboarding 21)", async () => {
  await reset();
  for (const n of [1, 2, 3, 4]) {
    const id = await add(`Campus ${n}`, '2026-10-09', { start_time: '6 PM', source_name: `CSB calendar ${n}` });
    await db.query(`update public.club_events set interests = '{live_music,campus}', interests_tagged_at = now() where id = $1`, [id]);
  }
  for (const n of [1, 2]) {
    const id = await add(`Trivia ${n}`, '2026-10-09', { start_time: '6 PM', source_name: `Taproom ${n}` });
    await db.query(`update public.club_events set interests = '{games}', interests_tagged_at = now() where id = $1`, [id]);
  }
  await signIn(ME, ['campus', 'games', 'outdoors']);
  assert.deepEqual(await titles('2026-10-08 12:00'), ['Campus 1', 'Trivia 1', 'Trivia 2', 'Campus 2', 'Campus 3', 'Campus 4'],
                   'the second campus Event counts 0.8, the third 0.64, as if from one calendar');
});

test("the City's and Joetown's other Events lift for their followers; a Place you follow is named first", async () => {
  await reset();
  await add('Pilates class', '2026-10-12', { start_time: '6 PM' });
  await add('Winterwalk', '2026-10-12', { start_time: '5 PM', source_name: 'JoeTown' });
  const fest = await add('Fall Fest', '2026-10-12', { start_time: '4 PM', source_name: 'JoeTown' });
  await db.query(`update public.club_events set place_entry_id = 'white-peony' where id = $1`, [fest]);
  await add('Bingo', '2026-10-09', { start_time: '6 PM', source_name: "Sal's" });
  await signIn(ME);
  assert.equal((await titles('2026-10-08 12:00'))[0], 'Bingo', 'following nothing: soonest first');
  await followPage(ME, 'city');
  await followPage(ME, 'town');
  await followPlace(ME);
  await signIn(ME);
  const by = Object.fromEntries((await reasons('2026-10-08 12:00')).map(([t, r, n]) => [t, [r, n]]));
  assert.deepEqual(by, { 'Pilates class': ['follow', CITY], Winterwalk: ['follow', 'Joetown'],
                         'Fall Fest': ['follow', PEONY], Bingo: ['tomorrow', null] });
  assert.deepEqual(await titles('2026-10-08 12:00'), ['Fall Fest', 'Pilates class', 'Bingo', 'Winterwalk'],
                   "Joetown's second Event counts half, as any host's");
  await noPlaces();
});

// After the best, and the loop (town-feed 23): the 20 soonest Events past their show-from day, and each round's
// places and repeats past them.
async function later(at) {
  const { rows } = await db.query(
    `select title from public.flat_town_feed(($1::timestamp at time zone 'America/Chicago'), false, true)`, [at]);
  return rows.map((r) => r.title);
}
async function more(round, opened = [], shown = [], at = '2026-10-08 12:00') {
  const { rows } = await db.query(
    `select m.kind, coalesce(p.name, e.title, b.title) as name
     from public.get_town_more(p_round => $1, p_opened => $2::uuid[], p_shown => $4::uuid[],
                               p_now => ($3::timestamp at time zone 'America/Chicago')) with ordinality m(kind, id, n)
     left join public.places p on p.id = m.id
     left join public.club_events e on e.id = m.id
     left join public.board_items b on b.id = m.id
     order by m.n`, [round, opened, at, shown]);
  return rows.map((r) => `${r.kind}:${r.name}`);
}
async function place(name, type = 'cafe', logo = true) {
  await db.exec('reset role');
  const { rows: [{ id }] } = await db.query(
    `insert into public.places (lat, lon, family, name, entry_id, primary_type, search_logo) values (45.5, -94.3, 'business', $1, $2, $3, $4) returning id`,
    [name, name.toLowerCase().replace(/\W+/g, '-'), type, logo ? JSON.stringify({ url: `https://x/${name}.webp` }) : null]);
  return id;
}

test('later Events: past their show-from day, soonest first, 20 at a time, under the ranked list\'s rules', async () => {
  await reset();
  await add('Next week', '2026-10-12', { start_time: '6 PM' });
  await add('Craft fair', '2026-12-05', { start_time: '10 AM' });
  await add('Concert', '2026-12-01', { start_time: '7 PM', source_name: 'Choir' });
  await add('Muted bingo', '2026-11-30', { start_time: '6 PM', source_name: "Sal's" });
  const hidden = await add('Hidden trivia', '2026-11-29', { start_time: '6 PM', source_name: 'Taproom' });
  for (let n = 1; n <= 25; n += 1) await add(`Far ${String(n).padStart(2, '0')}`, `2027-01-${String(n).padStart(2, '0')}`, { source_name: `Host ${n}` });
  await signIn(ME);
  await db.query('select public.set_not_interested($1)', [hidden]);
  await db.exec('reset role');
  await db.query(`insert into public.feed_mutes (user_id, host, name) values ($1, $2, $2)`, [ME, "Sal's"]);
  await db.exec('set role authenticated');
  assert.deepEqual(await titles('2026-10-08 12:00'), ['Next week'], 'the ranked list keeps its own window');
  const rows = await later('2026-10-08 12:00');
  assert.equal(rows.length, 20);
  assert.deepEqual(rows.slice(0, 4), ['Concert', 'Craft fair', 'Far 01', 'Far 02'],
                   'soonest first; Not interested and Mute keep theirs out; nothing already in the ranked list');
  await db.exec('reset role; reset request.jwt.claim.sub; set role anon');
  assert.deepEqual((await later('2026-10-08 12:00')).slice(0, 2), ['Hidden trivia', 'Muted bingo'],
                   'signed out: the same, with nothing hidden');
  await db.exec('reset role');
});

test('places to try: those Search opens, no services, what you follow first, then the most followed', async () => {
  await reset();
  await noPlaces();
  const cafe = await place('Cafe');
  const bakery = await place('Bakery', 'bakery');
  const shop = await place('Shop', 'clothing_store');
  await place('Bank', 'bank');
  await place('No logo', 'bar', false);
  await place('Muted bar', 'bar');
  await place('Quiet deli', 'sandwich_shop');
  await signIn(ME);
  await db.exec('reset role');
  for (const [who, id] of [['c1', cafe], ['c2', cafe], ['c3', cafe], ['c4', bakery], ['c5', bakery]]) {
    await people(db, `00000000-0000-0000-0000-0000000000${who}`);
    await db.query(`insert into public.town_follows (follower_id, target_type, target_id) values ($1, 'place', $2)`,
      [`00000000-0000-0000-0000-0000000000${who}`, id]);
  }
  await db.query(`insert into public.town_follows (follower_id, target_type, target_id) values ($1, 'place', $2)`, [ME, shop]);
  await db.query(`insert into public.feed_mutes (user_id, host, name) values ($1, 'Muted bar', 'Muted bar')`, [ME]);
  await db.exec('set role authenticated');
  assert.deepEqual(await more(0), ['place:Shop', 'place:Cafe', 'place:Bakery', 'place:Quiet deli'],
                   'round 0 has no repeats');
  await db.exec('reset role; reset request.jwt.claim.sub; set role anon');
  const out = await more(0);
  assert.deepEqual(out.slice(0, 3), ['place:Cafe', 'place:Bakery', 'place:Shop'],
                   'signed out: the most followed first, your own follow counted as any neighbour\'s');
  assert.deepEqual(out.slice(3).sort(), ['place:Muted bar', 'place:Quiet deli'],
                   'nothing muted; never a service or a place Search can\'t open');
  await db.exec('reset role');
  await noPlaces();
});

test('a later round: unopened places first, a new order each round, one repeat under 7 days old after every 3', async () => {
  await reset();
  await noPlaces();
  const ids = [];
  for (const n of ['A', 'B', 'C', 'D', 'E', 'F', 'G']) ids.push(await place(`Place ${n}`));
  const shown = [
    await add('Fresh fest', '2026-10-20', { created_at: '2026-10-05 12:00-05' }),
    await add('Fresh run', '2026-10-21', { created_at: '2026-10-07 12:00-05' }),
    await add('Old gala', '2026-10-22', { created_at: '2026-09-25 12:00-05' })];
  // Put out this week but not on the phone's list (past its show-from day, say): never a repeat.
  await add('Fresh but far', '2026-12-20', { created_at: '2026-10-07 12:00-05' });
  await news('Fresh special', '2026-10-06 12:00');
  await news('Old special', '2026-09-20 12:00');
  shown.push(...(await db.query(`select id from public.board_items`)).rows.map((r) => r.id));
  await signIn(ME);
  assert.ok(!(await more(1, [ids[0], ids[1]])).some((r) => r.startsWith('again:')), 'no list sent: no repeats');
  const one = await more(1, [ids[0], ids[1]], shown);
  assert.deepEqual(one.map((r) => r.split(':')[0]),
    ['place', 'place', 'place', 'again', 'place', 'place', 'place', 'again', 'place', 'again']);
  const places = one.filter((r) => r.startsWith('place:'));
  assert.deepEqual(places.slice(-2).sort(), ['place:Place A', 'place:Place B'], 'the ones you opened go last');
  assert.deepEqual(one.filter((r) => r.startsWith('again:')).sort(), ['again:Fresh fest', 'again:Fresh run', 'again:Fresh special'],
                   'nothing older than 7 days comes back');
  const orders = [];
  for (const round of [2, 3, 4]) orders.push((await more(round, [ids[0], ids[1]], shown)).filter((r) => r.startsWith('place:')));
  assert.ok(orders.some((o) => o.slice(0, 5).join() !== places.slice(0, 5).join()), 'each round its own order');
  assert.deepEqual(await more(1, [ids[0], ids[1]], shown), one, 'and the same round asked again, the same');
  for (const o of orders) assert.deepEqual(o.slice(-2).sort(), ['place:Place A', 'place:Place B']);
  await db.exec('reset role');
  await noPlaces();
});

// Feed load (20261102155729_feed_once_per_open.sql): Event of the day reads only its slice of the Town
// feed, never the whole of it, and gives exactly what it gave when it read the whole feed.
const SHE = '00000000-0000-0000-0000-0000000000c1';
async function busyWeekend() {
  await reset();
  const e = {};
  const on = async (title, day, start, host, interests = null, draw = 2) => {
    e[title] = await add(title, day, { start_time: start, source_name: host });
    if (interests) await tagged(e[title], interests, draw);
    return e[title];
  };
  // Friday Oct 9, with the morning's picks.
  await on('Bake sale', '2026-10-09', '8 AM', 'Church', ['dining']);
  await on('Pancake breakfast', '2026-10-09', '9 AM', 'Legion', ['dining']);
  await on('Quilt show', '2026-10-09', '1 PM', 'Quilters', ['arts']);
  await on('Fix-It Clinic', '2026-10-09', '2 PM', 'Library', ['books']);
  await on('Parade', '2026-10-09', '3 PM', 'JoeTown', ['festivals'], 3);
  await on('Campus lecture', '2026-10-09', '4 PM', 'CSB', ['campus', 'books']);
  await on('Fall fair', '2026-10-09', '5 PM', 'Fair board', ['festivals'], 3);
  await on('Loud night', '2026-10-09', '9 PM', 'Loud bar', ['bars']);
  await on('Halloween party', '2026-10-09', '8 PM', 'Taproom', ['bars', 'live_music']);
  await on('Council meeting', '2026-10-09', '6 PM', 'City', [], 1);
  // The rest of each host's Events, which the feed's spacing reads, and a weekly regular.
  for (const d of ['2026-10-09', '2026-10-16', '2026-10-23']) await add('Trivia', d, { start_time: '7 PM', source_name: 'Taproom' });
  await on('Taproom brunch', '2026-10-10', '10 AM', 'Taproom', ['dining']);
  await on('Taproom show', '2026-10-10', '7 PM', 'Taproom', ['live_music'], 3);
  await on('Rummage sale', '2026-10-10', '9 AM', 'Church', ['dining']);
  await on('Campus concert', '2026-10-10', '2 PM', 'SJU', ['campus', 'live_music'], 3);
  await on('Campus play', '2026-10-12', '7 PM', 'CSB', ['campus', 'arts'], 3);
  await on('Fair cleanup', '2026-10-10', '8 AM', 'Fair board', ['outdoors']);
  await on('Legion fish fry', '2026-10-10', '5 PM', 'Legion', ['dining'], 3);
  await on('Second quilt show', '2026-10-13', '1 PM', 'Quilters', ['arts']);
  // Called off, still in the feed for the Heart it has: never a pick.
  await db.query(`update public.club_events set cancelled_at = now() where id = $1`, [e.Parade]);
  await people(db, SHE);
  await db.query(`insert into public.event_likes (event_id, user_id) values ($1, $2)`, [e.Parade, SHE]);
  await standouts('2026-10-09', [e.Parade, e['Fall fair'], e['Quilt show'], e['Loud night'], e['Bake sale'],
                                 e['Campus lecture'], e['Pancake breakfast'], e['Halloween party']]);
  // Saturday Oct 10 has no picks; Sunday Oct 11 has nothing on.
  return e;
}

// Each viewer as the stories read them: signed out, a neighbour with a hidden Event, a muted host and
// a Going, and the admin (the Score line).
async function asViewer(who, e) {
  if (who === 'out') { await db.exec('reset role; reset request.jwt.claim.sub; reset request.jwt.claims; set role anon'); return; }
  await signIn(ME, ['dining', 'campus', 'arts']);
  await db.exec('reset role');
  await db.query(`insert into public.feed_mutes (user_id, host, name) values ($1, 'Loud bar', 'Loud bar') on conflict do nothing`, [ME]);
  await db.query(`insert into public.feed_actions (user_id, item_id, action, at)
                  values ($1, $2, 'not_interested', timestamptz '2026-10-01 12:00-05') on conflict do nothing`, [ME, e['Quilt show']]);
  await db.query(`insert into public.event_rsvps (event_id, user_id) values ($1, $2) on conflict do nothing`, [e['Taproom brunch'], ME]);
  await db.exec(`set role authenticated; ${who === 'admin' ? `set request.jwt.claims = '${ADMIN}'` : 'reset request.jwt.claims'}`);
}
const MOMENTS = ['00:00', '07:00', '10:30', '15:00', '18:30', '21:30', '23:30']
  .flatMap((t) => ['2026-10-09', '2026-10-10', '2026-10-11'].map((d) => `${d} ${t}`));
// The new functions through the lens (above): an Event's card unpacked into the old columns. A news row's
// category left the answer with codebase-health-2 03 (no app read it), so the old feed's is read as none.
const rowsOf = async (fn, at) => (await db.query(
  `select * from public.${fn}(($1::timestamp at time zone 'America/Chicago'))`, [at])).rows;
const noNewsCategory = (rows) => rows.map((r) => (r.kind === 'news' ? { ...r, category: null } : r));

test('feed-load: Event of the day picks what it did when it read the whole feed: signed out, signed in, admin, every day and time', async () => {
  const e = await busyWeekend();
  const seen = {};
  for (const who of ['out', 'in', 'admin']) {
    await asViewer(who, e);
    for (const at of MOMENTS) {
      const now = await rowsOf('flat_event_of_the_day', at);
      assert.deepEqual(now, await rowsOf('old_event_of_the_day', at), `${who} at ${at}`);
      seen[`${who} ${at}`] = now.map((r) => r.title);
    }
  }
  await db.exec('reset role; reset request.jwt.claims');
  // The stories reach every way a pick goes: picks that fit, a called-off pick, a hidden one, a muted
  // host's, one that's over, a day with no picks, a day with nothing on.
  assert.deepEqual(seen['out 2026-10-09 07:00'], ['Bake sale', 'Quilt show', 'Fall fair']);
  assert.deepEqual(seen['in 2026-10-09 07:00'], ['Bake sale', 'Campus lecture', 'Fall fair'],
                   'not the hidden quilt show, nor the muted loud night; the cancelled parade never');
  assert.deepEqual(seen['in 2026-10-09 10:30'], ['Pancake breakfast', 'Campus lecture', 'Fall fair'],
                   'the bake sale is over: the next morning pick takes its spot');
  assert.deepEqual(seen['out 2026-10-10 00:00'], ['Campus concert'],
                   "no picks: the feed's top Event; the Taproom show counts half behind its host's other Events");
  assert.deepEqual(seen['in 2026-10-10 00:00'], ['Taproom brunch'], 'no picks: the one you are Going to');
  assert.deepEqual(seen['out 2026-10-11 07:00'], [], 'nothing on');
  assert.ok(seen['admin 2026-10-09 07:00'].length === 3);
});

test('feed-load: get_town_feed gives the same rows in the same order as before it moved to private.town_feed', async () => {
  const e = await busyWeekend();
  await news('Taco Tuesday', '2026-10-08 17:00', { source_name: 'Taproom', interests: ['dining'] });
  await news('Road work on Minnesota St', '2026-10-08 09:00', { category: 'road' });
  for (const who of ['out', 'in', 'admin']) {
    await asViewer(who, e);
    for (const at of ['2026-10-08 12:00', '2026-10-09 07:00', '2026-10-09 15:00', '2026-10-10 18:30']) {
      for (const n of [false, true]) {
        // And after the best (town-feed 23): the later Events, which ignore news.
        for (const later of [false, true]) {
          const sql = (fn) => db.query(`select * from public.${fn}(($1::timestamp at time zone 'America/Chicago'), $2, $3)`,
                                       [at, n, later]);
          const [a, b] = [(await sql('flat_town_feed')).rows, noNewsCategory((await sql('old_town_feed')).rows)];
          if (!later) assert.ok(a.length > 3);
          assert.deepEqual(a, b, `${who} at ${at}, news ${n}, later ${later}`);
        }
      }
    }
  }
  await db.exec('reset role; reset request.jwt.claims');
  // A later migration that gives get_town_feed a body of its own again would leave Event of the day
  // reading the old one: change private.town_feed instead.
  const { rows: [{ def }] } = await db.query(`select pg_get_functiondef('public.get_town_feed(timestamptz, boolean, boolean)'::regprocedure) as def`);
  assert.match(def, /private\.town_feed\(p_now, p_news, null, p_later\)/);
});

// Calls to each function during one read, counted by Postgres itself (track_functions): the counts
// after it less those before it.
async function callsDuring(sql, as) {
  const counts = async () => Object.fromEntries((await db.query(`select funcname, calls::int from pg_stat_xact_user_functions
    where funcname in ('get_town_feed', 'old_town_feed', 'town_feed')`)).rows.map((r) => [r.funcname, r.calls]));
  await db.exec(`reset role; begin; set local track_functions = 'all'`);
  const was = await counts();
  await db.exec(as);
  await db.query(sql);
  await db.exec('reset role');
  const now = await counts();
  await db.exec('commit');
  return Object.fromEntries(Object.entries(now).map(([f, n]) => [f, n - (was[f] ?? 0)]).filter(([, n]) => n > 0));
}

test('feed-load: with 5,000 people, Event of the day never works out the whole feed, and reads faster', async () => {
  await fiveThousand();
  const READER = '00000000-0000-0000-0001-000000000042';
  const at = '2026-10-08 12:00';
  const eotd = (fn, when = at) => db.query(`select * from public.${fn}(($1::timestamp at time zone 'America/Chicago'))`, [when]);
  const median = async (fn, when) => {
    await eotd(fn, when); // warm up
    const times = [];
    for (let i = 0; i < 5; i++) { const t0 = performance.now(); await eotd(fn, when); times.push(performance.now() - t0); }
    return times.sort((a, b) => a - b)[2];
  };
  await signIn(READER);
  const as = `set role authenticated; set request.jwt.claim.sub = '${READER}'`;
  // No picks written (Daily's other days, or a morning the job didn't run): the day's Events.
  const out = {};
  out.oldNone = await median('old_event_of_the_day', at);
  out.newNone = await median('get_event_of_the_day', at);
  assert.deepEqual((await eotd('flat_event_of_the_day')).rows, (await eotd('old_event_of_the_day')).rows);
  assert.equal((await eotd('get_event_of_the_day')).rows.length, 1);
  // The morning's picks: four of the day's Events.
  await db.exec('reset role');
  const { rows: today } = await db.query(`select id from public.club_events where event_date = '2026-10-08' order by title limit 4`);
  await standouts('2026-10-08', today.map((r) => r.id));
  await signIn(READER);
  out.oldPicks = await median('old_event_of_the_day', '2026-10-08 07:00');
  out.newPicks = await median('get_event_of_the_day', '2026-10-08 07:00');
  const picked = (await eotd('flat_event_of_the_day', '2026-10-08 07:00')).rows;
  assert.deepEqual(picked, (await eotd('old_event_of_the_day', '2026-10-08 07:00')).rows);
  assert.ok(picked.length >= 1);
  console.log(`  get_event_of_the_day with 5,000 people, median: no picks ${out.oldNone.toFixed(1)} ms before, ` +
              `${out.newNone.toFixed(1)} ms now; with picks ${out.oldPicks.toFixed(1)} ms before, ${out.newPicks.toFixed(1)} ms now`);
  // Postgres's own count: the old one ran the whole feed once a read; the new one never does.
  const q = (fn) => `select * from public.${fn}(('2026-10-08 07:00'::timestamp at time zone 'America/Chicago'))`;
  assert.deepEqual(await callsDuring(q('old_event_of_the_day'), as), { old_town_feed: 1 });
  assert.deepEqual(await callsDuring(q('get_event_of_the_day'), as), { town_feed: 1 });
  assert.deepEqual(await callsDuring(q('get_town_feed'), as), { get_town_feed: 1, town_feed: 1 });
  // Each read works out a slice, far smaller than the feed: at most half its time, either way.
  assert.ok(out.newNone < out.oldNone / 2, `no picks: ${out.newNone} ms against ${out.oldNone}`);
  assert.ok(out.newPicks < out.oldPicks / 2, `picks: ${out.newPicks} ms against ${out.oldPicks}`);
  await db.exec(`reset role; delete from public.places where entry_id like 'speed-place-%'`);
});

// Posts (town-feed 29, BP app references/post-screen): a neighbour's own words, maybe a photo, for 7
// days once the check said yes. The app asks with p_news, as it does for news.
async function post(by, words, more = {}) {
  await db.exec('reset role');
  const row = { at: '2026-10-08 09:00', status: 'approved', friendsOnly: false, tagged: null, photo: null, aspect: null, ...more };
  const { rows } = await db.query(
    `insert into public.club_events (kind, title, submitted_by, status, created_at, friends_only, tagged, image_url, image_aspect)
     values ('post', $1, $2, $3, ($4::timestamp at time zone 'America/Chicago'), $5, $6, $7, $8) returning id`,
    [words, by, row.status, row.at, row.friendsOnly, row.tagged, row.photo, row.aspect]);
  return rows[0].id;
}
async function posts(at, news = true) {
  const { rows } = await db.query(
    `select title, kind, poster, event_date, leaves_at from public.flat_town_feed(($1::timestamp at time zone 'America/Chicago'), $2)
     where kind = 'post'`, [at, news]);
  return rows;
}
const postTitles = async (at) => (await posts(at)).map((r) => r.title);

test('a neighbour\'s post shows for 7 days with who posted it, and only to an app that asks', async () => {
  await reset();
  await neighbour(ANNA, 'Anna Lee', { photo: PHOTO });
  await post(ANNA, 'Anyone up for sledding?');
  await signIn(ME);
  const [row] = await posts('2026-10-08 12:00');
  assert.equal(row.title, 'Anyone up for sledding?');
  assert.equal(row.event_date, null);
  assert.deepEqual(row.poster, { id: ANNA, name: 'Anna Lee', photo: PHOTO, tagged: [], friends_only: false });
  assert.deepEqual(await posts('2026-10-08 12:00', false), [], 'an older app never gets a row with no date');
  assert.deepEqual(await postTitles('2026-10-15 08:59'), ['Anyone up for sledding?']);
  assert.deepEqual(await postTitles('2026-10-15 09:01'), [], 'gone after 7 days');
  assert.deepEqual(await postTitles('2026-10-08 08:59'), [], 'nor before it was posted');
});

test('a pending or refused post never shows, except a pending one to its poster', async () => {
  await reset();
  await neighbour(ANNA, 'Anna Lee');
  await post(ANNA, 'Waiting', { status: 'pending' });
  await post(ANNA, 'Refused', { status: 'rejected' });
  await signIn(ME);
  assert.deepEqual(await postTitles('2026-10-08 12:00'), []);
  await signIn(ANNA);
  assert.deepEqual(await postTitles('2026-10-08 12:00'), [], 'the feed shows only what the check passed');
});

test('a Friends-only post reaches the poster and their friends, and no one else', async () => {
  await reset();
  await neighbour(ANNA, 'Anna Lee');
  await neighbour(BEN, 'Ben Ortiz');
  await post(ANNA, 'Just for friends', { friendsOnly: true });
  await post(ANNA, 'For the Town', { at: '2026-10-08 08:00' });
  await signIn(ME);
  assert.deepEqual(await postTitles('2026-10-08 12:00'), ['For the Town']);
  assert.deepEqual((await db.query(`select title from public.club_events where kind = 'post'`)).rows.map((r) => r.title),
                   ['For the Town'], 'not even a plain read hands it over');
  await befriend(ME, ANNA);
  await signIn(ME);
  assert.deepEqual((await postTitles('2026-10-08 12:00')).sort(), ['For the Town', 'Just for friends']);
  await signIn(ANNA);
  assert.deepEqual((await postTitles('2026-10-08 12:00')).sort(), ['For the Town', 'Just for friends']);
  assert.deepEqual((await posts('2026-10-08 12:00')).map((r) => [r.title, r.poster.friends_only]).sort(),
                   [['For the Town', false], ['Just for friends', true]], 'and its card says who can see it');
  await signIn(BEN);
  assert.deepEqual(await postTitles('2026-10-08 12:00'), ['For the Town']);
  await db.exec(`reset role; reset request.jwt.claim.sub; set role anon`);
  assert.deepEqual(await postTitles('2026-10-08 12:00'), ['For the Town'], 'signed out sees the Town\'s only');
});

test('a post from someone you blocked, or who blocked you, or a nameless account, stays out', async () => {
  await reset();
  await neighbour(ANNA, 'Anna Lee');
  await neighbour(BEN, 'Ben Ortiz');
  await neighbour(CAL, '');
  await post(ANNA, 'From Anna');
  await post(BEN, 'From Ben');
  await post(CAL, 'From nobody');
  await db.query(`insert into private.blocks (blocker_id, blocked_id) values ($1, $2), ($3, $1)`, [ME, ANNA, BEN]);
  await signIn(ME);
  assert.deepEqual(await postTitles('2026-10-08 12:00'), []);
});

test('Not interested keeps out that post alone, even when two photo posts share no words', async () => {
  await reset();
  await neighbour(ANNA, 'Anna Lee');
  const one = await post(ANNA, '', { photo: 'https://example.com/a.jpg' });
  await post(ANNA, '', { photo: 'https://example.com/b.jpg', at: '2026-10-08 08:00' });
  await db.query(`insert into auth.users (id) values ($1) on conflict do nothing`, [ME]);
  await db.query(`insert into public.feed_actions (user_id, item_id, action, at)
                  values ($1, $2, 'not_interested', now())`, [ME, one]);
  await signIn(ME);
  assert.equal((await posts('2026-10-08 12:00')).length, 1);
});

test('a second post from the same neighbour counts half, as a host\'s second Event does', async () => {
  await reset();
  await neighbour(ANNA, 'Anna Lee');
  await neighbour(BEN, 'Ben Ortiz');
  await post(ANNA, 'A');
  await post(ANNA, 'B');
  await post(BEN, 'C');
  await signIn(ME);
  assert.deepEqual(await postTitles('2026-10-08 12:00'), ['A', 'C', 'B']);
});

test('your own post and a friend\'s rise above a stranger\'s; points halve each day', async () => {
  await reset();
  await neighbour(ANNA, 'Anna Lee');
  await neighbour(BEN, 'Ben Ortiz');
  await post(BEN, 'Stranger, just now', { at: '2026-10-08 11:00' });
  await post(BEN, 'Stranger, yesterday', { at: '2026-10-07 11:00' });
  await post(ANNA, 'Friend, this morning', { at: '2026-10-08 10:00' });
  await befriend(ME, ANNA);
  await db.exec('reset role');
  await db.query(`insert into public.town_follows (follower_id, target_type, target_id) values ($1, 'profile', $2)`, [ME, ANNA]);
  await neighbour(ME, 'Me Myself');
  await post(ME, 'Mine, two days ago', { at: '2026-10-06 11:00' });
  await signIn(ME);
  // Friend: (1 + 3 yours + 2 new) × 0.94; stranger now: (1 + 2 new) × 0.97; mine: (1 + 3) × 0.25;
  // stranger yesterday: 1 × 0.5, not New any more.
  assert.deepEqual(await postTitles('2026-10-08 12:00'),
                   ['Friend, this morning', 'Stranger, just now', 'Mine, two days ago', 'Stranger, yesterday']);
});

test('the poster names the friends they tagged, in their order', async () => {
  await reset();
  await neighbour(ANNA, 'Anna Lee');
  await neighbour(BEN, 'Ben Ortiz');
  await neighbour(CAL, 'Cal Ng');
  await post(ANNA, 'Sledding', { tagged: [CAL, BEN] });
  await signIn(ME);
  const [row] = await posts('2026-10-08 12:00');
  assert.deepEqual(row.poster.tagged, [{ id: CAL, name: 'Cal Ng' }, { id: BEN, name: 'Ben Ortiz' }]);
  await signIn(CAL);
  const [mine] = await posts('2026-10-08 12:00');
  assert.deepEqual(mine.poster.tagged, [{ id: CAL, name: 'Cal Ng' }, { id: BEN, name: 'Ben Ortiz' }],
                   'a friend tagged sees their own name on it too');
});

test('a post with a photo sends its shape, so the card is the right size before the photo loads', async () => {
  await reset();
  await neighbour(ANNA, 'Anna Lee');
  await post(ANNA, 'Burger night', { photo: 'https://example.com/p.jpg', aspect: 0.8 });
  await signIn(ME);
  const [row] = await posts('2026-10-08 12:00');
  assert.ok(Math.abs(row.poster.aspect - 0.8) < 1e-6);
});

// The Event card (BP app codebase-health-2, tickets 02 and 03): the Town feed and Daily's Event of the day send
// each Event's card whole, beside only their own, read here as PostgREST hands an RPC's rows to the app
// (json_agg).
// What every feed row sends: news' and posts' columns, the feed's own, and the card (null on news and posts).
const FEED_KEYS = ['card', 'club_id', 'created_at', 'description', 'heart_count', 'hearted', 'id', 'image_url', 'in_club',
  'kind', 'leaves_at', 'location', 'place_picture', 'poster', 'reason', 'reason_name', 'recurrence', 'saved', 'score',
  'source_name', 'source_url', 'title'];
const asTheAppReads = async (sql, params = []) => JSON.parse((await db.query(
  `select coalesce(json_agg(t), '[]')::text as body from (${sql}) t`, params)).rows[0].body);

test('the Town feed sends a full Event card: photo, found link, about, host, game, friends, called off', async () => {
  await reset();
  // SJU Athletics' registry entry, as host_entries names it (live, and here from its migration).
  await db.exec(`delete from public.place_photos; delete from public.places;
    insert into public.sources (town, status, method, entry_id, url, name) values ('st-joseph-mn', 'active', 'fetch', 'activities-athletic-sju', 'https://gojohnnies.com/', 'SJU Athletics');
    insert into public.clubs (name, status, own_entry_id) values ('Johnnie Football Boosters', 'approved', 'activities-athletic-sju');
    insert into public.place_photos (entry_id, url, source_url, position, kind, status, hue, width, height) values
      ('activities-athletic-sju', 'https://x/sju-logo.webp', 'https://gojohnnies.com/', 0, 'logo', 'live', 20, null, null),
      ('clemens-field', 'https://x/field.webp', 'https://csbsju.edu/', 1, 'photo', 'live', null, 1600, 1067);
    insert into public.teams (id, name, short_name, logo_url) values
      ('saint-johns', 'Saint John''s', 'SJU', 'https://x/sju.png'), ('concordia', 'Concordia', 'Concordia', null);`);
  const id = await add('SJU Football vs Concordia', day(2), { source_name: 'SJU Athletics', start_time: '1 PM',
                                                             category: 'sports' });
  await db.query(`update public.club_events set location = 'Clemens Field', image_url = 'https://x/flyer.jpg',
      end_at = $2::date + time '21:00', place_entry_id = 'clemens-field', description = 'Homecoming against the Cobbers.',
      what = 'Football game', source_url = 'https://gojohnnies.com/sports/football/schedule', sport = 'Football',
      team_ids = '{saint-johns,concordia}', occasion = 'Homecoming', cancelled_at = now()
    where id = $1`, [id, day(2)]);
  // Called off stays in the feed only once someone Hearted it.
  await people(db, BEN);
  await db.query(`insert into public.event_likes (event_id, user_id) values ($1, $2)`, [id, BEN]);
  await neighbour(ANNA, 'Anna Lee', { photo: PHOTO });
  await befriend(ME, ANNA);
  await goes(id, ANNA);
  await goes(id, ME);
  await signIn(ME);
  const rows = await asTheAppReads(`select * from public.get_town_feed(($1::timestamp at time zone 'America/Chicago'), true)`,
                                   [nowTown()]);
  await db.exec('reset role; delete from public.place_photos;');
  const row = rows.find((r) => r.id === id);
  const { card } = row;
  assert.equal(typeof card, 'object', 'one nested value, never a string the app has to parse again');
  assert.deepEqual(Object.keys(card).sort(), CARD_KEYS);
  assert.deepEqual([card.id, card.title, card.event_date, card.start_time, card.location, card.image_url, card.category],
                   [id, 'SJU Football vs Concordia', day(2), '1 PM', 'Clemens Field', 'https://x/flyer.jpg', 'sports']);
  assert.equal(new Date(card.end_at).toISOString(), `${day(2)}T21:00:00.000Z`);
  assert.deepEqual([card.club_name, card.source_name], ['Johnnie Football Boosters', 'SJU Athletics']);
  assert.deepEqual([card.going_count, card.going, card.cancelled, card.all_day], [2, true, true, false]);
  assert.equal(card.place_picture.url, 'https://x/field.webp');
  assert.deepEqual(card.host_picture, { url: 'https://x/sju-logo.webp', kind: 'logo', hue: 20 });
  assert.deepEqual([card.description, card.what, card.source_url],
                   ['Homecoming against the Cobbers.', 'Football game', 'https://gojohnnies.com/sports/football/schedule']);
  assert.deepEqual([card.game.sport, card.game.occasion, card.game.teams.map((t) => t.name), card.game.final],
                   ['Football', 'Homecoming', ["Saint John's", 'Concordia'], null]);
  assert.deepEqual(card.friends_going, [{ name: 'Anna', photo: PHOTO }]);
  // Beside the card, only the feed's own (codebase-health-2 03): news' and posts' columns are empty on an Event.
  assert.deepEqual(Object.keys(row).sort(), FEED_KEYS);
  assert.deepEqual([row.title, row.location, row.image_url, row.source_name, row.created_at, row.place_picture,
                    row.description, row.source_url, row.poster], [null, null, null, null, null, null, null, null, null]);
  assert.deepEqual([row.kind, row.heart_count, row.hearted, row.saved], ['event', 1, false, false]);
});

test('the Town feed sends a bare Event card with empties, and none with news or a post', async () => {
  await reset();
  await neighbour(ANNA, 'Anna Lee');
  const id = await add('Porch jam', '2026-10-09', { source_name: null, submitted_by: ANNA });
  await news('Road work on Minnesota St', '2026-10-08 09:00', { category: 'road' });
  await post(ANNA, 'Anyone up for sledding?');
  await signIn(ME);
  const rows = await asTheAppReads(
    `select * from public.get_town_feed(('2026-10-08 12:00'::timestamp at time zone 'America/Chicago'), true)`);
  await db.exec('reset role');
  assert.deepEqual(rows.map((r) => r.kind).sort(), ['event', 'news', 'post']);
  const by = Object.fromEntries(rows.map((r) => [r.kind, r]));
  const { card } = by.event;
  assert.deepEqual(Object.keys(card).sort(), CARD_KEYS);
  assert.deepEqual(card, {
    id, title: 'Porch jam', event_date: '2026-10-09', start_time: null, location: null, image_url: null, category: null,
    club_name: null, source_name: null, end_at: null, all_day: false, created_at: card.created_at,
    going_count: 0, going: false, cancelled: false, place_picture: null, host_picture: null, description: null,
    what: null, source_url: null, game: null, friends_going: [],
  });
  assert.ok(!Number.isNaN(Date.parse(card.created_at)));
  assert.deepEqual([by.news.card, by.post.card], [null, null]);
  // News and posts keep their own columns; every row sends the same keys.
  assert.deepEqual(rows.map((r) => Object.keys(r).sort()), [FEED_KEYS, FEED_KEYS, FEED_KEYS]);
  assert.deepEqual([by.news.title, by.news.source_name, by.post.title], ['Road work on Minnesota St', 'The Wandering Cow', 'Anyone up for sledding?']);
  assert.equal(by.event.title, null, "an Event's title is its card's");
});

test("Daily's Event of the day sends the Event card, with the found link and host picture it never had", async () => {
  await reset();
  await db.exec(`delete from public.daily_standouts; delete from public.place_photos; delete from public.places;
    insert into public.places (lat, lon, family, name, entry_id, search_logo) values
      (45.5, -94.3, 'business', 'The Wandering Cow', 'cow-wandering', '{"url": "https://x/cow-logo.webp", "hue": 19}');
    insert into public.sources (town, status, method, entry_id, url, name) values ('st-joseph-mn', 'active', 'fetch', 'cow-wandering', 'https://cow/events', 'The Wandering Cow');`);
  const id = await add('Sundae Social', '2026-10-09', { start_time: '6 PM', source_name: 'The Wandering Cow' });
  await db.query(`update public.club_events set source_url = 'https://cow/events/sundae' where id = $1`, [id]);
  await db.exec('set role anon');
  const rows = await asTheAppReads(
    `select * from public.get_event_of_the_day(('2026-10-09 07:00'::timestamp at time zone 'America/Chicago'))`);
  await db.exec('reset role; delete from public.places;');
  assert.deepEqual(rows.map((r) => r.card.title), ['Sundae Social']);
  // Beside the card, only the feed's own (codebase-health-2 03).
  assert.deepEqual(Object.keys(rows[0]).sort(), ['card', 'club_id', 'heart_count', 'hearted', 'id', 'in_club',
                                                 'leaves_at', 'reason', 'reason_name', 'recurrence', 'saved', 'score']);
  const { card } = rows[0];
  assert.deepEqual(Object.keys(card).sort(), CARD_KEYS);
  assert.equal(card.source_url, 'https://cow/events/sundae');
  assert.deepEqual(card.host_picture, { url: 'https://x/cow-logo.webp', kind: 'logo', hue: 19 });
  assert.deepEqual([card.going, card.going_count, card.friends_going], [false, 0, []], 'signed out');
});
