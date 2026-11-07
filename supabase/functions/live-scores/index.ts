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

type Game = { id: string; grp: string }

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
    if (!res.ok) throw new Error(`${name}: ${res.status} ${await res.text()}`)
    return res.json()
  }
  const games = (await rpc("start_live_scores", {})) as Game[]
  if (games.length === 0) return json({ games: 0 }, 200)
  EdgeRuntime.waitUntil(listen(games, rpc).catch((e) => console.error("[live-scores]", e)))
  return json({ games: games.length }, 202)
})

async function listen(games: Game[], rpc: (name: string, body: unknown) => Promise<unknown>) {
  // Each game's score channel and its plays channel, both written through record_live_score.
  const groups = games.flatMap((g) => [g.grp, g.grp.replace(/\/game$/, "/plays")].map((grp) => ({ id: g.id, grp })))
  const byGroup = new Map(groups.map((g) => [g.grp.toLowerCase(), g.id]))
  // Pushes are written one at a time, in the order they came: a score and its play arrive together, and
  // writes racing each other could land an older score last. The backup's read, if any, goes first.
  let writes: Promise<unknown> = backup(games)
    .then((b) => b && rpc("record_live_score", { p_event: b.id, p_game: b.game }))
    .catch((e) => console.error("[live-scores] backup", e))
  // The writes land even when the hub fails, which is when the backup's is needed.
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
        const read = gameOf(message.data)
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
    await writes
  }
}

// While FILE_HOST is down, one game's whole file from sidearmstats.com (the file SIDEARM's page opens with), in
// the first minute of each 10, games taking turns. Nothing while FILE_HOST answers: the file is cached
// (x-cache-hit), so it could land an older score over a push's.
async function backup(games: Game[], now = Date.now()): Promise<{ id: string; game: unknown } | null> {
  if (now % BACKUP_MS >= 60_000) return null
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
