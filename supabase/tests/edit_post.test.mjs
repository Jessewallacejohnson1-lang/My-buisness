// Fixed stories for editing a post (supabase/migrations/*_edit_post.sql, BP app town-feed 44): the check claims an
// edit only on the poster's own live post, 10 a day, keeping what it replaced; a yes writes the words, the Place and
// the kept @ names and nothing else; the poster can't write a live post directly. Run in PGlite:
// `npm install && npm test` in this folder.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { realDatabase, people } from './fixture.mjs';

const db = await realDatabase();
const ME = '00000000-0000-0000-0000-0000000000b2';
const PAL = '00000000-0000-0000-0000-0000000000d4';
const YOU = '00000000-0000-0000-0000-0000000000c3';
const HABIT = '00000000-0000-0000-0000-00000000aa01';
const PHOTO = `https://lxdgwhvqjqmqliobwjpi.supabase.co/storage/v1/object/public/event-images/${ME}/abc.jpg`;
await people(db, ME, PAL, YOU);
await db.query(`insert into public.town_profiles (user_id, display_name) values ($1, 'Avery Lund'), ($2, 'Sam Lee'), ($3, 'Ana Nguyen')`,
               [ME, PAL, YOU]);
await db.query(`insert into public.places (id, name, lat, lon, family, entry_id) values
  ($1, 'Bad Habit Brewing Company', 45.56, -94.32, 'food', 'bad-habit')`, [HABIT]);
await db.exec(`insert into private.friendships (a, b, requested_by) values ('${[ME, PAL].sort().join("', '")}', '${ME}')`);
let n = 0;

/** A post of `who`'s, live unless `extra` says, with its words. */
async function posted(who, words, extra = {}) {
  await db.exec('reset role');
  const id = `00000000-0000-0000-0000-${String(++n).padStart(12, '0')}`;
  const row = { id, submitted_by: who, category: 'other', kind: 'post', title: words, status: 'approved',
                location: 'St. Joseph Farmers Market', friends_only: false, tagged: [PAL], image_url: PHOTO,
                image_aspect: 1.49, checked_at: new Date().toISOString(), ...extra };
  const cols = Object.keys(row);
  await db.query(`insert into public.club_events (${cols.join(', ')}) values (${cols.map((_, i) => `$${i + 1}`).join(', ')})`,
                 Object.values(row));
  return id;
}
const claim = async (id, who, words, place = 'St. Joseph Farmers Market') => { await db.exec('reset role');
  return (await db.query(`select public.claim_edit($1, $2, $3, $4) as r`, [id, who, words, place])).rows[0].r; };
const apply = async (id, who, words, place, names = null) => { await db.exec('reset role');
  return (await db.query(`select public.apply_post_edit($1, $2, $3, $4, $5) as r`,
                         [id, who, words, place, names === null ? null : JSON.stringify(names)])).rows[0].r; };
const row = async (id) => { await db.exec('reset role');
  return (await db.query(`select title, location, at_names, image_url, image_aspect, friends_only, tagged, status, kind
                          from public.club_events where id = $1`, [id])).rows[0]; };
const forget = async () => { await db.exec('reset role'); await db.exec('delete from private.post_edit_checks'); };

test('the check claims an edit of your own live post, and keeps the words and Place it replaces', async () => {
  await forget();
  const id = await posted(ME, 'Farmers market was packed this moring.');
  assert.equal(await claim(id, ME, 'Farmers market was packed this morning.', 'Centennial Park'), 'claimed');
  const log = (await db.query(`select user_id, event_id, old_title, old_location from private.post_edit_checks`)).rows;
  assert.deepEqual(log, [{ user_id: ME, event_id: id, old_title: 'Farmers market was packed this moring.',
                           old_location: 'St. Joseph Farmers Market' }]);
});

test('someone else\'s post, a post waiting or turned down, and an Event are refused', async () => {
  await forget();
  assert.equal(await claim(await posted(YOU, 'Not mine'), ME, 'Mine now'), 'refused');
  assert.equal(await claim(await posted(ME, 'Waiting', { status: 'pending' }), ME, 'Changed'), 'refused');
  assert.equal(await claim(await posted(ME, 'Declined', { status: 'rejected' }), ME, 'Changed'), 'refused');
  assert.equal(await claim(await posted(ME, 'Porch concert', { kind: 'event', event_date: '2026-12-05', tagged: null,
                                                               start_time: '19:00' }), ME, 'Changed'), 'refused');
  assert.equal(Number((await db.query('select count(*) as c from private.post_edit_checks')).rows[0].c), 0, 'a refusal costs nothing');
});

