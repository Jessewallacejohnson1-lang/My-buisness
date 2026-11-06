// Fixed stories for clear_account_rows, the rows half of Settings' Delete account (BP app docs/plans/launch-ready,
// ticket 01; the files and the account itself are the delete-account edge function's). Run in PGlite: `npm test`.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { realDatabase } from './fixture.mjs';

const db = await realDatabase();
const LEAVING = '00000000-0000-0000-0000-00000000000a';
const NEIGHBOR = '00000000-0000-0000-0000-00000000000b';
const id = (n) => `00000000-0000-0000-0000-0000000000${n}`;
const POST = id('e1');
const PENDING = id('e2');
const ALONE = id('e3');
const OTHERS = id('e4');
const PAST = id('e5');
const THEIRS = id('e6');
const FOUND = id('e7');
const PHOTO = 'https://example.test/event-images/a/photo.jpg';

async function reset() {
  await db.exec(`delete from private.chat_reports; delete from public.club_events; delete from auth.users;
    insert into auth.users (id) values ('${LEAVING}'), ('${NEIGHBOR}');
    insert into public.town_profiles (user_id, display_name) values ('${LEAVING}', 'Avery'), ('${NEIGHBOR}', 'Blake');
    insert into public.club_events (id, title, status, kind, submitted_by, event_date, image_url) values
      ('${POST}', 'my words', 'approved', 'post', '${LEAVING}', null, '${PHOTO}'),
      ('${PENDING}', 'Waiting', 'pending', 'event', '${LEAVING}', current_date + 7, '${PHOTO}'),
      ('${ALONE}', 'Only me', 'approved', 'event', '${LEAVING}', current_date + 7, '${PHOTO}'),
      ('${OTHERS}', 'Block party', 'approved', 'event', '${LEAVING}', current_date + 7, '${PHOTO}'),
      ('${PAST}', 'Last week', 'approved', 'event', '${LEAVING}', current_date - 7, '${PHOTO}'),
      ('${THEIRS}', 'Blake''s picnic', 'approved', 'event', '${NEIGHBOR}', current_date + 7, '${PHOTO}'),
      ('${FOUND}', 'Found at the library', 'approved', 'event', null, current_date + 7, '${PHOTO}');
    insert into public.event_rsvps (event_id, user_id) values
      ('${ALONE}', '${LEAVING}'),
      ('${OTHERS}', '${LEAVING}'), ('${OTHERS}', '${NEIGHBOR}'),
      ('${PAST}', '${NEIGHBOR}'),
      ('${THEIRS}', '${LEAVING}'), ('${THEIRS}', '${NEIGHBOR}');
    insert into public.event_likes (event_id, user_id) values ('${POST}', '${NEIGHBOR}');`);
}

async function as(role, sub, sql) {
  await db.exec(`set role ${role}; select set_config('request.jwt.claims', '${sub ? JSON.stringify({ sub }) : ''}', false);`);
  try { return await db.query(sql); } finally { await db.exec('reset role;'); }
}

const clear = () => as('service_role', null, `select public.clear_account_rows('${LEAVING}') keep`);
const events = async () => (await db.query(
  'select id, submitted_by, cancelled_at is not null as cancelled, image_url from public.club_events order by id')).rows;

test("their posts and Events go, except an upcoming Event others are Going to; nobody else's is touched", async () => {
  await reset();
  await clear();
  const left = await events();
  assert.deepEqual(left.map((e) => e.id), [OTHERS, THEIRS, FOUND]);
  const [kept, theirs, found] = left;
  assert.equal(kept.cancelled, true);
  assert.equal(kept.image_url, null, 'its photo file is about to go, so the card must not point at it');
  for (const e of [theirs, found]) {
    assert.equal(e.cancelled, false);
    assert.equal(e.image_url, PHOTO);
  }
});

test('once the account goes, the kept Event has no author and the people Going are told it was canceled', async () => {
  await reset();
  await clear();
  await db.exec(`delete from auth.users where id = '${LEAVING}'`);
  const left = await events();
  assert.equal(left.find((e) => e.id === OTHERS).submitted_by, null);
  const told = (await as('authenticated', NEIGHBOR, 'select card from public.get_my_changes()')).rows;
  assert.deepEqual(told.map((r) => r.card.id), [OTHERS]);
});

test('their Going leaves the counts of Events they were Going to', async () => {
  await reset();
  await clear();
  await db.exec(`delete from auth.users where id = '${LEAVING}'`);
  const going = (await db.query(`select user_id from public.event_rsvps where event_id = '${THEIRS}'`)).rows;
  assert.deepEqual(going.map((r) => r.user_id), [NEIGHBOR]);
});

test('it names only their own photos in a chat report still open, so those files stay', async () => {
  await reset();
  await db.exec(`insert into private.chat_reports (sender_name, kind, photo_path, reason, resolved_at) values
    ('Avery', 'photo', '${LEAVING}/open.jpg', 'bullying', null),
    ('Avery', 'photo', '${LEAVING}/settled.jpg', 'scam', now()),
    ('Avery', 'text', null, 'scam', null),
    ('Blake', 'photo', '${NEIGHBOR}/other.jpg', 'violence', null)`);
  const { rows } = await clear();
  assert.deepEqual(rows[0].keep, [`${LEAVING}/open.jpg`]);
});

test('running it twice is safe, so a retry can finish a delete that stopped partway', async () => {
  await reset();
  await clear();
  const once = await events();
  await clear();
  assert.deepEqual((await events()).map((e) => [e.id, e.cancelled]), once.map((e) => [e.id, e.cancelled]));
});

test('only the edge function can call it', async () => {
  await reset();
  await assert.rejects(as('authenticated', LEAVING, `select public.clear_account_rows('${LEAVING}')`), /permission denied/);
  await assert.rejects(as('authenticated', NEIGHBOR, `select public.clear_account_rows('${LEAVING}')`), /permission denied/);
  await assert.rejects(as('anon', null, `select public.clear_account_rows('${LEAVING}')`), /permission denied/);
  assert.equal((await events()).length, 7);
});
