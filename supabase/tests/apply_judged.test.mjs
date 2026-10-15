// Stories for the morning writer's database half (supabase/migrations/*_apply_judged*.sql), run
// in PGlite: a found event its schedule dropped is marked cancelled, never deleted, and comes
// back when its source lists it again (BP app docs/plans/watch-every-place, ticket 11). Run:
// `npm install && npm test` in this folder. The tables are the subset the functions write.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { PGlite } from '@electric-sql/pglite';

const migration = (f) => readFileSync(new URL(`../migrations/${f}`, import.meta.url), 'utf8');

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
  assert.deepEqual(await row(), [{ title: 'Cancelled: Sartell Volleyball vs ROCORI', day: '2026-10-20', off: true }]);
  assert.equal((await apply([], [], [], [], [id], [])).cancelled, 0, 'marked once');
  // Its own source lists it again, a day later: the re-read restores and moves it.
  await apply(game('2026-10-21'), [], [], [], [], []);
  assert.deepEqual(await row(), [{ title: 'Sartell Volleyball vs ROCORI', day: '2026-10-21', off: false }]);
  // Back on through another school's mention.
  await apply([], [], [], [], [id], []);
  assert.equal((await apply([], [], [], [], [], [id])).restored, 1);
  assert.deepEqual(await row(), [{ title: 'Sartell Volleyball vs ROCORI', day: '2026-10-21', off: false }]);

  const { rows: [{ n }] } = await db.query(`select count(*)::int as n from pg_proc where proname = 'apply_judged'`);
  assert.equal(n, 1, 'one apply_judged, no second one with four lists');
  assert.ok('cancelled_at' in (await db.query('select public.listed_for_writer() as l')).rows[0].l[0]);
});
