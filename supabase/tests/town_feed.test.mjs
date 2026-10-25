// Fixed stories for the Town feed function (supabase/migrations/*_town_feed*.sql), run in
// PGlite: Postgres compiled to WASM, so no Docker. Run: `npm install && npm test` in this
// folder. The schema below is the subset of schema.sql the function reads.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { loadavg } from 'node:os';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { PGlite } from '@electric-sql/pglite';
import { creating } from './migrations.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const migrations = process.env.MIGRATIONS ?? join(here, '..', 'migrations');
// The function as first built, then each file that re-creates it: the recipe (ticket 18),
// hearts (real-life actions, ticket 03), saves and own-row reads (ticket 19), with the
// counting helpers it reads.
const files = creating(migrations, ['public.get_town_feed', 'public.place_picture', 'public.town_feed_series_label',
  'private.town_feed_place', 'private.going_count', 'private.heart_count', 'private.friends_going',
  'private.event_game', 'public.get_event_of_the_day', 'private.entry_picture', 'private.host_picture']);
// Friends (ticket 28) read the Friends builds' rule for who may be shown, as it is now.
const findable = readdirSync(migrations).filter((f) => f.endsWith('_unfriend_and_block.sql'))
  .map((f) => readFileSync(join(migrations, f), 'utf8'))[0]
  .match(/create or replace function private\.findable\(p_user uuid\)[\s\S]*?\$\$;/)[0];
// (Views, ticket 20: the table, its summary and the clean-up load with town_feed_views; the
// pg_cron jobs in feed_jobs don't, since PGlite has no pg_cron.)
const playground = JSON.parse(readFileSync(join(here, 'town_feed_playground.json'), 'utf8'));

