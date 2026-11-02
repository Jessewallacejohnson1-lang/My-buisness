// The cloud routines' saves, as the account they really run as: the Watch key's role, `watch` (BP app
// loopholes 12). Its grants are only the scripts' own calls, so each save here runs as `watch` with
// nothing but what Supabase and the migrations give it, and the break-ins it must never manage are
// tried at the end. The other stories run as the database owner: on 2026-10-25 interests_21's
// trigger, in schema private, refused every save for a day while they passed (BP app smooth-mornings
// 02). This one loads every migration, oldest first, so a grant, trigger or function the job can't
// use fails the push and names itself.
// Run: `npm install && npm test` in this folder.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { PGlite } from '@electric-sql/pglite';

const here = dirname(fileURLToPath(import.meta.url));
const migrations = process.env.MIGRATIONS ?? join(here, '..', 'migrations');

const db = await PGlite.create();
// What a Supabase project has before any migration: the API roles (service_role skips row
// security), their grants and the owner's default grants, and stand-ins for the platform's auth,
// storage (row security on, as live) and cron. No other role may use schema auth, as live.
await db.exec(`
  create role anon nologin; create role authenticated nologin; create role service_role nologin bypassrls;
  create schema extensions; create schema auth; create schema storage; create schema cron;
  grant usage on schema public, extensions, auth, storage to anon, authenticated, service_role;
  alter default privileges in schema public grant all on tables to anon, authenticated, service_role;
  alter default privileges in schema public grant all on functions to anon, authenticated, service_role;
  alter default privileges in schema public grant all on sequences to anon, authenticated, service_role;
  create table auth.users (id uuid primary key, email text, phone text, is_anonymous boolean not null default false,
    raw_user_meta_data jsonb, created_at timestamptz default now());
  create function auth.jwt() returns jsonb language sql stable as
    $$ select coalesce(nullif(current_setting('request.jwt.claims', true), ''), '{}')::jsonb $$;
  -- As live, uid and role read the claims themselves: a body naming auth.jwt() needs schema auth.
  create function auth.uid() returns uuid language sql stable as
    $$ select nullif(nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub', '')::uuid $$;
  create function auth.role() returns text language sql stable as
    $$ select nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role' $$;
  create table storage.buckets (id text primary key, name text, public boolean, file_size_limit bigint,
    allowed_mime_types text[]);
  create table storage.objects (id uuid primary key default gen_random_uuid(), bucket_id text, name text, owner uuid);
  alter table storage.objects enable row level security;
  create function storage.foldername(name text) returns text[] language sql immutable as
    $$ select string_to_array(name, '/') $$;
  create function cron.schedule(name text, sched text, cmd text) returns bigint language sql as $$ select 1::bigint $$;
  create function cron.unschedule(name text) returns boolean language sql as $$ select true $$;
  create publication supabase_realtime;
`);
// The live rows aren't here, so a migration's own rows that point at them (team_activities'
// teams) skip their foreign keys while loading. Extensions are the platform's.
await db.exec('set session_replication_role = replica');
for (const f of readdirSync(migrations).filter((f) => f.endsWith('.sql')).sort()) {
  try {
    await db.exec(readFileSync(join(migrations, f), 'utf8').replace(/create extension[^;]*;/gi, ''));
  } catch (e) {
    throw new Error(`${f} didn't load: ${e.message}`);
  }
}
await db.exec('reset session_replication_role');

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

const day = (n) => new Date(Date.now() + n * 864e5).toISOString().slice(0, 10);
const uid = 'mshsl:153:rocori|sartell:1';
const game = (date, more = {}) => ({ status: 'approved', title: 'Sartell Volleyball vs ROCORI', event_date: date,
  start_time: '7 PM', end_at: null, all_day: false, location: 'ROCORI High School, Cold Spring', description: null,
  source_name: 'ROCORI High School', source_url: 'https://rocori.sharpschool.net/athletics', source_uid: uid,
  category: 'sports_leagues', shows_from: day(-14), place_entry_id: 'rocori-high-school', sport: 'Volleyball',
  team_ids: ['rocori', 'sartell'], team_names: ['ROCORI', 'Sartell'], occasion: 'Senior Night', ...more });
