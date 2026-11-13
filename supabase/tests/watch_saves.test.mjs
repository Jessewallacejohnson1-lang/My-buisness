// The cloud routines' saves, as the account they really run as: the Watch key's role, `watch` (BP app
// loopholes 12). Its grants are only the scripts' own calls, so each save here runs as `watch` with
// nothing but what Supabase and the migrations give it, and the break-ins it must never manage are
// tried at the end. The other stories mostly write as the database owner: on 2026-10-25 interests_21's
// trigger, in schema private, refused every save for a day while they passed (BP app smooth-mornings
// 02). This one writes as the job does, so a grant, trigger or function the job can't use fails the
// push and names itself.
// Run: `npm install && npm test` in this folder.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { realDatabase } from './fixture.mjs';
import { townDay } from './town_day.mjs';

const db = await realDatabase();
// One call as PostgREST makes it with the Watch key, on plans made fresh: a plan the owner made
// keeps working for any role without its schema rights checked again. A refusal names the triggers
// in its context on the table the statement writes, or else the function it stopped in.
async function asJob(what, sql, params = []) {
  await db.exec(`discard plans; set role watch; set request.jwt.claims = '{"role": "watch"}'`);
  try {
    return (await db.query(sql, params)).rows;
  } catch (e) {
    await db.exec('reset role');
    const context = `${e.where ?? ''}\n${sql}`;
    const triggers = (await db.query(
      `select format('trigger %s on %s.%s (%s)', t.tgname, n.nspname, c.relname, t.tgfoid::regproc) as t
       from pg_trigger t join pg_class c on c.oid = t.tgrelid join pg_namespace n on n.oid = c.relnamespace
       where not t.tgisinternal and $1 like '%' || t.tgfoid::regproc || '(%'
         and $1 like '%' || n.nspname || '.' || c.relname || ' %'`,
      [context])).rows.map((r) => r.t);
    const stopped = (e.where ?? '').split('\n')[0];
    assert.fail(`${what}, as watch: ${e.message}${triggers.length ? `\n  in ${triggers.join('\n  in ')}`
                                                                          : stopped ? `\n  at ${stopped}` : ''}`);
  } finally {
    await db.exec('reset role; reset request.jwt.claims');
  }
}

const day = townDay;
const uid = 'mshsl:153:rocori|sartell:1';
const game = (date, more = {}) => ({ status: 'approved', title: 'Sartell Volleyball vs ROCORI', event_date: date,
  start_time: '7 PM', end_at: null, all_day: false, location: 'ROCORI High School, Cold Spring', description: null,
  source_name: 'ROCORI High School', source_url: 'https://rocori.sharpschool.net/athletics', source_uid: uid,
  category: 'sports_leagues', shows_from: day(-14), place_entry_id: 'rocori-high-school', sport: 'Volleyball',
  team_ids: ['rocori', 'sartell'], team_names: ['ROCORI', 'Sartell'], occasion: 'Senior Night', ...more });
const news = { title: 'Flight Friday', blurb: 'Four scoops for $5 on Fridays.', category: 'business',
  source_name: 'The Wandering Cow', source_url: 'https://www.instagram.com/p/x/', tier: 1, status: 'published',
  starts_at: null, interests: ['breweries'], place_entry_id: 'cow-wandering' };
// write_judged.payloads' six lists.
const apply = (events, mentions, news, cancelled = [], restored = []) => asJob('apply_judged',
  'select public.apply_judged($1, $2, $3, $4, $5, $6) as r',
  [events, mentions, [], news, cancelled, restored].map((l) => JSON.stringify(l))).then((rows) => rows[0].r);