const db = await PGlite.create();
await db.exec(`
  set timezone = 'UTC';
  create role anon; create role authenticated;
  create schema auth;
  grant usage on schema auth to anon, authenticated;
  create table auth.users (id uuid primary key, is_anonymous boolean not null default false,
    banned_until timestamptz);
  create function auth.uid() returns uuid language sql stable as
    $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
  -- The admin, for the score breakdown: on when a story sets test.admin.
  create function public.is_admin() returns boolean language sql stable as
    $$ select coalesce(current_setting('test.admin', true), '') = 'on' $$;
  create table public.clubs (id uuid primary key default gen_random_uuid(), name text not null,
    status text not null default 'approved', entry_id text, place_entry_id text,
    created_at timestamptz not null default now());
  create table public.club_members (id uuid primary key default gen_random_uuid(), club_id uuid not null,
    user_id uuid not null, created_at timestamptz not null default now(), unique (club_id, user_id));
  -- The source registry's pages (watch-every-place 02): no read rule for neighbours, as live.
  create table public.sources (id uuid primary key default gen_random_uuid(), entry_id text not null,
    url text, name text);
  create table public.club_events (
    id uuid primary key default gen_random_uuid(), club_id uuid, submitted_by uuid,
    status text not null default 'approved', title text not null, event_date date,
    start_time text, created_at timestamptz not null default now(), location text,
    image_url text, kind text not null default 'event', category text,
    end_at timestamptz, all_day boolean not null default false,
    source_name text, shows_from date, place_entry_id text, description text,
    sport text, team_ids text[], occasion text);
  -- The schools a game card names (game-card 01, 20261020120000_game_card.sql).
  create table public.teams (id text primary key, name text not null, short_name text not null,
    logo_url text, color text, uuid uuid not null default gen_random_uuid(), colors text[],
    local boolean not null default false, nickname text);
  -- Where events happen, with their pictures (place-photos): the app's places rows, then the
  -- photos Block Party keeps (loaded from their migrations below).
  create table public.places (id uuid primary key default gen_random_uuid(), name text, entry_id text,
    logo_url text, search_logo jsonb);
  -- Town news (town-feed 35), as schema.sql makes it; the migration adds interests and its place.
  create table public.board_items (id uuid primary key default gen_random_uuid(), title text not null,
    blurb text, category text not null, source_name text not null, source_url text,
    tier numeric not null default 1, status text not null default 'staging', starts_at timestamptz,
    created_at timestamptz not null default now(), published_at timestamptz, image_url text,
    fetched_at timestamptz);
  create table public.event_rsvps (
    id uuid primary key default gen_random_uuid(), event_id uuid not null,
    user_id uuid not null, created_at timestamptz not null default now());
  create table public.event_saves (
    event_id uuid not null, user_id uuid not null, created_at timestamptz not null default now(),
    primary key (event_id, user_id));
  create table public.event_likes (
    id uuid primary key default gen_random_uuid(), event_id uuid not null,
    user_id uuid not null, created_at timestamptz not null default now(),
    unique (event_id, user_id));
  create table public.town_profiles (
    user_id uuid primary key, interests text[] not null default '{}'::text[],
    display_name text, avatar_url text);
  -- The Friends builds' tables (friend_requests, unfriend_and_block), as they are live.
  create schema if not exists private;
  create table private.friendships (a uuid not null, b uuid not null, requested_by uuid not null,
    created_at timestamptz not null default now(), primary key (a, b), check (a < b));
  create table private.blocks (blocker_id uuid not null, blocked_id uuid not null,
    created_at timestamptz not null default now(), primary key (blocker_id, blocked_id));
  create index event_rsvps_event_idx on public.event_rsvps (event_id);
  create index event_rsvps_user_id_idx on public.event_rsvps (user_id);
  create index event_saves_user_id_idx on public.event_saves (user_id);
  create index event_likes_event_idx on public.event_likes (event_id);
  create index event_likes_user_id_idx on public.event_likes (user_id);

  -- The live read rules (schema.sql), so a signed-out read is tested as it runs live.
  alter table public.club_events enable row level security;
  alter table public.event_rsvps enable row level security;
  alter table public.clubs enable row level security;
  alter table public.event_saves enable row level security;
  alter table public.event_likes enable row level security;
  alter table public.town_profiles enable row level security;
  alter table public.club_members enable row level security;
  alter table public.sources enable row level security;
  alter table public.board_items enable row level security;
  create policy "read published items" on public.board_items for select to public
    using (status = 'published');
  create policy "read memberships" on public.club_members for select to authenticated using (true);
  create policy "read events" on public.club_events for select to public
    using (status = 'approved' or submitted_by = auth.uid() or is_admin());
  create policy "read rsvps" on public.event_rsvps for select to authenticated using (true);
  create policy "read clubs" on public.clubs for select to public using (true);
  create policy "event saves select" on public.event_saves for select to authenticated using (true);
  create policy "own likes select" on public.event_likes for select to public
    using (auth.uid() = user_id);
  create policy "town_profiles_select_own" on public.town_profiles for select to public
    using (auth.uid() = user_id);
  grant select on all tables in schema public to anon, authenticated;
  -- Supabase gives anon and authenticated every privilege on each new public table, so a
  -- table that must not be read has to revoke it: copied here, so the revoke is tested.
  alter default privileges in schema public grant all on tables to anon, authenticated;
`);
await db.exec(findable);
for (const f of ['20261016150000_place_photos.sql', '20261016170000_place_photo_kind.sql'])
  await db.exec(readFileSync(join(migrations, f), 'utf8'));
for (const f of files) await db.exec(readFileSync(join(migrations, f), 'utf8'));

const CITY = 'City of St. Joseph';
const ME = '00000000-0000-0000-0000-00000000000a';

