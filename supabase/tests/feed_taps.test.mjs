// Fixed stories for every tap on a card (supabase/migrations/*_feed_taps.sql, BP app docs/plans/feed-learns, ticket 02),
// run in PGlite: the four new kinds go in as the app sends them, once per person, item, kind and Town day; News's go in
// news_actions; a row whose item has gone is skipped, never the batch. Run: `npm test` in this folder.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { realDatabase, people } from './fixture.mjs';

const [ANNA, BEN] = ['a', 'b'].map((x) => `00000000-0000-0000-0000-00000000000${x}`);
const [FAIR, POST, GONE] = ['1', '2', '3'].map((x) => `00000000-0000-0000-0000-00000000010${x}`);
const [STORY, OLD_STORY] = ['1', '2'].map((x) => `00000000-0000-0000-0000-00000000020${x}`);
const db = await realDatabase();
await people(db, ANNA, BEN);
await db.exec(`insert into public.club_events (id, title, kind) values ('${FAIR}', 'Fair', 'event'), ('${POST}', 'Hi', 'post');
               insert into public.board_items (id, title, category, source_name)
                 values ('${STORY}', 'New menu', 'business', 'The Cow')`);

// One batch as the app sends it: signed in, only the item and the kind, in one insert.
async function send(who, table, rows) {
  await db.exec(`set role authenticated; set request.jwt.claim.sub = '${who}'`);
  try {
    await db.query(`insert into public.${table} (item_id, action) select * from unnest($1::uuid[], $2::text[])`,
      [rows.map((r) => r[0]), rows.map((r) => r[1])]);
  } finally {
    await db.exec('reset role; reset request.jwt.claim.sub');
  }
}
const saved = async (table) => (await db.query(`select user_id, item_id, action from public.${table} order by at, action`))
  .rows.map((r) => [r.user_id, r.item_id, r.action]);
const clear = () => db.exec('delete from public.feed_actions; delete from public.news_actions');

test('the four new taps on an Event and a post are saved once a Town day each', async () => {
  await clear();
  await send(ANNA, 'feed_actions', [[FAIR, 'photo'], [FAIR, 'photo'], [FAIR, 'place'], [FAIR, 'map'], [FAIR, 'link'],
                                    [POST, 'photo'], [POST, 'place'], [FAIR, 'view']]);
  await send(ANNA, 'feed_actions', [[FAIR, 'map'], [POST, 'photo']]);
  assert.deepEqual((await saved('feed_actions')).sort(), [
    [ANNA, FAIR, 'link'], [ANNA, FAIR, 'map'], [ANNA, FAIR, 'photo'], [ANNA, FAIR, 'place'], [ANNA, FAIR, 'view'],
    [ANNA, POST, 'photo'], [ANNA, POST, 'place'],
  ]);
});

test('the next Town day saves the same tap again', async () => {
  await clear();
  await db.query(`insert into public.feed_actions (user_id, item_id, action, at) values ($1, $2, 'map', '2026-10-30 23:30-05')`,
    [ANNA, FAIR]);
  await db.query(`insert into public.feed_actions (user_id, item_id, action, at) values ($1, $2, 'map', '2026-10-31 00:10-05')`,
    [ANNA, FAIR]);
  assert.equal((await saved('feed_actions')).length, 2);
});

test('a tap on an Event or post that has gone is skipped, and the rest of the batch still lands', async () => {
  await clear();
  await send(ANNA, 'feed_actions', [[GONE, 'link'], [FAIR, 'view'], [FAIR, 'link']]);
  assert.deepEqual((await saved('feed_actions')).sort(), [[ANNA, FAIR, 'link'], [ANNA, FAIR, 'view']]);
});

test("News opens and taps go in news_actions, once a Town day each, a gone story's skipped", async () => {
  await clear();
  await send(ANNA, 'news_actions', [[STORY, 'open'], [STORY, 'photo'], [STORY, 'photo'], [STORY, 'place'],
                                    [STORY, 'link'], [OLD_STORY, 'open']]);
  await send(BEN, 'news_actions', [[STORY, 'open']]);
  await send(ANNA, 'news_actions', [[STORY, 'open']]);
  assert.deepEqual((await saved('news_actions')).sort(), [
    [ANNA, STORY, 'link'], [ANNA, STORY, 'open'], [ANNA, STORY, 'photo'], [ANNA, STORY, 'place'], [BEN, STORY, 'open'],
  ]);
});

test('a kind the table does not know is refused', async () => {
  await assert.rejects(send(ANNA, 'feed_actions', [[FAIR, 'stare']]), /feed_actions_action_check/);
  await assert.rejects(send(ANNA, 'news_actions', [[STORY, 'map']]), /news_actions_action_check/);
});

test('nobody reads news_actions through the API, nor writes as someone else or signed out', async () => {
  await clear();
  await send(ANNA, 'news_actions', [[STORY, 'open']]);
  await db.exec(`set role authenticated; set request.jwt.claim.sub = '${ANNA}'`);
  await assert.rejects(db.query('select * from public.news_actions'), /permission denied/, 'not even your own');
  await assert.rejects(db.query(`insert into public.news_actions (user_id, item_id, action) values ($1, $2, 'link')`,
    [BEN, STORY]), /permission denied/, "not in a neighbour's name");
  await db.exec('set role anon; reset request.jwt.claim.sub');
  await assert.rejects(db.query(`insert into public.news_actions (item_id, action) values ($1, 'link')`, [STORY]),
    /permission denied/, 'signed out');
  await db.exec('reset role');
});

test("an account's or a story's deletion takes its rows", async () => {
  await clear();
  await send(BEN, 'news_actions', [[STORY, 'open']]);
  await send(BEN, 'feed_actions', [[FAIR, 'link']]);
  await db.exec(`delete from auth.users where id = '${BEN}'`);
  assert.deepEqual([...await saved('news_actions'), ...await saved('feed_actions')], []);
  await people(db, BEN);
  await send(ANNA, 'news_actions', [[STORY, 'link']]);
  await db.exec(`delete from public.board_items where id = '${STORY}'`);
  assert.deepEqual(await saved('news_actions'), []);
});
