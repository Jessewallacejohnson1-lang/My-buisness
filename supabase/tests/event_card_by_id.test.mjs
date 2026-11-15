// Fixed stories for get_event_card (supabase/migrations/*_event_card_by_id.sql, BP app inside-cards 29): the bell's
// "Your event is live" door reads your own just-posted Event's card by its id. Run: `npm install && npm test` here.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { realDatabase, people } from './fixture.mjs';
import { CARD_KEYS } from './event_card.mjs';

const db = await realDatabase();
const ME = '00000000-0000-0000-0000-00000000000a';
const NEIGHBOUR = '00000000-0000-0000-0000-00000000000b';

async function reset() {
  await db.exec(`reset role; delete from public.event_likes; delete from public.event_rsvps;
                 delete from public.club_events; delete from public.town_profiles; delete from auth.users;
                 reset request.jwt.claim.sub;`);
  await people(db, ME, NEIGHBOUR);
}

async function post(title, more = {}) {
  const row = { by: ME, status: 'approved', kind: 'event', ...more };
  const { rows } = await db.query(
    `insert into public.club_events (title, event_date, status, kind, submitted_by)
     values ($1, current_date + 30, $2, $3, $4) returning id`,
    [title, row.status, row.kind, row.by]);
  return rows[0].id;
}

async function card(id, as = ME) {
  await db.exec(`set role authenticated; set request.jwt.claim.sub = '${as}'`);
  const { rows } = await db.query('select card from public.get_event_card($1)', [id]);
  await db.exec('reset role');
  return rows.map((r) => r.card);
}

test('your own Event a month out comes back as its whole card, your heart and its count in it', async () => {
  await reset();
  const party = await post('Block party on 2nd Ave');
  await db.query('insert into public.event_likes (event_id, user_id) values ($1, $2), ($1, $3)', [party, ME, NEIGHBOUR]);
  const [mine] = await card(party);
  assert.deepEqual(Object.keys(mine).sort(), CARD_KEYS);
  assert.equal(mine.title, 'Block party on 2nd Ave');
  assert.equal(mine.hearted, true);
  assert.equal(mine.heart_count, 2);
});

test('someone else\'s Event, one waiting for Review, and a post are never sent', async () => {
  await reset();
  const theirs = await post('Their garage sale', { by: NEIGHBOUR });
  const waiting = await post('Waiting for Review', { status: 'pending' });
  const words = await post('Just words', { kind: 'post' });
  for (const id of [theirs, waiting, words]) assert.deepEqual(await card(id), []);
  assert.deepEqual(await card(theirs, NEIGHBOUR).then((c) => c.length), 1);
});

test('signed out, the read is refused', async () => {
  await reset();
  const party = await post('Block party on 2nd Ave');
  await db.exec('set role anon');
  await assert.rejects(db.query('select card from public.get_event_card($1)', [party]), /permission denied/);
  await db.exec('reset role');
});
