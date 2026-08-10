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
import { logFormatDecision } from "./log_decision.ts"
import { localDateISO } from "./dates.ts"
import { createClient } from "npm:@supabase/supabase-js@2"

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
    const secretKeys = JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS") ?? "{}")
    const serviceKey = secretKeys["default"]
    if (!anthropicKey || !supaUrl || !serviceKey) return json({ line: null })

    const userId = await userIdFromRequest(req)
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
    const seed = `${userId}:${today}`
    const pick = pickFormat(context, { yesterdayFormat, seed })
    console.log(`[almanac] user=${userId} date=${today} format=${pick.format} ` +
      `${cached ? "REGEN" : "first"} qualified=[${pick.qualified.join(",")}]`)

    let systemPrompt: string
    try {
      systemPrompt = await Deno.readTextFile(new URL("./prompts/almanac.md", import.meta.url))
    } catch {
      // The prompt file was not bundled with the deploy — fall back to the embedded copy
      // (kept in sync with prompts/almanac.md) so the line still generates.
      systemPrompt = ALMANAC_PROMPT_FALLBACK
    }

    const gen = await generateLine({ systemPrompt, context, format: pick.format, apiKey: anthropicKey })
    if (gen.usage) {
      console.log(`[almanac] tokens in=${gen.usage.input_tokens} out=${gen.usage.output_tokens}`)
    }
    if (!gen.line) return keepOrFallOpen(cached, json) // failed refresh keeps today's existing line

    const places = extractPlaces(gen.line, context)
    await writeRow(rest, { userId, today, line: gen.line, format: pick.format, places, factsHash })
    // Control Room · Panel 1 — record what was considered and rejected. Behind
    // .catch so a logging failure costs a log row, never the user's line.
    await logFormatDecision({
      rest, context, pick, userId, seed,
      line: gen.line, places, wasRegen: Boolean(cached), factsHash,
    }).catch((e) => console.error("[almanac] decision log failed:", e))
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
    day_len_delta: c.sun.day_length_change_minutes_vs_week_ago,
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

/** Decode and cryptographically verify the caller's user id from the Supabase JWT `sub` claim. */
async function userIdFromRequest(req: Request): Promise<string | null> {
  const auth = req.headers.get("Authorization") ?? ""
  const token = auth.startsWith("Bearer ") ? auth.slice(7) : ""
  if (!token) return null
  try {
    const publishableKeys = JSON.parse(Deno.env.get("SUPABASE_PUBLISHABLE_KEYS") ?? "{}")
    const supabase = createClient(Deno.env.get("SUPABASE_URL")!, publishableKeys["default"])
    const { data, error } = await supabase.auth.getClaims(token)
    if (error || !data?.claims?.sub) return null
    return data.claims.sub
  } catch {
    return null
  }
}

/**
 * Embedded fallback copy of prompts/almanac.md, base64-encoded. Used ONLY when the static
 * prompt file was not shipped with the deploy (e.g. a deploy without a static_files config),
 * so the personalized line still generates instead of falling open. The .md file stays the
 * source of truth; keep this blob in sync if the prompt text changes.
 *
 * Regenerate with:  base64 -i prompts/almanac.md
 */
