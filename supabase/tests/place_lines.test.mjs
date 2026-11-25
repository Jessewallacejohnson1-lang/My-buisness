// Fixed stories for the places' saved order (supabase/migrations/*_places_take_turns.sql, BP app community-value 05):
// nobody in the app reads or writes it, places of one turn trade places, what put something out this week leads the wall,
// the rest keep their spot, and nobody is left out.
// Run: `npm install && npm test` in this folder.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { people, realDatabase } from './fixture.mjs';

const db = await realDatabase();
const uuid = (n) => `00000000-0000-0000-0000-${String(n).padStart(12, '0')}`;
const me = uuid(900);
await people(db, me);
const names = Array.from({ length: 120 }, (_, n) => `p${n}`);
await db.exec(names.map((name, n) => `insert into public.places (id, name, lat, lon, family, entry_id, search_logo)
  values ('${uuid(n + 1)}', '${name}', 45.5, -94.3, 'business', '${name}', '{"url":"https://x/${name}.webp","hue":${n}}');`).join('\n'));
// p0 to p9 take turns on both, p10 to p14 a later turn, the rest keep their spot.
const line = (n) => ({ id: uuid(n + 1), spot: n + 1, wall: n < 10 ? 1 : n < 15 ? 2 : null, feed: n < 10 ? 1 : n < 15 ? 2 : null });
const lines = names.map((_, n) => line(n));
const as = async (role, sql, params = []) => {
  await db.exec(`discard plans; set role ${role}`);
  try { return (await db.query(sql, params)).rows; } finally { await db.exec('reset role'); }
};
const save = (role, list = lines) => as(role, 'select public.save_place_lines($1) as n', [JSON.stringify(list)]).then((r) => r[0].n);
const wall = async () => (await db.query(`select name from public.places where closed_at is null and search_logo->>'url' is not null
  order by (search_logo->>'rank')::int`)).rows.map((r) => r.name);
const deal = (at) => db.query('select private.deal_places($1) as n', [at]).then((r) => r.rows[0].n);
const feed = async (at) => (await db.query(`select p.name from public.get_town_more(p_now => $1) with ordinality m(kind, id, n)
  join public.places p on p.id = m.id order by m.n`, [at])).rows.map((r) => r.name);

test('the cloud role saves the whole list, and the wall is dealt at once', async () => {
  assert.equal(await save('watch'), 120);
  assert.deepEqual(await wall(), names, 'nothing is fresh: every place at its spot');
  const { rows } = await db.query(`select search_logo from public.places where name = 'p7'`);
  assert.deepEqual(rows[0].search_logo, { url: 'https://x/p7.webp', hue: 7, rank: 7 }, 'the logo keeps the rest');
});

test('nobody in the app reads or writes it', async () => {
  for (const role of ['anon', 'authenticated']) {
    await assert.rejects(as(role, 'select * from private.place_lines'));
    await assert.rejects(save(role));
    await assert.rejects(as(role, 'select private.deal_places()'));
  }
  await assert.rejects(as('watch', 'select * from private.place_lines'), 'the cloud role only saves');
});

test('a short list is refused and changes nothing', async () => {
  await assert.rejects(save('watch', lines.slice(0, 50)), /not the whole Town/);
  assert.deepEqual(await wall(), names);
});

test('on the wall, what put out an Event or News this week leads its turn, in a new order each day', async () => {
  const at = '2026-11-24 15:00+00';
  for (const n of [3, 5, 8]) {
    await db.query(`insert into public.club_events (title, status, place_entry_id, event_date, created_at) values ($1, 'approved', $1, '2026-12-01', '2026-11-20')`, [`p${n}`]);
  }
  await db.query(`insert into public.board_items (title, blurb, category, source_name, status, tier, place_entry_id, published_at)
    values ('New soup', 'Soup.', 'business', 'p6', 'published', 1, 'p6', '2026-11-22'), ('Old', 'Old.', 'business', 'p1', 'published', 1, 'p1', '2026-11-10')`);
  await db.query(`insert into public.club_events (title, status, place_entry_id, event_date, created_at) values ('late', 'approved', 'p40', '2026-12-01', '2026-11-23')`);
  assert.ok(await deal(at) > 0);
  const one = await wall();
  assert.deepEqual(one.slice(0, 4).sort(), ['p3', 'p5', 'p6', 'p8'], 'this week, an Event or News');
  assert.deepEqual(one.slice(4, 10), ['p0', 'p1', 'p2', 'p4', 'p7', 'p9'], 'then the rest of the turn at their spot');
  assert.deepEqual(one.slice(10), names.slice(10), 'a place with no turn never moves, whatever it posts');
  assert.equal(await deal(at), 0, 'dealt again the same day, the same');
  const days = [];
  for (let d = 25; d <= 27; d += 1) { await deal(`2026-11-${d} 15:00+00`); days.push((await wall()).slice(0, 4).join()); }
  assert.ok(new Set([one.slice(0, 4).join(), ...days]).size > 1, 'another day, another order');
  await deal('2026-12-20 15:00+00');
  assert.deepEqual(await wall(), names, 'a month later nothing is fresh');
});

test("at the feed's end the popular trade places at each read, and nobody is left out", async () => {
  const [one, two, three] = [await feed('2026-11-24 15:00+00'), await feed('2026-11-24 15:01+00'), await feed('2026-11-24 15:02+00')];
  for (const o of [one, two, three]) {
    assert.deepEqual(o.slice(0, 10).sort(), names.slice(0, 10).sort(), 'the first turn');
    assert.deepEqual(o.slice(10, 15).sort(), names.slice(10, 15).sort(), 'then the second');
    assert.deepEqual(o.slice(15), names.slice(15), 'then each at its spot');
  }
  assert.ok(new Set([one, two, three].map((o) => o.slice(0, 10).join())).size > 1);
});

test('what you follow leads the feed\'s end, and a closed place or one not listed yet is handled', async () => {
  await db.query(`insert into public.town_follows (follower_id, target_type, target_id) values ($1, 'place', $2)`, [me, uuid(100)]);
  await db.query(`insert into public.places (id, name, lat, lon, family, entry_id, search_logo) values ($1, 'new', 45.5, -94.3, 'food', 'new', '{"url":"https://x/new.webp"}')`, [uuid(500)]);
  await db.query(`update public.places set closed_at = now() where name = 'p2'`);
  await db.exec(`set request.jwt.claims = '${JSON.stringify({ sub: me, role: 'authenticated' })}'`);
  const mine = await feed('2026-11-24 15:00+00');
  await db.exec('reset request.jwt.claims');
  assert.equal(mine[0], 'p99');
  assert.ok(!mine.includes('p2'));
  assert.equal(mine.at(-1), 'new');
  await deal('2026-11-24 15:00+00');
  assert.equal((await wall()).at(-1), 'new', 'not listed yet: last');
});