async function reset() {
  await db.exec(`reset role; delete from public.feed_actions;
                 refresh materialized view private.feed_item_stats;
                 delete from public.event_rsvps; delete from public.club_events;
                 delete from public.event_saves; delete from public.event_likes;
                 delete from public.town_profiles; delete from private.friendships;
                 delete from private.blocks; delete from public.club_members;
                 delete from public.clubs; delete from public.sources; delete from public.teams;
                 delete from public.board_items; delete from public.feed_mutes;
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

test('signed out, the feed reads as the public role with the same counts', async () => {
  await reset();
  const id = await add('Bake sale', '2026-10-09', { start_time: '11 AM' });
  await add('Hidden draft', '2026-10-09', { status: 'pending', submitted_by: ME });
  await db.query(`insert into public.event_rsvps (event_id, user_id) values ($1, $2)`, [id, ME]);
  const counts = async () => (await db.query(
    `select title, going_count, rsvpd from public.get_town_feed(
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
  await db.query(`insert into public.event_likes (event_id, user_id) values ($1, $2), ($1, $3), ($4, $3)`,
                 [fair, ME, OTHER, quiz]);
  const hearts = async () => (await db.query(
    `select title, heart_count, hearted from public.get_town_feed(
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

test('the feed says whether you saved each event, and only yours', async () => {
  await reset();
  const fair = await add('Fall fair', '2026-10-09', { start_time: '11 AM' });
  await add('Quiz night', '2026-10-09', { start_time: '7 PM' });
  const OTHER = '00000000-0000-0000-0000-0000000000c3';
  await db.query(`insert into public.event_saves (event_id, user_id) values ($1, $2)`, [fair, YOU]);
  const saves = async () => (await db.query(
    `select title, saved from public.get_town_feed(
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
    `select going_count, heart_count from public.get_town_feed(
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
  await db.exec(`set test.admin = 'on'`);
  const rows = await feed('2026-10-08 12:00');
  assert.deepEqual(rows.map((r) => [r.title, r.reason, r.reason_name, r.score.interest]),
                   [['Trivia at the taproom', 'interest', 'bars', 6], ['Pancake breakfast', 'interest', 'dining', 3],
                    ['Council meeting', 'tomorrow', null, 0]]);
});

test("one interest can't flood the feed: each further Event on the same interest counts x 0.7", async () => {
  await reset();
  // Six games from six schools at the same hour, and two other things a little later.
  for (let n = 1; n <= 6; n++)
    await add(`Game ${n}`, '2026-10-09', { start_time: '6 PM', category: 'watch_sports', source_name: `School ${n}` });
  await add('Book club', '2026-10-09', { start_time: '7 PM', category: 'books', source_name: 'Library' });
  await add('Choir concert', '2026-10-09', { start_time: '7 PM', category: 'live_music', source_name: 'Arts center' });
  await db.exec(`set test.admin = 'on'`);
  const rows = await feed('2026-10-08 12:00');
  assert.deepEqual(rows.map((r) => r.title.startsWith('Game') ? 'game' : r.title),
                   ['game', 'Book club', 'Choir concert', 'game', 'game', 'game', 'game', 'game'],
                   'by host alone the six games would lead; a second game is worth less than the book club');
  assert.deepEqual(rows.filter((r) => r.title.startsWith('Game')).map((r) => [r.score.spacing, Number(r.score.topicSpacing.toFixed(4))]),
                   [[1, 1], [1, 0.7], [1, 0.49], [1, 0.343], [1, 0.2401], [1, 0.1681]]);
});

test("how much an Event draws the town out is everyone's starting point: 0, 1.5 or 3 points, 2 when not rated", async () => {
  await reset();
  const fair = await add('Art fair', '2026-10-09', { start_time: '10 AM', source_name: 'Arts council' });
  const council = await add('Council meeting', '2026-10-09', { start_time: '9 AM', source_name: 'City' });
  await add('Book sale', '2026-10-09', { start_time: '11 AM', source_name: 'Library' });
  await db.query(`update public.club_events set draw = 3 where id = $1`, [fair]);
  await db.query(`update public.club_events set draw = 1 where id = $1`, [council]);
  await db.exec(`set test.admin = 'on'`);
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
  const council = await add('Council meeting', '2026-10-09', { start_time: '9 AM' });
  const meetingLastWeek = await add('Planning commission', '2026-10-01', { start_time: '6 PM' });
  await add('Bingo', '2026-10-09', { start_time: '11 AM', source_name: "Sal's" });
  await db.query(`update public.club_events set draw = 1 where id in ($1, $2)`, [council, meetingLastWeek]);
  await tap('event_likes', fair, YOU, '2026-10-04 12:00');
  await tap('event_likes', meetingLastWeek, YOU, '2026-10-01 19:00');
  await tap('event_likes', zoo, YOU, '2026-10-07 12:00');
  await tap('event_rsvps', zoo, YOU, '2026-10-07 12:00');
  await signIn(YOU);
  await db.exec(`set test.admin = 'on'`);
  const rows = Object.fromEntries((await feed('2026-10-08 12:00')).map((r) => [r.title, r]));
  // The craft fair you hearted lifts the Zoo day; the Zoo day's own taps don't count for it, and
  // being Going still lowers it as ever.
  assert.deepEqual([rows['Zoo day'].reason, rows['Zoo day'].reason_name, rows['Zoo day'].score.tapped,
                    rows['Zoo day'].score.acted], ['tapped', CITY, 2, 0.4]);
  assert.equal(rows['Council meeting'].score.tapped, 0, 'a council meeting never rises');
  assert.equal(rows['Bingo'].score.tapped, 0, 'a host you never tapped');
});

test('two tapped Events give 3, one Event tapped three ways counts once, 90 days back and no further', async () => {
  await reset();
  const zoo = await add('Zoo day', '2026-10-09', { start_time: '10 AM' });
  const market = await add('Market', '2026-07-25', { start_time: '8 AM' });
  const parade = await add('Parade', '2026-08-01', { start_time: '11 AM' });
  const spring = await add('Spring fling', '2026-06-20', { start_time: '1 PM' });
  for (const t of ['event_rsvps', 'event_saves', 'event_likes']) await tap(t, market, YOU, '2026-07-25 09:00');
  const OTHER = '00000000-0000-0000-0000-0000000000c9';
  await tap('event_likes', parade, OTHER, '2026-08-01 12:00');
  await tap('event_likes', spring, YOU, '2026-06-20 14:00');
  await signIn(YOU);
  await db.exec(`set test.admin = 'on'`);
  const tapped = async () => (await feed('2026-10-08 12:00')).find((r) => r.title === 'Zoo day').score.tapped;
  assert.equal(await tapped(), 2, "75 days back counts, three ways is one Event, a neighbour's heart and 110 days back don't");
  await tap('event_likes', parade, YOU, '2026-08-01 12:00');
  await signIn(YOU);
  await db.exec(`set test.admin = 'on'`);
  assert.equal(await tapped(), 3, 'two other Events of its host');
});

// Friends shape the feed (ticket 28). The helper names friends only on Events not over by the
// clock, so these stories date their Events from today rather than the fixed week above.
const day = (n) => new Date(Date.now() + n * 86400000).toLocaleDateString('en-CA', { timeZone: 'America/Chicago' });
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

test('a friend Going lifts an Event and names them, newest Going first; two friends count at most', async () => {
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
  await db.exec(`set test.admin = 'on'`);
  assert.equal((await feed(nowTown()))[0].score.friend, 8);
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
  await db.exec(`set test.admin = 'on'`);
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

test('never more than 3 of one kind in a row while another kind is left', async () => {
  // Events are the only kind in the feed until posts, updates and news exist, so this
  // drives the placing step the feed uses directly.
  const ids = [1, 2, 3, 4, 5].map((n) => `00000000-0000-0000-0000-00000000010${n}`);
  const { rows } = await db.query(
    `select id, spot from private.town_feed_place($1::uuid[], $2::text[], $3::text[], $4::text[], $5::float8[],
       $6::boolean[], 3, 0.5, 1, 4) order by spot`,
    [ids, ['event', 'event', 'event', 'event', 'post'], ['a', 'b', 'c', 'd', 'e'], [null, null, null, null, null],
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
    interest: 3, friend: 0, follow: 0, popular: 0, viewers: 0, size: 0, sizeStep: 1, draw: 1.5, tapped: 0, daysAway: 1,
    soon: 0.9057, acted: 1, notInterested: 1, spacing: 1, topicSpacing: 1, newSpot: false, total: 4.9815, spot: 1, of: 1,
  });
});

test('the admin\'s breakdown on a longer feed: same host halves, nothing moved when nothing is new', async () => {
  await reset();
  for (const [i, h] of ['8 AM', '9 AM', '10 AM', '11 AM', '12 PM'].entries())
    await add(`Meeting ${i + 1}`, '2026-10-09', { start_time: h });
  await db.exec(`set test.admin = 'on'`);
  const rows = await feed('2026-10-08 12:00');
  assert.deepEqual(rows.map((r) => [r.score.spot, r.score.spacing, r.score.newSpot]),
                   [[1, 1, false], [2, 0.5, false], [3, 0.25, false], [4, 0.125, false], [5, 0.0625, false]]);
  assert.ok(rows.every((r) => r.score.total > 0));
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

test("the playground's sample week gives the playground's whole order for each of its four people", async () => {
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
    : why.startsWith("You've been into ") ? ['tapped', why.slice(17, -7)]
    : { 'New in town': ['new', null], 'Big in town': ['size', null], 'Happening today': ['today', null],
        'Happening tomorrow': ['tomorrow', null], 'Coming up soon': ['soon', null] }[why];
  for (const [n, p] of playground.people.entries()) {
    const person = `00000000-0000-0000-0000-0000000002${String(n).padStart(2, '0')}`;
    await db.exec('reset role');
    for (const g of p.going)
      await db.query(`insert into public.event_rsvps (event_id, user_id) values ($1, $2)`, [id[g], person]);
    for (const s of p.saved)
      await db.query(`insert into public.event_saves (event_id, user_id) values ($1, $2)`, [id[s], person]);
    for (const h of p.hearted)
      await db.query(`insert into public.event_likes (event_id, user_id) values ($1, $2)`, [id[h], person]);
    await signIn(person, p.interests);
    const rows = await feed(playground.now);
    assert.deepEqual(rows.map((r) => byTitle[r.title]), p.order, p.name);
    assert.deepEqual(rows.map((r) => [r.reason, r.reason_name]), p.why.map(code), p.name);
  }
});

// Views (ticket 20). `seen` adds people who saw an event in the feed, `going` people Going,
// then refreshes the summary as its 10-minute job does.
async function seen(event, people, from = 0) {
  await db.exec('reset role');
  await db.query(`insert into auth.users (id) select ('00000000-0000-0000-0002-' || lpad(g::text, 12, '0'))::uuid
                  from generate_series($1::int, $1::int + $2::int - 1) g on conflict do nothing`, [from, people]);
  await db.query(`insert into public.feed_actions (id, user_id, item_id, action)
                  select gen_random_uuid(), ('00000000-0000-0000-0002-' || lpad(g::text, 12, '0'))::uuid, $3, 'view'
                  from generate_series($1::int, $1::int + $2::int - 1) g`, [from, people, event]);
}
async function going(event, people, from = 0) {
  await db.exec('reset role');
  await db.query(`insert into public.event_rsvps (event_id, user_id)
                  select $3, ('00000000-0000-0000-0003-' || lpad(g::text, 12, '0'))::uuid
                  from generate_series($1::int, $1::int + $2::int - 1) g`, [from, people, event]);
}
async function refreshStats() {
  await db.exec('reset role; refresh materialized view private.feed_item_stats');
}
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

test('popularity per view lifts an event, and says popular when it leads', async () => {
  await reset();
  const hit = await add('Crawfish boil', '2026-10-09', { start_time: '5 PM', source_name: 'Krewe' });
  const quiet = await add('Book club', '2026-10-09', { start_time: '5 PM', source_name: 'Library' });
  await seen(hit, 20); await seen(quiet, 20);
  await going(hit, 6);
  await refreshStats();
  const rows = await feed('2026-10-08 12:00');
  assert.deepEqual(rows.map((r) => [r.title, r.reason]), [['Crawfish boil', 'popular'], ['Book club', 'tomorrow']]);
});

test('many views with few Going does not lift', async () => {
  await reset();
  const crowded = await add('Street fair', '2026-10-09', { start_time: '5 PM', source_name: 'City' });
  const loved = await add('Potluck', '2026-10-09', { start_time: '5 PM', source_name: 'Church' });
  await seen(crowded, 500); await going(crowded, 10);
  await seen(loved, 20, 1000); await going(loved, 6, 100);
  await refreshStats();
  const rows = await feed('2026-10-08 12:00');
  assert.deepEqual(rows.map((r) => r.title), ['Potluck', 'Street fair']);
  assert.notEqual(rows[1].reason, 'popular');
});

test('popular as the reason needs 3 Going and the top quarter; one Going still counts its points', async () => {
  await reset();
  const one = await add('Dog park meetup', '2026-10-09', { start_time: '10 AM', source_name: 'Megan' });
  await seen(one, 5); await going(one, 1);
  await refreshStats();
  await db.exec(`set test.admin = 'on'`);
  const [row] = await feed('2026-10-08 12:00');
  assert.equal(row.score.popular, 1, 'one Going in a floor of 20: 1 point');
  assert.equal(row.reason, 'tomorrow', 'one person is not popular');
  // Never seen in the feed: no popularity at all.
  await db.exec(`reset role; delete from public.feed_actions; refresh materialized view private.feed_item_stats`);
  await db.exec(`set test.admin = 'on'`);
  assert.equal((await feed('2026-10-08 12:00'))[0].score.popular, 0);
});

test('an event nobody has seen takes no rank from the ones people saw', async () => {
  await reset();
  const unseen = await add('Big unseen', '2026-10-09', { start_time: '9 AM', source_name: 'A' });
  const seenA = await add('Seen A', '2026-10-09', { start_time: '10 AM', source_name: 'B' });
  const seenB = await add('Seen B', '2026-10-09', { start_time: '11 AM', source_name: 'C' });
  await going(unseen, 9);
  await seen(seenA, 20); await going(seenA, 6, 100);
  await seen(seenB, 20, 1000); await going(seenB, 1, 200);
  await refreshStats();
  const reasons = Object.fromEntries((await feed('2026-10-08 12:00')).map((r) => [r.title, r.reason]));
  assert.equal(reasons['Seen A'], 'popular', 'the unseen event did not push it out of the top quarter');
  assert.notEqual(reasons['Big unseen'], 'popular');
});

test('a new event seen by 30 people no longer takes the new spot', async () => {
  await reset();
  for (const [i, h] of ['8 AM', '9 AM', '10 AM', '11 AM', '12 PM'].entries())
    await add(`Old ${i + 1}`, '2026-10-09', { start_time: h, source_name: `Host ${i}` });
  const fresh = await add('New', '2026-10-20', { start_time: '6 PM', source_name: 'Newcomer',
                                                 created_at: '2026-10-07 12:00-05' });
  await seen(fresh, 29);
  await refreshStats();
  assert.equal((await feed('2026-10-08 12:00'))[3].reason, 'new', '29 viewers: still new');
  await seen(fresh, 1, 500);
  await refreshStats();
  assert.ok((await feed('2026-10-08 12:00')).every((r) => r.reason !== 'new'), '30 viewers: not new');
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

test('the feed is read in under 100 ms with 5,000 people', async () => {
  await reset();
  // About eight weeks of a busy Town: 200 events, 5,000 people with three picks each,
  // 50,000 Going, 10,000 saves and 50,000 hearts.
  const picks = ['live_music', 'dining', 'lakes_biking', 'families_kids', 'bars', 'outdoors'];
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
    insert into auth.users (id) select user_id from public.town_profiles on conflict do nothing;
    update public.town_profiles set display_name = 'Neighbour ' || right(user_id::text, 4);
    insert into private.friendships (a, b, requested_by)
    select least(r, f), greatest(r, f), r
    from (select '00000000-0000-0000-0001-000000000042'::uuid r) x,
         (select user_id f from public.town_profiles
          where user_id <> '00000000-0000-0000-0001-000000000042' order by user_id limit 200) y;
    analyze;`);
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
  // GitHub's shared runner reads it about 2.5x slower than the Mac (102 ms against 40 ms,
  // 2026-10-16), so its budget is 2.5x too. So does a busy Mac: at a load of 70 the pre-push
  // check read 159 ms and refused a push that touched no SQL (2026-10-18).
  const busy = loadavg()[0] > 8;
  const budget = process.env.CI || busy ? 250 : 100;
  assert.ok(times[2] < budget, `median ${times[2].toFixed(1)} ms, budget ${budget}`);
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
    insert into public.places (name, entry_id, logo_url, search_logo) values
      ('Sal''s Bar & Grill', 'sals', 'https://x/pin.png', '{"url":"https://x/sals.webp","hue":7,"chroma":true}'),
      ('Coborn''s', 'coborns', 'https://x/coborns-pin.png', null),
      ('Grey Co', 'grey', null, '{"url":"https://x/grey.webp","hue":40,"chroma":false}');`);
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

  await db.query(`insert into public.club_events (title, event_date, source_name, place_entry_id, created_at)
                  values ('Trivia', '2026-10-09', 'Krewe', 'krewe', '2026-09-01 12:00-05'),
                         ('Walk', '2026-10-09', $1, null, '2026-09-01 12:00-05')`, [CITY]);
  await db.exec('set role anon');
  const { rows } = await db.query(`select title, place_picture
    from public.get_town_feed(('2026-10-08 12:00'::timestamp at time zone 'America/Chicago')) order by title`);
  await db.exec('reset role');
  assert.deepEqual(rows.map((r) => [r.title, r.place_picture?.url ?? null]),
                   [['Trivia', 'https://x/food.webp'], ['Walk', null]], 'signed out too');
  await db.exec('delete from public.place_photos; delete from public.places;');
});

test('each event carries its own description, for the Event page\'s About', async () => {
  await reset();
  const fair = await add('Fall fair', '2026-10-09');
  await add('Council meeting', '2026-10-09');
  await db.query(`update public.club_events set description = 'Apple cider and a hay ride.' where id = $1`, [fair]);
  await db.exec('set role anon');
  const { rows } = await db.query(`select title, description
    from public.get_town_feed(('2026-10-08 12:00'::timestamp at time zone 'America/Chicago')) order by title`);
  await db.exec('reset role');
  assert.deepEqual(rows.map((r) => [r.title, r.description]),
                   [['Council meeting', null], ['Fall fair', 'Apple cider and a hay ride.']]);
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
    from public.get_town_feed(('2026-10-08 12:00'::timestamp at time zone 'America/Chicago')) order by title`);
  assert.deepEqual(rows.map((r) => [r.title, r.what]), [['Fall fair', null], ['Rev. Daniel Groody: Koch Chair Lecture', 'Lecture']]);
  const day = (await db.query(`select title, what, game
    from public.get_event_of_the_day(('2026-10-09 18:00'::timestamp at time zone 'America/Chicago'))`)).rows;
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
    from public.get_town_feed(('2026-10-08 12:00'::timestamp at time zone 'America/Chicago')) order by title`);
  await db.exec('reset role');
  // A team with a row carries its uuid (hello-drop 03); one with none, null. The uuid is random.
  const sju = rows.find((r) => r.title.startsWith('SJU')).game.teams[0];
  assert.match(sju.id, /^[0-9a-f-]{36}$/);
  const games = rows.map((r) => [r.title, r.game && { ...r.game, teams: r.game.teams.map(({ id, ...t }) => t) }]);
  assert.deepEqual(games, [
    ['Albany Volleyball vs Foley', { sport: 'Volleyball', occasion: null, teams: [
      { name: 'albany', short: 'albany', logo: null, color: null, local: false, colors: null, nickname: null },
      { name: 'foley', short: 'foley', logo: null, color: null, local: false, colors: null, nickname: null }], final: null }],
    ['Fall fair', null],
    ['SJU Football vs Concordia: Homecoming', { sport: 'Football', occasion: 'Homecoming', teams: [
      { name: "Saint John's", short: "Saint John's", logo: 'https://x/sju.png', color: '#C20430', local: false, colors: null, nickname: null },
      { name: 'Concordia', short: 'Concordia', logo: null, color: null, local: false, colors: null, nickname: null }], final: null }]]);
});

test("a game's final rides its game, host first, and keeps its card a day past the game", async () => {
  await reset();
  const game = await add('Sartell Girls Soccer vs Sauk Rapids-Rice', '2026-10-06', { start_time: '5 PM' });
  await add('Fall fair', '2026-10-07');
  await db.query(`update public.club_events set sport = 'Girls Soccer', team_ids = array['sartell', 'sauk-rapids-rice']
    where id = $1`, [game]);
  const at = async (t) => (await db.query(`select title, game, leaves_at, reason, reason_name
    from public.get_town_feed(($1::timestamp at time zone 'America/Chicago')) order by title`, [t])).rows;
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
  await db.query(`insert into public.sources (entry_id, url, name) values
      ('st-joe-rod-gun-club', 'https://stjoerodandgunclub.org/events/?ical=1', 'St Joe Rod and Gun Club'),
      ('cidery', 'https://cidery.example/events', 'Milk & Honey Ciders')`);
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
    from public.get_town_feed(('2026-10-08 12:00'::timestamp at time zone 'America/Chicago'))
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
  `select title, rsvpd from public.get_event_of_the_day(($1::timestamp at time zone 'America/Chicago'))`, [at])).rows;
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
     from public.get_town_feed(($1::timestamp at time zone 'America/Chicago'), true)`, [at]);
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

test('road alerts, unpublished news and news with no post to open stay out', async () => {
  await reset();
  await news('I-94 crash', '2026-10-08 17:00', { category: 'road', source_name: 'Minnesota 511' });
  await news('Still being checked', '2026-10-08 17:00', { status: 'staging' });
  await news('No link', '2026-10-08 17:00', { source_url: ' ' });
  await news('Taco Tuesday', '2026-10-08 17:00', { source_name: 'Neighbors Route 75' });
  await db.exec('set role anon');
  assert.deepEqual(await newsTitles('2026-10-08 18:00'), ['Taco Tuesday']);
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

test('a news item shows its place\'s logo before its photo', async () => {
  await reset();
  await db.exec(`delete from public.place_photos; delete from public.places;
    insert into public.place_photos (entry_id, url, source_url, position, kind, status, width, height) values
      ('cow-wandering', 'https://x/cow-photo.webp', 'https://cow', 0, 'photo', 'live', 800, 600);
    insert into public.places (name, entry_id, search_logo) values
      ('The Wandering Cow', 'cow-wandering', '{"url": "https://x/cow-logo.webp", "hue": 19}');`);
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
    insert into public.places (name, entry_id, search_logo) values
      ('The Wandering Cow', 'cow-wandering', '{"url": "https://x/cow-logo.webp", "hue": 19}');
    insert into public.sources (entry_id, url, name) values ('cow-wandering', 'https://cow/events', 'The Wandering Cow');`);
  await add('Sundae Social', '2026-10-09', { start_time: '6 PM', source_name: 'The Wandering Cow' });
  await add('Bake sale', '2026-10-09', { start_time: '7 PM', source_name: 'Nobody Known' });
  await db.exec('set role anon');
  const { rows } = await db.query(`select title, host_picture
     from public.get_town_feed(('2026-10-08 18:00'::timestamp at time zone 'America/Chicago'))`);
  const by = Object.fromEntries(rows.map((r) => [r.title, r.host_picture]));
  assert.deepEqual(by['Sundae Social'], { url: 'https://x/cow-logo.webp', kind: 'logo', hue: 19 },
    'sources has no read rule for neighbours, and the logo still shows');
  assert.equal(by['Bake sale'], null, 'no known host: the app shows its first letter');
  // A host the registry names differently (host-names): its entry, by the name the card shows.
  await db.exec(`reset role; insert into public.host_entries (name, entry_id) values ('Nobody Known', 'cow-wandering')`);
  await db.exec('set role anon');
  const again = await db.query(`select title, host_picture
     from public.get_town_feed(('2026-10-08 18:00'::timestamp at time zone 'America/Chicago'))`);
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

test("Not interested lowers its host's and its main interest's other Events × 0.3, back to × 1 by day 90", async () => {
  await reset();
  const fair = await add('Craft fair', '2026-10-09', { start_time: '10 AM', source_name: 'Parks', category: 'arts' });
  await add('Zoo day', '2026-10-09', { start_time: '11 AM', source_name: 'Parks', category: 'outdoors' });
  await add('Gallery night', '2026-10-09', { start_time: '6 PM', source_name: 'Gallery', category: 'arts' });
  await add('Bingo', '2026-10-09', { start_time: '7 PM', source_name: "Sal's", category: 'games' });
  // Arts is only its second interest: a shared tag that isn't the main one lowers nothing (Jesse,
  // 2026-10-22: a broad tag would dim much of the feed).
  const quilts = await add('Quilt show', '2026-10-09', { start_time: '1 PM', source_name: 'Church' });
  await db.query(`update public.club_events set interests = '{community,arts}', interests_tagged_at = now() where id = $1`, [quilts]);
  await notInterested(fair, YOU, '2026-10-08 12:00');
  const x = async (at) => {
    await signIn(YOU);
    await db.exec(`set test.admin = 'on'`);
    return Object.fromEntries((await feed(at)).map((r) => [r.title, r.score.notInterested]));
  };
  assert.deepEqual(await x('2026-10-08 12:00'), { 'Zoo day': 0.3, 'Gallery night': 0.3, Bingo: 1, 'Quilt show': 1 });
  // Halfway through the 90 days: halfway back.
  await db.exec(`reset role; update public.feed_actions set at = at - interval '45 days'`);
  assert.deepEqual(await x('2026-10-08 12:00'), { 'Zoo day': 0.65, 'Gallery night': 0.65, Bingo: 1, 'Quilt show': 1 });
  await db.exec(`reset role; update public.feed_actions set at = at - interval '46 days'`);
  assert.deepEqual(await x('2026-10-08 12:00'), { 'Zoo day': 1, 'Gallery night': 1, Bingo: 1, 'Quilt show': 1 });
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
  await db.exec(`set test.admin = 'on'`);
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
  const { rows: [{ id: club }] } = await db.query(`insert into public.clubs (name) values ('Rod and Gun Club') returning id`);
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
    insert into public.places (name, entry_id, adults_only) values ('The Middy', 'middy', true),
      ('Sal''s Bar & Grill', 'bar-grill-sals', false);`);
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
