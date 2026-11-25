// Fixed stories for the Places' ratings (supabase/migrations/*_place_ratings.sql, BP app community-value 03): nobody in
// the app reads or writes one, the cloud's role can rate, a closed Place drops out, and love counts people, not taps.
// Run: `npm install && npm test` in this folder.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { people, realDatabase } from './fixture.mjs';

const db = await realDatabase();
const uuid = (n) => `00000000-0000-0000-0000-${String(n).padStart(12, '0')}`;
const [cafe, church] = [uuid(1), uuid(2)];
const [ann, bo, guest, host] = [uuid(11), uuid(12), uuid(13), uuid(14)];
const [night, story] = [uuid(21), uuid(31)];
await people(db, ann, bo, guest, host);
await db.exec(`
  update auth.users set is_anonymous = true where id = '${guest}';
  insert into public.places (id, name, lat, lon, family, entry_id) values
    ('${cafe}', 'Cafe', 45.5, -94.3, 'food', 'cafe'), ('${church}', 'Church', 45.5, -94.3, 'business', 'church');
  insert into public.club_events (id, title, status, place_entry_id, event_date, submitted_by, importance) values
    ('${night}', 'Trivia', 'approved', 'cafe', current_date + 3, '${host}', 3);
  insert into public.board_items (id, title, blurb, category, source_name, status, tier, place_entry_id) values
    ('${story}', 'New soup', 'Soup.', 'business', 'Cafe', 'published', 1, 'cafe');
`);
const as = async (role, sql, params = [], sub = null) => {
  await db.exec(`discard plans; set role ${role}`);
  if (sub) await db.exec(`set request.jwt.claims = '${JSON.stringify({ sub, role })}'`);
  try { return (await db.query(sql, params)).rows; } finally { await db.exec('reset role; reset request.jwt.claims'); }
};
const judge = (level, sure = true) => ({ level, sure, proof: 'a fact' });
const rating = (id, level, more = {}) => ({ id, a: judge(level), b: judge(level), judged: level, sure: true, love: 0, level, note: null, ...more });
const save = (role, ...ratings) => as(role, 'select public.save_place_ratings($1) as n', [JSON.stringify(ratings)]).then((r) => r[0].n);
const levels = async () => Object.fromEntries((await db.query('select place_id, level from private.place_levels')).rows.map((r) => [r.place_id, r.level]));
const love = async () => (await db.query('select private.place_love($1) as n', [cafe])).rows[0].n;

test('the cloud role rates, and reads what was rated before today', async () => {
  assert.equal(await save('watch', rating(cafe, 4), rating(church, 3)), 2);
  assert.deepEqual(await levels(), { [cafe]: 4, [church]: 3 });
  const now = () => as('watch', 'select public.place_ratings_now() as r').then((r) => r[0].r);
  assert.deepEqual(await now(), {}, "today's round is not yet what came before");
  await save('watch', rating(cafe, 5));
  assert.equal((await db.query(`select count(*)::int as n from private.place_ratings where place_id = '${cafe}'`)).rows[0].n, 1,
    'rated twice in one day, the second stays');
  await db.exec(`update private.place_ratings set rated_at = now() - interval '30 days'`);
  assert.equal((await now())[cafe].level, 5);
  await save('watch', rating(cafe, 4));
  assert.equal((await now())[cafe].level, 5, 'the round before today');
  assert.equal((await levels())[cafe], 4, 'the newest counts');
  assert.equal((await db.query(`select count(*)::int as n from private.place_ratings where place_id = '${cafe}'`)).rows[0].n, 2, 'the old one is history');
});

test('nobody in the app reads or writes a rating: signed out, signed in, or who runs the Place', async () => {
  for (const [role, sub] of [['anon', null], ['authenticated', ann], ['authenticated', host]]) {
    for (const sql of ['select * from private.place_ratings', 'select * from private.place_levels', 'select public.place_facts()',
      'select public.place_ratings_now()', `select public.save_place_ratings('[]')`, `select private.place_love('${cafe}')`]) {
      await assert.rejects(as(role, sql, [], sub), /permission denied/, `${role}: ${sql}`);
    }
  }
  for (const sql of ['select * from private.place_ratings', 'select * from private.place_levels', 'delete from private.place_ratings']) {
    await assert.rejects(as('watch', sql), /permission denied/, `watch: ${sql}`);
  }
});

test('a rating needs both proofs and a level from 1 to 5, and one not sure is never a 1 or a 5', async () => {
  await assert.rejects(save('watch', rating(cafe, 3, { b: { level: 3, sure: true, proof: ' ' } })), /check constraint/);
  await assert.rejects(save('watch', rating(cafe, 6)), /check constraint/);
  await assert.rejects(save('watch', rating(cafe, 5, { sure: false })), /check constraint/);
  await assert.rejects(save('watch', rating(cafe, 1, { sure: false })), /check constraint/);
});

test('a Place that closes drops out at once, and cannot be rated', async () => {
  await db.exec(`update public.places set closed_at = now() where id = '${church}'`);
  assert.equal((await levels())[church], undefined);
  assert.equal(await save('watch', rating(church, 5)), 0);
  await db.exec(`update public.places set closed_at = null where id = '${church}'`);
});

test("love counts people: one person's many taps once, a guest's and the poster's none, a look none", async () => {
  assert.equal(await love(), 0);
  await db.exec(`
    insert into public.event_likes (event_id, user_id) values ('${night}', '${ann}'), ('${night}', '${guest}'), ('${night}', '${host}');
    insert into public.event_rsvps (event_id, user_id) values ('${night}', '${ann}');
    insert into public.town_follows (follower_id, target_type, target_id) values ('${ann}', 'place', '${cafe}');
    insert into public.feed_actions (user_id, item_id, action) values ('${bo}', '${night}', 'open'), ('${bo}', '${night}', 'view');
  `);
  assert.equal(await love(), 1, 'Ann, once');
  await db.exec(`insert into public.news_likes (user_id, item_id) values ('${bo}', '${story}')`);
  assert.equal(await love(), 2, 'and Bo, for a heart on its News');
  await db.exec(`update public.news_likes set created_at = now() - interval '40 days'`);
  assert.equal(await love(), 1, 'a month later it no longer counts');
});

test('the facts name every open Place, with its Events and News and no rating', async () => {
  const facts = (await as('watch', 'select public.place_facts() as f'))[0].f;
  const its = Object.fromEntries(facts.map((f) => [f.id, f]));
  assert.deepEqual(its[cafe].events, [{ title: 'Trivia', dates: 1, importance: 3, upcoming: true }]);
  assert.deepEqual([its[cafe].news.length, its[cafe].follows, its[cafe].love], [1, 1, 1]);
  assert.deepEqual([its[church].events, its[church].news, its[church].love], [[], [], 0]);
  assert.ok(!facts.some((f) => 'level' in f || 'judged' in f));
});
