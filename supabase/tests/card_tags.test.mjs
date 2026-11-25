// Fixed stories for the cards' hidden tags (supabase/migrations/*_card_tags.sql, BP app feed-learns 03): the cloud's role
// tags Events and News from one list, and nobody in the app reads or writes a tag.
// Run: `npm install && npm test` in this folder.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { people, realDatabase } from './fixture.mjs';
import { townDay } from './town_day.mjs';

const db = await realDatabase();
const uuid = (n) => `00000000-0000-0000-0000-${String(n).padStart(12, '0')}`;
const ann = uuid(11);
const [reading, past, post, off, story, old] = [uuid(21), uuid(22), uuid(23), uuid(24), uuid(31), uuid(32)];
await people(db, ann);
await db.exec(`
  insert into public.club_events (id, title, status, kind, event_date, source_name, location, description, cancelled_at, submitted_by) values
    ('${reading}', 'Poetry reading', 'approved', 'event', '${townDay(3)}', 'CSB', 'Gorecki', 'A  poet\nreads.', null, null),
    ('${past}', 'Old reading', 'approved', 'event', '${townDay(-3)}', 'CSB', null, null, null, null),
    ('${off}', 'Called off', 'approved', 'event', '${townDay(3)}', 'CSB', null, null, now(), null),
    ('${post}', 'My poem', 'approved', 'post', null, null, null, null, null, '${ann}');
  insert into public.board_items (id, title, blurb, category, source_name, status, tier, published_at, created_at) values
    ('${story}', 'New soup', 'Soup.', 'business', 'Cafe', 'published', 1, now(), now()),
    ('${old}', 'Old soup', 'Soup.', 'business', 'Cafe', 'published', 1, now() - interval '31 days', now() - interval '31 days');
`);
const as = async (role, sql, params = [], sub = null) => {
  await db.exec(`discard plans; set role ${role}`);
  if (sub) await db.exec(`set request.jwt.claims = '${JSON.stringify({ sub, role })}'`);
  try { return (await db.query(sql, params)).rows; } finally { await db.exec('reset role; reset request.jwt.claims'); }
};
const work = () => as('watch', 'select public.tag_work() as r').then((r) => r[0].r);
const word = (w, more = {}) => ({ word: w, first_by: 'card-tag.md', second_by: 'new-tag.md', ...more });
const save = (words, cards) => as('watch', 'select public.save_card_tags($1, $2) as r', [JSON.stringify(words), JSON.stringify(cards)])
  .then((r) => r[0].r);
const tagsOf = async (id) => (await db.query('select words from private.card_tags where event_id = $1 or news_id = $1', [id])).rows[0]?.words;

test('the work is the upcoming Events and the last month of News, never a post', async () => {
  const w = await work();
  assert.deepEqual(w.words, []);
  assert.deepEqual(w.events.map((e) => e.id), [reading], 'not the past one, the called-off one or the post');
  assert.deepEqual([w.events[0].host, w.events[0].place, w.events[0].about], ['CSB', 'Gorecki', 'A poet reads.']);
  assert.deepEqual(w.news.map((n) => n.id), [story]);
});

test('a card keeps only words on the list, as the list spells them, once each and in order', async () => {
  const got = await save([word('poetry'), word("Saint John's")], [
    { kind: 'event', id: reading, words: ["saint john's", 'Poetry', 'poetry', 'never agreed'] },
    { kind: 'news', id: story, words: ['poetry'] },
    { kind: 'event', id: past, words: ['never agreed'] },
  ]);
  assert.deepEqual(got, { words: 2, events: 2, news: 1, list: 2 });
  assert.deepEqual(await tagsOf(reading), ["Saint John's", 'poetry']);
  assert.deepEqual(await tagsOf(story), ['poetry']);
  assert.deepEqual(await tagsOf(past), [], 'a card with no word on the list is done, with none');
  const w = await work();
  assert.deepEqual([w.words, w.events, w.news], [['poetry', "Saint John's"], [], []], 'tagged once, it is done');
});

test('a word is never on the list twice, in any spelling, and never with one agent', async () => {
  assert.equal((await save([word('POETRY'), word('polka')], [])).words, 1);
  assert.deepEqual((await work()).words, ['poetry', 'polka', "Saint John's"]);
  await assert.rejects(save([word('jazz', { second_by: 'card-tag.md' })], []), /check constraint/, 'one agent twice');
  await assert.rejects(save([word('jazz', { second_by: null })], []), /not-null/);
  for (const bad of ['#jazz', 'two  spaces', ' jazz', 'a'.repeat(31), 'jazz; drop', '']) {
    await assert.rejects(save([word(bad)], []), /check constraint/, bad);
  }
});

test('a card tagged again takes the new words, and one that goes takes its tags with it', async () => {
  await save([], [{ kind: 'event', id: reading, words: ['polka'] }]);
  assert.deepEqual(await tagsOf(reading), ['polka']);
  await db.exec(`delete from public.club_events where id = '${reading}'`);
  assert.equal(await tagsOf(reading), undefined);
});

test('a post gets no tag, named as either kind', async () => {
  const got = await save([], [{ kind: 'event', id: post, words: ['polka'] }, { kind: 'news', id: post, words: ['polka'] }]);
  assert.deepEqual([got.events, got.news], [0, 0]);
});

test('nobody in the app reads or writes a tag, signed out or in, and the cloud only through its two functions', async () => {
  for (const [role, sub] of [['anon', null], ['authenticated', ann]]) {
    for (const sql of ['select * from private.tags', 'select * from private.card_tags', 'select public.tag_work()',
      `select public.save_card_tags('[]', '[]')`]) {
      await assert.rejects(as(role, sql, [], sub), /permission denied/, `${role}: ${sql}`);
    }
  }
  for (const sql of ['select * from private.tags', 'select * from private.card_tags', 'delete from private.card_tags',
    `insert into private.tags values ('x1', now(), 'a', 'b')`]) {
    await assert.rejects(as('watch', sql), /permission denied/, `watch: ${sql}`);
  }
});
