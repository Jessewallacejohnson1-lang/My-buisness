// Supabase Edge Function: live-scores — a game card's live score (BP app docs/plans/game-card, ticket 03).
//
// SIDEARM's live stats page gets each change pushed over SignalR 2.0 (BP app
// references/game-card/live-channel.md): hub `sidearm` at v2-realtime.sidearmsports.com, a channel per
// school, sport and topic (`livestats/csbsju/football/game`, `.../plays` for the scoring plays, ticket 05). pg_cron's private.wake_live_scores calls this every
// minute while an SJU or CSB game is on; it answers at once and listens about a minute in the background,
// writing each pushed Game through public.record_live_score. public.start_live_scores hands out the games at
// most once in 50 seconds, so a second call, from anyone, listens to nothing: verify_jwt is off. While SIDEARM's
// file host is down, a whole file from sidearmstats.com every 10 minutes stands in (`backup`).
//
// An SJU or CSB game also has its school's own file read every 30 s (`schoolReads`, game-card 21): the stat crew's
// file on gojohnnies.com or gobennies.com, uncached, which kept up while every push failed (2026-11-07). The backup
// leaves those games alone: its cached file could land an older score over the school's.
//
// Deploy: supabase functions deploy live-scores --project-ref lxdgwhvqjqmqliobwjpi, which keeps verify_jwt off
// from supabase/config.toml; or the Supabase MCP's deploy_edge_function with verify_jwt false. Composio's
// SUPABASE_DEPLOY_FUNCTION has no such setting and turns it back on: follow it with SUPABASE_UPDATE_A_FUNCTION,
// verify_jwt false. A missed one gets pg_cron's call refused (401), and each refusal shows as a failed
// live-scores run in cron.job_run_details (loopholes 05).

