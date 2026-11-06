// Who can list the photos in `avatars` and `event-images`, whose folders are named by user id (BP app
// loopholes 19). Public photo links don't read this rule, so they aren't a story here.
// Run: `npm install && npm test` in this folder.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { realDatabase, people } from './fixture.mjs';

const db = await realDatabase();
const ANA = '00000000-0000-0000-0000-0000000000a1';
const BEN = '00000000-0000-0000-0000-0000000000b2';
await people(db, ANA, BEN);

async function as(role, who, sql, params = []) {
  await db.exec(`set role ${role}; set request.jwt.claims = '${JSON.stringify(who ? { sub: who } : {})}'`);
  try {
    return (await db.query(sql, params)).rows.map((row) => row.name);
  } finally {
    await db.exec('reset role; reset request.jwt.claims');
  }
}

for (const bucket of ['avatars', 'event-images']) {
  const list = `select name from storage.objects where bucket_id = '${bucket}'`;
  const add = `insert into storage.objects (bucket_id, name) values ('${bucket}', $1) returning name`;
  await db.query(`insert into storage.objects (bucket_id, name) values ($1, $2), ($1, $3)`,
                 [bucket, `${ANA}/one.jpg`, `${BEN}/two.jpg`]);

  test(`${bucket}: signed out lists nobody`, async () => {
    assert.deepEqual(await as('anon', null, list), []);
  });

  test(`${bucket}: signed in lists only your own folder`, async () => {
    assert.deepEqual(await as('authenticated', ANA, list), [`${ANA}/one.jpg`]);
    assert.deepEqual(await as('authenticated', BEN, list), [`${BEN}/two.jpg`]);
  });

  test(`${bucket}: you can add a photo to your own folder, and only your own`, async () => {
    const mine = `${ANA}/new.jpg`;
    assert.deepEqual(await as('authenticated', ANA, add, [mine]), [mine]);
    await assert.rejects(as('authenticated', ANA, add, [`${BEN}/new.jpg`]), /row-level security/);
    await assert.rejects(as('anon', null, add, [`${ANA}/anon.jpg`]), /row-level security|permission denied/);
  });
}

test('avatars: you can replace your own photo', async () => {
  const mine = `${ANA}/new.jpg`;
  const replace = `update storage.objects set bucket_id = 'avatars' where bucket_id = 'avatars' and name = $1 returning name`;
  assert.deepEqual(await as('authenticated', ANA, replace, [mine]), [mine]);
});

test('event-images: you can delete your own post\'s photo, and only your own', async () => {
  const remove = `delete from storage.objects where bucket_id = 'event-images' and name = $1 returning name`;
  assert.deepEqual(await as('authenticated', ANA, remove, [`${BEN}/two.jpg`]), []);
  assert.deepEqual(await as('authenticated', ANA, remove, [`${ANA}/one.jpg`]), [`${ANA}/one.jpg`]);
  assert.deepEqual(await as('authenticated', BEN, `select name from storage.objects where bucket_id = 'event-images'`), [`${BEN}/two.jpg`]);
});
