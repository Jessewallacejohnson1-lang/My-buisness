// The Review queue shows what each item is and why it waits (supabase/migrations/*_review_queue_details.sql,
// BP app launch-ready 07): list_held() and list_reports() send each item's Event card and its poster, to the admin
// alone. Run: `npm test` in this folder.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { realDatabase, people, adminClaims } from './fixture.mjs';

const db = await realDatabase();
const ADMIN = await adminClaims(db);
const [MAYA, YOU] = ['00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-0000000000e2'];
const PHOTO = `https://lxdgwhvqjqmqliobwjpi.supabase.co/storage/v1/object/public/avatars/${MAYA}/me.jpg`;

async function reset() {
  await db.exec(`reset role; reset request.jwt.claims; reset request.jwt.claim.sub;
                 delete from public.reports; delete from public.club_events; delete from public.town_profiles;`);
  await people(db, MAYA, YOU);
  await db.query(`insert into public.town_profiles (user_id, display_name, avatar_url) values ($1, ' Maya ', $2)`,
    [MAYA, PHOTO]);
}

async function add(title, more = {}) {
  const row = { kind: 'event', event_date: '2026-11-10', start_time: '6:30 PM', status: 'pending', submitted_by: null,
                source_name: null, description: null, checked_at: null, created_at: '2026-11-07 12:00-06', ...more };
  const { rows } = await db.query(
    `insert into public.club_events (title, kind, event_date, start_time, status, submitted_by, source_name, description,
       checked_at, created_at)
     values ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10) returning id`,
    [title, row.kind, row.event_date, row.start_time, row.status, row.submitted_by, row.source_name, row.description,
     row.checked_at, row.created_at]);
  return rows[0].id;
}

const asAdmin = () => db.exec(`reset role; set request.jwt.claims = '${ADMIN}'; set role authenticated`);
const asNeighbour = () => db.exec(`reset role; reset request.jwt.claims;
  set request.jwt.claims = '${JSON.stringify({ sub: YOU, role: 'authenticated' })}'; set role authenticated`);
const held = async () => (await db.query('select * from public.list_held()')).rows;
const reported = async () => (await db.query('select * from public.list_reports()')).rows;

test("a neighbour's held post comes with its words, its poster and whether the check was asked", async () => {
  await reset();
  await add('Bingo night', { submitted_by: MAYA, description: 'Bring a friend', checked_at: '2026-11-07 13:00-06' });
  await add('Leaf raking', { submitted_by: MAYA, event_date: '2026-11-08' });
  await asAdmin();
  const rows = await held();
  assert.deepEqual(rows.map((r) => [r.card.title, r.checked_at !== null]), [['Leaf raking', false], ['Bingo night', true]]);
  const bingo = rows[1];
  assert.equal(bingo.kind, 'event');
  assert.equal(bingo.card.description, 'Bring a friend');
  assert.equal(bingo.card.event_date, '2026-11-10');
  assert.deepEqual([bingo.poster.name, bingo.poster.photo], ['Maya', PHOTO]);
});

test('a found Event that waits has its host and no poster', async () => {
  await reset();
  await add('Fare for All', { source_name: 'City of St. Joseph' });
  await asAdmin();
  const [row] = await held();
  assert.equal(row.card.source_name, 'City of St. Joseph');
  assert.equal(row.poster, null);
});

test('an everyday post has no date and still comes back, last, with its words and poster', async () => {
  await reset();
  await add('Lost cat on 3rd Ave', { kind: 'post', event_date: null, start_time: null, submitted_by: MAYA });
  await add('Bingo night', { submitted_by: MAYA });
  await asAdmin();
  const rows = await held();
  assert.deepEqual(rows.map((r) => [r.kind, r.card.title, r.card.event_date]),
    [['event', 'Bingo night', '2026-11-10'], ['post', 'Lost cat on 3rd Ave', null]]);
  assert.equal(rows[1].poster.name, 'Maya');
});

test("a deleted poster's post still waits, with no poster", async () => {
  await reset();
  await add('Bingo night', { submitted_by: MAYA });
  await db.query('delete from public.town_profiles where user_id = $1', [MAYA]);
  await asAdmin();
  const [row] = await held();
  assert.equal(row.card.title, 'Bingo night');
  assert.equal(row.poster, null);
});

test('a reported Event comes with its card, its poster, how many reports and when the first came', async () => {
  await reset();
  const fair = await add('Craft fair', { status: 'approved', submitted_by: MAYA, description: 'Local makers' });
  await db.query(`insert into public.reports (event_id, reason, at) values
                  ($1, 'wrong_info', '2026-10-26 09:00-05'), ($1, 'scam', '2026-10-27 09:00-05')`, [fair]);
  await asAdmin();
  const [row] = await reported();
  assert.deepEqual([row.title, row.reasons, row.reports], ['Craft fair', ['scam', 'wrong_info'], 2]);
  assert.equal(row.first_at.toISOString(), '2026-10-26T14:00:00.000Z');
  assert.equal(row.card.description, 'Local makers');
  assert.equal(row.poster.name, 'Maya');
});

test('only the admin gets anything: a neighbour gets none, and signed out may not ask', async () => {
  await reset();
  const fair = await add('Craft fair', { status: 'approved' });
  await add('Bingo night', { submitted_by: MAYA });
  await db.query(`insert into public.reports (event_id, reason) values ($1, 'scam')`, [fair]);
  await asNeighbour();
  assert.deepEqual(await held(), []);
  assert.deepEqual(await reported(), []);
  await db.exec('reset role; reset request.jwt.claims; set role anon');
  await assert.rejects(held(), /permission denied/);
  await assert.rejects(reported(), /permission denied/);
  await db.exec('reset role');
});
