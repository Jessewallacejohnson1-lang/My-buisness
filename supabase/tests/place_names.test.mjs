// Fixed stories for a place's name in its own lettering (supabase/migrations/*_place_names.sql, BP app
// follows 02): everyone reads it, nobody but the service role writes it, and an Event's photo gets its
// place's name or none. Run: `npm install && npm test` in this folder.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { realDatabase } from './fixture.mjs';

const db = await realDatabase();
await db.exec(`
  insert into public.club_events (id, title, status, place_entry_id) values
    ('00000000-0000-0000-0000-000000000001', 'Krewe night', 'approved', 'krewe'), ('00000000-0000-0000-0000-000000000002', 'Nowhere', 'approved', 'nowhere'),
    ('00000000-0000-0000-0000-000000000003', 'At no place', 'approved', null), ('00000000-0000-0000-0000-000000000004', 'Well night', 'approved', 'well');
  insert into public.place_names (entry_id, url) values ('krewe', 'https://x/krewe/name-1.png');
  insert into public.place_names (entry_id, url, kind) values ('well', 'https://x/well/logo.webp', 'emblem');
`);
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
