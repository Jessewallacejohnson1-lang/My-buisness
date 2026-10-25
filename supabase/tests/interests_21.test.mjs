// Fixed stories for the move from 18 interests to 21 (supabase/migrations/*_interests_21.sql, BP app
// onboarding 20): old ids stored anywhere become the new ones, on the day and on every later save.
// Run: `npm install && npm test` in this folder.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { PGlite } from '@electric-sql/pglite';

const here = dirname(fileURLToPath(import.meta.url));
const migrations = process.env.MIGRATIONS ?? join(here, '..', 'migrations');
const file = readdirSync(migrations).find((f) => f.endsWith('_interests_21.sql'));

const db = await PGlite.create();
await db.exec(`
  create schema private;
  create table public.town_profiles (user_id int primary key, interests text[] not null default '{}');
  create table public.club_events (id int primary key, interests text[] not null default '{}', category text);
  create table public.board_items (id int primary key, interests text[]);
  insert into public.town_profiles values (1, '{art_exhibits,coffee,books}'), (2, '{outdoors}');
  insert into public.club_events values (1, '{sports_leagues,live_music}', 'breweries'), (2, '{}', 'faith'), (3, '{}', null);
  insert into public.board_items values (1, '{farmers_market}'), (2, null);
`);
await db.exec(readFileSync(join(migrations, file), 'utf8'));

const rows = async (sql) => (await db.query(sql)).rows;

test('the day it runs, old ids everywhere become the new ones', async () => {
  assert.deepEqual(await rows('select user_id, interests from public.town_profiles order by 1'),
    [{ user_id: 1, interests: ['art_theater', 'crafts', 'coffee', 'books'] }, { user_id: 2, interests: ['outdoors'] }]);
  assert.deepEqual(await rows('select id, interests, category from public.club_events order by 1'),
    [{ id: 1, interests: ['watch_sports', 'live_music'], category: 'bars' },
     { id: 2, interests: [], category: 'faith' }, { id: 3, interests: [], category: null }]);
  assert.deepEqual(await rows('select id, interests from public.board_items order by 1'),
    [{ id: 1, interests: ['markets'] }, { id: 2, interests: null }]);
});

test('an older app or the morning job saving old ids gets the new ones', async () => {
  await db.exec(`update public.town_profiles set interests = '{sports_leagues,fitness_yoga,health_wellness}' where user_id = 2`);
  await db.exec(`insert into public.club_events values (4, '{trails_hiking,parks_gardens}', 'art_exhibits')`);
  await db.exec(`insert into public.board_items values (3, '{breweries}')`);
  assert.deepEqual((await rows('select interests from public.town_profiles where user_id = 2'))[0].interests,
    ['watch_sports', 'play_sports', 'health']);
  assert.deepEqual(await rows('select interests, category from public.club_events where id = 4'),
    [{ interests: ['outdoors'], category: 'art_theater' }]);
  assert.deepEqual((await rows('select interests from public.board_items where id = 3'))[0].interests, ['bars']);
});

test('new ids, and books, are left as picked', async () => {
  await db.exec(`update public.town_profiles set interests = '{books,campus,town_meetings}' where user_id = 2`);
  assert.deepEqual((await rows('select interests from public.town_profiles where user_id = 2'))[0].interests,
    ['books', 'campus', 'town_meetings']);
});
