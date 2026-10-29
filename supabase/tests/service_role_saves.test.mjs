// The morning job's saves, as the account it really runs as (BP app smooth-mornings 02). Its
// scripts write over the service role key, so each call runs as `service_role` with only the
// grants Supabase and the migrations give it. The other stories run as the database owner: on
// 2026-10-25 interests_21's trigger, in schema private, refused every save for a day while they
// passed. This one loads every migration, oldest first, and makes each of the job's writes as
// service_role, so a trigger or function it can't run fails the push and names itself.
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
// storage and cron.
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
  create function auth.uid() returns uuid language sql stable as $$ select nullif(auth.jwt() ->> 'sub', '')::uuid $$;
  create function auth.role() returns text language sql stable as $$ select auth.jwt() ->> 'role' $$;
  create table storage.buckets (id text primary key, name text, public boolean, file_size_limit bigint,
    allowed_mime_types text[]);
  create table storage.objects (id uuid primary key default gen_random_uuid(), bucket_id text, name text, owner uuid);
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

// One call as PostgREST makes it with the service key, on plans made fresh: a plan the owner made
// keeps working for any role without its schema rights checked again. A refusal names the triggers
// in its context on the table the statement writes, or else the function it stopped in.
async function asJob(what, sql, params = []) {
  await db.exec(`discard plans; set role service_role; set request.jwt.claims = '{"role": "service_role"}'`);
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
    assert.fail(`${what}, as service_role: ${e.message}${triggers.length ? `\n  in ${triggers.join('\n  in ')}`
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
