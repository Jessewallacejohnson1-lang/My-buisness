// Review shows an edited post's old words (supabase/migrations/*_review_old_words.sql, BP app backlog 29): when a
// reported post was edited after its first report, list_reports sends the words and Place as they stood then; an edit
// before the report, a refused edit that changed nothing, or no edit sends none. Run: `npm test` in this folder.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { realDatabase, people, adminClaims } from './fixture.mjs';

const db = await realDatabase();
const ADMIN = await adminClaims(db);
const [POSTER, YOU] = ['00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000a2'];
let n = 0;

async function reset() {
  await db.exec(`reset role; reset request.jwt.claims;
                 delete from private.post_edit_checks; delete from public.reports; delete from public.club_events;`);
  await people(db, POSTER, YOU);
}

/** A live post of POSTER's, with its words and Place. */
async function posted(words, place) {
  await db.exec('reset role');
  const id = `00000000-0000-0000-0000-${String(++n).padStart(12, '0')}`;
  await db.query(`insert into public.club_events (id, kind, title, location, submitted_by, status, category)
                  values ($1, 'post', $2, $3, $4, 'approved', 'other')`, [id, words, place, POSTER]);
  return id;
}
async function reported(id, at) {
  await db.exec('reset role');
  await db.query(`insert into public.reports (event_id, reason, at) values ($1, 'scam', $2)`, [id, at]);
}
/** An edit check at `at` (logged as claim_edit logs it), and the edit itself when the check said yes. */
async function edited(id, at, words, place, yes = true) {
  await db.exec('reset role');
  await db.query(`insert into private.post_edit_checks (user_id, event_id, at, old_title, old_location)
                  select submitted_by, id, $2, title, location from public.club_events where id = $1`, [id, at]);
  if (yes) await db.query('update public.club_events set title = $2, location = $3 where id = $1', [id, words, place]);
}
async function shown(id) {
  await db.exec(`reset role; set request.jwt.claims = '${ADMIN}'; set role authenticated`);
  const { rows } = await db.query('select title, was_title, was_place from public.list_reports() where event_id = $1', [id]);
  return rows[0];
}

test('a post edited after its report shows the words and Place that were reported', async () => {
  await reset();
  const id = await posted('BUY CHEAP FOLLOWERS NOW', 'Centennial Park');
  await reported(id, '2026-11-14T10:00:00Z');
  await edited(id, '2026-11-14T11:00:00Z', 'Farmers market was packed', 'Cloverdale Park');
  await edited(id, '2026-11-14T12:00:00Z', 'Farmers market was packed this morning', 'Cloverdale Park');
  assert.deepEqual(await shown(id), { title: 'Farmers market was packed this morning', was_title: 'BUY CHEAP FOLLOWERS NOW',
                                      was_place: 'Centennial Park' }, 'the first edit after the report holds what was reported');
});

test('a Place-only edit shows the reported words and Place; a blank Place comes back as none', async () => {
  await reset();
  const id = await posted('Porch lights are up', null);
  await reported(id, '2026-11-14T10:00:00Z');
  await edited(id, '2026-11-14T11:00:00Z', 'Porch lights are up', 'Millstream Park');
  assert.deepEqual(await shown(id), { title: 'Porch lights are up', was_title: 'Porch lights are up', was_place: null });
});

test('no edit, an edit before the report, or a refused edit shows nothing', async () => {
  await reset();
  const plain = await posted('Plain post', null);
  await reported(plain, '2026-11-14T10:00:00Z');
  const before = await posted('First words', null);
  await edited(before, '2026-11-14T09:00:00Z', 'Second words', null);
  await reported(before, '2026-11-14T10:00:00Z');
  const refused = await posted('Kind words', 'Centennial Park');
  await reported(refused, '2026-11-14T10:00:00Z');
  await edited(refused, '2026-11-14T11:00:00Z', 'SPAM', null, false);
  for (const id of [plain, before, refused]) {
    const row = await shown(id);
    assert.equal(row.was_title, null);
    assert.equal(row.was_place, null);
  }
});

test('only the admin reads it', async () => {
  await reset();
  const id = await posted('Something', null);
  await reported(id, '2026-11-14T10:00:00Z');
  await db.exec(`reset role; set request.jwt.claims = '${JSON.stringify({ sub: YOU, role: 'authenticated' })}'; set role authenticated`);
  assert.deepEqual((await db.query('select * from public.list_reports()')).rows, []);
});
