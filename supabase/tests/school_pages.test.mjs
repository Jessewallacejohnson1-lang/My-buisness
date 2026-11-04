// Two schools to follow from onboarding's Schools (BP app onboarding 28). Run: `npm install && npm test`.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { realDatabase, people } from './fixture.mjs';

const db = await realDatabase();
const ME = '00000000-0000-0000-0000-00000000000a';

test('following a school page lifts the Events its source posts', async () => {
  await people(db, ME);
  const { rows: pages } = await db.query(
    `select slug, kind, source_name, picture_kind from public.town_pages where kind = 'School' order by slug`);
  assert.deepEqual(pages.map(p => p.slug), ['st-johns-prep', 'st-joseph-catholic']);
  assert.equal(pages[0].picture_kind, 'logo');
  assert.equal(pages[1].picture_kind, null);

  for (const [title, source] of [['Fall play', "St. John's Prep"], ['Bake sale', 'Elsewhere']]) {
    await db.query(
      `insert into public.club_events (title, event_date, start_time, status, kind, source_name, interests, interests_tagged_at)
       values ($1, '2026-11-20', '7 PM', 'approved', 'event', $2, '{}', now())`, [title, source]);
  }
  const { rows: [{ id }] } = await db.query(`select id from public.town_pages where slug = 'st-johns-prep'`);
  await db.query(`insert into public.town_follows (follower_id, target_type, target_id) values ($1, 'page', $2)`, [ME, id]);

  await db.exec(`set role authenticated; set request.jwt.claim.sub = '${ME}'`);
  const { rows } = await db.query(
    `select f.card->>'title' as title, f.reason from public.get_town_feed('2026-11-18 12:00-06'::timestamptz) f where f.kind = 'event'`);
  await db.exec(`reset role; reset request.jwt.claim.sub`);
  assert.equal(rows[0].title, 'Fall play');
  assert.equal(rows[0].reason, 'follow');
});
