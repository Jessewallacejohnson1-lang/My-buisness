// Fixed stories for city_boards and meeting_board (supabase/migrations/*_city_boards.sql): which board a
// City meeting belongs to, run in PGlite under the live read rules (BP app docs/plans/follows, ticket 03).
// Run: `npm install && npm test` in this folder.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { realDatabase } from './fixture.mjs';

const db = await realDatabase();
async function boardOf(title, source = 'City of St. Joseph', draw = 1) {
  await db.exec('set role anon');
  const { rows } = await db.query(
    `select b.name from (select jsonb_populate_record(null::public.club_events,
       jsonb_build_object('title', $1::text, 'source_name', $2::text, 'draw', $3::smallint)) e) r
     left join public.city_boards b on b.id = public.meeting_board(r.e)`,
    [title, source, draw]);
  await db.exec('reset role');
  return rows[0].name;
}

test("each of St. Joseph's five boards claims its meetings as the City's calendar writes them", async () => {
  assert.equal(await boardOf('City Council Meeting'), 'City Council');
  assert.equal(await boardOf('City Council Work Session'), 'City Council');
  assert.equal(await boardOf('Planning Commission'), 'Planning Commission');
  assert.equal(await boardOf('Park Board Meeting'), 'Park Board');
  assert.equal(await boardOf('Economic Development Authority'), 'Economic Development Authority');
  assert.equal(await boardOf('Joint Planning Board (as needed)'), 'Joint Planning Board');
});

test('a City meeting matching no board belongs to the City only', async () => {
  assert.equal(await boardOf('Board of Appeal and Equalization'), null);
});

test("only the City's own meetings belong to its boards", async () => {
  assert.equal(await boardOf('City Council Meeting', 'Kennedy Community School'), null);
  assert.equal(await boardOf('Park Board Meeting', 'City of St. Joseph', 2), null);
});

test('anyone can read the boards, and nobody can change them', async () => {
  await db.exec('set role anon');
  const { rows } = await db.query('select count(*)::int n from public.city_boards');
  assert.equal(rows[0].n, 5);
  await assert.rejects(db.exec(`insert into public.city_boards (town, city_name, name, title_prefixes)
    values ('st-joseph-mn', 'City of St. Joseph', 'Fake Board', array['Fake'])`));
  await db.exec('reset role');
});
