// Stories for the morning writer's database half (supabase/migrations/*_apply_judged*.sql), run
// in PGlite: a found event its schedule dropped is marked cancelled, never deleted, and comes
// back when its source lists it again (BP app docs/plans/watch-every-place, ticket 11); its
// title stays as written, since the app shows the Canceled tag (ticket 12). Run:
// `npm install && npm test` in this folder. The tables are the subset the functions write.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { PGlite } from '@electric-sql/pglite';
import { creating } from './migrations.mjs';

const migration = (f) => readFileSync(new URL(`../migrations/${f}`, import.meta.url), 'utf8');

test('the story below loads every migration that makes the writer\'s functions', () => {
  // A new one fails here until the story applies it, rather than testing the old functions.
  assert.deepEqual(creating(new URL('../migrations', import.meta.url).pathname,
                            ['public.apply_judged', 'public.listed_for_writer']),
                   ['20261015120000_apply_judged.sql', '20261015200100_apply_judged_cancelled.sql',
                    '20261016090200_apply_judged_title_kept.sql', '20261016160000_event_places.sql',
                    '20261020120000_game_card.sql', '20261023003100_town_news_writer.sql']);
});

test('a dropped game is marked cancelled once, and restored by a re-read or another mention', async () => {
  const db = await PGlite.create();
  await db.exec(`create role anon; create role authenticated; create role service_role;
    create table public.club_events (id uuid primary key default gen_random_uuid(), club_id uuid, submitted_by uuid,
      status text not null default 'pending', title text not null, event_date date, start_time text, location text,
      description text, kind text not null default 'event', category text, end_at timestamptz, all_day boolean not null default false,
      source_name text, source_url text, source_uid text, shows_from date, review_reason text,
      constraint club_events_source_uid_key unique (source_name, source_uid));
    create table public.event_mentions (event_id uuid not null, source_name text not null, source_url text not null,
      source_uid text, trust text not null, sure boolean not null, first_seen timestamptz default now(),
      last_seen timestamptz default now(), primary key (event_id, source_name, source_url));
    create table public.board_items (id uuid primary key default gen_random_uuid(), title text, blurb text, category text,
      source_name text, source_url text, tier numeric, status text, starts_at timestamptz, published_at timestamptz,
      fetched_at timestamptz);
    create unique index on public.board_items (lower(title), source_name, coalesce(starts_at, '-infinity'::timestamptz));`);
  await db.exec(migration('20261015120000_apply_judged.sql'));
  await db.exec('alter table public.club_events add column if not exists cancelled_at timestamptz;');
  await db.exec(migration('20261015200100_apply_judged_cancelled.sql'));
  // Titles marked before ticket 12 lose "Cancelled: "; a title someone wrote that way stays.
  await db.exec(`insert into public.club_events (title, cancelled_at, source_name, source_uid) values
    ('Cancelled: Apollo Football vs Tech', now(), 'Apollo High School', 'x1');
    insert into public.club_events (title, cancelled_at, submitted_by) values
    ('Cancelled: the knitting circle''s own wording', now(), gen_random_uuid());`);
  await db.exec(migration('20261016090200_apply_judged_title_kept.sql'));
  assert.deepEqual((await db.query('select title from public.club_events order by title')).rows.map((r) => r.title),
                   ['Apollo Football vs Tech', "Cancelled: the knitting circle's own wording"]);
  await db.exec('delete from public.club_events');

  const game = (day) => [{ status: 'approved', title: 'Sartell Volleyball vs ROCORI', event_date: day,
    start_time: '7 PM', end_at: null, all_day: false, location: 'ROCORI High School, Cold Spring',
    description: null, source_name: 'ROCORI High School', source_url: 'u',
    source_uid: 'mshsl:153:rocori|sartell:1', category: 'sports_leagues', shows_from: '2026-10-06' }];
  const apply = async (...lists) => (await db.query(
    `select public.apply_judged(${lists.map((_, i) => `$${i + 1}`).join(', ')}) as r`,
    lists.map((l) => JSON.stringify(l)))).rows[0].r;
  const row = async () => (await db.query(
    `select title, event_date::text as day, cancelled_at is not null as off from public.club_events`)).rows;

  // A call with the four lists it always took still works.
  assert.equal((await apply(game('2026-10-20'), [], [], [])).events, 1);
  const { rows: [{ id }] } = await db.query('select id from public.club_events');
  assert.equal((await apply([], [], [], [], [id], [])).cancelled, 1);
  assert.deepEqual(await row(), [{ title: 'Sartell Volleyball vs ROCORI', day: '2026-10-20', off: true }]);
  assert.equal((await apply([], [], [], [], [id], [])).cancelled, 0, 'marked once');
  // Its own source lists it again, a day later: the re-read restores and moves it.
  await apply(game('2026-10-21'), [], [], [], [], []);
  assert.deepEqual(await row(), [{ title: 'Sartell Volleyball vs ROCORI', day: '2026-10-21', off: false }]);
  // Back on through another school's mention.
  await apply([], [], [], [], [id], []);
  assert.equal((await apply([], [], [], [], [], [id])).restored, 1);
  assert.deepEqual(await row(), [{ title: 'Sartell Volleyball vs ROCORI', day: '2026-10-21', off: false }]);

  // Every found event knows the place it is at (Jesse, 2026-10-16), and a writer from before
  // place_entry_id, re-reading it, leaves the place alone.
  await db.exec('create table public.places (id uuid primary key default gen_random_uuid(), name text);');
  await db.exec(migration('20261016160000_event_places.sql'));
  const placed = (day) => game(day).map((g) => ({ ...g, place_entry_id: 'rocori-high-school' }));
  await apply(placed('2026-10-21'), [], [], []);
  const place = async () => (await db.query('select place_entry_id as p from public.club_events')).rows[0].p;
  assert.equal(await place(), 'rocori-high-school');
  await apply(game('2026-10-21'), [], [], []);
  assert.equal(await place(), 'rocori-high-school', 'an older writer keeps the place');

  // A game names its sport and two teams (game-card 01): a team it hasn't seen gets its row, no
  // logo or color yet, and one already there keeps its own; a re-read without the game clears it.
  await db.exec('create schema if not exists private;');
  await db.exec(migration('20261020120000_game_card.sql'));
  await db.exec(`insert into public.teams (id, name, short_name, color) values ('sartell', 'Sartell', 'Sartell', '#1A4C9C')`);
  const teamed = (day) => placed(day).map((g) => ({ ...g, sport: 'Volleyball', team_ids: ['rocori', 'sartell'],
    team_names: ['ROCORI', 'Sartell'], occasion: 'Senior Night' }));
  await apply(teamed('2026-10-21'), [], [], []);
  assert.deepEqual((await db.query(`select sport, team_ids, occasion from public.club_events`)).rows,
                   [{ sport: 'Volleyball', team_ids: ['rocori', 'sartell'], occasion: 'Senior Night' }]);
  assert.deepEqual((await db.query(`select id, name, short_name, color from public.teams order by id`)).rows,
                   [{ id: 'rocori', name: 'ROCORI', short_name: 'ROCORI', color: null },
                    { id: 'sartell', name: 'Sartell', short_name: 'Sartell', color: '#1A4C9C' }]);
  await apply(placed('2026-10-21'), [], [], []);
  assert.deepEqual((await db.query(`select sport, team_ids, occasion from public.club_events`)).rows,
                   [{ sport: null, team_ids: null, occasion: null }], 'a game read wrong once clears');
  await assert.rejects(db.exec(`update public.club_events set team_ids = array['a']`), /team_ids_pair/);

  // News carries its interests and the place that posted it (town-feed 35); a re-read keeps the
  // interests it had and takes the place again, and a writer from before them changes neither.
  await db.exec(migration('20261023003100_town_news_writer.sql'));
  const special = (more = {}) => [{ title: 'Flight Friday', blurb: 'Four scoops for $5 on Fridays.', category: 'business',
    source_name: 'The Wandering Cow', source_url: 'https://www.instagram.com/p/x/', tier: 1, status: 'published',
    starts_at: null, ...more }];
  const stored = async () => (await db.query(
    `select interests, place_entry_id as place, status from public.board_items where title = 'Flight Friday'`)).rows;
  assert.equal((await apply([], [], [], special({ interests: ['dining'], place_entry_id: 'cow-wandering' }))).news, 1);
  assert.deepEqual(await stored(), [{ interests: ['dining'], place: 'cow-wandering', status: 'published' }]);
  await apply([], [], [], special({ interests: ['coffee'], place_entry_id: 'cow-wandering' }));
  await apply([], [], [], special());
  assert.deepEqual(await stored(), [{ interests: ['dining'], place: 'cow-wandering', status: 'published' }]);

  const { rows: [{ n }] } = await db.query(`select count(*)::int as n from pg_proc where proname = 'apply_judged'`);
  assert.equal(n, 1, 'one apply_judged, no second one with four lists');
  assert.ok('cancelled_at' in (await db.query('select public.listed_for_writer() as l')).rows[0].l[0]);
});