test('prepare and write: the registry sync, the listed events, apply_judged and the fingerprints', async () => {
  const page = { entry_id: 'rocori-high-school', url: 'https://rocori.sharpschool.net/athletics', town: 'st-joseph-mn',
    name: 'ROCORI High School', status: 'active', kind: null, method: 'fetch', trust: 'official', place_id: null, extra: {} };
  const sync = `insert into public.sources (entry_id, url, town, name, status, kind, method, trust, place_id, extra)
    select entry_id, url, town, name, status, kind, method, trust, place_id, extra
    from jsonb_populate_recordset(null::public.sources, $1)
    on conflict (entry_id, url) do update set town = excluded.town, name = excluded.name, status = excluded.status,
      kind = excluded.kind, method = excluded.method, trust = excluded.trust, place_id = excluded.place_id,
      extra = excluded.extra`;
  await asJob('prepare: sources sync', sync, [JSON.stringify([page])]);
  await asJob('prepare: sources state', `select entry_id, url, last_hash, last_checked_at, last_error, failing_since,
    failing_reads, set_aside_at from public.sources`);
  // A failing page: since when, then set aside (smooth-mornings 04); a good read clears both; the sync
  // clears a page no longer watched.
  const check = (fields, params) => asJob('prepare: sources check', `update public.sources set last_checked_at = now(),
    ${fields} where entry_id = $1 and url = $2`, [page.entry_id, page.url, ...params]);
  await check('last_error = $3, failing_since = now(), failing_reads = 1', ['HTTP Error 500']);
  await check('last_error = $3, failing_reads = 3, set_aside_at = now()', ['HTTP Error 500']);
  await check('last_error = null, failing_since = null, failing_reads = 0, set_aside_at = null', []);
  await asJob('prepare: clear a page no longer watched', `update public.sources set last_error = null,
    failing_since = null, failing_reads = 0, set_aside_at = null where entry_id = $1 and url = $2`,
    ['old-page', 'https://old.example/']);
  await asJob('listed_for_writer', 'select public.listed_for_writer()');

  const first = await apply([game(day(7))], [{ event_source_name: 'ROCORI High School', event_source_uid: uid,
    source_name: 'Sartell High School', source_url: 'https://sartell.k12.mn.us/athletics', source_uid: 's1',
    trust: 'official', sure: true }], [news]);
  // The counts it always gave, and which items it added (smooth-mornings 05): the game and the News.
  assert.deepEqual([first.events, first.mentions, first.news, first.added], [1, 1, 1, { events: [0], news: [0] }]);
  const [{ id }] = await asJob('read back', 'select id from public.club_events');
  // The next morning it moved a day and its schedule dropped it, then another school listed it again. The
  // same News came back: written over the one there, not added (a reworded repeat the plan leaves out).
  const next = await apply([game(day(8), { description: 'Senior night: the Storm honors its seniors before the game.' })],
    [], [{ ...news, blurb: 'Four scoops for $5 every Friday.' }]);
  assert.deepEqual([next.events, next.news, next.added], [1, 1, { events: [], news: [] }]);
  assert.equal((await apply([], [], [], [id])).cancelled, 1);
  assert.equal((await apply([], [], [], [], [id])).restored, 1);
  await asJob('write: fingerprints', `update public.sources set last_hash = $3, last_changed_at = now()
    where entry_id = $1 and url = $2`, [page.entry_id, page.url, 'f00d']);

  assert.deepEqual(await asJob('read back', `select event_date::text as day, category, moved_at is not null as moved,
    cancelled_at is null as listed from public.club_events`), [{ day: day(8), category: 'watch_sports', moved: true, listed: true }]);
});

test('tag, describe and standouts write onto the Event', async () => {
  const { rows: [{ id }] } = await db.query(`insert into public.club_events (status, title, event_date, location,
    source_name, source_uid) values ('approved', 'Haunted Hayride', $1, 'Hayloft Farm', 'Hayloft Farm', 'h1')
    returning id`, [day(8)]);
  await asJob('tag', `update public.club_events set interests = $2, draw = $3, what = $4, interests_tagged_at = now()
    where id = $1`, [id, ['outdoors', 'trails_hiking'], 3, 'Hayride']);
  await asJob('describe', `update public.club_events set description = $2, price = $3, described_at = now(),
    about_written_at = now() where id = $1`,
              [id, 'A tractor-pulled ride through the haunted woods, with cider and a bonfire after. Dress warm.', '$15, kids $8']);
  await asJob('standouts: clear today', 'delete from public.daily_standouts where town = $1 and day = $2',
              ['st-joseph-mn', day(8)]);
  await asJob('standouts', `insert into public.daily_standouts (town, day, event_id, rank, why)
    select town, day, event_id, rank, why from jsonb_populate_recordset(null::public.daily_standouts, $1)`,
              [JSON.stringify([{ town: 'st-joseph-mn', day: day(8), event_id: id, rank: 1, why: 'The last hayride of the season.' }])]);
  assert.deepEqual(await asJob('read back', `select e.interests, e.draw, e.price, s.rank from public.club_events e
    join public.daily_standouts s on s.event_id = e.id`), [{ interests: ['outdoors'], draw: 3, price: '$15, kids $8', rank: 1 }]);
});

