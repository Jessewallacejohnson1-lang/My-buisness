// Fixed stories for the move from 18 interests to 21 (supabase/migrations/*_interests_21.sql, BP app
// onboarding 20): old ids become the new ones on every save.
// Run: `npm install && npm test` in this folder.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { realDatabase, people } from './fixture.mjs';

const ANNA = '00000000-0000-0000-0000-00000000000a';
const db = await realDatabase();
await people(db, ANNA);
await db.exec(`insert into public.town_profiles (user_id) values ('${ANNA}')`);
const rows = async (sql) => (await db.query(sql)).rows;

test('an older app or the morning job saving old ids gets the new ones', async () => {
  await db.exec(`update public.town_profiles set interests = '{sports_leagues,fitness_yoga,health_wellness}' where user_id = '${ANNA}'`);
  await db.exec(`insert into public.club_events (title, interests, category) values ('Hike', '{trails_hiking,parks_gardens}', 'art_exhibits')`);
  await db.exec(`insert into public.board_items (title, category, source_name, interests) values ('Flight Friday', 'business', 'The Cow', '{breweries}')`);
  assert.deepEqual((await rows(`select interests from public.town_profiles where user_id = '${ANNA}'`))[0].interests,
    ['watch_sports', 'play_sports', 'health']);
  assert.deepEqual(await rows(`select interests, category from public.club_events where title = 'Hike'`),
    [{ interests: ['outdoors'], category: 'art_theater' }]);
  assert.deepEqual((await rows(`select interests from public.board_items where title = 'Flight Friday'`))[0].interests, ['bars']);
});

test('new ids, and books, are left as picked', async () => {
  await db.exec(`update public.town_profiles set interests = '{books,campus,town_meetings}' where user_id = '${ANNA}'`);
  assert.deepEqual((await rows(`select interests from public.town_profiles where user_id = '${ANNA}'`))[0].interests,
    ['books', 'campus', 'town_meetings']);
});
