// Fixed stories for a business's page in Search (BP app docs/plans/place-photos, ticket 01), run
// in PGlite: the links and About the page shows (supabase/migrations/*_place_page.sql, which fills
// them from the registry's sources), and the saved photos the app reads with the public key.
// Run: `npm install && npm test` in this folder.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { PGlite } from '@electric-sql/pglite';

const here = dirname(fileURLToPath(import.meta.url));
const migrations = process.env.MIGRATIONS ?? join(here, '..', 'migrations');
const run = (f) => db.exec(readFileSync(join(migrations, f), 'utf8'));

const db = await PGlite.create();
await db.exec(`
  create role anon;
  -- The subset of public.places the page reads.
  create table public.places (id uuid primary key default gen_random_uuid(), name text, entry_id text);
  insert into public.places (name, entry_id) values
    ('Krewe Restaurant', 'krewe'), ('Her Hair Studio', 'her-hair-studio'), ('Autobody 2000 Inc', 'auto-body-2000'),
    ('CMS Autobody', 'cms-autobody'), ('Plain Shop', 'plain-shop'), ('Joetown Smashburger', null);
`);
await run('20261014120000_source_registry.sql');
await db.exec(`
  insert into public.sources (entry_id, url, town, name, status, kind, method) values
    ('krewe', 'https://krewemn.com/saint-joseph-krewe-restaurant-events', 'st-joseph-mn', 'Krewe', 'active', 'website', 'fetch'),
    ('krewe', 'https://krewemn.com/', 'st-joseph-mn', 'Krewe', 'active', 'website', 'fetch'),
    ('krewe', 'https://www.facebook.com/krewerestaurant/', 'st-joseph-mn', 'Krewe', 'active', 'facebook', 'search_snippet'),
    ('krewe', 'https://krewemn.com/feed', 'st-joseph-mn', 'Krewe', 'active', 'rss', 'fetch'),
    ('krewe', 'https://old-krewe.com/', 'st-joseph-mn', 'Krewe', 'retired', 'website', 'fetch'),
    ('her-hair-studio', 'http://www.herhairstudiomn.com/', 'st-joseph-mn', 'Her Hair Studio', 'active', 'website', 'fetch'),
    ('her-hair-studio', 'https://www.herhairstudiomn.com/', 'st-joseph-mn', 'Her Hair Studio', 'active', 'website', 'fetch'),
    ('auto-body-2000', 'http://autobody2011161494-422835.hibustudio.com/', 'st-joseph-mn', 'Auto Body 2000', 'active', 'website', 'fetch'),
    ('cms-autobody', 'https://cmsautobody0.wixsite.com/website/blog', 'st-joseph-mn', 'CMS Autobody', 'active', 'website', 'fetch');
`);
await run('20261016150000_place_photos.sql');
await run('20261016170000_place_photo_kind.sql');
await db.exec('alter table public.place_photos add column if not exists hue smallint;');
await run('20261017190000_place_page.sql');

const links = async (entry) =>
  (await db.query('select links from public.places where entry_id = $1', [entry])).rows[0].links;

test("a place's links: its website's home first, then its social pages", async () => {
  assert.deepEqual(await links('krewe'), [
    { kind: 'website', url: 'https://krewemn.com/' },
    { kind: 'facebook', url: 'https://www.facebook.com/krewerestaurant/' },
  ], 'the home page, not the events page; no feed; nothing retired');
  assert.deepEqual(await links('her-hair-studio'), [{ kind: 'website', url: 'https://www.herhairstudiomn.com/' }],
    'https before http');
});

test('a site that is gone gets no row; one on a shared host keeps its page', async () => {
  assert.deepEqual(await links('auto-body-2000'), [], 'its domain no longer exists (scan of 2026-10-16)');
  assert.deepEqual(await links('cms-autobody'), [{ kind: 'website', url: 'https://cmsautobody0.wixsite.com/website' }]);
  assert.deepEqual(await links('plain-shop'), [], 'no sources: an empty list, never null');
});

test('the About is the two proof places\' own words, and nothing for the rest', async () => {
  const { rows } = await db.query('select entry_id, about from public.places where about is not null order by entry_id');
  assert.deepEqual(rows.map((r) => r.entry_id), ['her-hair-studio', 'krewe']);
  assert.match(rows[1].about, /^New Orleans-inspired Southern cooking/);
});

test('the public key reads only live photos, cover first', async () => {
  await db.exec(`
    insert into public.place_photos (entry_id, url, source_url, position, kind, status) values
      ('krewe', 'https://x/food-2.webp', 'https://krewemn.com/', 1, 'photo', 'live'),
      ('krewe', 'https://x/food-1.webp', 'https://krewemn.com/', 0, 'photo', 'live'),
      ('krewe', 'https://x/new.webp', 'https://krewemn.com/', 0, 'photo', 'proposed'),
      ('krewe', 'https://x/old.webp', 'https://krewemn.com/', 0, 'photo', 'retired');
    grant select on public.place_photos to anon;
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
