// Fixed stories for team_activities and activity_has_event (supabase/migrations/*_team_activities.sql):
// each local school's approved activities, and which of them a game belongs to, run in PGlite under the
// live read rules (BP app docs/plans/school-activities, ticket 01). Run: `npm install && npm test` here.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { PGlite } from '@electric-sql/pglite';

const here = dirname(fileURLToPath(import.meta.url));
const migrations = process.env.MIGRATIONS ?? join(here, '..', 'migrations');
const file = readdirSync(migrations).find((f) => f.endsWith('_team_activities.sql'));

const db = await PGlite.create();
await db.exec(`
  create role anon; create role authenticated; create schema private;
  -- public.teams and public.club_events, only the columns an activity reads.
  create table public.teams (id text primary key, name text not null, short_name text not null,
    local boolean not null default false, nickname text);
  insert into public.teams (id, name, short_name, local) values
    ('apollo', 'Apollo', 'Apollo', true), ('tech', 'Tech', 'Tech', true), ('kennedy', 'Kennedy', 'Kennedy', false),
    ('cathedral', 'Cathedral', 'Cathedral', true), ('apollo-cathedral', 'Apollo-Cathedral', 'Apollo-Cathedral', true),
    ('rocori', 'ROCORI', 'ROCORI', true), ('sartell', 'Sartell', 'Sartell', true),
    ('sauk-rapids-rice', 'Sauk Rapids-Rice', 'Sauk Rapids-Rice', true),
    ('saint-benedict', 'Saint Benedict', 'Saint Benedict', true), ('saint-johns', 'Saint John''s', 'Saint John''s', true),
    ('albany', 'Albany', 'Albany', false);
  create table public.club_events (id uuid primary key default gen_random_uuid(), title text not null,
    sport text, team_ids text[]);
  grant select on public.teams, public.club_events to anon, authenticated;
  grant usage on schema private to anon, authenticated;
`);
await db.exec(readFileSync(join(migrations, file), 'utf8'));

// The activities of `school` that a game of `sport` between `teams` belongs to, as anyone reads them.
async function activitiesOf(school, sport, teams) {
  await db.exec('set role anon');
  const { rows } = await db.query(
    `with e as (select gen_random_uuid() id, 'game'::text title, $2::text sport, $3::text[] team_ids)
     select a.name from public.team_activities a, e
     where a.team_id = $1 and public.activity_has_event(a, e::public.club_events) order by a.sort`,
    [school, sport, teams]);
  await db.exec('reset role');
  return rows.map((r) => r.name);
}

test('a gendered game is the school activity of that sport and gender', async () => {
  assert.deepEqual(await activitiesOf('apollo', 'Girls Soccer', ['apollo', 'albany']), ['Girls Soccer']);
  assert.deepEqual(await activitiesOf('rocori', 'Boys Soccer', ['albany', 'rocori']), ['Soccer (boys)']);
  assert.deepEqual(await activitiesOf('rocori', 'Girls Swim', ['rocori', 'albany']), ['Swimming & Diving - Girls']);
});

test("a game's words for a sport meet the school's: Dance Team is Dance, Rugby is SJU Rugby", async () => {
  assert.deepEqual(await activitiesOf('apollo', 'Dance Team', ['apollo', 'albany']), ['Dance']);
  assert.deepEqual(await activitiesOf('saint-johns', 'Rugby', ['saint-johns', 'albany']), ['SJU Rugby']);
  assert.deepEqual(await activitiesOf('saint-johns', 'Swimming and Diving', ['saint-johns', 'albany']), ['Swimming and Diving']);
});

test("a game naming no gender is the school's own row for that sport", async () => {
  assert.deepEqual(await activitiesOf('cathedral', 'Volleyball', ['cathedral', 'albany']), ['Volleyball (girls)']);
  assert.deepEqual(await activitiesOf('apollo', 'Volleyball', ['apollo', 'albany']), ['Volleyball (girls)']);
});

test("Kennedy's grade 7-12 rows take Apollo's games, and only the right ones", async () => {
  assert.deepEqual(await activitiesOf('kennedy', 'Girls Swim', ['apollo', 'albany']), ['Girls Swimming 7-12']);
  assert.deepEqual(await activitiesOf('kennedy', 'Volleyball', ['apollo', 'albany']), []);
  assert.deepEqual(await activitiesOf('kennedy', 'Volleyball', ['kennedy', 'albany']), ['Volleyball 6-8 (girls)']);
});

test('a sport the school lists no activity for, or a game it is not in, belongs to none', async () => {
  assert.deepEqual(await activitiesOf('rocori', 'Rugby', ['rocori', 'albany']), []);
  assert.deepEqual(await activitiesOf('apollo', 'Girls Soccer', ['tech', 'albany']), []);
  assert.deepEqual(await activitiesOf('apollo', null, ['apollo', 'albany']), []);
});

test('anyone can read the approved list, nobody can change it, and Kennedy has a page', async () => {
  await db.exec('set role anon');
  const { rows } = await db.query(`select team_id, count(*)::int n from public.team_activities group by 1 order by 1`);
  assert.deepEqual(Object.fromEntries(rows.map((r) => [r.team_id, r.n])), {
    apollo: 67, 'apollo-cathedral': 1, cathedral: 50, kennedy: 43, rocori: 49, 'saint-benedict': 46,
    'saint-johns': 43, sartell: 76, 'sauk-rapids-rice': 49, tech: 65,
  });
  await assert.rejects(db.exec(`insert into public.team_activities (team_id, name, kind, sort) values ('apollo', 'Fake', 'club', 99)`));
  assert.equal((await db.query(`select local from public.teams where id = 'kennedy'`)).rows[0].local, true);
  await db.exec('reset role');
});
