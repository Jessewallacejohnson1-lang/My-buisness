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
                    '20261020120000_game_card.sql', '20261023003100_town_news_writer.sql',
                    '20261024090000_keep_longer_description.sql', '20261025090000_keep_place_on_reread.sql',
                    '20261026132256_apply_judged_followers_only.sql', '20261026135926_apply_judged_keeps_public.sql',
                    '20261029151242_apply_judged_says_what_it_did.sql']);
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
    source_uid: 'mshsl:153:rocori|sartell:1', category: 'watch_sports', shows_from: '2026-10-06' }];
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

  // A re-read keeps a fuller About researched by hand (Jesse, 2026-10-23), and takes a longer one.
  await db.exec(migration('20261024090000_keep_longer_description.sql'));
  const about = async () => (await db.query('select description as d from public.club_events')).rows[0].d;
  await db.exec(`update public.club_events set description = 'Senior night: the Storm honors its seniors before the game.'`);
  await apply(placed('2026-10-21'), [], [], []);
  assert.equal(await about(), 'Senior night: the Storm honors its seniors before the game.', 'an empty re-read keeps it');
  const longer = 'Senior night: the Storm honors its seniors before the game, then hosts Sartell in a Central Lakes match.';
  await apply(placed('2026-10-21').map((g) => ({ ...g, description: longer })), [], [], []);
  assert.equal(await about(), longer, 'a longer one replaces it');

  // A re-read with no place keeps the one it had (Sal's, 2026-10-25); a new place still moves it.
  await db.exec(migration('20261025090000_keep_place_on_reread.sql'));
  const where = async () => (await db.query('select location as l from public.club_events')).rows[0].l;
  await apply(placed('2026-10-21').map((g) => ({ ...g, location: null })), [], [], []);
  assert.equal(await where(), 'ROCORI High School, Cold Spring', 'an empty place keeps the old one');
  await apply(placed('2026-10-21').map((g) => ({ ...g, location: '' })), [], [], []);
  assert.equal(await where(), 'ROCORI High School, Cold Spring', 'a blank place keeps it too');
  await apply(placed('2026-10-21').map((g) => ({ ...g, location: 'Sartell High School' })), [], [], []);
  assert.equal(await where(), 'Sartell High School', 'a new place moves it');

  // A Bound Event for followers only, with its school and activity (school-activities 03); a writer
  // from before them makes it everyone's.
  await db.exec(`alter table public.club_events add column followers_only boolean not null default false,
    add column activity_team text, add column activity_name text`);
  await db.exec(migration('20261026132256_apply_judged_followers_only.sql'));
  const marks = async () => (await db.query(
    'select followers_only as f, activity_team as team, activity_name as name from public.club_events')).rows;
  await apply(placed('2026-10-21').map((g) => ({ ...g, followers_only: true, activity_team: 'rocori',
                                                activity_name: 'Volleyball, Girls' })), [], [], []);
  assert.deepEqual(await marks(), [{ f: true, team: 'rocori', name: 'Volleyball, Girls' }]);
  await apply(placed('2026-10-21'), [], [], []);
  assert.deepEqual(await marks(), [{ f: false, team: null, name: null }]);

  // Listed by a public page, it stays everyone's when Bound alone reads it again, and a re-read naming
  // no activity keeps the one it had.
  await db.exec(migration('20261026135926_apply_judged_keeps_public.sql'));
  const bound = placed('2026-10-21').map((g) => ({ ...g, followers_only: true, activity_team: 'rocori',
                                                  activity_name: 'Volleyball, Girls' }));
  await apply(bound, [], [], []);
  assert.deepEqual(await marks(), [{ f: false, team: 'rocori', name: 'Volleyball, Girls' }]);
  await apply(placed('2026-10-21'), [], [], []);
  assert.deepEqual(await marks(), [{ f: false, team: 'rocori', name: 'Volleyball, Girls' }]);

  // The save says which items it added, by their place in its lists (smooth-mornings 05): every other Event
  // was merged into one already listed, every other News a repeat. Its counts stay as they were. One News is
  // one link: the same post again under a reworded title is a repeat, and left as it is.
  await db.exec(migration('20261029151242_apply_judged_says_what_it_did.sql'));
  const hayride = placed('2026-10-22').map((g) => ({ ...g, title: 'Haunted Hayride', source_uid: 'hay:1' }));
  const post = { blurb: 'Boo baskets are back.', category: 'business', source_name: 'White Peony Boutique',
    source_url: 'https://www.instagram.com/p/DeBoo/', tier: 1, status: 'published', starts_at: null, own_link: true };
  const first = await apply([...hayride, ...placed('2026-10-21')], [], [], [{ ...post, title: 'Boo baskets for Halloween' }]);
  assert.deepEqual([first.events, first.news, first.added], [2, 1, { events: [0], news: [0] }]);
  const again = await apply(hayride, [], [], [{ ...post, title: 'Halloween boo baskets are back' }]);
  assert.deepEqual([again.events, again.news, again.added], [1, 0, { events: [], news: [] }]);
  const titles = async (source) => (await db.query(
    'select title from public.board_items where source_name = $1 order by title', [source])).rows.map((r) => r.title);
  assert.deepEqual(await titles('White Peony Boutique'), ['Boo baskets for Halloween'], 'the repeat is left out');
  // A home page (or a writer from before this, which says nothing of the link) is no link of its own:
  // two News sharing it are two, and the title rule still finds a re-read. One post twice in one call is one.
  const page = { ...post, source_name: 'Stearns County', source_url: 'https://www.stearnscountymn.gov/', own_link: false };
  const cow = { ...post, source_name: 'The Wandering Cow', source_url: 'https://www.instagram.com/p/DeCow/' };
  assert.deepEqual((await apply([], [], [], [{ ...page, title: 'Early Voting' }, { ...page, title: 'County Road 134 closed' },
    { ...cow, title: 'Pumpkin pie is the flavor' }, { ...cow, title: 'Flavor of the week: pumpkin pie' }])).added.news,
  [0, 1, 2]);
  const reread = await apply([], [], [], [{ ...page, title: 'early voting' }]);
  assert.deepEqual([reread.news, reread.added.news], [1, []], 'a re-read by title is written, not added');
  assert.deepEqual(await titles('Stearns County'), ['County Road 134 closed', 'Early Voting']);
  assert.deepEqual(await titles('The Wandering Cow'), ['Flight Friday', 'Pumpkin pie is the flavor']);
  assert.deepEqual((await apply([], [], [], [])), { events: 0, news: 0, mentions: 0, published_by_mention: 0,
                                                     cancelled: 0, restored: 0, added: { events: [], news: [] } });

  const { rows: [{ n }] } = await db.query(`select count(*)::int as n from pg_proc where proname = 'apply_judged'`);
  assert.equal(n, 1, 'one apply_judged, no second one with four lists');
  // The writer's list runs from yesterday on, and the game above has a fixed date: today it is.
  await db.exec('update public.club_events set event_date = current_date');
  assert.ok('cancelled_at' in (await db.query('select public.listed_for_writer() as l')).rows[0].l[0]);
});
