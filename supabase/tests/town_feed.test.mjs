// Fixed stories for the Town feed function (supabase/migrations/*_town_feed*.sql), run in
// PGlite: Postgres compiled to WASM, so no Docker. Run: `npm install && npm test` in this
// folder. The schema below is the subset of schema.sql the function reads.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { PGlite } from '@electric-sql/pglite';

const here = dirname(fileURLToPath(import.meta.url));
const migrations = process.env.MIGRATIONS ?? join(here, '..', 'migrations');
// The function as first built, then the recipe that re-creates it (ticket 18).
const files = readdirSync(migrations)
  .filter((f) => f.endsWith('_town_feed.sql') || f.endsWith('_town_feed_recipe.sql')).sort();
const playground = JSON.parse(readFileSync(join(here, 'town_feed_playground.json'), 'utf8'));

const db = await PGlite.create();
await db.exec(`
  set timezone = 'UTC';
  create role anon; create role authenticated;
  create schema auth;
  grant usage on schema auth to anon, authenticated;
  create function auth.uid() returns uuid language sql stable as
    $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
  -- The admin, for the score breakdown: on when a story sets test.admin.
  create function public.is_admin() returns boolean language sql stable as
    $$ select coalesce(current_setting('test.admin', true), '') = 'on' $$;
  create table public.clubs (id uuid primary key default gen_random_uuid(), name text not null);
  create table public.club_events (
    id uuid primary key default gen_random_uuid(), club_id uuid, submitted_by uuid,
    status text not null default 'approved', title text not null, event_date date,
    start_time text, created_at timestamptz not null default now(), location text,
    image_url text, kind text not null default 'event', category text,
    end_at timestamptz, all_day boolean not null default false,
    source_name text, shows_from date);
  create table public.event_rsvps (
    id uuid primary key default gen_random_uuid(), event_id uuid not null,
    user_id uuid not null, created_at timestamptz not null default now());
  create table public.event_saves (
    event_id uuid not null, user_id uuid not null, created_at timestamptz not null default now(),
    primary key (event_id, user_id));
  create table public.town_profiles (
    user_id uuid primary key, interests text[] not null default '{}'::text[]);
  create index event_rsvps_event_idx on public.event_rsvps (event_id);
  create index event_rsvps_user_id_idx on public.event_rsvps (user_id);
  create index event_saves_user_id_idx on public.event_saves (user_id);

  -- The live read rules (schema.sql), so a signed-out read is tested as it runs live.
  alter table public.club_events enable row level security;
  alter table public.event_rsvps enable row level security;
  alter table public.clubs enable row level security;
  alter table public.event_saves enable row level security;
  alter table public.town_profiles enable row level security;
  create policy "read events" on public.club_events for select to public
    using (status = 'approved' or submitted_by = auth.uid() or is_admin());
  create policy "read rsvps" on public.event_rsvps for select to authenticated using (true);
  create policy "read clubs" on public.clubs for select to public using (true);
  create policy "event saves select" on public.event_saves for select to authenticated using (true);
  create policy "town_profiles_select_own" on public.town_profiles for select to public
    using (auth.uid() = user_id);
  grant select on all tables in schema public to anon, authenticated;
`);
for (const f of files) await db.exec(readFileSync(join(migrations, f), 'utf8'));

const CITY = 'City of St. Joseph';
const ME = '00000000-0000-0000-0000-00000000000a';

async function reset() {
  await db.exec(`reset role; delete from public.event_rsvps; delete from public.club_events;
                 delete from public.event_saves; delete from public.town_profiles;
                 reset request.jwt.claim.sub; reset test.admin;`);
}

// Created well before the stories' dates, so nothing is new unless a story says so.
async function add(title, date, more = {}) {
  const row = { source_name: CITY, start_time: null, end_at: null, all_day: false,
                shows_from: null, status: 'approved', submitted_by: null, category: null,
                created_at: '2026-09-01 12:00-05', ...more };
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
  await db.query(`insert into public.town_profiles (user_id, interests) values ($1, $2)
                  on conflict (user_id) do update set interests = excluded.interests`, [id, interests]);
  await db.exec(`set role authenticated; set request.jwt.claim.sub = '${id}'`);
}

