// Every migration file has a version of its own. Supabase keys applied migrations by the
// 14-digit prefix, so two files sharing one can't both be applied: on 2026-10-16 the friends
// migration and place_picture were both written as 20261016180000 by two chats at once (BP app
// retro, 2026-10-17). Run: `npm test` in this folder.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync } from 'node:fs';

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
