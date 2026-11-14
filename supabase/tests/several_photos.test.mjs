// Fixed stories for several photos in a post (supabase/migrations/*_several_photos.sql, BP app town-feed 46): the
// check claims a post's later photos only when each is the poster's own upload named for that post; the Town feed and
// the bell send them in the poster's order; and a file a post shows can't be deleted from under it. Run in PGlite:
// `npm install && npm test` in this folder.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { realDatabase, people, adminClaims } from './fixture.mjs';

const db = await realDatabase();
const ADMIN = await adminClaims(db);
const ME = '00000000-0000-0000-0000-0000000000b2';
const YOU = '00000000-0000-0000-0000-0000000000c3';
const PAL = '00000000-0000-0000-0000-0000000000d4';
const PHOTOS = 'https://lxdgwhvqjqmqliobwjpi.supabase.co/storage/v1/object/public/event-images/';
await people(db, ME, YOU, PAL);
await db.query(`insert into public.town_profiles (user_id, display_name) values
  ($1, 'Avery Lund'), ($2, 'Ana Nguyen'), ($3, 'Sam Rivera')`, [ME, YOU, PAL]);
await db.exec(`insert into private.friendships (a, b, requested_by) values ('${[ME, PAL].sort().join("', '")}', '${ME}')`);
await db.exec(`insert into storage.buckets (id, name, public) values ('event-images', 'event-images', true) on conflict (id) do nothing`);
let n = 0;

async function as(role, sub) {
  await db.exec(`reset role; set role ${role};`);
  await db.query(`select set_config('request.jwt.claims', $1, false)`, [sub ? JSON.stringify({ sub, role, is_anonymous: false }) : '']);
}

const nextId = () => `00000000-0000-0000-0000-${String(++n).padStart(12, '0')}`;
/** `who`'s upload number `k` for post `id`: the first is <id>.jpg, the rest <id>-<k>.jpg. */
const photo = (who, id, k = 1) => `${PHOTOS}${who}/${id}${k === 1 ? '' : `-${k}`}.jpg`;

/** A pending post of `who`'s (or town-plus's plain Event with kind 'event') with its id and any extra columns. */
async function posted(who, id, extra = {}) {
  await db.exec('reset role');
  const base = extra.kind === 'event'
    ? { title: 'Porch concert', event_date: '2026-12-05', start_time: '19:00', location: 'Millstream Park' }
    : { kind: 'post', title: 'Millstream was packed today' };
  const row = { id, submitted_by: who, category: 'other', ...base, ...extra };
  const cols = Object.keys(row);
  await db.query(`insert into public.club_events (${cols.join(', ')}) values (${cols.map((_, i) => `$${i + 1}`).join(', ')})`,
                 Object.values(row));
  return id;
}
const claim = async (id, who) => { await db.exec('reset role');
  return (await db.query('select public.claim_submit($1, $2) as ok', [id, who])).rows[0].ok; };

/** A pending post of `who`'s with photos 1 to `count`, each its own upload, unless `more` says otherwise. */
async function withPhotos(who, count, more) {
  const id = nextId();
  return posted(who, id, { image_url: photo(who, id), more_photos: more ?? Array.from({ length: count - 1 }, (_, i) => photo(who, id, i + 2)) });
}

test('a post with up to 10 photos of its own is claimed, its later ones in the poster\'s order', async () => {
  const id = nextId();
  const order = [5, 2, 10, 3, 4, 6, 7, 8, 9].map((k) => photo(ME, id, k));
  await posted(ME, id, { image_url: photo(ME, id), more_photos: order });
  assert.equal(await claim(id, ME), true);
  await db.exec('reset role');
  assert.deepEqual((await db.query('select more_photos from public.club_events where id = $1', [id])).rows[0].more_photos, order,
                   'kept exactly as picked');
  assert.equal(await claim(await withPhotos(ME, 2), ME), true, 'two photos');
  assert.equal(await claim(await posted(ME, nextId(), { image_url: `${PHOTOS}${ME}/0a1b.jpg` }), ME), true,
               'one photo, as before');
});

test('more than 10 photos, or an empty list, can\'t be saved at all', async () => {
  const id = nextId();
  await assert.rejects(posted(ME, id, { image_url: photo(ME, id), more_photos: Array.from({ length: 10 }, (_, i) => photo(ME, id, i + 2)) }),
                       /club_events_more_photos_check/);
  await assert.rejects(posted(ME, nextId(), { image_url: photo(ME, id), more_photos: [] }), /club_events_more_photos_check/);
});

