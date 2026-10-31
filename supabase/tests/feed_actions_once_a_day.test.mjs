// Fixed stories for one feed action per person per Event per kind per Town day
// (supabase/migrations/*_feed_actions_once_a_day.sql, BP app docs/plans/loopholes, ticket 04), run in
// PGlite. Run: `npm test` in this folder.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { PGlite } from '@electric-sql/pglite';
import { creating } from './migrations.mjs';

const migrations = process.env.MIGRATIONS ?? new URL('../migrations', import.meta.url).pathname;
const db = await PGlite.create();
await db.exec(`
  set timezone = 'UTC';
  create role anon; create role authenticated;
  create schema private;
  create table public.feed_actions (id uuid primary key default gen_random_uuid(), user_id uuid not null,
    item_id uuid not null, action text not null, at timestamptz not null default now(),
    constraint feed_actions_action_check check (action in ('view', 'open', 'not_interested', 'reported')));
`);
for (const f of creating(migrations, ['private.feed_actions_once_a_day'])) await db.exec(readFileSync(join(migrations, f), 'utf8'));

const [ANNA, BEN] = ['a', 'b'].map((x) => `00000000-0000-0000-0000-00000000000${x}`);
const [FAIR, QUIZ] = ['1', '2'].map((x) => `00000000-0000-0000-0000-00000000010${x}`);
// Town time, Central.
const send = (rows) => db.query(`insert into public.feed_actions (user_id, item_id, action, at)
  select * from unnest($1::uuid[], $2::uuid[], $3::text[], $4::timestamptz[])`,
  [rows.map((r) => r[0]), rows.map((r) => r[1]), rows.map((r) => r[2]), rows.map((r) => `${r[3]}-05`)]);
const saved = async () => (await db.query(`select user_id, item_id, action, to_char(at at time zone 'America/Chicago', 'MM-DD HH24:MI') as town_time
  from public.feed_actions order by at`)).rows.map((r) => [r.user_id, r.item_id, r.action, r.town_time]);

test('a card seen again the same Town day is not saved again; a new card in the same batch is', async () => {
  await send([[ANNA, FAIR, 'view', '2026-10-30 09:00']]);
  // A second feed load: the fair again (and twice within the batch), the quiz new, the fair opened.
  await send([[ANNA, FAIR, 'view', '2026-10-30 18:00'], [ANNA, FAIR, 'view', '2026-10-30 18:00'],
              [ANNA, QUIZ, 'view', '2026-10-30 18:00'], [ANNA, FAIR, 'open', '2026-10-30 18:01']]);
  // Ben's view is his own; late at night is still the 30th in town though it is the 31st in UTC.
  await send([[BEN, FAIR, 'view', '2026-10-30 23:30'], [ANNA, FAIR, 'view', '2026-10-30 23:30']]);
  // The next Town day counts again.
  await send([[ANNA, FAIR, 'view', '2026-10-31 00:10']]);
  assert.deepEqual(await saved(), [
    [ANNA, FAIR, 'view', '10-30 09:00'],
    [ANNA, QUIZ, 'view', '10-30 18:00'],
    [ANNA, FAIR, 'open', '10-30 18:01'],
    [BEN, FAIR, 'view', '10-30 23:30'],
    [ANNA, FAIR, 'view', '10-31 00:10'],
  ]);
});

test('a share is a feed action again', async () => {
  await send([[BEN, QUIZ, 'share', '2026-10-31 08:00']]);
  assert.deepEqual((await saved()).at(-1), [BEN, QUIZ, 'share', '10-31 08:00']);
});