test('finish: the morning report is one row a morning, the last finish kept, and no one in the app reads it', async () => {
  // As PostgREST writes POST morning_reports?on_conflict=day with resolution=merge-duplicates.
  const save = (report) => asJob('finish: morning report', `insert into public.morning_reports (day, report, saved_at)
    values ($1, $2, now()) on conflict (day) do update set day = excluded.day, report = excluded.report,
    saved_at = excluded.saved_at`, [day(0), report]);
  await save('Morning watch, first finish');
  await save('Morning watch, finish run again');
  assert.deepEqual(await asJob('read back', 'select report from public.morning_reports'),
                   [{ report: 'Morning watch, finish run again' }]);
  // The report's game lines (game-card 22): refused on 2026-11-08 until watch could call it.
  assert.deepEqual(await asJob('finish: live_marks', 'select * from public.live_marks($1)',
                               ['{00000000-0000-0000-0000-000000000001}']),
                   [{ event_id: '00000000-0000-0000-0000-000000000001', sources: [], alerted_at: null, alert_why: null }]);
  for (const role of ['anon', 'authenticated']) {
    await db.exec(`set role ${role}`);
    await assert.rejects(db.query('select report from public.morning_reports'), /permission denied/, role);
    await db.exec('reset role');
  }
});

test('photos, map spots and hours: the photo, social and accounts routines and the finish', async () => {
  await db.query(`insert into public.places (entry_id, name, lat, lon, family) values ('hayloft', 'Hayloft Farm', 45.56, -94.32, 'food')`);
  const { rows: [{ id }] } = await db.query(`insert into public.club_events (status, title, event_date, location,
    source_name, source_uid, place_entry_id) values ('approved', 'Corn Maze Night', $1, 'Hayloft Farm', 'Hayloft Farm',
    'm1', 'hayloft') returning id`, [day(9)]);
  await asJob('reads: Events with their club, and Going and likes counts', `select e.id, c.name,
    (select count(*) from public.event_rsvps r where r.event_id = e.id) as going,
    (select count(*) from public.event_likes l where l.event_id = e.id) as likes
    from public.club_events e left join public.clubs c on c.id = e.club_id`);
  await asJob('reads: News', `select title, source_name, place_entry_id, source_url, status, created_at, published_at, starts_at, ends_on
    from public.board_items`);
  await asJob('reads: teams', 'select id, name, short_name, aliases from public.teams');
  await asJob('event_picture', 'select public.event_picture($1)', [id]);
  await asJob('photos: what each place has', 'select id, entry_id, position, url, source_url, credit, added_at, kind, status from public.place_photos');
  // Storage writes the file as the caller first (then as itself), so the row rule decides.
  await asJob('photos: the file', `insert into storage.objects (bucket_id, name) values ('places', 'st-joseph-mn/events/abc.webp')`);
  await asJob('photos: the row', `insert into public.place_photos (entry_id, town, url, source_url, kind, event_id, status,
    width, height, description, credit, proposed_by) values ('hayloft', 'st-joseph-mn', 'https://x/abc.webp',
    'https://hayloft.example/', 'event', $1, 'live', 1080, 1350, 'A corn maze at dusk', null, 'event photos')`, [id]);
  await asJob('photos: looked at', 'update public.club_events set photo_checked_at = now() where id = $1', [id]);
  // A News's own photo (town-feed 53): the News read, its row, and the News marked looked at.
  const { rows: [{ id: story }] } = await db.query(`insert into public.board_items (title, category, source_name, source_url,
    status, place_entry_id) values ('New maze', 'business', 'Hayloft Farm', 'https://www.instagram.com/p/x/', 'published', 'hayloft')
    returning id`);
  await asJob('photos: News from posts', `select id, title, blurb, source_name, source_url, place_entry_id from public.board_items
    where status = 'published' and photo_checked_at is null and source_url ~ '(facebook|instagram)[.]com/'`);
  await asJob('photos: a News photo', `insert into public.place_photos (entry_id, town, url, source_url, kind, news_id, status,
    width, height, description, credit, proposed_by) values ('hayloft', 'st-joseph-mn', 'https://x/news.webp',
    'https://www.instagram.com/p/x/', 'news', $1, 'live', 720, 960, 'Kids in the maze', 'Hayloft Farm', 'event photos')`, [story]);
  await asJob('photos: News looked at', 'update public.board_items set photo_checked_at = now() where id = $1', [story]);
  // The refresh's take-down pick (BP app agent-guardrails 09): `takedown` reads the live row, then adds
  // the pick the way PostgREST's ignore-duplicates does, so a photo asked about before stays as Jesse left it.
  const { rows: [{ id: photo }] } = await db.query(`insert into public.place_photos (entry_id, url, source_url)
    values ('hayloft', 'https://x/stock.webp', 'https://hayloft.example/') returning id`);
  await asJob('photos: the live row', 'select entry_id from public.place_photos where status = $1 and id = $2', ['live', photo]);
  const pick = `insert into public.photo_takedowns (photo_id, reason, proposed_by) values ($1, 'A stock photo', 'the monthly refresh')
    on conflict (photo_id) do nothing returning photo_id`;
  assert.equal((await asJob('photos: a take-down pick', pick, [photo])).length, 1);
  assert.equal((await asJob('photos: the same pick again', pick, [photo])).length, 0);
  await asJob('map spots', 'update public.club_events set lat = $2, lng = $3, no_place = $4 where id = $1',
    [id, 45.561, -94.321, false]);
  await asJob('accounts: places', 'select entry_id, name, address, links, hours from public.places where entry_id is not null');
  await asJob('accounts: Google hours', `update public.places set hours = $2 where entry_id = $1`, ['hayloft', { mon: '9-5' }]);
  assert.deepEqual(await asJob('read back', `select e.lat, p.status, (select hours from public.places) as hours
    from public.club_events e join public.place_photos p on p.event_id = e.id`),
    [{ lat: 45.561, status: 'live', hours: { mon: '9-5' } }]);
  // The finish's Apple Maps step (apple_maps.check): a place Apple calls closed for good is hidden and
  // its upcoming Events cancelled, and the app's public read no longer shows it.
  const open = await asJob('Apple Maps: open places', 'select id, entry_id, name, apple_place_id from public.places where closed_at is null');
  await asJob('Apple Maps: hide a closed place', 'update public.places set closed_at = now() where id = $1', [open[0].id]);
  const cancelled = await asJob('Apple Maps: its upcoming Events cancelled', `update public.club_events set cancelled_at = now()
    where place_entry_id = $1 and event_date >= $2 and cancelled_at is null returning id`, ['hayloft', day(0)]);
  assert.deepEqual(cancelled, [{ id }]);
  await db.exec(`set role anon; set request.jwt.claims = '{"role": "anon"}'`);
  try {
    assert.deepEqual((await db.query('select name from public.places')).rows, [], 'the app no longer reads a closed place');
  } finally {
    await db.exec('reset role; reset request.jwt.claims');
  }
});

