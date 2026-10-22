// Fixed stories for a place's name in its own lettering (supabase/migrations/*_place_names.sql, BP app
// follows 02): everyone reads it, nobody but the service role writes it, and an Event's photo gets its
// place's name or none. Run: `npm install && npm test` in this folder.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { PGlite } from '@electric-sql/pglite';

const here = dirname(fileURLToPath(import.meta.url));
const migrations = process.env.MIGRATIONS ?? join(here, '..', 'migrations');
const file = readdirSync(migrations).find((f) => f.endsWith('_place_names.sql'));

const db = await PGlite.create();
await db.exec(`
  create role anon; create role authenticated;
  create table public.club_events (id uuid primary key, place_entry_id text);
  grant select on public.club_events to anon, authenticated;
  insert into public.club_events values
    ('00000000-0000-0000-0000-000000000001', 'krewe'), ('00000000-0000-0000-0000-000000000002', 'nowhere'),
    ('00000000-0000-0000-0000-000000000003', null);
`);
await db.exec(readFileSync(join(migrations, file), 'utf8'));
await db.exec(`insert into public.place_names (entry_id, url) values ('krewe', 'https://x/krewe/name-1.png')`);
await db.exec(`insert into public.club_events values ('00000000-0000-0000-0000-000000000004', 'well')`);
await db.exec(`insert into public.place_names (entry_id, url, kind) values ('well', 'https://x/well/logo.webp', 'emblem')`);

const name = async (event) => (await db.query('select public.event_place_name($1) as u', [event])).rows[0].u;

test("an Event gets its place's name, or none", async () => {
  await db.exec('set role anon');
  try {
    assert.deepEqual(await name('00000000-0000-0000-0000-000000000001'), { url: 'https://x/krewe/name-1.png', kind: 'name' });
    assert.deepEqual(await name('00000000-0000-0000-0000-000000000004'), { url: 'https://x/well/logo.webp', kind: 'emblem' });
    assert.equal(await name('00000000-0000-0000-0000-000000000002'), null, 'a place with no name cut yet');
    assert.equal(await name('00000000-0000-0000-0000-000000000003'), null, 'an Event at no place');
  } finally { await db.exec('reset role'); }
});

test('everyone reads the names; nobody signed in writes them', async () => {
  for (const role of ['anon', 'authenticated']) {
    await db.exec(`set role ${role}`);
    try {
      assert.equal((await db.query('select count(*)::int as n from public.place_names')).rows[0].n, 2);
      await assert.rejects(db.query(`insert into public.place_names (entry_id, url) values ('x', 'y')`));
    } finally { await db.exec('reset role'); }
  }
});
