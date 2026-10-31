// Supabase Edge Function: live-scores — a game card's live score (BP app docs/plans/game-card, ticket 03).
//
// SIDEARM's live stats page gets each change pushed over SignalR 2.0 (BP app
// references/game-card/live-channel.md): hub `sidearm` at v2-realtime.sidearmsports.com, a channel per
// school, sport and topic (`livestats/csbsju/football/game`, `.../plays` for the scoring plays, ticket 05). pg_cron's private.wake_live_scores calls this every
// minute while an SJU or CSB game is on; it answers at once and listens about a minute in the background,
// writing each pushed Game through public.record_live_score. public.start_live_scores hands out the games at
// most once in 50 seconds, so a second call, from anyone, listens to nothing: verify_jwt is off.
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
  const neg = await (await fetch(`${HUB}/negotiate?clientProtocol=1.3&connectionData=${HUB_DATA}`, { headers: UA })).json()
  const query = `transport=webSockets&clientProtocol=1.3&connectionToken=${encodeURIComponent(neg.ConnectionToken)}` +
    `&connectionData=${HUB_DATA}`
  const ws = new WebSocket(`${HUB.replace("https", "wss")}/connect?${query}`)
  // Pushes are written one at a time, in the order they came: a score and its play arrive together, and
  // writes racing each other could land an older score last.
  let writes: Promise<unknown> = Promise.resolve()

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
  await writes
}

// A push is the new value itself, or "GET:<url>" asking the page to fetch it as JSONP (sidearm.realtime.all.js).
async function gameOf(data: unknown): Promise<unknown | null> {
  if (typeof data !== "string") return data ?? null
  if (!data.startsWith("GET:")) return parse(data)
  // Only SIDEARM's own hosts: a push never sends this function anywhere else.
  let url: URL
  try {
    url = new URL(data.slice(4))
  } catch {
    return null
  }
  if (url.protocol !== "https:" || !/(^|\.)(sidearmstats|sidearmsports)\.com$/.test(url.hostname)) return null
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