// Rows at a Town time ("2026-10-08 12:00"), Central time either side of DST.
async function feed(at) {
  const { rows } = await db.query(
    `select title, event_date::text as day, recurrence, rsvpd, leaves_at, reason, reason_name, score
     from public.get_town_feed(($1::timestamp at time zone 'America/Chicago'))`, [at]);
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

test('signed out, the feed reads as the public role and counts no RSVPs', async () => {
  await reset();
  const id = await add('Bake sale', '2026-10-09', { start_time: '11 AM' });
  await add('Hidden draft', '2026-10-09', { status: 'pending', submitted_by: ME });
  await db.query(`insert into public.event_rsvps (event_id, user_id) values ($1, $2)`, [id, ME]);
  const counts = async () => (await db.query(
    `select title, going_count, rsvpd from public.get_town_feed(
       ('2026-10-08 12:00'::timestamp at time zone 'America/Chicago'))`)).rows;
  await db.exec(`set role anon`);
  assert.deepEqual(await counts(), [{ title: 'Bake sale', going_count: 0, rsvpd: false }]);
  await db.exec(`reset role; set role authenticated; set request.jwt.claim.sub = '${ME}'`);
  // Your own draft is readable to you, but only approved events are in the feed.
  assert.deepEqual(await counts(), [{ title: 'Bake sale', going_count: 1, rsvpd: true }]);
});

// ---- The recipe (ticket 18): each neighbour's own order, by the playground's weights ----

const YOU = '00000000-0000-0000-0000-00000000000b';

test('a picked interest lifts an event, and only a picked one', async () => {
  await reset();
  await add('Choir concert', '2026-10-12', { start_time: '3 PM', category: 'live_music' });
  await add('Bake sale', '2026-10-09', { start_time: '11 AM', category: 'dining', source_name: 'Parish' });
  // Signed out, or with other picks, sooner wins.
  assert.deepEqual(await titles('2026-10-08 12:00'), ['Bake sale', 'Choir concert']);
  await signIn(YOU, ['biking']);
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
  await db.exec(`set test.admin = 'on'`);
  const soon = Object.fromEntries((await feed('2026-10-08 12:00')).map((r) => [r.title, r.score.soon]));
  assert.deepEqual(soon, { 'Today': 1, 'A week out': 0.5, 'Two weeks out': 0.25 });
});

test('a bigger event lifts, its size read from how early it shows', async () => {
  await reset();
  await add('Small, tomorrow', '2026-10-09', { start_time: '6 PM' });
  await add('Medium, in 3 days', '2026-10-11', { start_time: '6 PM', source_name: 'Arts center',
                                                shows_from: '2026-09-16' });
  await add('Big, in 3 days', '2026-10-11', { start_time: '7 PM', source_name: 'Park board',
                                             shows_from: '2026-08-22' });
  const rows = await feed('2026-10-08 12:00');
  assert.deepEqual(rows.map((r) => [r.title, r.reason]), [
    ['Big, in 3 days', 'size'],
    ['Medium, in 3 days', 'size'],
    ['Small, tomorrow', 'tomorrow'],
  ]);
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

test('the same host is spaced out: each further item from it counts half', async () => {
  await reset();
  await add('Cafe 1', '2026-10-09', { start_time: '8 AM', source_name: 'Cafe' });
  await add('Cafe 2', '2026-10-09', { start_time: '9 AM', source_name: 'Cafe' });
  await add('Cafe 3', '2026-10-09', { start_time: '10 AM', source_name: 'Cafe' });
  await add('Library', '2026-10-09', { start_time: '7 PM', source_name: 'Library' });
  assert.deepEqual(await titles('2026-10-08 12:00'), ['Cafe 1', 'Library', 'Cafe 2', 'Cafe 3']);
});

test('never more than 3 of one kind in a row while another kind is left', async () => {
  // Events are the only kind in the feed until posts, updates and news exist, so this
  // drives the placing step the feed uses directly.
  const ids = [1, 2, 3, 4, 5].map((n) => `00000000-0000-0000-0000-00000000010${n}`);
  const { rows } = await db.query(
    `select id, spot from public.town_feed_place($1::uuid[], $2::text[], $3::text[], $4::float8[],
       $5::boolean[], 3, 0.5, 4) order by spot`,
    [ids, ['event', 'event', 'event', 'event', 'post'], ['a', 'b', 'c', 'd', 'e'],
     [5, 4, 3, 2, 1], [false, false, false, false, false]]);
  assert.deepEqual(rows.map((r) => r.id), [ids[0], ids[1], ids[2], ids[4], ids[3]]);
});

test('one new event gets spot 4 when it would sit lower', async () => {
  await reset();
  for (const [i, h] of ['8 AM', '9 AM', '10 AM', '11 AM', '12 PM'].entries())
    await add(`Old ${i + 1}`, '2026-10-09', { start_time: h, source_name: `Host ${i}` });
  await add('New', '2026-10-20', { start_time: '6 PM', source_name: 'Newcomer',
                                   created_at: '2026-10-07 12:00-05' });
  await add('Newer, further', '2026-10-21', { start_time: '6 PM', source_name: 'Other',
                                              created_at: '2026-10-07 13:00-05' });
  const rows = await feed('2026-10-08 12:00');
  assert.deepEqual(rows.map((r) => r.title),
                   ['Old 1', 'Old 2', 'Old 3', 'New', 'Old 4', 'Old 5', 'Newer, further']);
  assert.equal(rows[3].reason, 'new');
  // Two days on it's no longer new, and drops back to its place.
  await db.query(`update public.club_events set created_at = '2026-10-05 12:00-05'`);
  assert.deepEqual((await titles('2026-10-08 12:00')).slice(3, 5), ['Old 4', 'Old 5']);
});

test('the score breakdown is filled for the admin and null for everyone else', async () => {
  await reset();
  await add('Bake sale', '2026-10-09', { start_time: '12 PM', category: 'dining' });
  await signIn(YOU, ['dining']);
  assert.equal((await feed('2026-10-08 12:00'))[0].score, null);
  await db.exec(`set test.admin = 'on'`);
  const { score } = (await feed('2026-10-08 12:00'))[0];
  assert.deepEqual(score, {
    interest: 3, friend: 0, follow: 0, popular: 0, size: 0, sizeStep: 1, daysAway: 1,
    soon: 0.9057, acted: 1, spacing: 1, newSpot: false, total: 3.6229, spot: 1, of: 1,
  });
});

test('signed out, the public key gets the same recipe with no personal terms', async () => {
  await reset();
  await add('Concert', '2026-10-12', { start_time: '3 PM', category: 'live_music' });
  await add('Fair', '2026-10-14', { start_time: '10 AM', source_name: 'Fair board',
                                    shows_from: '2026-08-20' });
  await db.exec(`set role anon`);
  const rows = await feed('2026-10-08 12:00');
  assert.deepEqual(rows.map((r) => [r.title, r.reason, r.score]),
                   [['Fair', 'size', null], ['Concert', 'soon', null]]);
});

test("the playground's sample week gives the playground's top 8 for each of its four people", async () => {
  await reset();
  const id = {};
  for (const e of playground.events) {
    const [day, hm] = e.at.split(' ');
    const [h, m] = hm.split(':').map(Number);
    const showsFrom = new Date(Date.parse(day) - playground.lead[e.size] * 86400000)
      .toISOString().slice(0, 10);
    id[e.id] = await add(e.title, day, {
      start_time: `${h % 12 || 12}${m ? `:${String(m).padStart(2, '0')}` : ''} ${h < 12 ? 'AM' : 'PM'}`,
      source_name: e.host, shows_from: showsFrom, category: e.interest,
      created_at: `${e.created}-05`,
    });
  }
  const byTitle = Object.fromEntries(playground.events.map((e) => [e.title, e.id]));
  // The playground's why() line, as the code and name the app turns into words.
  const code = (why) => why.startsWith('Matches ') ? ['interest', why.slice(8)]
    : { 'New in town': ['new', null], 'Big in town': ['size', null], 'Happening today': ['today', null],
        'Happening tomorrow': ['tomorrow', null], 'Coming up soon': ['soon', null] }[why];
  for (const [n, p] of playground.people.entries()) {
    const person = `00000000-0000-0000-0000-0000000002${String(n).padStart(2, '0')}`;
    await db.exec('reset role');
    for (const g of p.going)
      await db.query(`insert into public.event_rsvps (event_id, user_id) values ($1, $2)`, [id[g], person]);
    for (const s of p.saved)
      await db.query(`insert into public.event_saves (event_id, user_id) values ($1, $2)`, [id[s], person]);
    await signIn(person, p.interests);
    const rows = (await feed(playground.now)).slice(0, 8);
    assert.deepEqual(rows.map((r) => byTitle[r.title]), p.top8, p.name);
    assert.deepEqual(rows.map((r) => [r.reason, r.reason_name]), p.why.map(code), p.name);
  }
});

test('the feed is read in under 100 ms with 5,000 people', async () => {
  await reset();
  // About eight weeks of a busy Town: 200 events, 5,000 people with three picks each,
  // 50,000 Going and 10,000 saves.
  const picks = ['live_music', 'dining', 'biking', 'families_kids', 'breweries', 'trails_hiking'];
  await db.query(`
    insert into public.club_events (title, event_date, source_name, start_time, category, created_at)
    select 'Event ' || g, date '2026-10-08' + (g % 56), 'Host ' || (g % 40), (g % 12 + 1) || ' PM',
           ($1::text[])[g % 6 + 1], timestamptz '2026-09-01 12:00-05'
    from generate_series(1, 200) g`, [picks]);
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
    analyze;`);
  const { rows: [{ n }] } = await db.query(`select count(*)::int n from public.event_rsvps`);
  assert.ok(n >= 45000, `${n} Going rows`);
  await signIn('00000000-0000-0000-0001-000000000042');
  await feed('2026-10-08 12:00'); // warm up
  const times = [];
  for (let i = 0; i < 5; i++) {
    const t0 = performance.now();
    await feed('2026-10-08 12:00');
    times.push(performance.now() - t0);
  }
  times.sort((a, b) => a - b);
  console.log(`  get_town_feed with 5,000 people: median ${times[2].toFixed(1)} ms`);
  assert.ok(times[2] < 100, `median ${times[2].toFixed(1)} ms`);
});