const HUB = "https://v2-realtime.sidearmsports.com/signalr"
const HUB_DATA = encodeURIComponent(JSON.stringify([{ name: "sidearm" }]))
const UA = { "User-Agent": "BlockPartyBot/1.0 (+https://blockpartystjoe.com)" }
// Ten seconds short of the next minute's start, so two listeners rarely overlap (and an overlap only writes
// the same score twice).
const LISTEN_MS = 50_000
// Where a push's game file lives. Its certificate ran out 2026-11-06, 6 PM, and every push's read failed with it.
const FILE_HOST = "https://api-realtime-stats.prod.sidearmdev.com/"
// The backup's one read of sidearmstats.com, as its robots.txt asks (Crawl-delay: 600).
const BACKUP_MS = 600_000
// SJU's and CSB's own sites, by SIDEARM folder: SIDEARM's list names the school as a team.
const SITES: Record<string, { host: string; school: RegExp }> = {
  csb: { host: "gobennies.com", school: /benedict/i },
  csbsju: { host: "gojohnnies.com", school: /\b(saint|st\.?) john['’]?s\b/i },
}
// Their robots.txt allows /api/ at one read per 30 s (Crawl-delay: 30). Each site's slots fall at :05 and :35 past
// the minute, so this minute's listener and the next never read a site closer than 30 s apart.
const SITE_MS = 30_000
const SLOT_AT = 5_000
// SIDEARM's list of games with live stats (its Event Central page reads it), for each game's file on its site.
const LIST = "https://aggregation-service.sidearmsports.com/services/games.ashx"

type Game = { id: string; grp: string }
type Rpc = (name: string, body: unknown) => Promise<unknown>
type Listed = {
  date_info?: { datetime_utc?: string }
  sport?: { shortname?: string }
  media?: { livestats_feed?: string | null }
  home_team?: { name?: string }
  away_team?: { name?: string }
}

declare const EdgeRuntime: { waitUntil(p: Promise<unknown>): void }

Deno.serve(async () => {
  const url = Deno.env.get("SUPABASE_URL")
  const key = JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS") ?? "{}")["default"]
  if (!url || !key) return json({ error: "misconfigured" }, 500)
  const rpc = async (name: string, body: unknown) => {
    const res = await fetch(`${url}/rest/v1/rpc/${name}`, {
      method: "POST",
      headers: { apikey: key, Authorization: `Bearer ${key}`, "Content-Type": "application/json" },
      body: JSON.stringify(body),
    })
    const text = await res.text()
    if (!res.ok) throw new Error(`${name}: ${res.status} ${text}`)
    // A function that returns nothing (save_live_feed) answers with no body.
    return text ? JSON.parse(text) : null
  }
  const games = (await rpc("start_live_scores", {})) as Game[]
  if (games.length === 0) return json({ games: 0 }, 200)
  EdgeRuntime.waitUntil(listen(games, rpc).catch((e) => console.error("[live-scores]", e)))
  return json({ games: games.length }, 202)
})

export async function listen(games: Game[], rpc: Rpc, start = Date.now()) {
  const feeds = await feedsOf(games, rpc, start).catch((e) => (console.error("[live-scores] feeds", e), new Map()))
  // Each game's score channel and its plays channel, both written through record_live_score.
  const groups = games.flatMap((g) => [g.grp, g.grp.replace(/\/game$/, "/plays")].map((grp) => ({ id: g.id, grp })))
  const byGroup = new Map(groups.map((g) => [g.grp.toLowerCase(), g.id]))
  // Pushes are written one at a time, in the order they came: a score and its play arrive together, and
  // writes racing each other could land an older score last. The backup's read, if any, goes first.
  let writes: Promise<unknown> = backup(games.filter((g) => !feeds.has(g.id)))
    .then((b) => b && rpc("record_live_score", { p_event: b.id, p_game: b.game }))
    .catch((e) => console.error("[live-scores] backup", e))
  // Each school file's read joins the same line of writes when it starts, so a read and a push land in the order
  // they began.
  const school = (async () => {
    for (const r of schoolReads(feeds, start)) {
      // A slot gone by while the list was read is skipped: read late, it would sit closer than 30 s to the next.
      if (r.at < Date.now()) continue
      await new Promise((done) => setTimeout(done, r.at - Date.now()))
      const read = schoolFile(r.url).catch((e) => (console.error("[live-scores] school", e), null))
      writes = writes
        .then(() => read)
        .then((game) => game && rpc("record_live_score", { p_event: r.id, p_game: game }))
        .catch((e) => console.error("[live-scores] school", e))
    }
  })()
  // The writes land even when the hub fails, which is when the backup's and the school's are needed.
  try {
    const neg = await (await fetch(`${HUB}/negotiate?clientProtocol=1.3&connectionData=${HUB_DATA}`, { headers: UA })).json()
    const query = `transport=webSockets&clientProtocol=1.3&connectionToken=${encodeURIComponent(neg.ConnectionToken)}` +
      `&connectionData=${HUB_DATA}`
    const ws = new WebSocket(`${HUB.replace("https", "wss")}/connect?${query}`)

    ws.onmessage = (event) => {
      const frame = JSON.parse(String(event.data))
      // SignalR 2.0 has no /start: the socket's init frame is the cue to join.
      if (frame.S === 1) {
        groups.forEach((g, i) => ws.send(JSON.stringify({ H: "sidearm", M: "join", A: [g.grp], I: i })))
        return
      }
      for (const call of frame.M ?? []) {
        if (String(call.M).toLowerCase() !== "message") continue
        const message = call.A?.[0]
        const id = byGroup.get(String(message?.group ?? "").toLowerCase())
        if (!id) continue
        // Every push, raw, until the first live games show what SIDEARM sends.
        console.log(`[live-scores] ${message.group}: ${JSON.stringify(message.data).slice(0, 2000)}`)
        // Caught as it starts, not only at its turn in the line: a read that fails while an earlier write is still
        // going has no one listening yet, and the runtime ends the whole run on it ("event loop error"), the school
        // reads with it (2026-11-07: 12 of 16 minutes lost CSB hockey's 2nd read).
        const read = gameOf(message.data).catch((e) => (console.error("[live-scores] push", e), null))
        writes = writes
          .then(() => read)
          .then((game) => game && rpc("record_live_score", { p_event: id, p_game: game }))
          .catch((e) => console.error("[live-scores] push", e))
      }
    }
    ws.onerror = (e) => console.error("[live-scores] socket", (e as ErrorEvent).message)

    await new Promise((done) => setTimeout(done, LISTEN_MS))
    ws.close()
  } finally {
    await school
    await writes
  }
}

// Each game's file on its school's site: kept in the database, else looked for in SIDEARM's list of games on now and
// kept (a miss too, for 10 minutes), so the 2 MB list is read once per game day.
export async function feedsOf(games: Game[], rpc: Rpc, now = Date.now()): Promise<Map<string, string>> {
  const rows = (await rpc("live_feeds", { p_events: games.map((g) => g.id) })) as { event_id: string; url: string | null }[]
  const feeds = new Map(rows.map((r) => [r.event_id, r.url]))
  const missing = games.filter((g) => !feeds.has(g.id) && SITES[g.grp.split("/")[1]])
  if (missing.length) {
    const window = `start_date=${new Date(now - 6 * 3600_000).toISOString()}&end_date=${new Date(now + 3600_000).toISOString()}`
    const res = await fetch(`${LIST}?livestats=1&${window}`, { headers: UA, signal: AbortSignal.timeout(20_000) })
    console.log(`[live-scores] list: ${res.status}`)
    const list = res.ok ? ((await res.json()) as { data?: Listed[] }).data : null
    for (const g of Array.isArray(list) ? missing : []) {
      const url = feedOf(list!, g, now)
      await rpc("save_live_feed", { p_event: g.id, p_url: url })
      feeds.set(g.id, url)
    }
  }
  return new Map([...feeds].filter((f): f is [string, string] => !!f[1]))
}

// Our game in SIDEARM's list: its file on the school's own site, in its sport, with the school as a team (CSB's gym
// also hosts other schools' games: Hamline vs Morris, 2026-11-07), the nearest to now if two.
export function feedOf(list: Listed[], g: Game, now: number): string | null {
  const [, folder, sport] = g.grp.split("/")
  const site = SITES[folder]
  if (!site) return null
  const file = new RegExp(`^https://${site.host.replace(".", "\\.")}/api/livestats\\?game_id=\\d+$`)
  const away = (x: Listed) => {
    const at = Date.parse(x.date_info?.datetime_utc ?? "")
    return Number.isNaN(at) ? Infinity : Math.abs(at - now)
  }
  return list
    .filter((x) => x.sport?.shortname === sport && file.test(x.media?.livestats_feed ?? "") &&
                   [x.home_team?.name, x.away_team?.name].some((n) => site.school.test(n ?? "")))
    .sort((a, b) => away(a) - away(b))[0]?.media?.livestats_feed ?? null
}

// The reads in one listener's minute: each site's slots at :05 and :35, its games taking turns slot by slot.
export function schoolReads(feeds: Map<string, string>, start: number): { at: number; id: string; url: string }[] {
  const bySite = new Map<string, [string, string][]>()
  for (const f of [...feeds].sort((a, b) => a[0].localeCompare(b[0]))) {
    const host = new URL(f[1]).hostname
    bySite.set(host, [...(bySite.get(host) ?? []), f])
  }
  const reads: { at: number; id: string; url: string }[] = []
  for (let at = Math.ceil((start - SLOT_AT) / SITE_MS) * SITE_MS + SLOT_AT; at < start + LISTEN_MS; at += SITE_MS) {
    for (const turns of bySite.values()) {
      const [id, url] = turns[Math.floor(at / SITE_MS) % turns.length]
      reads.push({ at, id, url })
    }
  }
  return reads
}

// The whole file, written as the backup's is: every play so far in LastPlays.
export async function schoolFile(url: string): Promise<unknown | null> {
  const res = await fetch(`${url}&detail=full`, { headers: UA, signal: AbortSignal.timeout(10_000) })
    .catch((e) => (console.error(`[live-scores] school ${url}`, e), null))
  if (!res) return null
  console.log(`[live-scores] school ${url}: ${res.status}`)
  const read = (res.ok ? parse(await res.text()) : null) as { Game?: object; Plays?: unknown[] } | null
  if (!read?.Game) return null
  return { Game: { ...read.Game, ...(Array.isArray(read.Plays) ? { LastPlays: read.Plays } : {}) } }
}

// While FILE_HOST is down, one game's whole file from sidearmstats.com (the file SIDEARM's page opens with), in
// the first minute of each 10, games taking turns. Nothing while FILE_HOST answers: the file is cached
// (x-cache-hit), so it could land an older score over a push's.
async function backup(games: Game[], now = Date.now()): Promise<{ id: string; game: unknown } | null> {
  if (games.length === 0 || now % BACKUP_MS >= 60_000) return null
  // Short waits: the pushes' writes queue behind this.
  const up = await fetch(FILE_HOST, { method: "HEAD", headers: UA, signal: AbortSignal.timeout(5_000) })
    .then(() => true, () => false)
  if (up) return null
  // In a fixed order, so two games really take turns (the database hands them out in no set order).
  const g = [...games].sort((a, b) => a.id.localeCompare(b.id))[Math.floor(now / BACKUP_MS) % games.length]
  const file = g.grp.replace(/^livestats\/|\/game$/g, "")
  const res = await fetch(`https://sidearmstats.com/${file}/game.json?detail=full`,
                          { headers: UA, signal: AbortSignal.timeout(10_000) })
  console.log(`[live-scores] backup ${file}: ${res.status}`)
  const read = (res.ok ? parse(await res.text()) : null) as { Game?: object; Plays?: unknown[] } | null
  if (!read?.Game) return null
  // Every play so far, oldest first as the scoring plays keep them: the file's own LastPlays holds only the newest
  // five, and ten minutes of scoring plays and fouls would be lost.
  const plays = Array.isArray(read.Plays) ? { LastPlays: read.Plays } : {}
  return { id: g.id, game: { Game: { ...read.Game, ...plays } } }
}

// A push is the new value itself, or "GET:<url>" asking the page to fetch it as JSONP (sidearm.realtime.all.js).
async function gameOf(data: unknown): Promise<unknown | null> {
  if (typeof data !== "string") return data ?? null
  if (!data.startsWith("GET:")) return parse(data)
  // Only SIDEARM's own hosts: a push never sends this function anywhere else. The game's file itself is on
  // sidearmdev.com (api-realtime-stats.prod.sidearmdev.com, SJU football 2026-10-31): without it every push
  // was dropped and the game never went live.
  let url: URL
  try {
    url = new URL(data.slice(4))
  } catch {
    return null
  }
  if (url.protocol !== "https:" || !/(^|\.)(sidearmstats|sidearmsports|sidearmdev)\.com$/.test(url.hostname)) {
    return null
  }
  const res = await fetch(url, { headers: UA })
  return res.ok ? parse(await res.text()) : null
}

function parse(text: string): unknown | null {
  // JSONP: callback({...}); plain JSON otherwise.
  const body = text.trim().replace(/^[\w$.]*\(([\s\S]*)\);?$/, "$1")
  try {
    return JSON.parse(body)
  } catch {
    return null
  }
}

function json(body: unknown, status: number) {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } })
}