// The finish's parts step (event_parts.keep, BP app happening-now 03): a long Event's parts, its new ones written before
// its old ones go (a failed write never empties it), and the app reads them only through get_event_parts.
test("parts of a long Event: written, then the old ones taken away, by the job; read by the app", async () => {
  const { rows: [{ id }] } = await db.query(`insert into public.club_events (status, title, event_date, all_day, end_at,
    location, source_name, source_uid) values ('approved', 'Drawings Exhibition', $1, true, now() + interval '30 days',
    'Gorecki Gallery', 'CSB', 'x1') returning id`, [day(0)]);
  const part = { event_id: id, title: 'Artist talk', starts_at: new Date(Date.now() + 86400e3).toISOString(), ends_at: null,
    source_url: 'https://csbsju.edu/show', source_line: 'Artist talk Thursday at 3 PM', same_as: null };
  await asJob('parts: the step is on', 'select event_id from public.event_parts limit 1');
  // Two mornings: the same talk again, then a reception beside it; each morning's stamp is its own.
  const mornings = [[part], [part, { ...part, title: 'Reception' }]];
  for (const [n, rows] of mornings.entries()) {
    const stamp = new Date(Date.now() + n * 1000).toISOString();
    await asJob('parts: write', `insert into public.event_parts (event_id, title, starts_at, ends_at, source_url, source_line, same_as, found_at)
      select event_id, title, starts_at, ends_at, source_url, source_line, same_as, found_at
      from jsonb_populate_recordset(null::public.event_parts, $1)
      on conflict (event_id, starts_at, title) do update set ends_at = excluded.ends_at, source_url = excluded.source_url,
        source_line = excluded.source_line, same_as = excluded.same_as, found_at = excluded.found_at`,
      [JSON.stringify(rows.map((r) => ({ ...r, found_at: stamp })))]);
    await asJob('parts: take away the old', 'delete from public.event_parts where event_id = $1 and found_at < $2', [id, stamp]);
  }
  await db.exec(`set role anon; set request.jwt.claims = '{"role": "anon"}'`);
  try {
    assert.deepEqual((await db.query('select title from public.get_event_parts($1)', [id])).rows,
      [{ title: 'Artist talk' }, { title: 'Reception' }], 'the app reads both parts, once each');
    await assert.rejects(db.query(`insert into public.event_parts (event_id, title, starts_at, source_url, source_line)
      values ($1, 'Mine', now(), 'x', 'x')`, [id]), /permission denied|row-level security/, 'the app writes none');
  } finally {
    await db.exec('reset role; reset request.jwt.claims');
  }
});

