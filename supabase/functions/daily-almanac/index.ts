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
import { buildAlmanacContext } from "./context.ts"
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

    // --- One generation per user per day, ever -------------------------------
    const cached = await readCached(rest, userId, today)
    if (cached) return json({ line: cached.body_text, format: cached.format_used, cached: true })

    // --- Build the day, pick a format ----------------------------------------
    const data = postgrestDataSource(rest)
    const context = await buildAlmanacContext({ userId, now, tz: TZ, data })
    const yesterdayFormat = context.recent_history.formats[0] ?? null
    const pick = pickFormat(context, { yesterdayFormat, seed: `${userId}:${today}` })
    console.log(`[almanac] user=${userId} date=${today} format=${pick.format} ` +
      `qualified=[${pick.qualified.join(",")}] reason="${pick.reason}"`)

    // --- Generate --------------------------------------------------------------
    let systemPrompt: string
    try {
      systemPrompt = await Deno.readTextFile(new URL("./prompts/almanac.md", import.meta.url))
    } catch {
      return json({ line: null }) // no prompt on disk → fall open
    }

    const gen = await generateLine({ systemPrompt, context, format: pick.format, apiKey: anthropicKey })
    if (gen.usage) {
      console.log(`[almanac] tokens in=${gen.usage.input_tokens} out=${gen.usage.output_tokens}`)
    }
    if (!gen.line) return json({ line: null }) // generation failed — fall open, no row written

    // --- Store (one row per user per day) + return ---------------------------
    const places = extractPlaces(gen.line, context)
    await writeRow(rest, { userId, today, line: gen.line, format: pick.format, places })
    return json({ line: gen.line, format: pick.format, cached: false })
  } catch {
    return json({ line: null })
  }
})

interface CachedRow {
  body_text: string
  format_used: string
}

async function readCached(
  rest: (path: string, init?: RequestInit) => Promise<Response>,
  userId: string,
  today: string,
): Promise<CachedRow | null> {
  try {
    const res = await rest(`almanac_daily?select=body_text,format_used&user_id=eq.${userId}&date=eq.${today}`)
    if (!res.ok) return null
    const rows = await res.json()
    const row = rows?.[0]
    return row && row.body_text ? { body_text: row.body_text, format_used: row.format_used } : null
  } catch {
    return null
  }
}

async function writeRow(
  rest: (path: string, init?: RequestInit) => Promise<Response>,
  row: { userId: string; today: string; line: string; format: string; places: string[] },
): Promise<void> {
  try {
    await rest(`almanac_daily?on_conflict=user_id,date`, {
      method: "POST",
      headers: { Prefer: "resolution=merge-duplicates,return=minimal" },
      body: JSON.stringify({
        user_id: row.userId,
        date: row.today,
        body_text: row.line,
        format_used: row.format,
        places_mentioned: row.places,
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
