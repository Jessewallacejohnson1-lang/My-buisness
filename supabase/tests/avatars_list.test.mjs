// Who can list the avatars bucket (BP app loopholes 19). Public photo links don't read this rule, so
// they aren't a story here. Run: `npm install && npm test` in this folder.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { realDatabase, people } from './fixture.mjs';

const db = await realDatabase();
const ANA = '00000000-0000-0000-0000-0000000000a1';
const BEN = '00000000-0000-0000-0000-0000000000b2';
await people(db, ANA, BEN);
await db.query(`insert into storage.objects (bucket_id, name)
                values ('avatars', $1), ('avatars', $2)`, [`${ANA}/avatar-1.jpg`, `${BEN}/avatar-2.jpg`]);

async function as(role, who, sql, params = []) {
  await db.exec(`set role ${role}; set request.jwt.claims = '${JSON.stringify(who ? { sub: who } : {})}'`);
  try {
    return (await db.query(sql, params)).rows.map((row) => row.name);
  } finally {
    await db.exec('reset role; reset request.jwt.claims');
  }
}
const LIST = `select name from storage.objects where bucket_id = 'avatars'`;
const ADD = `insert into storage.objects (bucket_id, name) values ('avatars', $1) returning name`;

test('signed out lists nobody', async () => {
  assert.deepEqual(await as('anon', null, LIST), []);
});

test('signed in lists only your own folder', async () => {
  assert.deepEqual(await as('authenticated', ANA, LIST), [`${ANA}/avatar-1.jpg`]);
  assert.deepEqual(await as('authenticated', BEN, LIST), [`${BEN}/avatar-2.jpg`]);
});

test('you can still add and replace your own photo, and only your own', async () => {
  const mine = `${ANA}/avatar-new.jpg`;
  assert.deepEqual(await as('authenticated', ANA, ADD, [mine]), [mine]);
  assert.deepEqual(await as('authenticated', ANA, `update storage.objects set bucket_id = 'avatars' where name = $1 returning name`, [mine]), [mine]);
  await assert.rejects(as('authenticated', ANA, ADD, [`${BEN}/avatar-new.jpg`]), /row-level security/);
  await assert.rejects(as('anon', null, ADD, [`${ANA}/avatar-anon.jpg`]), /row-level security|permission denied/);
});