const news = { title: 'Flight Friday', blurb: 'Four scoops for $5 on Fridays.', category: 'business',
  source_name: 'The Wandering Cow', source_url: 'https://www.instagram.com/p/x/', tier: 1, status: 'published',
  starts_at: null, interests: ['breweries'], place_entry_id: 'cow-wandering', own_link: true };
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
  // same post came back reworded: one News is one link.
  const next = await apply([game(day(8), { description: 'Senior night: the Storm honors its seniors before the game.' })],
    [], [{ ...news, title: 'Four scoops for $5 every Friday' }]);
  assert.deepEqual([next.events, next.news, next.added], [1, 0, { events: [], news: [] }]);
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
  await asJob('describe', 'update public.club_events set description = $2, described_at = now() where id = $1',
              [id, 'A tractor-pulled ride through the haunted woods, with cider and a bonfire after. Dress warm.']);
  await asJob('standouts: clear today', 'delete from public.daily_standouts where town = $1 and day = $2',
              ['st-joseph-mn', day(8)]);
  await asJob('standouts', `insert into public.daily_standouts (town, day, event_id, rank, why)
    select town, day, event_id, rank, why from jsonb_populate_recordset(null::public.daily_standouts, $1)`,
              [JSON.stringify([{ town: 'st-joseph-mn', day: day(8), event_id: id, rank: 1, why: 'The last hayride of the season.' }])]);
  assert.deepEqual(await asJob('read back', `select e.interests, e.draw, s.rank from public.club_events e
    join public.daily_standouts s on s.event_id = e.id`), [{ interests: ['outdoors'], draw: 3, rank: 1 }]);
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
  await asJob('reads: News', 'select title, source_name, place_entry_id from public.board_items');
  await asJob('reads: teams', 'select id, name, short_name, aliases from public.teams');
  await asJob('event_picture', 'select public.event_picture($1)', [id]);
  await asJob('photos: what each place has', 'select id, entry_id, position, url, source_url, credit, added_at, kind, status from public.place_photos');
  // Storage writes the file as the caller first (then as itself), so the row rule decides.
  await asJob('photos: the file', `insert into storage.objects (bucket_id, name) values ('places', 'st-joseph-mn/events/abc.webp')`);
  await asJob('photos: the row', `insert into public.place_photos (entry_id, town, url, source_url, kind, event_id, status,
    width, height, description, credit, proposed_by) values ('hayloft', 'st-joseph-mn', 'https://x/abc.webp',
    'https://hayloft.example/', 'event', $1, 'live', 1080, 1350, 'A corn maze at dusk', null, 'event photos')`, [id]);
  await asJob('photos: looked at', 'update public.club_events set photo_checked_at = now() where id = $1', [id]);
  // The refresh's take-down pick (BP app agent-guardrails 09): `takedown` reads the live row, then adds
  // the pick the way PostgREST's ignore-duplicates does, so a photo asked about before stays as Jesse left it.
  const { rows: [{ id: photo }] } = await db.query(`insert into public.place_photos (entry_id, url, source_url)
    values ('hayloft', 'https://x/stock.webp', 'https://hayloft.example/') returning id`);
  await asJob('photos: the live row', 'select entry_id from public.place_photos where status = $1 and id = $2', ['live', photo]);
  const pick = `insert into public.photo_takedowns (photo_id, reason, proposed_by) values ($1, 'A stock photo', 'the monthly refresh')
    on conflict (photo_id) do nothing returning photo_id`;
  assert.equal((await asJob('photos: a take-down pick', pick, [photo])).length, 1);
  assert.equal((await asJob('photos: the same pick again', pick, [photo])).length, 0);
  await asJob('map spots', 'update public.club_events set lat = $2, lng = $3 where id = $1', [id, 45.561, -94.321]);
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
  await refused("change a Place's Apple Maps id", `update public.places set apple_place_id = 'x'`);
  await refused('take a place photo down', `update public.place_photos set status = 'retired'`);
  await refused("decide a take-down (Jesse's Keep)", 'update public.photo_takedowns set kept_at = now()');
  await refused("put a file in another bucket (someone's photo)", `insert into storage.objects (bucket_id, name) values ('avatars', 'u1/a.jpg')`);
  await refused("read a neighbour's profile", 'select * from public.town_profiles');
});
