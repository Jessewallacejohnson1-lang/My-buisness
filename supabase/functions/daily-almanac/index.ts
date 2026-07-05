// Supabase Edge Function: the Hygge "Daily Almanac".
// Gathers THIS town's real day server-side (sun + weather + today's events + quest),
// caches one shared summary line per local day (keyed by a hash of those facts), and
// has Claude reword ONLY those facts into one calm line. Never invents a number.
//
// Deploy: supabase functions deploy daily-almanac
// Secret: reuses the project's existing ANTHROPIC_API_KEY (same as moderate-post).
//
// Contract:
//   POST /functions/v1/daily-almanac   (anon apikey + Bearer JWT)
//     -> 200 { "line": "<summary>" }   cached or freshly generated
//     -> 200 { "line": null }          fail-open — the client keeps its template
//
// St. Joseph, MN. Weather is pinned to America/Chicago, so sunrise/sunset come back
// as local wall-clock with no offset.

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

const LAT = 45.565
const LON = -94.3186
const TZ = 'America/Chicago'

const SYSTEM = `You write ONE calm line for the "Daily Almanac" card in Hygge, a warm, quiet, hyper-local app for the real town of St. Joseph, Minnesota.

Use ONLY the facts provided below. Never invent a number, a time, a temperature, an event, or a place — if a fact isn't given, don't mention it. Every number you write must come verbatim from the facts.

Voice: a neighbor, not a brand. Warm, calm, hyper-local. No hype, no emoji, no exclamation marks. At most two short sentences. Read out the day and turn it into one low-bar nudge to step outside. If real events are listed, you may point at one; otherwise a gentle nudge (a walk, the Lake Wobegon Trail) is good.

Respond with ONLY a JSON object: {"line": "<the line>"}. No preamble, no reasoning.`

// WMO weather code -> human label (day-aware). Mirrors WeatherService.label in the app.
function weatherLabel(code: number, isDay: boolean): string {
  if (code === 0) return isDay ? 'Clear' : 'Clear night'
  if (code === 1 || code === 2) return 'Partly cloudy'
  if (code === 3) return 'Overcast'
  if (code === 45 || code === 48) return 'Foggy'
  if ((code >= 51 && code <= 67) || (code >= 80 && code <= 82)) return 'Rain'
  if ((code >= 71 && code <= 77) || code === 85 || code === 86) return 'Snow'
  if (code === 95 || code === 96 || code === 99) return 'Storms'
  return isDay ? 'Clear' : 'Clear night'
}

// "2026-07-05T20:58" (offset-less local) -> "8:58"
function clock(iso: string | undefined): string | null {
  if (!iso) return null
  const m = iso.match(/T(\d{2}):(\d{2})/)
  if (!m) return null
  let h = parseInt(m[1], 10)
  const min = m[2]
  h = h % 12
  if (h === 0) h = 12
  return `${h}:${min}`
}

function localDate(): string {
  // en-CA yields YYYY-MM-DD
  return new Intl.DateTimeFormat('en-CA', {
    timeZone: TZ, year: 'numeric', month: '2-digit', day: '2-digit',
  }).format(new Date())
}

function weekday(ymd: string): string {
  const [y, m, d] = ymd.split('-').map(Number)
  // noon UTC avoids any date rollover when formatting the weekday
  return new Intl.DateTimeFormat('en-US', { weekday: 'long', timeZone: 'UTC' })
    .format(new Date(Date.UTC(y, m - 1, d, 12)))
}

