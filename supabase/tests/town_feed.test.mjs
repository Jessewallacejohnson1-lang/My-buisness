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
  'private.event_game', 'public.get_event_of_the_day', 'private.entry_picture', 'private.host_picture',
  'private.sidearm_live', 'public.record_live_score', 'private.sidearm_scoring', 'public.activity_has_event',
  'public.meeting_board', 'public.event_picture', 'private.event_subject', 'private.season_of', 'private.christmas_time', 'private.event_gender', 'private.christmas_fit']);
// Friends (ticket 28) read the Friends builds' rule for who may be shown, as it is now.
const findable = readdirSync(migrations).filter((f) => f.endsWith('_unfriend_and_block.sql'))
  .map((f) => readFileSync(join(migrations, f), 'utf8'))[0]
  .match(/create or replace function private\.findable\(p_user uuid\)[\s\S]*?\$\$;/)[0];
// (Views, ticket 20: the table, its summary and the clean-up load with town_feed_views; the
// pg_cron jobs in feed_jobs don't, since PGlite has no pg_cron.)

const db = await PGlite.create();
await db.exec(`
  set timezone = 'UTC';
  create role anon; create role authenticated; create role service_role;
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
    sport text, team_ids text[], occasion text, source_url text);
  -- The schools a game card names (game-card 01, 20261020120000_game_card.sql).
  create table public.teams (id text primary key, name text not null, short_name text not null,
    logo_url text, color text, uuid uuid not null default gen_random_uuid(), colors text[],
    local boolean not null default false, nickname text, school_name text);
  -- The schools whose activities can be followed (school-activities 01 and 02), for the activities'
  -- migration to name; the stories add the teams they need, as reset() empties the table.
  insert into public.teams (id, name, short_name, local) values
    ('apollo', 'Apollo', 'Apollo', true), ('tech', 'Tech', 'Tech', true), ('cathedral', 'Cathedral', 'Cathedral', true),
    ('apollo-cathedral', 'Apollo-Cathedral', 'Apollo-Cathedral', true), ('rocori', 'ROCORI', 'ROCORI', true),
    ('sartell', 'Sartell', 'Sartell', true), ('sauk-rapids-rice', 'Sauk Rapids-Rice', 'Sauk Rapids-Rice', true),
    ('saint-benedict', 'Saint Benedict', 'Saint Benedict', true), ('saint-johns', 'Saint John''s', 'Saint John''s', true);
  create table public.town_follows (id uuid primary key default gen_random_uuid(), follower_id uuid not null,
    target_type text not null, target_id uuid not null, unique (follower_id, target_type, target_id));
  -- The Town's pages (follows 04, 20261027143913_city_pages.sql), as live: Joetown and the City.
  create table public.town_pages (id uuid primary key default gen_random_uuid(), town text not null,
    slug text not null, name text not null, kind text not null, source_name text not null, picture text,
    picture_kind text, unique (town, slug));
  insert into public.town_pages (town, slug, name, kind, source_name, picture_kind) values
    ('st-joseph-mn', 'town', 'Joetown', 'St. Joseph''s events', 'JoeTown', 'town'),
    ('st-joseph-mn', 'city', 'City of St. Joseph', 'City government', 'City of St. Joseph', null);
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
// The stories empty teams between them; the activities stay, matched by their ids.
await db.exec(`alter table public.team_activities drop constraint team_activities_team_id_fkey,
                 drop constraint team_activities_fielded_by_fkey`);

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
                 delete from public.board_items; delete from public.feed_mutes; delete from public.town_follows;
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
  await db.exec(`set test.admin = 'on'`);
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
  await tap('event_likes', parade, OTHER, '2026-08-01 12:00');
  await tap('event_likes', spring, YOU, '2026-06-20 14:00');
  const tapped = async () => {
    await signIn(YOU);
    await db.exec(`set test.admin = 'on'`);
    return (await feed('2026-10-08 12:00')).find((r) => r.title === 'Zoo day').score.tapped;
  };
  assert.equal(await tapped(), 0, "a neighbour's heart and 110 days back don't count");
  for (const t of ['event_rsvps', 'event_saves', 'event_likes']) await tap(t, market, YOU, '2026-07-25 09:00');
  assert.equal(await tapped(), 3, '75 days back counts');
  await tap('event_likes', parade, YOU, '2026-08-01 12:00');
  assert.equal(await tapped(), 3, 'a second Event of its host adds nothing');
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
  await db.exec(`set test.admin = 'on'`);
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
  await add('Posted since', '2026-10-09', { start_time: '6 PM', source_name: 'B', created_at: '2026-10-07 12:00-05' });
  const past = await add('Old craft fair', '2026-10-01', { start_time: '10 AM', source_name: 'C' });
  await add('Yours', '2026-10-09', { start_time: '7 PM', source_name: 'C' });
  await tap('event_likes', past, YOU, '2026-10-01 12:00');
  // A first open: no last visit, so nothing is New.
  await signIn(YOU);
  await db.exec(`set test.admin = 'on'`);
  assert.ok((await feed('2026-10-08 12:00')).every((r) => r.reason !== 'new'));
  // You last looked on the 6th.
  await viewed(old, YOU, '2026-10-06 09:00');
  await signIn(YOU);
  await db.exec(`set test.admin = 'on'`);
  const rows = await feed('2026-10-08 12:00');
  assert.deepEqual(rows.map((r) => [r.title, r.reason, r.score.new]),
                   [['Yours', 'tapped', 0], ['Posted since', 'new', 2], ['Old', 'tomorrow', 0]]);
  assert.equal(rows[1].score.newSpot, true);
});

test('New ends once you have seen it, and a view in the last 30 minutes is not a last visit', async () => {
  await reset();
  const old = await add('Old', '2026-10-09', { start_time: '10 AM', source_name: 'A' });
  const fresh = await add('Posted since', '2026-10-09', { start_time: '6 PM', source_name: 'B', created_at: '2026-10-07 12:00-05' });
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
                                           created_at: '2026-10-07 12:00-05' });
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
  await add('Posted since', '2026-10-09', { start_time: '6 PM', source_name: 'B', created_at: '2026-10-07 12:00-05' });
  await viewed(old, ME, '2026-10-06 09:00');
  await signIn(YOU);
  assert.ok((await feed('2026-10-08 12:00')).every((r) => r.reason !== 'new'));
  await db.exec(`reset role; set role anon; reset request.jwt.claim.sub`);
  assert.deepEqual((await db.query('select * from private.my_views()')).rows, [], 'signed out reads no views');
});

test('the score breakdown is filled for the admin and null for everyone else', async () => {
  await reset();
  await add('Bake sale', '2026-10-09', { start_time: '12 PM', category: 'dining' });
  await signIn(YOU, ['dining']);
  assert.equal((await feed('2026-10-08 12:00'))[0].score, null);
  await db.exec(`set test.admin = 'on'`);
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
  await db.exec(`set test.admin = 'on'`);
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
    insert into public.places (name, entry_id) select 'Place ' || g, 'speed-place-' || g from generate_series(1, 5) g;
    insert into public.town_follows (follower_id, target_type, target_id)
    select '00000000-0000-0000-0001-000000000042', 'place', id from public.places where entry_id like 'speed-place-%';
    update public.club_events set place_entry_id = 'speed-place-' || (split_part(title, ' ', 2)::int / 5 % 5 + 1)
    where split_part(title, ' ', 2)::int % 5 = 0;
    insert into public.clubs (name) select 'Group ' || g from generate_series(1, 3) g;
    insert into public.club_members (club_id, user_id)
    select id, '00000000-0000-0000-0001-000000000042' from public.clubs where name like 'Group %';
    update public.club_events e set club_id = c.id
    from (select id, row_number() over (order by id) n from public.clubs where name like 'Group %') c
    where split_part(e.title, ' ', 2)::int % 7 = 0 and split_part(e.title, ' ', 2)::int / 7 % 3 + 1 = c.n;
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

test("an event card shows its place's photo of what the event is, in season, taking turns (event-photos 07)", async () => {
  await reset();
  await db.exec(`delete from public.place_photos; delete from public.places;
    insert into public.place_photos (entry_id, url, source_url, position, kind, status, width, height, subjects, seasons, description) values
      ('arena', 'https://x/cover.webp', 'https://arena.org/', 0, 'photo', 'live', 1600, 1067, '{}', '{}', null),
      ('arena', 'https://x/hockey-a.webp', 'https://arena.org/g', 1, 'scene', 'live', 1600, 1067, '{hockey}', '{}', 'Hockey game in play'),
      ('arena', 'https://x/hockey-b.webp', 'https://arena.org/g', 2, 'scene', 'live', 1600, 1067, '{hockey}', '{}', 'Fans cheering a goal'),
      ('arena', 'https://x/hockey-snow.webp', 'https://arena.org/g', 3, 'scene', 'live', 1600, 1067, '{hockey}', '{winter}', 'Pond hockey in the snow'),
      ('arena', 'https://x/hoops-fall.webp', 'https://arena.org/g', 4, 'scene', 'live', 1600, 1067, '{basketball}', '{fall}', 'Game in the fall'),
      ('arena', 'https://x/hockey-gone.webp', 'https://arena.org/g', 0, 'scene', 'retired', 1600, 1067, '{hockey}', '{}', 'Taken down');`);
  const subject = async (t, s, c) => (await db.query('select private.event_subject($1, $2, $3) as s', [t, s, c])).rows[0].s;
  assert.equal(await subject('Sauna, Yoga, Ice Bath, Cider', null, 'health'), 'sauna', 'the same list as scenes.py');
  assert.equal(await subject('Cathedral vs Foley · JV', 'Boys Basketball', 'watch_sports'), 'basketball');
  assert.equal(await subject('The Nolan Lecture', null, 'faith'), 'talk');
  assert.equal(await subject('Central Lakes Jazz Festival', null, 'live_music'), 'band');
  assert.equal(await subject('Organic Gardening Workshop', null, null), 'talk', 'organic is no organ: \\y is a word edge');
  assert.equal(await subject('7th Grade', null, 'watch_sports'), 'sports');
  assert.equal(await subject('Fall Picture Retakes', null, null), 'place');
  const season = async (d) => (await db.query('select private.season_of($1::date) as s', [d])).rows[0].s;
  assert.deepEqual([await season('2026-11-30'), await season('2026-12-01'), await season('2027-02-28')], ['fall', 'winter', 'winter']);

  const add = async (title, date, sport = null) => (await db.query(
    `insert into public.club_events (title, event_date, sport, category, source_name, place_entry_id)
     values ($1, $2, $3, 'watch_sports', 'Arena', 'arena') returning id`, [title, date, sport])).rows[0].id;
  const pic = async (id) => (await db.query('select public.event_picture($1) as p', [id])).rows[0].p;
  const winter = await pic(await add('Hockey vs Foley', '2026-12-10', 'Boys Hockey'));
  assert.equal(winter.url, 'https://x/hockey-snow.webp', "a photo made for the event's season before one for any");
  assert.equal(winter.credit, null);
  assert.equal(winter.site, 'https://arena.org/g', 'credited to its page like a place photo');
  assert.deepEqual(winter.more.map((m) => m.url), ['https://x/cover.webp'], "the Event page's more: the place's photos, no scenes");
  const fall = [];
  for (const d of ['2026-11-02', '2026-11-03', '2026-11-04', '2026-11-05', '2026-11-06', '2026-11-07', '2026-11-08', '2026-11-09'])
    fall.push((await pic(await add(`Hockey vs ${d}`, d))).url);
  assert.deepEqual([...new Set(fall)].sort(), ['https://x/hockey-a.webp', 'https://x/hockey-b.webp'],
                   'out of season the any-season photos take turns, never the snow one nor a retired one');
  assert.equal((await pic(await add('Hoops vs Albany', '2026-12-12', 'Girls Basketball'))).url, 'https://x/cover.webp',
               'a fall photo never shows in winter: the place picture instead');
  assert.equal((await pic(await add('Fall Picture Retakes', '2026-11-02'))).url, 'https://x/cover.webp', 'no subject: the place picture');
  assert.equal((await db.query("select public.place_picture('arena') as p")).rows[0].p.url, 'https://x/cover.webp',
               'a scene is never the place cover');
  assert.equal(await pic('00000000-0000-0000-0000-000000000000'), null);

  await db.exec(`delete from public.club_events;
                  insert into public.club_events (title, event_date, sport, category, source_name, place_entry_id, created_at)
                  values ('Hockey vs Sartell', '2026-10-09', 'Boys Hockey', 'watch_sports', 'Arena', 'arena', '2026-09-01 12:00-05')`);
  await db.exec('set role anon');
  const { rows } = await db.query(`select title, place_picture
    from public.get_town_feed(('2026-10-08 12:00'::timestamp at time zone 'America/Chicago'))`);
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
    `insert into public.club_events (title, event_date, category, source_name, place_entry_id, created_at)
     values ($1, '2026-10-09', 'art_theater', 'Saint John''s Prep', 'prep', '2026-09-01 12:00-05') returning id`, [title])).rows[0].id;
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
    from public.get_town_feed(('2026-10-08 12:00'::timestamp at time zone 'America/Chicago')) order by title`);
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

