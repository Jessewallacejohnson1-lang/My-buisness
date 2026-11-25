// Fixed stories for Follow 3's line (supabase/migrations/*_follow_line.sql, BP app community-value 04): only the cloud's
// role saves it, a photo picked by hand stays, who is not in the line leaves it, and a broken run changes nothing.
// Run: `npm install && npm test` in this folder.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { realDatabase } from './fixture.mjs';

const db = await realDatabase();
const uuid = (n) => `00000000-0000-0000-0000-${String(n).padStart(12, '0')}`;
await db.exec(`insert into public.places (id, name, lat, lon, family)
  select ('00000000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid, 'Place ' || n, 45.5, -94.3, 'business' from generate_series(1, 120) n`);
const as = async (role, sql, params = []) => {
  await db.exec(`discard plans; set role ${role}`);
  try { return (await db.query(sql, params)).rows; } finally { await db.exec('reset role'); }
};
const line = (n = 110, more = {}) => Array.from({ length: n }, (_, i) =>
  ({ id: uuid(i + 1), spot: i < 60 ? i + 1 : null, fit: i + 1, group: i % 2 ? 'food' : null, late: i === 5, ...more[i + 1] }));
const save = (role, rows) => as(role, 'select public.save_follow_line($1) as n', [JSON.stringify(rows)]).then((r) => r[0].n);
const spot = async (n) => (await db.query('select follow_spot s from public.places where id = $1', [uuid(n)])).rows[0].s;
const all = async () => JSON.stringify((await db.query('select id, follow_spot from public.places order by id')).rows);

test('the line is saved whole: spots, fits, the mix, and the Town pages in it', async () => {
  await save('watch', [...line(), { page: 'city', spot: 200, fit: 150, group: null, late: false }]);
  assert.deepEqual(await spot(1), { spot: 1, fit: 1, late: false, photo: null });
  assert.deepEqual(await spot(2), { spot: 2, fit: 2, group: 'food', late: false, photo: null });
  assert.equal((await spot(6)).late, true);
  assert.deepEqual(await spot(100), { fit: 100, group: 'food', late: false, photo: null });
  assert.equal(await spot(115), null);
  const pages = (await db.query('select slug, follow_spot s from public.town_pages where follow_spot is not null')).rows;
  assert.deepEqual(pages, [{ slug: 'city', s: { spot: 200, fit: 150, late: false } }]);
});

test('a photo stays until a row names another, and whoever leaves the line has no spot', async () => {
  await save('watch', line(110, { 1: { photo: 'https://x.co/a.webp' } }));
  assert.equal((await spot(1)).photo, 'https://x.co/a.webp');
  await save('watch', line(105));
  assert.equal((await spot(1)).photo, 'https://x.co/a.webp');
  assert.equal(await spot(110), null);
  await save('watch', line().slice(1).map((r) => (r.spot === 2 ? { ...r, spot: 1 } : r)));
  assert.deepEqual(await spot(1), { photo: 'https://x.co/a.webp' }, 'out of the line, its photo waits');
  await save('watch', line());
  assert.equal((await spot(1)).photo, 'https://x.co/a.webp');
  assert.equal((await db.query('select count(*)::int n from public.town_pages where follow_spot is not null')).rows[0].n, 0);
  await save('watch', line(105, { 1: { photo: null } }));
  assert.equal((await spot(1)).photo, null);
});

test('a closed Place is in no line', async () => {
  await db.exec(`update public.places set closed_at = now() where id = '${uuid(3)}'`);
  await save('watch', line());
  assert.equal(await spot(3), null);
  await db.exec(`update public.places set closed_at = null where id = '${uuid(3)}'`);
});

test('a broken run changes nothing: too short, two on one spot, no first, or an odd value', async () => {
  const before = await all();
  for (const rows of [line(40), [], line(110, { 2: { spot: 1 } }), line(110, { 1: { spot: 99 } }), line(110, { 4: { spot: 'x' } }),
    line(110, { 4: { group: 7 } }), line(110, { 4: { fit: 2.5 } }), line(110, { 4: { fit: -3 } }), [...line(), { id: uuid(1), spot: 111, fit: 111 }],
    line(110, { 4: { id: uuid(999) } }), line().map(({ id, ...r }) => r), [...line(), { page: 'nowhere', spot: 111, fit: 111 }]]) {
    await assert.rejects(save('watch', rows));
    assert.equal(await all(), before);
  }
});

test('the facts name every open place, its kind and each page with its upcoming Events, each title once', async () => {
  await db.exec(`update public.places set primary_type = 'bakery' where id = '${uuid(1)}';
    insert into public.club_events (title, status, source_name, event_date) select t, 'approved', g.source_name, current_date + d
    from public.town_pages g, (values ('Council', 3), ('Council', 9), ('Parks', 4), ('Old', -4)) v (t, d) where g.slug = 'city'`);
  const facts = (await as('watch', 'select public.follow_line_facts() f'))[0].f;
  assert.equal(facts.kinds[uuid(1)], 'bakery');
  const city = facts.pages.find((p) => p.slug === 'city');
  assert.equal(city.events, 2);
});

test('nobody in the app saves a line, signed out or in', async () => {
  for (const role of ['anon', 'authenticated']) {
    await assert.rejects(save(role, line()), /permission denied/, role);
    await assert.rejects(as(role, 'select public.follow_line_facts()'), /permission denied/, role);
  }
});

test('the spots already live keep their shape', async () => {
  await db.exec(`update public.places set follow_spot = '{"spot": 1, "photo": "https://x.co/b.webp"}' where id = '${uuid(1)}'`);
  await assert.rejects(db.exec(`update public.places set follow_spot = '{"rank": 5}' where id = '${uuid(1)}'`), /check constraint/);
});