// The finish's team logos step (team_logos.keep, BP app game-card 17): a team's logo, saved once, and the team
// takes it, which shows its waiting games (private.team_logo_changed, run as the job).
test("team logos: a new team's logo and colors", async () => {
  await asJob('team logos: the team', `insert into public.teams (id, name, short_name) values ('mankato-east', 'Mankato East', 'Mankato East')`);
  await asJob('team logos: the file', `insert into storage.objects (bucket_id, name) values ('places', 'teams/mankato-east/logo-0a1b2c3d4e.png')`);
  await asJob('team logos: the team takes it', `update public.teams set logo_url = $2, color = $3, colors = $4
    where id = $1 and logo_url is null`, ['mankato-east', 'https://x/logo.png', '#F2B417', ['#F2B417', '#000000']]);
  assert.deepEqual(await asJob('read back', `select logo_url, colors from public.teams where id = 'mankato-east'`),
    [{ logo_url: 'https://x/logo.png', colors: ['#F2B417', '#000000'] }]);
  await asJob('team logos: the ones taken down before', 'select id, name, logo_refused from public.teams where logo_url is null');
});

// The weekly step for what has nothing scheduled (BP app nothing-scheduled 04): the Sunday finish counts the things due
// (nothing_scheduled.read_rows and last_walks), and a walk remembers each thing it walked.
test('nothing scheduled: the Sunday count reads, and each thing walked is remembered', async () => {
  await asJob('count: school activities', `select id, team_id, name, kind, note from public.team_activities
    where team_id in ('apollo', 'tech') order by id limit 1000 offset 0`);
  await asJob('count: activities_next', 'select public.activities_next($1) as n', [['apollo', 'tech']]);
  await asJob('count: Groups', `select id, name, kind, own_entry_id, place_entry_id, page_url from public.clubs
    where status = 'approved'`);
  await asJob('count: busy Places and Groups', `select place_entry_id, club_id from public.club_events
    where status = 'approved' and cancelled_at is null and event_date >= $1 order by id limit 1000 offset 0`, [day(0)]);
  // As PostgREST writes POST date_walks?on_conflict=thing with resolution=merge-duplicates.
  const walked = (things, at) => asJob('keep: things walked', `insert into public.date_walks (thing, walked_at)
    select thing, walked_at from jsonb_populate_recordset(null::public.date_walks, $1)
    on conflict (thing) do update set thing = excluded.thing, walked_at = excluded.walked_at`,
    [JSON.stringify(things.map((thing) => ({ thing, walked_at: at })))]);
  await walked(['group:g1', 'place:cafe'], '2026-11-15T12:00:00Z');
  await walked(['place:cafe'], '2026-12-13T12:00:00Z');
  assert.deepEqual((await asJob('count: last walks', 'select thing, walked_at from public.date_walks order by thing'))
    .map((r) => [r.thing, r.walked_at.toISOString()]),
    [['group:g1', '2026-11-15T12:00:00.000Z'], ['place:cafe', '2026-12-13T12:00:00.000Z']]);
  // The paid rung (06): each page it read, with its verdict, so a turned-down page isn't paid for again.
  await asJob('posts: pages read', `insert into public.date_walks (thing, walked_at, verdict)
    select thing, walked_at, verdict from jsonb_populate_recordset(null::public.date_walks, $1)
    on conflict (thing) do update set thing = excluded.thing, walked_at = excluded.walked_at, verdict = excluded.verdict`,
    [JSON.stringify([{ thing: 'page:https://www.facebook.com/vtwintavern', walked_at: '2026-11-22T18:00:00Z', verdict: 'kept' },
      { thing: 'page:https://www.facebook.com/st.joefoodshelf', walked_at: '2026-11-22T18:00:00Z', verdict: 'turned_down' }])]);
  assert.deepEqual((await asJob('posts: pages turned down', `select thing, walked_at, verdict from public.date_walks
    where thing like 'page:%' order by thing`)).map((r) => [r.thing, r.verdict]),
    [['page:https://www.facebook.com/st.joefoodshelf', 'turned_down'], ['page:https://www.facebook.com/vtwintavern', 'kept']]);
  await assert.rejects(db.query(`insert into public.date_walks (thing, verdict) values ('place:cafe2', 'kept')`),
    /date_walks_verdict_check/, 'a verdict is only a page\'s');
  for (const role of ['anon', 'authenticated']) {
    await db.exec(`set role ${role}`);
    await assert.rejects(db.query('select thing from public.date_walks'), /permission denied/, role);
    await db.exec('reset role');
  }
});