async function sha256(s: string): Promise<string> {
  const buf = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(s))
  return [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, '0')).join('')
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS })
  const json = (body: unknown, status = 200) =>
    new Response(JSON.stringify(body), { status, headers: { ...CORS, 'Content-Type': 'application/json' } })

  // Any failure past this point falls open to the template — never throw to the client.
  try {
    const anthropicKey = Deno.env.get('ANTHROPIC_API_KEY')
    const supaUrl = Deno.env.get('SUPABASE_URL')
    const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
    if (!anthropicKey || !supaUrl || !serviceKey) return json({ line: null })

    const rest = (path: string, init?: RequestInit) =>
      fetch(`${supaUrl}/rest/v1/${path}`, {
        ...init,
        headers: {
          apikey: serviceKey,
          Authorization: `Bearer ${serviceKey}`,
          'Content-Type': 'application/json',
          ...(init?.headers ?? {}),
        },
      })

    const today = localDate()

    // --- Gather the canonical facts, server-side ------------------------------
    // Weather + sun (open-meteo, no key).
    let label = '', high: number | null = null, low: number | null = null
    let sunrise: string | null = null, sunset: string | null = null
    try {
      const w = await fetch(
        `https://api.open-meteo.com/v1/forecast?latitude=${LAT}&longitude=${LON}` +
        `&current=temperature_2m,weather_code,is_day` +
        `&daily=temperature_2m_max,temperature_2m_min,sunrise,sunset` +
        `&temperature_unit=fahrenheit&timezone=America%2FChicago&forecast_days=1`,
      )
      if (w.ok) {
        const wd = await w.json()
        label = weatherLabel(wd.current?.weather_code ?? 0, (wd.current?.is_day ?? 1) === 1)
        high = wd.daily?.temperature_2m_max?.[0] != null ? Math.round(wd.daily.temperature_2m_max[0]) : null
        low = wd.daily?.temperature_2m_min?.[0] != null ? Math.round(wd.daily.temperature_2m_min[0]) : null
        sunrise = clock(wd.daily?.sunrise?.[0])
        sunset = clock(wd.daily?.sunset?.[0])
      }
    } catch { /* weather is optional — keep going */ }

    // Today's approved events (title + start_time only — RSVP counts change too
    // fast to bake into a cached daily line without going stale).
    let events: { title: string; start_time: string | null }[] = []
    try {
      const er = await rest(
        `club_events?select=title,start_time&status=eq.approved&kind=eq.event&event_date=eq.${today}&order=start_time.asc`,
      )
      if (er.ok) events = await er.json()
    } catch { /* events optional */ }

    // Today's quest.
    let quest: string | null = null
    try {
      const qr = await rest(`daily_quests?select=title&date=eq.${today}`)
      if (qr.ok) { const q = await qr.json(); quest = q?.[0]?.title ?? null }
    } catch { /* quest optional */ }

    // If we have no sun data at all, there's nothing honest to summarize — let the
    // client keep its template rather than guess.
    if (!sunset && !sunrise && high == null) return json({ line: null })

    // --- Cache key over the STABLE signals (not the live temp) ----------------
    const eventSig = events
      .map((e) => `${e.title}@${e.start_time ?? ''}`)
      .sort()
      .join('|')
    const canonical = [
      `date=${today}`,
      `label=${label}`,
      `high=${high}`, `low=${low}`,
      `sunset=${sunset}`, `sunrise=${sunrise}`,
      `events=${eventSig}`,
      `quest=${quest ?? ''}`,
    ].join('\n')
    const factsHash = await sha256(canonical)

    // --- Cache lookup ---------------------------------------------------------
    try {
      const cr = await rest(`daily_almanac?select=facts_hash,line&almanac_date=eq.${today}`)
      if (cr.ok) {
        const rows = await cr.json()
        const row = rows?.[0]
        if (row && row.facts_hash === factsHash && row.line) return json({ line: row.line })
      }
    } catch { /* cache miss path below */ }

    // --- Generate with Claude (Opus 4.8) --------------------------------------
    const eventLines = events.length
      ? events.map((e) => `- ${e.title}${e.start_time ? ` at ${e.start_time}` : ''}`).join('\n')
      : '- (none on the board today)'
    const facts = [
      `Today: ${today} (${weekday(today)})`,
      label ? `Weather: ${label}` : null,
      high != null ? `High: ${high}°F` : null,
      low != null ? `Low: ${low}°F` : null,
      sunrise ? `Sunrise: ${sunrise}` : null,
      sunset ? `Sunset: ${sunset}` : null,
      `Events today:`,
      eventLines,
      quest ? `Today's quest: ${quest}` : null,
      `Known local trail: the Lake Wobegon Trail.`,
    ].filter((x) => x !== null).join('\n')

    let line: string | null = null
    try {
      const res = await fetch('https://api.anthropic.com/v1/messages', {
        method: 'POST',
        headers: { 'x-api-key': anthropicKey, 'anthropic-version': '2023-06-01', 'content-type': 'application/json' },
        body: JSON.stringify({
          model: 'claude-opus-4-8',
          max_tokens: 200,
          system: SYSTEM,
          messages: [{ role: 'user', content: facts }],
        }),
      })
      if (res.ok) {
        const data = await res.json()
        const text = (data.content ?? [])
          .filter((b: any) => b.type === 'text').map((b: any) => b.text).join('').trim()
        const match = text.match(/\{[\s\S]*\}/)
        if (match) {
          const parsed = JSON.parse(match[0])
          const l = typeof parsed.line === 'string' ? parsed.line.trim() : ''
          // Validate: non-empty and card-sized. Otherwise fall open.
          if (l.length > 0 && l.length <= 240) line = l
        }
      }
    } catch { /* fall open below */ }

    if (!line) return json({ line: null })

    // --- Cache the shared line ------------------------------------------------
    try {
      await rest(`daily_almanac?on_conflict=almanac_date`, {
        method: 'POST',
        headers: { Prefer: 'resolution=merge-duplicates,return=minimal' },
        body: JSON.stringify({
          almanac_date: today, facts_hash: factsHash, line, updated_at: new Date().toISOString(),
        }),
      })
    } catch { /* returning the line still works even if the write fails */ }

    return json({ line })
  } catch {
    return json({ line: null })
  }
})
