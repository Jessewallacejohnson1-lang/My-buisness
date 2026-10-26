// Fixed stories for the moved-or-canceled notice (supabase/migrations/*_moved_notices.sql, BP app
// docs/plans/school-activities, ticket 04): which edits count as a move, and get_my_changes, what the
// bell's Notifications page lists. PGlite, like the others: `npm install && npm test` in this folder.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { PGlite } from '@electric-sql/pglite';

const here = dirname(fileURLToPath(import.meta.url));
const migrations = process.env.MIGRATIONS ?? join(here, '..', 'migrations');
const one = (suffix) => readFileSync(join(migrations, readdirSync(migrations).find((f) => f.endsWith(suffix))), 'utf8');

const ME = '00000000-0000-0000-0000-00000000000a';
const OTHER = '00000000-0000-0000-0000-00000000000b';
const db = await PGlite.create();
await db.exec(`
  set timezone = 'UTC';
  create role anon; create role authenticated; create schema private; create schema auth;
  grant usage on schema auth, private to anon, authenticated;
  create function auth.uid() returns uuid language sql stable as
    $$ select nullif(current_setting('request.jwt.claims', true)::jsonb ->> 'sub', '')::uuid $$;
  create function private.findable(p uuid) returns boolean language sql stable as $$ select true $$;
  create table public.places (id uuid primary key);
  create table public.teams (id text primary key, name text not null, short_name text not null,
    local boolean not null default false, nickname text, uuid uuid not null default gen_random_uuid(),
    logo_url text, colors text[]);
  insert into public.teams (id, name, short_name, local, logo_url) values
    ('apollo', 'Apollo', 'Apollo', true, 'https://x/apollo.png'), ('tech', 'Tech', 'Tech', true, null),
    ('kennedy', 'Kennedy', 'Kennedy', false, null), ('cathedral', 'Cathedral', 'Cathedral', true, null),
    ('apollo-cathedral', 'Apollo-Cathedral', 'Apollo-Cathedral', true, null),
    ('rocori', 'ROCORI', 'ROCORI', true, null), ('sartell', 'Sartell', 'Sartell', true, null),
    ('sauk-rapids-rice', 'Sauk Rapids-Rice', 'Sauk Rapids-Rice', true, null),
    ('saint-benedict', 'Saint Benedict', 'Saint Benedict', true, null),
    ('saint-johns', 'Saint John''s', 'Saint John''s', true, null), ('albany', 'Albany', 'Albany', false, null);
  create table public.clubs (id uuid primary key default gen_random_uuid(), name text not null);
  create table public.club_events (id uuid primary key default gen_random_uuid(), title text not null,
    sport text, team_ids text[], event_date date, start_time text, location text,
    status text not null default 'approved', cancelled_at timestamptz, kind text not null default 'event',
    image_url text, category text, club_id uuid, source_name text, end_at timestamptz,
    all_day boolean not null default false, created_at timestamptz not null default now(),
    place_entry_id text, occasion text, description text);
  create table public.event_rsvps (id uuid primary key default gen_random_uuid(), event_id uuid not null,
    user_id uuid not null);
  create table public.town_follows (id uuid primary key default gen_random_uuid(), follower_id uuid not null,
    target_type text not null, target_id uuid not null,
    constraint town_follows_target_type_check check (target_type in ('club', 'profile', 'place', 'team')),
    unique (follower_id, target_type, target_id));
  grant select on all tables in schema public to anon, authenticated;
  -- The feed's helpers the read calls, as stand-ins: their own stories test them.
  create function private.going_count(uuid) returns int language sql stable as $$ select 0 $$;
  create function public.place_picture(text) returns jsonb language sql stable as $$ select null::jsonb $$;
  create function private.event_game(text, text[], text) returns jsonb language sql stable as
    $$ select jsonb_build_object('sport', $1) $$;
  grant execute on all functions in schema private to authenticated;
`);
await db.exec(one('_team_activities.sql'));
await db.exec(one('_activity_follows.sql'));
await db.exec(one('_school_names.sql'));
await db.exec(`set check_function_bodies = off`);
await db.exec(one('_activity_follow_lift.sql'));
await db.exec(`reset check_function_bodies`);
await db.exec(one('_moved_notices.sql'));
await db.exec(`grant execute on all functions in schema private to authenticated`);

const soon = (days) => new Date(Date.now() + days * 864e5).toISOString().slice(0, 10);
const game = async (fields = {}) => {
  const f = { title: 'Apollo Volleyball vs Sartell', sport: 'Volleyball', team_ids: ['apollo', 'sartell'],
    event_date: soon(3), start_time: '7 PM', location: 'Apollo High School', ...fields };
  return (await db.query(`insert into public.club_events (title, sport, team_ids, event_date, start_time, location)
    values ($1, $2, $3, $4, $5, $6) returning id`,
    [f.title, f.sport, f.team_ids, f.event_date, f.start_time, f.location])).rows[0].id;
};
const edit = (id, set, args = []) => db.query(`update public.club_events set ${set} where id = $1`, [id, ...args]);
const moved = async (id) => (await db.query(`select moved_at is not null as moved, moved_from
  from public.club_events where id = $1`, [id])).rows[0];
const as = async (who, sql, args = []) => {
  await db.exec(`set role authenticated; select set_config('request.jwt.claims', '${JSON.stringify({ sub: who })}', false)`);
  try { return (await db.query(sql, args)).rows; } finally { await db.exec('reset role'); }
};
const mine = async (who = ME) => (await as(who, `select * from public.get_my_changes()`));

