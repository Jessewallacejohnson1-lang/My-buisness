// A short note with a "Wrong info" report (supabase/migrations/*_report_note.sql, BP app backlog 26): the
// neighbour may say what's wrong; moderate-post reads the note once (claim_notes) before the admin sees it, and
// list_reports shows only the notes it kept, 3 at most, newest first. Who reported is never kept.
// Run: `npm test` in this folder.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { realDatabase, people, adminClaims } from './fixture.mjs';

const db = await realDatabase();
const ADMIN = await adminClaims(db);
const [YOU, QUIET] = ['00000000-0000-0000-0000-0000000000f1', '00000000-0000-0000-0000-0000000000f2'];

async function reset() {
  await db.exec(`reset role; reset request.jwt.claims; reset request.jwt.claim.sub;
                 delete from public.reports; delete from public.club_events;`);
  await people(db, YOU, QUIET);
  await db.query('update auth.users set is_anonymous = (id = $1)', [QUIET]);
}

async function found(title) {
  const { rows } = await db.query(
    `insert into public.club_events (title, kind, event_date, start_time, status, source_name)
     values ($1, 'event', '2026-11-16', '5:30 PM', 'approved', 'CSB SJU Campus Events') returning id`, [title]);
  return rows[0].id;
}

const as = (sub) => db.exec(`reset role; reset request.jwt.claims;
  set request.jwt.claims = '${JSON.stringify({ sub, role: 'authenticated' })}'; set role authenticated`);
const asAdmin = () => db.exec(`reset role; set request.jwt.claims = '${ADMIN}'; set role authenticated`);
const report = (event, reason, note) =>
  db.query('select public.report_event($1, $2, $3) as recheck', [event, reason, note]);
const kept = async () => (await db.exec('reset role'),
  (await db.query('select reason, note, note_ok from public.reports order by at, id')).rows);
const claim = async (event) => (await db.exec('reset role; set role service_role'),
  (await db.query('select * from public.claim_notes($1)', [event])).rows);
const notesShown = async () => (await asAdmin(), (await db.query('select * from public.list_reports()')).rows);

test('a Wrong info report keeps its note, trimmed and cut to 150 letters; an empty one keeps none', async () => {
  await reset();
  const chi = await found('Embodied Spirit Chi Kung');
  await as(YOU);
  await report(chi, 'wrong_info', '  Starts at 6 now, not 5:30  ');
  await report(chi, 'wrong_info', 'x'.repeat(200));
  await report(chi, 'wrong_info', '   ');
  // Reports made in the same instant have no order (their time is the key), so the stories compare them sorted.
  const rows = await kept();
  assert.deepEqual(rows.map((r) => r.note).sort(), ['Starts at 6 now, not 5:30', 'x'.repeat(150), null].sort());
  assert.ok(rows.every((r) => r.note_ok === null), 'nothing is checked yet');
});

test('only Wrong info carries a note, only from a real account, and at most 3 an Event', async () => {
  await reset();
  const chi = await found('Embodied Spirit Chi Kung');
  await as(YOU);
  await report(chi, 'scam', 'buy my stuff');
  await as(QUIET);
  await report(chi, 'wrong_info', 'from an account with no sign-in');
  await as(YOU);
  for (const n of ['one', 'two', 'three', 'four']) await report(chi, 'wrong_info', n);
  const rows = await kept();
  assert.deepEqual(rows.filter((r) => r.note).map((r) => r.note).sort(), ['one', 'three', 'two'], 'the fourth note is dropped');
  assert.deepEqual(rows.map((r) => r.reason).sort(), ['scam', 'wrong_info', 'wrong_info', 'wrong_info', 'wrong_info', 'wrong_info'],
    'every report still counts');
});

test("today's app still reports with two arguments", async () => {
  await reset();
  const chi = await found('Embodied Spirit Chi Kung');
  await as(YOU);
  await db.query(`select public.report_event(p_event => $1, p_reason => 'wrong_info')`, [chi]);
  assert.deepEqual((await kept()).map((r) => [r.reason, r.note]), [['wrong_info', null]]);
});

test('the check claims each note once, and only the service key may ask', async () => {
  await reset();
  const chi = await found('Embodied Spirit Chi Kung');
  await as(YOU);
  await report(chi, 'wrong_info', 'Starts at 6 now');
  await report(chi, 'scam', null);
  await assert.rejects(db.query('select * from public.claim_notes($1)', [chi]), /permission denied/);
  assert.deepEqual((await claim(chi)).map((r) => r.note), ['Starts at 6 now']);
  assert.deepEqual(await claim(chi), [], 'a retry or a second call pays nothing');
  assert.deepEqual((await kept()).map((r) => [r.reason, r.note_ok]).sort(), [['scam', null], ['wrong_info', false]]);
});

test('the queue shows only notes the check kept, the 3 newest first, and never to a neighbour', async () => {
  await reset();
  const chi = await found('Embodied Spirit Chi Kung');
  await db.query(`insert into public.reports (event_id, reason, note, note_ok, at) values
    ($1, 'wrong_info', 'oldest kept', true, '2026-11-10 09:00-06'),
    ($1, 'wrong_info', 'turned down', null, '2026-11-11 09:00-06'),
    ($1, 'wrong_info', 'claimed, no answer yet', false, '2026-11-12 09:00-06'),
    ($1, 'wrong_info', 'second kept', true, '2026-11-12 10:00-06'),
    ($1, 'wrong_info', 'newest kept', true, '2026-11-13 09:00-06'),
    ($1, 'wrong_info', 'third kept', true, '2026-11-12 11:00-06')`, [chi]);
  await db.query(`update public.reports set note = null where note = 'turned down'`);
  const [row] = await notesShown();
  assert.equal(row.reports, 6);
  assert.deepEqual(row.notes, ['newest kept', 'third kept', 'second kept']);
  await as(YOU);
  assert.deepEqual((await db.query('select * from public.list_reports()')).rows, []);
  await db.exec('reset role');
});

test('a report with no kept note shows none, and Keep takes the notes with the reports', async () => {
  await reset();
  const chi = await found('Embodied Spirit Chi Kung');
  await as(YOU);
  await report(chi, 'wrong_info', null);
  const [row] = await notesShown();
  assert.deepEqual(row.notes, []);
  await db.query('select public.resolve_reports($1, false)', [chi]);
  assert.deepEqual(await kept(), []);
});
