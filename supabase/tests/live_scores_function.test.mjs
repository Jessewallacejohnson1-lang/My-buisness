// Failure drills for the live-scores edge function itself (supabase/functions/live-scores/index.ts, BP app
// docs/plans/game-card/issues/22-never-blind-quietly.md): one listener's minute with SIDEARM's hub, the school's site and
// sidearmstats.com faked, on a fake clock. Each failure reaches public.record_live_read with its reason, and none ends
// the run. Node 24 imports the TypeScript as it is. Run: `npm test` in this folder.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { listen, schoolReads } from '../functions/live-scores/index.ts';

const SCHOOL = 'https://gobennies.com/api/livestats?game_id=10289';
const hockey = readFileSync(new URL('sidearm-live-csb-whockey.json', import.meta.url), 'utf8');

test('two games on one site take turns: each read once a minute, the site never twice within 30 s', () => {
  const feeds = new Map([['hockey', SCHOOL], ['basketball', 'https://gobennies.com/api/livestats?game_id=10367'],
                         ['football', 'https://gojohnnies.com/api/livestats?game_id=17791']]);
  // Four listeners in a row, each starting a moment after its minute.
  const start = Date.parse('2026-11-07T20:00:00.300Z');
  const reads = [0, 1, 2, 3].flatMap((m) => schoolReads(feeds, start + m * 60_000));
  for (const host of ['gobennies.com', 'gojohnnies.com']) {
    const times = reads.filter((r) => new URL(r.url).hostname === host).map((r) => r.at).sort((a, b) => a - b);
    times.slice(1).forEach((t, i) => assert.ok(t - times[i] >= 30_000, `${host} read ${t - times[i]} ms after the last`));
  }
  assert.deepEqual(['hockey', 'basketball', 'football'].map((id) => reads.filter((r) => r.id === id).length), [4, 4, 8]);
});

test("one minute: every failure reaches the database with its reason, a failed push read while a write is going ends " +
     "nothing, and the backup reads its turn", async (t) => {
  // The first minute of a 10, so the backup reads.
  const start = Date.parse('2026-11-07T20:00:00.500Z');
  t.mock.timers.enable({ apis: ['setTimeout', 'Date'], now: start });
  t.mock.method(console, 'log', () => {});
  t.mock.method(console, 'error', () => {});
  const loose = [];
  const onLoose = (e) => loose.push(e);
  process.on('unhandledRejection', onLoose);

  const fetched = [];
  const certificate = () => new TypeError('fetch failed',
    { cause: Object.assign(new Error('certificate has expired'), { code: 'CERT_HAS_EXPIRED' }) });
  const timeout = () => Object.assign(new Error('The operation was aborted due to timeout'), { name: 'TimeoutError' });
  const realFetch = globalThis.fetch;
  globalThis.fetch = async (url) => {
    url = String(url);
    fetched.push({ url, at: Date.now() - start });
    if (url.includes('/negotiate')) return Response.json({ ConnectionToken: 'token' });
    if (url.startsWith('https://sidearmstats.com/csb/whockey/game.json')) return new Response(hockey);
    if (url.startsWith('https://api-realtime-stats.prod.sidearmdev.com/')) throw certificate();
    if (url.startsWith(SCHOOL)) {
      if (fetched.filter((f) => f.url.startsWith(SCHOOL)).length === 1) return new Response('down', { status: 503 });
      throw timeout();
    }
    throw new Error(`unexpected fetch ${url}`);
  };
  // SIDEARM's hub: the join cue, then a game push whose file host's certificate expired, a push pointing somewhere new
  // (2026-10-31), and a plays push carrying its plays.
  const realSocket = globalThis.WebSocket;
  globalThis.WebSocket = class {
    constructor() {
      const say = (ms, frame) => setTimeout(() => this.onmessage({ data: JSON.stringify(frame) }), ms);
      const push = (group, data) => ({ M: [{ M: 'message', A: [{ group, data }] }] });
      say(10, { S: 1 });
      say(1000, push('livestats/csb/whockey/game', 'GET:https://api-realtime-stats.prod.sidearmdev.com/jsonp:csb_whockey_game'));
      say(1100, push('livestats/csb/whockey/game', 'GET:https://api-realtime-stats.example.com/jsonp:csb_whockey_game'));
      say(1200, push('livestats/csb/whockey/plays', [{ Id: '55', Narrative: 'Shot by LFC, save.' }]));
    }
    send() {}
    close() {}
  };

  const reads = [];
  const rpc = async (name, body) => {
    if (name === 'live_feeds') return [{ event_id: 'hockey', url: SCHOOL }];
    if (name === 'live_backup_turn') return 'hockey';
    assert.equal(name, 'record_live_read');
    reads.push(body);
    // The backup's write is slow, so the pushes fail while it is still going (2026-11-07's "event loop error").
    if (body.p_source === 'backup') await new Promise((done) => setTimeout(done, 3000));
    return 'live';
  };

  try {
    let done = false;
    const run = listen([{ id: 'hockey', grp: 'livestats/csb/whockey/game' }], rpc, start).finally(() => { done = true; });
    for (let i = 0; i < 200 && !done; i++) {
      await new Promise((go) => setImmediate(go));
      t.mock.timers.tick(500);
    }
    await run;
  } finally {
    globalThis.fetch = realFetch;
    globalThis.WebSocket = realSocket;
    process.off('unhandledRejection', onLoose);
  }

  assert.deepEqual(reads.map((r) => [r.p_source, r.p_why]), [
    ['backup', null],
    ['push', 'certificate expired'],
    ['push', 'push pointed at api-realtime-stats.example.com'],
    ['push', null],
    ['school', 'HTTP 503'],
    ['school', 'timed out']]);
  assert.equal(reads[0].p_game.Game.HomeTeam.Name, 'Saint Benedict', "the backup's whole file");
  assert.equal(reads[0].p_game.Game.LastPlays.length, 55, 'with every play so far');
  assert.deepEqual(reads[3].p_game, [{ Id: '55', Narrative: 'Shot by LFC, save.' }]);
  assert.ok(reads.every((r) => r.p_event === 'hockey'));
  assert.deepEqual(fetched.filter((f) => f.url.startsWith(SCHOOL)).map((f) => f.at), [4500, 34500],
                   "the school's site at :05 and :35 only");
  assert.deepEqual(loose, [], 'no failed read left unheard');
});