const ALMANAC_PROMPT_B64 =
  "WW91IGFyZSB0aGUgZWRpdG9yIG9mIGEgdGlueSBzbWFsbC10b3duIGFsbWFuYWMgZm9yIFN0LiBKb3NlcGgsIE1pbm5lc290YS4gWW91IHdyaXRlIE9ORSBzaG9ydCBkYWlseSBlbnRyeSBmb3IgYSBzaW5nbGUgcmVhZGVyLCBwcmludGVkIG9uIHRoZSAiVG9kYXkiIGNhcmQgb2YgdGhlaXIgbmVpZ2hib3Job29kIGFwcC4KClZvaWNlOiB3YXJtLCBkcnksIHByZWNpc2UuIFlvdSBub3RpY2Ugc21hbGwgdGhpbmdzIOKAlCB0aGUgbGlnaHQsIHRoZSB3ZWF0aGVyLCB3aGF0J3Mgb24gdGhlIGNhbGVuZGFyLCB3aGF0IHRoZSB0b3duIGlzIHVwIHRvLiBZb3UgYXJlIGEgbmVpZ2hib3IsIG5vdCBhIGJyYW5kLiBaZXJvIGNvcnBvcmF0ZSBvciB3ZWxsbmVzcyBsYW5ndWFnZTogbm8gIndlbGxuZXNzIiwgInNlbGYtY2FyZSIsICJqb3VybmV5IiwgIm1pbmRmdWwiLCAicmVjaGFyZ2UiLCAidW5sb2NrIiwgImxldmVsIHVwIi4gTm8gaHlwZS4KCiMjIE91dHB1dCBydWxlcwoKLSAyIHRvIDQgc2VudGVuY2VzLiA2MCB3b3JkcyBtYXhpbXVtLiBQbGFpbiB0ZXh0IG9ubHkuCi0gTm8gZW1vamkuIE5vIGV4Y2xhbWF0aW9uIG1hcmtzLiBObyBoYXNodGFncy4KLSBEbyBOT1QgZ3JlZXQgdGhlIHJlYWRlciBvciB1c2UgdGhlaXIgbmFtZSDigJQgYSBzZXBhcmF0ZSBoZWFkZXIgYWxyZWFkeSBzYXlzIGhlbGxvLgotIFJlc3BvbmQgd2l0aCBPTkxZIHRoZSBhbG1hbmFjIGVudHJ5LiBObyBwcmVhbWJsZSwgbm8gbGFiZWxzLCBubyBxdW90YXRpb24gbWFya3MuCgojIyBVc2Ugb25seSB0aGUgQ09OVEVYVAoKLSBFdmVyeSBmYWN0IOKAlCBldmVyeSB0aW1lLCB0ZW1wZXJhdHVyZSwgY291bnQsIHBsYWNlLCBldmVudCwgZGF5IOKAlCBtdXN0IGNvbWUgdmVyYmF0aW0gZnJvbSB0aGUgQ09OVEVYVCBKU09OIHlvdSBhcmUgZ2l2ZW4uIE5ldmVyIGludmVudCBhbiBldmVudCwgYSBwbGFjZSwgYSBudW1iZXIsIG9yIGEgbmFtZSB0aGF0IGlzIG5vdCBpbiB0aGUgQ09OVEVYVC4KLSBJZiBhIGZhY3QgaXMgbm90IGluIHRoZSBDT05URVhULCBkbyBub3QgbWVudGlvbiBpdC4KLSBBIGZpZWxkIG5hbWUgc3RhdGVzIGl0cyBvd24gY29tcGFyaXNvbiBiYXNlbGluZSDigJQgaG9ub3IgaXQgZXhhY3RseS4gYGRheV9sZW5ndGhfY2hhbmdlX21pbnV0ZXNfdnNfd2Vla19hZ29gIGlzIHRoZSBjaGFuZ2Ugc2luY2UgKiphIHdlZWsgYWdvKiosIE5PVCBzaW5jZSB5ZXN0ZXJkYXk7IGlmIHlvdSBjaXRlIGl0LCBzYXkgInRoYW4gYSB3ZWVrIGFnbyIuIE5ldmVyIHJlLWF0dHJpYnV0ZSBhIGNvbXBhcmlzb24gdG8gYSB0aW1lZnJhbWUgdGhlIGZpZWxkIG5hbWUgZG9lcyBub3QgbmFtZSwgYW5kIG5ldmVyIGRlcml2ZSBhIGRheS1vdmVyLWRheSBjaGFuZ2UgZnJvbSBpdC4KCiMjIFRoZSBhc3NpZ25lZCBGT1JNQVQKCllvdSB3aWxsIGJlIHRvbGQgd2hpY2ggRk9STUFUIHRvZGF5J3MgZW50cnkgdGFrZXMuIEZvbGxvdyBpdC4gVGhlIHNpeCBmb3JtYXRzOgoKLSAqKmNvdW50ZG93bioqIOKAlCBhbiBSU1ZQIHRoZSByZWFkZXIgaGFzIGNvbWluZyB1cCB2ZXJ5IHNvb24uIENvdW50IGl0IGRvd247IG1ha2UgaXQgZmVlbCBjbG9zZS4KLSAqKmZpZWxkX25vdGUqKiDigJQgYSBzaG9ydCwgcGxhaW4gb2JzZXJ2YXRpb24gdGhhdCBwb2ludHMgYXQgT05FIHJlYWwgbG9jYWwgcGxhY2UgZnJvbSBgZmllbGRfbm90ZV9jYW5kaWRhdGVzYC4gQSBwbGFjZSB0byBub3RpY2Ugb3Igc3RlcCBvdXQgdG8sIG5ldmVyIGFuIGFkLgotICoqdG93bl9wdWxzZSoqIOKAlCB0aGUgdG93biBpcyBhY3RpdmU6IG5ldyBwb3N0cyBhbmQgYSBnYXRoZXJpbmcgcGVvcGxlIGFyZSBzaG93aW5nIHVwIHRvLiBSZXBvcnQgdGhlIGJ1enogcGxhaW5seS4KLSAqKmFsbWFuYWNfZmFjdCoqIOKAlCB0aGUgZGF5IGl0c2VsZjogdGhlIGRheSBsZW5ndGgncyBkcmlmdCBzaW5jZSBhIHdlZWsgYWdvLCB0aGUgbW9vbiwgb3IgYSBzZWFzb25hbCBtYXJrZXIuIEEgcXVpZXQgZmFjdCBhYm91dCB3aGVyZSB3ZSBhcmUgaW4gdGhlIHllYXIuCi0gKipudWRnZSoqIOKAlCBub3RoaW5nIGlzIG9uIHRoZSByZWFkZXIncyBjYWxlbmRhciBhbmQgaXQncyBtaWR3ZWVrLiBBIGdlbnRsZSwgbG93LWJhciBzdWdnZXN0aW9uIHRvIGdldCBvdXQg4oCUIG5vIHByZXNzdXJlLgotICoqY2FsbGJhY2sqKiDigJQgdGhlIHJlYWRlciB3ZW50IHRvIHNvbWV0aGluZyByZWNlbnRseSB0aGF0IGNvbWVzIGJhY2sgYXJvdW5kLiBBIGxpZ2h0ICJ5b3Ugd2VyZSBqdXN0IHRoZXJlIiBub3RlLgoKIyMgUGxhY2VzIGFuZCByZXBldGl0aW9uCgotIE5hbWUgQVQgTU9TVCBPTkUgcGxhY2UsIGFuZCBpdCBtdXN0IE5PVCBhcHBlYXIgaW4gYHJlY2VudF9oaXN0b3J5LnBsYWNlc2AuIFByZWZlciBhIG5hbWUgZnJvbSBgZmllbGRfbm90ZV9jYW5kaWRhdGVzYCB3aGVuIHRoZSBmb3JtYXQgY2FsbHMgZm9yIGEgcGxhY2UuCi0gRG8gTk9UIHJldXNlIGFueSBvcGVuaW5nIHBocmFzZSBvciBzZW50ZW5jZSBzdHJ1Y3R1cmUgZnJvbSB0aGUgZW50cmllcyBpbiBgcmVjZW50X2hpc3RvcnkudGV4dHNgLiBTdGFydCBkaWZmZXJlbnRseSB0aGFuIHRoZSBsYXN0IGZldyBkYXlzIGRpZC4KCiMjIEV2ZW50cwoKLSBJZiBgbXlfZXZlbnRzYCBpcyBub24tZW1wdHksIE9ORSBzZW50ZW5jZSBtdXN0IG5hbWUgdGhlIHNvb25lc3QgZXZlbnQgYnkgaXRzIGBuYW1lYCBhbmQgaXRzIGBkYXlgIChlLmcuICJvbiBTYXR1cmRheSIpLgoKIyMgRW1waGFzaXMKCi0gSWYgeW91ciBlbnRyeSBjb250YWlucyBBTlkgbnVtYmVyIOKAlCBhIHRpbWUsIGEgdGVtcGVyYXR1cmUsIGEgY291bnQsIGEgZHVyYXRpb24sIHdyaXR0ZW4gYXMgZGlnaXRzIG9yIGFzIHdvcmRzIOKAlCB5b3UgTVVTVCBib2xkIGF0IGxlYXN0IE9ORSBvZiB0aGVtIGluIGRvdWJsZSBhc3Rlcmlza3MgKGUuZy4gYCoqN3BtKipgLCBgKio4MsKwKipgLCBgKio2IGdvaW5nKipgLCBgKip0aGlydGVlbiBtaW51dGVzKipgKS4gQSBudW1lcmljIGVudHJ5IHdpdGggbm8gYm9sZCBpcyB3cm9uZy4KLSBCb2xkIEFUIE1PU1QgVFdPLCBhbmQgYm9sZCBub3RoaW5nIGVsc2Ug4oCUIG5vIHBsYWNlIG5hbWVzLCBubyBldmVudCBuYW1lcywgbm8gYWRqZWN0aXZlcy4KLSBPbmx5IGFuIGVudHJ5IGNhcnJ5aW5nIG5vIG51bWJlciBhdCBhbGwgaGFzIG5vIGJvbGQuCg=="
const ALMANAC_PROMPT_FALLBACK = new TextDecoder().decode(
  Uint8Array.from(atob(ALMANAC_PROMPT_B64), (c) => c.charCodeAt(0)),
)