test('a start 15 minutes off is no move; 30 minutes, another day or another place is', async () => {
  const id = await game();
  await edit(id, `start_time = '7:15 PM'`);
  assert.equal((await moved(id)).moved, false, 'a 15-minute nudge');
  await edit(id, `start_time = '7:45 PM'`);
  const m = await moved(id);
  assert.equal(m.moved, true);
  assert.equal(m.moved_from.start_time, '7:15 PM', 'from where it stood');

  const day = await game();
  await edit(day, `event_date = $2`, [soon(4)]);
  assert.equal((await moved(day)).moved, true, 'another day');

  const place = await game();
  await edit(place, `location = 'Apollo High School - Main Gym'`);
  assert.equal((await moved(place)).moved, false, 'the same place written longer');
  await edit(place, `location = 'Sartell High School'`);
  assert.equal((await moved(place)).moved, true, 'another place');
});

test('a time or place filled in is no move, and an Event already over never moves', async () => {
  const tba = await game({ start_time: 'TBA', location: null });
  await edit(tba, `start_time = '6 PM', location = 'Sartell High School'`);
  assert.equal((await moved(tba)).moved, false);

  const over = await game({ event_date: soon(-2) });
  await edit(over, `start_time = '3 PM'`);
  assert.equal((await moved(over)).moved, false);
});

test('moved back where it first was, it never moved; moved twice, it keeps where it first was', async () => {
  const id = await game();
  await edit(id, `start_time = '9 PM'`);
  await edit(id, `start_time = '7:00 PM'`);
  assert.deepEqual(await moved(id), { moved: false, moved_from: null }, 'a misread fixed next morning');

  await edit(id, `start_time = '8 PM'`);
  await edit(id, `start_time = '9 PM'`);
  const m = await moved(id);
  assert.equal(m.moved, true);
  assert.equal(m.moved_from.start_time, '7:00 PM');
});

test('Notifications lists what you follow and are Going to, and nothing else', async () => {
  await db.exec(`delete from public.club_events; delete from public.town_follows; delete from public.event_rsvps`);
  const volleyball = (await db.query(`select id from public.team_activities where team_id = 'apollo'
    and name ilike '%volleyball%' limit 1`)).rows[0].id;
  await db.query(`insert into public.town_follows (follower_id, target_type, target_id) values ($1, 'activity', $2)`,
    [ME, volleyball]);

  const followedMove = await game();
  await edit(followedMove, `start_time = '6 PM'`);
  const followedOff = await game({ title: 'Apollo Volleyball vs Tech', team_ids: ['apollo', 'tech'] });
  await edit(followedOff, `cancelled_at = now()`);
  const quiet = await game({ title: 'Apollo Volleyball vs ROCORI', team_ids: ['apollo', 'rocori'] });
  const notMine = await game({ title: 'Tech Football vs Sartell', sport: 'Football', team_ids: ['tech', 'sartell'] });
  await edit(notMine, `cancelled_at = now()`);
  const going = (await db.query(`insert into public.club_events (title, event_date, start_time, location,
    cancelled_at) values ('Music in Millstream Park', $1, '7 PM', 'Millstream Park', now() - interval '20 days')
    returning id`, [soon(5)])).rows[0].id;
  await db.query(`insert into public.event_rsvps (event_id, user_id) values ($1, $2)`, [going, ME]);
  const oldFollowed = await game({ title: 'Apollo Volleyball vs Albany', team_ids: ['apollo', 'albany'] });
  await edit(oldFollowed, `cancelled_at = now() - interval '8 days'`);

  const rows = await mine();
  assert.deepEqual(rows.map((r) => r.id).sort(), [followedMove, followedOff, going].sort(),
    'not the unchanged one, not one nobody follows, not a followed change from 8 days ago');
  const byId = Object.fromEntries(rows.map((r) => [r.id, r]));
  assert.match(byId[followedMove].followed, /^Apollo .*Volleyball/);
  assert.equal(byId[followedMove].followed_logo, 'https://x/apollo.png');
  assert.equal(byId[followedMove].moved_from.start_time, '7 PM');
  assert.equal(byId[followedMove].cancelled, false);
  assert.equal(byId[followedOff].cancelled, true);
  assert.equal(byId[going].followed, null, 'Going alone names nothing');
  assert.equal(byId[going].going, true, "a Going cancel stays until it's over, however old");
  assert.equal((await mine(OTHER)).length, 0, 'someone who follows nothing sees nothing');
  void quiet;
});

test('a whole school followed covers its activities, named with the sport', async () => {
  await db.exec(`delete from public.club_events; delete from public.town_follows; delete from public.event_rsvps`);
  const apollo = (await db.query(`select uuid from public.teams where id = 'apollo'`)).rows[0].uuid;
  await db.query(`insert into public.town_follows (follower_id, target_type, target_id) values ($1, 'team', $2)`,
    [OTHER, apollo]);
  const id = await game({ title: 'Apollo Football vs Tech', sport: 'Football', team_ids: ['apollo', 'tech'] });
  await edit(id, `location = 'Tech High School'`);
  const [row] = await mine(OTHER);
  assert.equal(row.id, id);
  assert.match(row.followed, /^Apollo .*Football/);
});
