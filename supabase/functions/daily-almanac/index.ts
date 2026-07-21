// Supabase Edge Function: the "Daily Almanac" — PER-USER edition.
//
// Replaces the old town-wide shared line. For the calling user, builds their real
// day server-side (weather + sun + moon + season + their RSVPs + town pulse + their
// own last-7 history), picks one of six formats deterministically, and has Claude
// (Haiku) write ONE warm, precise line from those facts. Cached one-per-user-per-day
// in almanac_daily — a user's line never regenerates once written.
//
// Deploy: supabase functions deploy daily-almanac
// Secret: reuses the project's existing ANTHROPIC_API_KEY (same as moderate-post).
//
// Contract (unchanged for the client):
//   POST /functions/v1/daily-almanac   (anon apikey + Bearer user JWT)
//     -> 200 { "line": "<entry>", "format": "...", "cached": bool }
//     -> 200 { "line": null }   fail-open — the client keeps its on-device template
//
// St. Joseph, MN. Weather pinned to America/Chicago.
import { buildAlmanacContext, type AlmanacContext } from "./context.ts"
import { makeRest, postgrestDataSource } from "./datasource.ts"
import { pickFormat } from "./variety.ts"
import { generateLine, extractPlaces } from "./generate.ts"
import { localDateISO } from "./dates.ts"

const TZ = "America/Chicago"

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS })
  const json = (body: unknown, status = 200) =>
    new Response(JSON.stringify(body), { status, headers: { ...CORS, "Content-Type": "application/json" } })

  // Any failure past this point falls open to the client's template — never throw.
  try {
    const anthropicKey = Deno.env.get("ANTHROPIC_API_KEY")
    const supaUrl = Deno.env.get("SUPABASE_URL")
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")
    if (!anthropicKey || !supaUrl || !serviceKey) return json({ line: null })

    const userId = userIdFromRequest(req)
    if (!userId) return json({ line: null })

    const now = new Date()
    const today = localDateISO(now, TZ)
    const rest = makeRest(supaUrl, serviceKey)
    const data = postgrestDataSource(rest)

    // --- Build the day's real context, then fingerprint its MATERIAL facts ----
    // We serve the cached line while the fingerprint matches, and rewrite the row
    // when the day's facts change — so the line stays fresh within the day, not
    // only at first open. (The row key is per user per day, so it also rolls at
    // local midnight.) Building the context is cheap; only Claude is gated.
    const context = await buildAlmanacContext({ userId, now, tz: TZ, data })
    const factsHash = await sha256(materialFacts(context))

    const cached = await readCached(rest, userId, today)
    if (cached && cached.facts_hash === factsHash && cached.body_text) {
      return json({ line: cached.body_text, format: cached.format_used, cached: true })
    }

    // --- Facts changed (or first line today) → pick a format and (re)generate --
    const yesterdayFormat = context.recent_history.formats[0] ?? null
    const pick = pickFormat(context, { yesterdayFormat, seed: `${userId}:${today}` })
    console.log(`[almanac] user=${userId} date=${today} format=${pick.format} ` +
      `${cached ? "REGEN" : "first"} qualified=[${pick.qualified.join(",")}]`)

    let systemPrompt: string
    try {
      systemPrompt = await Deno.readTextFile(new URL("./prompts/almanac.md", import.meta.url))
    } catch {
      return keepOrFallOpen(cached, json) // no prompt on disk → keep any existing line, else fall open
    }

    const gen = await generateLine({ systemPrompt, context, format: pick.format, apiKey: anthropicKey })
    if (gen.usage) {
      console.log(`[almanac] tokens in=${gen.usage.input_tokens} out=${gen.usage.output_tokens}`)
    }
    if (!gen.line) return keepOrFallOpen(cached, json) // failed refresh keeps today's existing line

    const places = extractPlaces(gen.line, context)
    await writeRow(rest, { userId, today, line: gen.line, format: pick.format, places, factsHash })
    return json({ line: gen.line, format: pick.format, cached: false })
  } catch {
    return json({ line: null })
  }
})

