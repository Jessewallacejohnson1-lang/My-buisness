// Stories for the morning writer's database half (supabase/migrations/*_apply_judged*.sql), run
// in PGlite: a found event its schedule dropped is marked cancelled, never deleted, and comes
// back when its source lists it again (BP app docs/plans/watch-every-place, ticket 11); its
// title stays as written, since the app shows the Canceled tag (ticket 12). Run:
// `npm install && npm test` in this folder.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { realDatabase } from './fixture.mjs';

test('a dropped game is marked cancelled once, and restored by a re-read or another mention', async () => {
  const db = await realDatabase();
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
  const placed = (day) => game(day).map((g) => ({ ...g, place_entry_id: 'rocori-high-school' }));
  await apply(placed('2026-10-21'), [], [], []);
  const place = async () => (await db.query('select place_entry_id as p from public.club_events')).rows[0].p;
  assert.equal(await place(), 'rocori-high-school');
  await apply(game('2026-10-21'), [], [], []);
  assert.equal(await place(), 'rocori-high-school', 'an older writer keeps the place');

  // A game names its sport and two teams (game-card 01): a team it hasn't seen gets its row, no
  // logo or color yet, and one already there keeps its own; a re-read without the game clears it.
  await db.exec(`insert into public.teams (id, name, short_name, color) values ('sartell', 'Sartell', 'Sartell', '#1A4C9C')`);
  const teamed = (day) => placed(day).map((g) => ({ ...g, sport: 'Volleyball', team_ids: ['rocori', 'sartell'],
    team_names: ['ROCORI', 'Sartell'], occasion: 'Senior Night' }));
  await apply(teamed('2026-10-21'), [], [], []);
  assert.deepEqual((await db.query(`select sport, team_ids, occasion from public.club_events`)).rows,
                   [{ sport: 'Volleyball', team_ids: ['rocori', 'sartell'], occasion: 'Senior Night' }]);
  assert.deepEqual((await db.query(`select id, name, short_name, color from public.teams where id in ('rocori', 'sartell') order by id`)).rows,
                   [{ id: 'rocori', name: 'ROCORI', short_name: 'ROCORI', color: null },
                    { id: 'sartell', name: 'Sartell', short_name: 'Sartell', color: '#1A4C9C' }]);
  await apply(placed('2026-10-21'), [], [], []);
  assert.deepEqual((await db.query(`select sport, team_ids, occasion from public.club_events`)).rows,
                   [{ sport: null, team_ids: null, occasion: null }], 'a game read wrong once clears');
  await assert.rejects(db.exec(`update public.club_events set team_ids = array['a']`), /team_ids_pair/);

  // News carries its interests and the place that posted it (town-feed 35); a re-read keeps the
  // interests it had and takes the place again, and a writer from before them changes neither.
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
  const about = async () => (await db.query('select description as d from public.club_events')).rows[0].d;
  await db.exec(`update public.club_events set description = 'Senior night: the Storm honors its seniors before the game.'`);
  await apply(placed('2026-10-21'), [], [], []);
  assert.equal(await about(), 'Senior night: the Storm honors its seniors before the game.', 'an empty re-read keeps it');
  const longer = 'Senior night: the Storm honors its seniors before the game, then hosts Sartell in a Central Lakes match.';
  await apply(placed('2026-10-21').map((g) => ({ ...g, description: longer })), [], [], []);
  assert.equal(await about(), longer, 'a longer one replaces it');

  // A re-read with no place keeps the one it had (Sal's, 2026-10-25); a new place still moves it.
  const where = async () => (await db.query('select location as l from public.club_events')).rows[0].l;
  await apply(placed('2026-10-21').map((g) => ({ ...g, location: null })), [], [], []);
  assert.equal(await where(), 'ROCORI High School, Cold Spring', 'an empty place keeps the old one');
  await apply(placed('2026-10-21').map((g) => ({ ...g, location: '' })), [], [], []);
  assert.equal(await where(), 'ROCORI High School, Cold Spring', 'a blank place keeps it too');
  await apply(placed('2026-10-21').map((g) => ({ ...g, location: 'Sartell High School' })), [], [], []);
  assert.equal(await where(), 'Sartell High School', 'a new place moves it');

  // A Bound Event for followers only, with its school and activity (school-activities 03).
  const marks = async (uid = 'mshsl:153:rocori|sartell:1') => (await db.query(
    'select followers_only as f, activity_team as team, activity_name as name from public.club_events where source_uid = $1', [uid])).rows;
  await apply(placed('2026-10-21').map((g) => ({ ...g, title: 'Volleyball banquet', source_uid: 'bound:1', followers_only: true,
                                                activity_team: 'rocori', activity_name: 'Volleyball, Girls' })), [], [], []);
  assert.deepEqual(await marks('bound:1'), [{ f: true, team: 'rocori', name: 'Volleyball, Girls' }]);
  await db.exec(`delete from public.club_events where source_uid = 'bound:1'`);

  // Listed by a public page, it stays everyone's when Bound alone reads it again, and a re-read naming
  // no activity keeps the one it had.
  const bound = placed('2026-10-21').map((g) => ({ ...g, followers_only: true, activity_team: 'rocori',
                                                  activity_name: 'Volleyball, Girls' }));
  await apply(bound, [], [], []);
  assert.deepEqual(await marks(), [{ f: false, team: 'rocori', name: 'Volleyball, Girls' }]);
  await apply(placed('2026-10-21'), [], [], []);
  assert.deepEqual(await marks(), [{ f: false, team: 'rocori', name: 'Volleyball, Girls' }]);

  // The save says which items it added, by their place in its lists (smooth-mornings 05): every other Event
  // was merged into one already listed. Its counts stay as they were.
  const hayride = placed('2026-10-22').map((g) => ({ ...g, title: 'Haunted Hayride', source_uid: 'hay:1' }));
  const post = { blurb: 'Boo baskets are back.', category: 'business', source_name: 'White Peony Boutique',
    source_url: 'https://www.instagram.com/p/DeBoo/', tier: 1, status: 'published', starts_at: null };
  const first = await apply([...hayride, ...placed('2026-10-21')], [], [], [{ ...post, title: 'Boo baskets for Halloween' }]);
  assert.deepEqual([first.events, first.news, first.added], [2, 1, { events: [0], news: [0] }]);

  // The plan decides which News is a repeat, by title and by link (write_judged.repeat_of, codebase-health-2
  // 04), and the save writes what it is sent: the same post under another title is added, and a writer still
  // sending own_link changes nothing. The safety net stays: a title its source already has (any case, the same
  // day) is written over that News, not added, so a slip in the plan can't flood the Town feed.
  const again = await apply(hayride, [], [], [{ ...post, title: 'Halloween boo baskets are back', own_link: true },
    { ...post, title: 'BOO BASKETS FOR HALLOWEEN', blurb: 'One more week.', source_url: 'https://www.instagram.com/p/DeBoo2/' }]);
  assert.deepEqual([again.events, again.news, again.added], [1, 2, { events: [], news: [0] }]);
  assert.deepEqual((await db.query(`select title, blurb from public.board_items
    where source_name = 'White Peony Boutique' order by title`)).rows,
                   [{ title: 'Boo baskets for Halloween', blurb: 'One more week.' },
                    { title: 'Halloween boo baskets are back', blurb: 'Boo baskets are back.' }]);
  assert.deepEqual((await apply([], [], [], [])), { events: 0, news: 0, mentions: 0, published_by_mention: 0,
                                                     cancelled: 0, restored: 0, added: { events: [], news: [] } });

  const { rows: [{ n }] } = await db.query(`select count(*)::int as n from pg_proc where proname = 'apply_judged'`);
  assert.equal(n, 1, 'one apply_judged, no second one with four lists');
  // The writer's list runs from the Town's yesterday on, and the game above has a fixed date: today it is.
  await db.exec(`update public.club_events set event_date = (now() at time zone 'America/Chicago')::date`);
  assert.ok('cancelled_at' in (await db.query('select public.listed_for_writer() as l')).rows[0].l[0]);
});
