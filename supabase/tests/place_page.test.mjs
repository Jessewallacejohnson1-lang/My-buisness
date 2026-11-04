// Fixed stories for a business's page in Search (BP app docs/plans/place-photos, ticket 01), run
// in PGlite: the saved photos the app reads with the public key.
// Run: `npm install && npm test` in this folder.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { realDatabase } from './fixture.mjs';

const db = await realDatabase();
test('the public key reads only live photos, cover first', async () => {
  await db.exec(`
    insert into public.place_photos (entry_id, url, source_url, position, kind, status) values
      ('krewe', 'https://x/food-2.webp', 'https://krewemn.com/', 1, 'photo', 'live'),
      ('krewe', 'https://x/food-1.webp', 'https://krewemn.com/', 0, 'photo', 'live'),
      ('krewe', 'https://x/new.webp', 'https://krewemn.com/', 0, 'photo', 'proposed'),
      ('krewe', 'https://x/old.webp', 'https://krewemn.com/', 0, 'photo', 'retired');
    set role anon;`);
  // What the app asks for (CommunityAPI.getPlacePhotos), as SQL.
  const { rows } = await db.query(`select entry_id, url, source_url as site from public.place_photos
    where status = 'live' and kind = 'photo' order by position`);
  await db.exec('reset role');
  assert.deepEqual(rows.map((r) => r.url), ['https://x/food-1.webp', 'https://x/food-2.webp']);
  await db.exec('set role anon');
  const all = await db.query('select url from public.place_photos');
  await db.exec('reset role');
  assert.equal(all.rows.length, 2, 'proposed and retired photos never reach the app');
});