interface CachedRow {
  body_text: string
  format_used: string
  facts_hash: string | null
}

async function readCached(
  rest: (path: string, init?: RequestInit) => Promise<Response>,
  userId: string,
  today: string,
): Promise<CachedRow | null> {
  try {
    const res = await rest(
      `almanac_daily?select=body_text,format_used,facts_hash&user_id=eq.${userId}&date=eq.${today}`,
    )
    if (!res.ok) return null
    const rows = await res.json()
    const row = rows?.[0]
    return row && row.body_text
      ? { body_text: row.body_text, format_used: row.format_used, facts_hash: row.facts_hash ?? null }
      : null
  } catch {
    return null
  }
}

/** A failed/absent generation keeps today's existing line (if any) rather than blanking. */
function keepOrFallOpen(cached: CachedRow | null, json: (b: unknown, s?: number) => Response): Response {
  if (cached && cached.body_text) {
    return json({ line: cached.body_text, format: cached.format_used, cached: true })
  }
  return json({ line: null })
}

/** SHA-256 hex of a string (Web Crypto — available in Deno). */
async function sha256(s: string): Promise<string> {
  const buf = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(s))
  return [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, "0")).join("")
}

/**
 * The day's MATERIAL facts — a change here means the line should be rewritten. Excludes
 * the exact high/low (a 1° forecast tick shouldn't churn a rewrite), plus recent_history
 * and field_note_candidates (ledger/derived, not "today's facts"). Includes weather state,
 * sun, moon, season, the user's events, last-attended, town pulse, and nothing_planned.
 */
function materialFacts(c: AlmanacContext): string {
  return JSON.stringify({
    condition: c.weather.condition,
    sunrise: c.sun.sunrise,
    sunset: c.sun.sunset,
    day_len_delta: c.sun.day_length_change_minutes,
    moon: c.moon_phase.name,
    seasons: c.calendar.season_markers.map((m) => m.key),
    events: c.my_events.map((e) => `${e.name}@${e.day}|${e.days_until}|${e.going_count}`),
    last_attended: c.last_attended
      ? `${c.last_attended.name}|${c.last_attended.days_ago}|${c.last_attended.recurs}`
      : null,
    pulse_posts: c.town_pulse.new_posts_24h,
    pulse_newest: c.town_pulse.newest_event
      ? `${c.town_pulse.newest_event.title}|${c.town_pulse.newest_event.going_count}`
      : null,
    nothing_planned: c.nothing_planned,
  })
}

async function writeRow(
  rest: (path: string, init?: RequestInit) => Promise<Response>,
  row: { userId: string; today: string; line: string; format: string; places: string[]; factsHash: string },
): Promise<void> {
  try {
    // Upsert on (user_id, date): first line of the day inserts, a same-day refresh
    // overwrites body_text/format/places/facts_hash and stamps updated_at.
    await rest(`almanac_daily?on_conflict=user_id,date`, {
      method: "POST",
      headers: { Prefer: "resolution=merge-duplicates,return=minimal" },
      body: JSON.stringify({
        user_id: row.userId,
        date: row.today,
        body_text: row.line,
        format_used: row.format,
        places_mentioned: row.places,
        facts_hash: row.factsHash,
        updated_at: new Date().toISOString(),
      }),
    })
  } catch {
    // Returning the line still works even if the write fails.
  }
}

/** Decode the caller's user id from the Supabase JWT `sub` claim (already gateway-verified). */
function userIdFromRequest(req: Request): string | null {
  const auth = req.headers.get("Authorization") ?? ""
  const token = auth.startsWith("Bearer ") ? auth.slice(7) : ""
  const payload = token.split(".")[1]
  if (!payload) return null
  try {
    const b64 = payload.replace(/-/g, "+").replace(/_/g, "/")
    const padded = b64 + "=".repeat((4 - (b64.length % 4)) % 4)
    const claims = JSON.parse(atob(padded))
    return typeof claims.sub === "string" ? claims.sub : null
  } catch {
    return null
  }
}