// The Sunday step keeps clubs' meeting times current (meeting_times.sunday, BP app nothing-scheduled 05): it reads each
// school's clubs with their stored times, writes a time that moved, and empties one the page dropped.
test("meeting times: a club's time read, moved and dropped by the Sunday step, and nothing else of its row", async () => {
  const clubs = await asJob('meets: the clubs', `select id, team_id, name, meets from public.team_activities
    where kind = 'club' and team_id in ('sartell', 'apollo') order by name`);
  const bible = clubs.find((c) => c.team_id === 'sartell' && c.name === 'Bible Study');
  assert.deepEqual(bible.meets, [{ days: ['fri'], time: '08:00' }], "03's migration stored Sartell's time");
  // As PostgREST writes PATCH team_activities?id=eq.<id> with return=minimal.
  const patch = (meets) => asJob('meets: a change', 'update public.team_activities set meets = $2 where id = $1',
    [bible.id, meets === null ? null : JSON.stringify(meets)]);
  await patch([{ days: ['thu'], time: '07:30' }]);
  assert.deepEqual((await db.query('select meets from public.team_activities where id = $1', [bible.id])).rows[0].meets,
    [{ days: ['thu'], time: '07:30' }]);
  await patch(null);
  assert.equal((await db.query('select meets from public.team_activities where id = $1', [bible.id])).rows[0].meets, null);
  await db.exec(`discard plans; set role watch; set request.jwt.claims = '{"role": "watch"}'`);
  try {
    await assert.rejects(db.query(`update public.team_activities set name = 'x' where id = $1`, [bible.id]),
      /permission denied/, "rename a club");
  } finally {
    await db.exec('reset role; reset request.jwt.claims');
  }
});

// Ticket 12's proof: a page that talks the job into trying any of these gets a refusal.
test('the Watch key is refused: deleting an Event, the waitlist, sign-in accounts, stored files, posts', async () => {
  const refused = async (what, sql) => {
    await db.exec(`discard plans; set role watch; set request.jwt.claims = '{"role": "watch"}'`);
    try {
      await assert.rejects(db.query(sql), /permission denied|row-level security/, what);
    } finally {
      await db.exec('reset role; reset request.jwt.claims');
    }
  };
  await refused('delete an Event', 'delete from public.club_events');
  await refused('read waitlist emails', 'select email from public.waitlist');
  await refused('list sign-in accounts', 'select email from auth.users');
  await refused('delete a stored photo', 'delete from storage.objects');
  await refused("change a neighbour's comment", `update public.event_comments set body = 'x'`);
  await refused('see who is Going', 'select user_id from public.event_rsvps');
  await refused('rename a Place', `update public.places set name = 'x'`);
  await refused('rename a team', `update public.teams set name = 'x'`);
  await refused('put back a logo taken down', `update public.teams set logo_refused = '{}'`);
  await refused("change a Place's Apple Maps id", `update public.places set apple_place_id = 'x'`);
  await refused('take a place photo down', `update public.place_photos set status = 'retired'`);
  await refused("decide a take-down (Jesse's Keep)", 'update public.photo_takedowns set kept_at = now()');
  await refused("put a file in another bucket (someone's photo)", `insert into storage.objects (bucket_id, name) values ('avatars', 'u1/a.jpg')`);
  await refused("read a neighbour's profile", 'select * from public.town_profiles');
});