test('words over 2,000, a Place over 120, and no words on a post with no photo are refused', async () => {
  await forget();
  const id = await posted(ME, 'Hello');
  assert.equal(await claim(id, ME, 'x'.repeat(2001)), 'refused');
  assert.equal(await claim(id, ME, 'Hello there', 'p'.repeat(121)), 'refused');
  assert.equal(await claim(await posted(ME, 'Words only', { image_url: null, image_aspect: null }), ME, '   '), 'refused');
  assert.equal(await claim(id, ME, ''), 'claimed', 'a photo post may lose all its words');
});

test('an 11th edit check in a day is the limit, for that person only', async () => {
  await forget();
  const id = await posted(ME, 'Ten tries');
  for (let i = 0; i < 10; i++) assert.equal(await claim(id, ME, `Try ${i}`), 'claimed');
  assert.equal(await claim(id, ME, 'Try 10'), 'limit');
  assert.equal(await claim(await posted(PAL, 'Mine'), PAL, 'Mine, edited'), 'claimed');
  await db.exec(`update private.post_edit_checks set at = now() - interval '25 hours'`);
  assert.equal(await claim(id, ME, 'Next day'), 'claimed');
});

test('a yes writes the words, the Place and the kept names, and nothing else moves', async () => {
  const id = await posted(ME, 'Old words');
  const before = await row(id);
  assert.equal(await apply(id, ME, 'Pint night at @Bad Habit Brewing with @Sam Lee and @Ana Nguyen', 'Bad Habit Brewing',
    [{ kind: 'place', id: HABIT, name: 'Bad Habit Brewing' }, { kind: 'user', id: PAL, name: 'Sam Lee' },
     { kind: 'user', id: YOU, name: 'Ana Nguyen' }]), true);
  const after = await row(id);
  assert.equal(after.title, 'Pint night at @Bad Habit Brewing with @Sam Lee and @Ana Nguyen');
  assert.equal(after.location, 'Bad Habit Brewing');
  assert.deepEqual(after.at_names, [{ kind: 'place', id: HABIT, name: 'Bad Habit Brewing' }, { kind: 'user', id: PAL, name: 'Sam Lee' }],
                   'a stranger\'s name is dropped, as a new post\'s is');
  for (const k of ['image_url', 'image_aspect', 'friends_only', 'tagged', 'status', 'kind']) {
    assert.deepEqual(after[k], before[k], `${k} stays`);
  }
});

test('a blank Place clears it; a post gone mid-check changes nothing', async () => {
  const id = await posted(ME, 'Somewhere');
  assert.equal(await apply(id, ME, 'Nowhere now', '  '), true);
  assert.equal((await row(id)).location, null);
  const gone = await posted(ME, 'Going away');
  await db.query('delete from public.club_events where id = $1', [gone]);
  assert.equal(await apply(gone, ME, 'Too late', 'Centennial Park'), false);
  const reported = await posted(ME, 'Taken down');
  await db.query(`update public.club_events set status = 'rejected', review_reason = 'reported' where id = $1`, [reported]);
  assert.equal(await apply(reported, ME, 'Sneaky', null), false);
  assert.equal((await row(reported)).title, 'Taken down');
  assert.equal(await apply(await posted(YOU, 'Theirs'), ME, 'Mine', null), false);
});

test('only the check may call either; the poster can\'t write a live post\'s words, photo or audience', async () => {
  const id = await posted(ME, 'Hands off');
  await db.exec('reset role; set role authenticated');
  await db.query(`select set_config('request.jwt.claims', $1, false)`, [JSON.stringify({ sub: ME, role: 'authenticated' })]);
  await assert.rejects(db.query(`select public.claim_edit($1, $2, 'x', null)`, [id, ME]), /permission denied/);
  await assert.rejects(db.query(`select public.apply_post_edit($1, $2, 'x', null, null)`, [id, ME]), /permission denied/);
  await db.query(`update public.club_events set title = 'Changed', image_url = null, friends_only = true where id = $1`, [id]);
  const after = await row(id);
  assert.equal(after.title, 'Hands off');
  assert.equal(after.image_url, PHOTO);
  assert.equal(after.friends_only, false);
});