test('a later photo that isn\'t the poster\'s own upload for this post is never claimed', async () => {
  const other = nextId();
  const cases = {
    'someone else\'s folder': (id) => [photo(YOU, id, 2)],
    'named for another post': () => [photo(ME, other, 2)],
    'numbered 1': (id) => [`${PHOTOS}${ME}/${id}-1.jpg`],
    'numbered 11': (id) => [photo(ME, id, 11)],
    'another site': (id) => [`https://example.com/${ME}/${id}-2.jpg`],
    'the same photo twice': (id) => [photo(ME, id, 2), photo(ME, id, 2)],
    'not a jpg': (id) => [`${PHOTOS}${ME}/${id}-2.png`],
  };
  for (const [why, more] of Object.entries(cases)) {
    const id = nextId();
    await posted(ME, id, { image_url: photo(ME, id), more_photos: more(id) });
    assert.equal(await claim(id, ME), false, why);
  }
  const bare = nextId();
  await posted(ME, bare, { more_photos: [photo(ME, bare, 2)] });
  assert.equal(await claim(bare, ME), false, 'later photos with no first');
  const event = nextId();
  await posted(ME, event, { kind: 'event', image_url: photo(ME, event), more_photos: [photo(ME, event, 2)] });
  assert.equal(await claim(event, ME), false, 'an Event keeps one photo');
});

test('the Town feed and the bell send a post\'s later photos in order; a one-photo post sends none', async () => {
  await db.exec('reset role');
  const at = "now() - interval '1 hour'";
  const many = nextId(), one = nextId();
  const later = [photo(PAL, many, 3), photo(PAL, many, 2)];
  await posted(PAL, many, { title: 'Four photos', status: 'approved', image_url: photo(PAL, many), more_photos: later,
                            image_aspect: 0.8, tagged: [ME] });
  await posted(PAL, one, { title: 'One photo', status: 'approved', image_url: photo(PAL, one), image_aspect: 1.5, tagged: [ME] });
  await db.exec(`update public.club_events set created_at = ${at} where id in ('${many}', '${one}')`);
  await as('authenticated', ME);
  const feed = (await db.query(`select title, image_url, poster from public.get_town_feed(now(), true) where kind = 'post'
                                order by title`)).rows;
  const bell = (await db.query('select title, poster from public.get_my_mentions() order by title')).rows;
  await db.exec('reset role');
  for (const rows of [feed, bell]) {
    assert.deepEqual(rows.map((r) => [r.title, r.poster.more_photos ?? null, r.poster.aspect]),
                     [['Four photos', later, 0.8], ['One photo', null, 1.5]]);
  }
  assert.equal(feed[0].image_url, photo(PAL, many), 'the first stays where it was');
});

test('a file a post shows can\'t be deleted by its poster until the post goes', async () => {
  const id = nextId();
  await posted(ME, id, { status: 'approved', image_url: photo(ME, id), more_photos: [photo(ME, id, 2)] });
  const refused = nextId();
  await posted(ME, refused, { status: 'rejected', review_reason: 'declined', image_url: photo(ME, refused) });
  const names = [`${ME}/${id}.jpg`, `${ME}/${id}-2.jpg`, `${ME}/stray.jpg`, `${ME}/${refused}.jpg`];
  for (const name of names) await db.query(`insert into storage.objects (bucket_id, name) values ('event-images', $1)`, [name]);
  const del = async (name) => (await db.query('delete from storage.objects where name = $1', [name])).affectedRows;
  await as('authenticated', ME);
  assert.equal(await del(names[0]), 0, 'the live post\'s first photo stays');
  assert.equal(await del(names[1]), 0, 'and its second');
  assert.equal(await del(names[2]), 1, 'a file no post shows goes');
  assert.equal(await del(names[3]), 1, 'a refused post\'s file goes');
  assert.equal((await db.query('delete from public.club_events where id = $1', [id])).affectedRows, 1, 'the post goes first');
  assert.equal(await del(names[0]), 1, 'then its photos');
  assert.equal(await del(names[1]), 1);
  await db.exec('reset role');
});

test('the Review queue sends a held or reported post\'s later photos with its poster', async () => {
  const held = nextId(), reported = nextId();
  await posted(PAL, held, { title: 'Held', image_url: photo(PAL, held), more_photos: [photo(PAL, held, 2)] });
  await posted(PAL, reported, { title: 'Reported', status: 'approved', image_url: photo(PAL, reported),
                                more_photos: [photo(PAL, reported, 3), photo(PAL, reported, 2)] });
  await db.query(`insert into public.reports (event_id, reason) values ($1, 'scam')`, [reported]);
  await db.exec(`reset role; set request.jwt.claims = '${ADMIN}'; set role authenticated`);
  const heldRow = (await db.query('select poster from public.list_held() where id = $1', [held])).rows[0];
  const reportRow = (await db.query('select poster from public.list_reports() where event_id = $1', [reported])).rows[0];
  await db.exec('reset role');
  assert.deepEqual(heldRow.poster.more_photos, [photo(PAL, held, 2)]);
  assert.equal(heldRow.poster.name, 'Sam Rivera', 'still the poster');
  assert.deepEqual(reportRow.poster.more_photos, [photo(PAL, reported, 3), photo(PAL, reported, 2)]);
});