test('a Christmas photo shows on a holiday event from November 1, on any from December 1 to January 6 (event-photos 07)', async () => {
  await reset();
  await db.exec(`delete from public.place_photos;
    insert into public.place_photos (entry_id, url, source_url, position, kind, status, subjects, seasons) values
      ('shop', 'https://x/cover.webp', 'https://shop.com/', 0, 'photo', 'live', '{}', '{}'),
      ('shop', 'https://x/sweaters.webp', 'https://shop.com/', 1, 'scene', 'live', '{shopping}', '{christmas}'),
      ('shop', 'https://x/racks.webp', 'https://shop.com/', 2, 'scene', 'live', '{shopping}', '{}');`);
  const pic = async (title, date) => (await db.query('select public.event_picture($1) as p', [(await db.query(
    `insert into public.club_events (title, event_date, source_name, place_entry_id) values ($1, $2, 'Shop', 'shop')
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
    `insert into public.club_events (title, event_date, sport, source_name, place_entry_id) values ($1, '2026-12-10', $2, 'Gym', 'gym')
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
    from public.get_town_feed(('2026-10-08 12:00'::timestamp at time zone 'America/Chicago')) order by title`);
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
    from public.get_town_feed(('2026-10-08 12:00'::timestamp at time zone 'America/Chicago')) order by title`);
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

// Live scores (game-card 03): SIDEARM's pushed Game to the card's live score, on the 2026-10-24 test's files.
const sjuLive = JSON.parse(readFileSync(join(here, 'sidearm-live-sju-msoc.json'), 'utf8'));
const sjuFinal = JSON.parse(readFileSync(join(here, 'sidearm-final-sju-msoc.json'), 'utf8'));
const csbOld = JSON.parse(readFileSync(join(here, 'sidearm-old-csb-wvball.json'), 'utf8'));
const sidearmLiveAll = async (game, day, host, file) => (await db.query(
  'select private.sidearm_live($1::jsonb, $2::date, $3, $4) as l', [JSON.stringify(game), day, host, file])).rows[0].l;
// The score, period and clock; the period scores and the host's side have their own checks (game-card 05).
const sidearmLive = async (...args) => {
  const l = await sidearmLiveAll(...args);
  if (!l) return l;
  const { periods, host_home, ...rest } = l;
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
  // The feed sends it in the game and keeps a game being played two more hours: still there at 5:30.
  await db.exec('set role anon');
  const feed = async (t) => (await db.query(`select game from public.get_town_feed(($1::timestamp at time zone 'America/Chicago'))
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
  const [row] = (await db.query(`select game from public.get_town_feed(('2026-10-24 13:30'::timestamp at time zone 'America/Chicago'))
    where game is not null`)).rows;
  await db.exec('reset role');
  assert.equal(row.game.plays.length, 3);
  // Volleyball keeps none: every point carries a score; its sets show instead.
  assert.deepEqual((await db.query(`select private.sidearm_scoring($1::jsonb, true, 'csb/wvball') as s`,
                                   [JSON.stringify(csbOld.LastPlays ?? csbOld.Game?.LastPlays ?? [])])).rows[0].s, []);
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
  await db.exec(`update private.live_listener set until = now() - interval '1 second'`);
  await start();
  assert.ok((await db.query('select until from private.live_listener')).rows[0].until > until, 'free again after it runs out');
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

test("Not interested lowers its host's other Events × 0.3, and nothing else, for as long as it stands", async () => {
  await reset();
  const fair = await add('Craft fair', '2026-10-09', { start_time: '10 AM', source_name: 'Parks', category: 'arts' });
  await add('Zoo day', '2026-10-09', { start_time: '11 AM', source_name: 'Parks', category: 'outdoors' });
  await add('Gallery night', '2026-10-09', { start_time: '6 PM', source_name: 'Gallery', category: 'arts' });
  await add('Bingo', '2026-10-09', { start_time: '7 PM', source_name: "Sal's", category: 'games' });
  await notInterested(fair, YOU, '2026-10-08 12:00');
  const x = async (at) => {
    await signIn(YOU);
    await db.exec(`set test.admin = 'on'`);
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

// Followed activities (school-activities 03): an activity starred on a school's page, or the whole
// school, lifts its Events and says so; a followers-only Event reaches only them.
async function follow(who, type, team, activity) {
  await db.exec('reset role');
  const id = activity
    ? (await db.query(`select id from public.team_activities where team_id = $1 and name = $2`, [team, activity])).rows[0].id
    : (await db.query(`select uuid from public.teams where id = $1`, [team])).rows[0].uuid;
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
  await db.exec(`set test.admin = 'on'`);
  const rows = await feed('2026-10-08 12:00');
  assert.deepEqual(rows.map((r) => [r.title, r.reason, r.reason_name, r.score.follow]), [
    ['Cathedral Volleyball vs Sartell', 'follow', 'Cathedral Volleyball (girls)', 3],
    ['Fall fair', 'tomorrow', null, 0]]);
  await db.exec('reset test.admin');
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
    `select title from public.get_event_of_the_day(('2026-10-09 12:00'::timestamp at time zone 'America/Chicago'))`);
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
  await db.exec(`set test.admin = 'on'`);
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
  await db.exec(`set test.admin = 'on'`);
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
  await db.exec(`set test.admin = 'on'`);
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
    `insert into public.places (name, entry_id) values ($1, $2) returning id`, [name, entry]);
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
     from public.get_town_feed(($1::timestamp at time zone 'America/Chicago'))`, [at]);
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
  await db.exec(`set test.admin = 'on'`);
  const [top, next] = await lifted('2026-10-08 12:00');
  assert.deepEqual([top.title, top.reason, top.reason_name, top.score.follow, top.score.pool],
                   ['Fall open house', 'follow', PEONY, 3, 'yours']);
  assert.deepEqual([next.title, next.reason, next.score.follow], ['Fall fair', 'tomorrow', 0]);
  await db.exec('reset test.admin');
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
  await db.exec(`set test.admin = 'on'`);
  const rows = await lifted('2026-10-08 12:00');
  assert.deepEqual(rows.map((r) => [r.title, r.score.yours, r.score.spacing]), [
    ['Open house 09', 3, 1], ['Open house 10', 3, 0.5], ['Open house 11', 3, 0.25]]);
  await db.exec('reset test.admin');
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
    `insert into public.clubs (name, own_entry_id) values ('Book Club', 'book-club') returning id`);
  await db.query(`insert into public.sources (entry_id, url, name) values ('book-club', 'https://books', 'Book Club site')`);
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
     from public.get_town_feed(('2026-10-08 12:00'::timestamp at time zone 'America/Chicago'))`);
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
  await db.exec(`set test.admin = 'on'`);
  const by = Object.fromEntries((await lifted('2026-10-08 12:00')).map((r) => [r.title, [r.score.yours, r.score.notInterested]]));
  assert.deepEqual(by, { 'Trunk show': [3, 0.3], 'Fall fair': [0, 1] });
  await db.exec('reset test.admin');
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
  const { rows: [{ id: club }] } = await db.query(`insert into public.clubs (name) values ('Book Club') returning id`);
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
  await db.exec(`set test.admin = 'on'`);
  const [row] = await lifted(`${day(0)} 12:00`);
  assert.deepEqual([row.reason, row.score.follow, row.score.friend, row.score.yours, row.friends_going.length],
                   ['follow', 3, 0, 3, 1]);
  await db.exec('reset test.admin; reset role');
  await db.query('delete from auth.users where id = $1', [FRIEND]);
  await noPlaces();
});

// The City, its boards and Joetown (town-feed 27): a page you follow lifts the Events carrying its name, a
// board its meetings; a City meeting (draw 1) reaches only the City's or that board's followers, lower.
async function followPage(who, slug) {
  await db.exec('reset role');
  await db.query(`insert into public.town_follows (follower_id, target_type, target_id)
                  select $1, 'page', id from public.town_pages where slug = $2`, [who, slug]);
}
async function followBoard(who, name) {
  await db.exec('reset role');
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
