// Every migration file has a version of its own. Supabase keys applied migrations by the
// 14-digit prefix, so two files sharing one can't both be applied: on 2026-10-16 the friends
// migration and place_picture were both written as 20261016180000 by two chats at once (BP app
// retro, 2026-10-17). Run: `npm test` in this folder.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync } from 'node:fs';
import { creating } from './migrations.mjs';

const dir = new URL('../migrations', import.meta.url).pathname;

test('every migration file has its own 14-digit version', () => {
  const files = readdirSync(dir).filter((f) => f.endsWith('.sql'));
  const badName = files.filter((f) => !/^\d{14}_[a-z0-9_]+\.sql$/.test(f));
  assert.deepEqual(badName, [], 'name it <yyyymmddhhmmss>_<what_it_does>.sql');
  // A plain fold, not Object.groupBy: GitHub's runner may carry Node 20.
  const byVersion = {};
  for (const f of files) (byVersion[f.slice(0, 14)] ??= []).push(f);
  const shared = Object.values(byVersion).filter((group) => group.length > 1);
  assert.deepEqual(shared, [], 'renumber the newer file past the newest migration on main');
});

// The Town feed is edited in supabase/town_feed.sql and each migration that remakes it is a copy,
// so a feed change reads as a small diff of that file (BP app codebase-health-2, ticket 12). A
// stale copy took the friends lift out of the live feed on 2026-10-17.
test('the newest Town feed migration holds supabase/town_feed.sql word for word', () => {
  const newest = creating(dir, ['private.town_feed', 'public.get_town_feed']).at(-1);
  const sql = readFileSync(`${dir}/${newest}`, 'utf8');
  const source = readFileSync(new URL('../town_feed.sql', import.meta.url), 'utf8').trim();
  assert.ok(sql.includes(source), `${newest} is not a copy of supabase/town_feed.sql. Edit that file, then ` +
    '`supabase migration new <name>` and `cat supabase/town_feed.sql >> <the new file>`. When it is your own ' +
    'and not applied yet, replace its copy instead.');
  // Nothing left over: an emptied or cut source file still passes the check above, and so does a
  // function hand-written below the copy.
  assert.doesNotMatch(sql.replace(source, ''), /create\s+(or\s+replace\s+)?function\s+(private\.town_feed|public\.get_town_feed)\s*\(/i,
    `${newest} makes the feed outside its copy of supabase/town_feed.sql, or that file has lost part of it`);
});
