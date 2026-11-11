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

  // A new team takes the short name the writer gives it, and one that exists keeps its own (game-card 16).
  await db.exec('alter table public.club_events enable trigger game_waits_for_logos');
  await db.exec(`insert into public.teams (id, name, short_name) values ('kept-team', 'Kept Team', 'Kept')`);
  const named = placed('2030-01-07').map((g) => ({ ...g, source_uid: 'bound:short', sport: 'Boys Basketball · JV',
    team_ids: ['litchfield-dassel-cokato', 'kept-team'], team_names: ['Litchfield-Dassel-Cokato', 'Kept Team'],
    team_shorts: ['Litchfield', 'Kept Team'] }));
  await apply(named, [], [], []);
  assert.deepEqual((await db.query(`select id, name, short_name from public.teams
                                    where id in ('litchfield-dassel-cokato', 'kept-team') order by id`)).rows,
    [{ id: 'kept-team', name: 'Kept Team', short_name: 'Kept' },
     { id: 'litchfield-dassel-cokato', name: 'Litchfield-Dassel-Cokato', short_name: 'Litchfield' }]);
  // It waits until both teams have logos, whatever writes it, then shows; a taken-down logo sends it back (Jesse, 2026-11-05).
  const status = async () => (await db.query(`select status from public.club_events where source_uid = 'bound:short'`)).rows[0].status;
  assert.equal(await status(), 'waiting_logo', 'a new team has no logo');
  await apply(named, [], [], []);
  assert.equal(await status(), 'waiting_logo', 'a re-read keeps it waiting');
  await db.exec(`update public.teams set logo_url = 'l' where id = 'kept-team'`);
  assert.equal(await status(), 'waiting_logo', 'one logo is not both');
  await db.exec(`update public.teams set logo_url = 'l' where id = 'litchfield-dassel-cokato'`);
  assert.equal(await status(), 'approved', 'both logos show it');
  await apply(named, [], [], []);
  assert.equal(await status(), 'approved', 'a re-read leaves it showing');
  await db.exec(`update public.teams set logo_url = null where id = 'kept-team'`);
  assert.equal(await status(), 'waiting_logo', 'a logo taken down hides it again');
  await db.exec(`update public.club_events set status = 'rejected' where source_uid = 'bound:short'`);
  await db.exec(`update public.teams set logo_url = 'l' where id = 'kept-team'`);
  assert.equal(await status(), 'rejected', "a decline stands");
  // Middle school or younger shows with a letter; 9th grade and up waits (Jesse, 2026-11-05).
  await db.exec(`update public.club_events set status = 'approved' where source_uid = 'bound:short'`);
  await db.exec(`update public.teams set logo_url = null where id = 'kept-team'`);
  for (const [sport, want] of [['Girls Basketball · 7th Grade', 'approved'], ['Boys Swim · MS', 'approved'],
    ['Girls Basketball · Middle school', 'approved'], ['MS Coed Wrestling', 'approved'], ['Boys Basketball · 6th', 'approved'],
    ['Boys Basketball · 9th Grade', 'waiting_logo'], ['Boys Basketball · JV', 'waiting_logo'], ['Boys Basketball · C-squad', 'waiting_logo'],
    ['Boys Basketball', 'waiting_logo'], ['Adapted Floor Hockey', 'waiting_logo']]) {
    await db.query(`update public.club_events set sport = $1 where source_uid = 'bound:short'`, [sport]);
    assert.equal(await status(), want, sport);
  }
  await db.exec('alter table public.club_events disable trigger game_waits_for_logos');
  await db.exec(`delete from public.club_events where source_uid = 'bound:short'`);
  await db.exec(`delete from public.teams where id in ('litchfield-dassel-cokato', 'kept-team')`);

  // A game names its sport and two teams (game-card 01): a team it hasn't seen gets its row, no
  // logo or color yet, and one already there keeps its own; a re-read without the game clears it.
  const seeded = (await db.query('select id from public.teams')).rows.map((r) => r.id);
  await db.exec(`insert into public.teams (id, name, short_name, color) values ('sartell', 'Sartell', 'Sartell', '#1A4C9C')`);
  const teamed = (day) => placed(day).map((g) => ({ ...g, sport: 'Volleyball', team_ids: ['rocori', 'sartell'],
    team_names: ['ROCORI', 'Sartell'], occasion: 'Senior Night' }));
  await apply(teamed('2026-10-21'), [], [], []);
  assert.deepEqual((await db.query(`select sport, team_ids, occasion from public.club_events`)).rows,
                   [{ sport: 'Volleyball', team_ids: ['rocori', 'sartell'], occasion: 'Senior Night' }]);
  assert.deepEqual((await db.query(`select id, name, short_name, color from public.teams where id <> all($1) order by id`, [seeded])).rows,
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
  // Its last day comes with it (BP app town-feed 49), and a re-read that gives none keeps it.
  const lastDay = async () => (await db.query(
    `select ends_on::text as d from public.board_items where title = 'Flight Friday'`)).rows[0].d;
  await apply([], [], [], special({ ends_on: '2026-11-29' }));
  assert.equal(await lastDay(), '2026-11-29');
  await apply([], [], [], special());
  assert.equal(await lastDay(), '2026-11-29');
  // A closing goes up when it says (BP app town-feed 50): a re-read leaves that alone, one inside its week goes up
  // now, and a story with no such day goes up now too.
  const up = async (title) => (await db.query(
    `select published_at, published_at <= now() as is_up from public.board_items where title = $1`, [title])).rows[0];
  const later = new Date(Date.now() + 13 * 864e5).toISOString();
  const closing = (title, shows_from, more = {}) => special({ title, shows_from, starts_at: later, ...more });
  await apply([], [], [], closing('Offices Closed', later));
  const held = await up('Offices Closed');
  assert.equal(held.published_at.toISOString(), later);
  assert.equal(held.is_up, false);
  await apply([], [], [], closing('Offices Closed', later, { blurb: 'Thursday, Nov 26' }));
  assert.equal((await up('Offices Closed')).published_at.toISOString(), later, 'a re-read leaves it');
  await apply([], [], [], closing('Library Closed', new Date(Date.now() - 864e5).toISOString()));
  assert.equal((await up('Library Closed')).is_up, true, 'inside its week, it goes up now');
  assert.equal((await up('Flight Friday')).is_up, true);
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
  // An About the describe step or the cleaning wrote (about_written_at; inside-cards 14) says only what it is and
  // what to expect, so it is shorter than the listing's words: a re-read never writes over it.
  await db.exec(`update public.club_events set description = 'The Storm honor their seniors.', about_written_at = now()`);
  await apply(placed('2026-10-21').map((g) => ({ ...g, description: longer })), [], [], []);
  assert.equal(await about(), 'The Storm honor their seniors.', 'a laid-out About stays against a longer re-read');
  // The price lands from a judged item, and a re-read with none keeps it (inside-cards 14).
  const price = async () => (await db.query('select price as p from public.club_events')).rows[0].p;
  await apply(placed('2026-10-21').map((g) => ({ ...g, price: '$5 at the door' })), [], [], []);
  assert.equal(await price(), '$5 at the door');
  await apply(placed('2026-10-21'), [], [], []);
  assert.equal(await price(), '$5 at the door', 'a re-read without a price keeps it');
  await apply(placed('2026-10-21').map((g) => ({ ...g, price: '' })), [], [], []);
  assert.equal(await price(), '$5 at the door', 'a blank price keeps it too');
  // Who it's for by age lands the same way, and only in the app's shapes (inside-cards 30).
  const ages = async () => (await db.query('select ages as a from public.club_events')).rows[0].a;
  await apply(placed('2026-10-21').map((g) => ({ ...g, ages: '21+' })), [], [], []);
  assert.equal(await ages(), '21+');
  await apply(placed('2026-10-21').map((g) => ({ ...g, ages: '' })), [], [], []);
  assert.equal(await ages(), '21+', 'a re-read that says no age keeps it');
  await assert.rejects(db.query(`update public.club_events set ages = 'all ages'`), /club_events_ages_shape/,
    'words outside the shapes are refused, so the app shows the field as it is');
  // Who it's for by gender too (town-feed 52), and a re-read that doesn't say keeps it.
  const gender = async () => (await db.query('select for_gender as g from public.club_events')).rows[0].g;
  await apply(placed('2026-10-21').map((g) => ({ ...g, gender: 'female' })), [], [], []);
  assert.equal(await gender(), 'female');
  await apply(placed('2026-10-21'), [], [], []);
  assert.equal(await gender(), 'female', 'a re-read that says no gender keeps it');
  await db.exec(`update public.club_events set about_written_at = null`);

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

// An About our describe step or the cleaning wrote (about_written_at) says only what it is and what to expect, so
// it is shorter on purpose: a re-read never writes over it. One the describe step only researched (described_at,
// found nothing) is still the source's own, and a fuller listing fills it (inside-cards 14, review).
test('a re-read fills an About only researched, and never one we wrote', async () => {
  const db = await realDatabase();
  const listing = (description) => [{ status: 'approved', title: 'Fall Craft Day', event_date: '2026-11-21',
    start_time: '10 AM', end_at: null, all_day: false, location: 'Community Center', description,
    source_name: 'City of St. Joseph', source_url: 'u', source_uid: 'rec1:1', category: 'learn_make',
    shows_from: '2026-11-01' }];
  const apply = (items) => db.query('select public.apply_judged($1, $2, $3, $4)',
    [JSON.stringify(items), '[]', '[]', '[]']);
  const about = async () => (await db.query('select description as d from public.club_events')).rows[0].d;
  const fuller = 'Make a wreath and a pinecone feeder to take home; every supply is on the tables, kids welcome.';

  await apply(listing('Crafts.'));
  await db.exec(`update public.club_events set described_at = now()`);
  await apply(listing(fuller));
  assert.equal(await about(), fuller, 'researched, nothing found: the fuller listing fills the thin About');

  await db.exec(`update public.club_events set description = 'Wreaths and feeders to take home.',
    described_at = now(), about_written_at = now()`);
  await apply(listing(`${fuller} Sign up on the City's registration site.`));
  assert.equal(await about(), 'Wreaths and feeders to take home.', 'written by us: a longer re-read leaves it');
});

test('a show open for days keeps its first day, while a dated Event moves with its source (town-feed 62)', async () => {
  const db = await realDatabase();
  const show = (uid, day) => [{ status: 'approved', title: 'Reflection: Selected Works', event_date: day,
    start_time: '10 AM', end_at: '2026-12-16T06:00:00Z', all_day: false, location: 'Benedicta Arts Center',
    description: null, source_name: 'CSB SJU Campus Events', source_url: 'u', source_uid: uid,
    category: 'art_theater', shows_from: day }];
  const apply = async (events) => db.query('select public.apply_judged($1, $2, $3, $4)',
    [JSON.stringify(events), '[]', '[]', '[]']);
  const day = async (uid) => (await db.query(
    'select event_date::text as d from public.club_events where source_uid = $1', [uid])).rows[0].d;
  await apply(show('run:Reflection: Selected Works', '2026-10-28'));
  await apply(show('run:Reflection: Selected Works', '2026-11-12'));
  assert.equal(await day('run:Reflection: Selected Works'), '2026-10-28', 'the next morning reads it from its next day');
  await apply(show('4758905', '2026-11-11'));
  await apply(show('4758905', '2026-11-12'));
  assert.equal(await day('4758905'), '2026-11-12', 'a dated Event its source moves, moves');
});
