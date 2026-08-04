// generate.ts — turn (context + assigned format) into one almanac line via Claude.
// Raw HTTP to the Anthropic Messages API (Deno edge functions have no SDK), mirroring
// moderate-post/index.ts. Model + params come from the spec: Haiku, 200 tokens, temp 1.0.
import type { AlmanacContext } from "./context.ts"
import type { AlmanacFormat } from "./variety.ts"

const MODEL = "claude-haiku-4-5" // == claude-haiku-4-5-20251001, the id moderate-post uses
const MAX_TOKENS = 200
const TEMPERATURE = 1.0
const MAX_LINE_CHARS = 400 // ~60 words + headroom; longer than this, fall open

const FORMAT_BRIEF: Record<AlmanacFormat, string> = {
  countdown: "Count down the soonest event in my_events — name it and its day, and make it feel close.",
  field_note: "Point at ONE place from field_note_candidates (never one in recent_history.places). A plain observation, not a recommendation.",
  town_pulse: "Report the town's activity: town_pulse.new_posts_24h new posts and the newest_event people are showing up to.",
  almanac_fact: "State a quiet fact about the day itself: the day-length change since a week ago (never call it a day-over-day change), the moon phase, or a season_markers entry.",
  nudge: "Nothing is planned and it's midweek — a gentle, low-bar nudge to get outside. No pressure, no place required.",
  callback: "The reader recently attended last_attended and it comes back around — a light 'you were just there' note.",
}

export interface GenerateResult {
  line: string | null
  usage: { input_tokens: number; output_tokens: number } | null
}

/** The user-turn message: the assigned format brief + the canonical CONTEXT JSON. */
export function buildUserMessage(context: AlmanacContext, format: AlmanacFormat): string {
  return [
    `FORMAT: ${format}`,
    FORMAT_BRIEF[format],
    "",
    "Write today's almanac entry using only the CONTEXT below.",
    "",
    "CONTEXT:",
    JSON.stringify(context, null, 2),
  ].join("\n")
}

type FetchLike = typeof fetch

/** Call Claude and return the validated line (null on any failure — the caller falls open). */
export async function generateLine(opts: {
  systemPrompt: string
  context: AlmanacContext
  format: AlmanacFormat
  apiKey: string
  model?: string
  fetchImpl?: FetchLike
}): Promise<GenerateResult> {
  const fetchImpl = opts.fetchImpl ?? fetch
  try {
    const res = await fetchImpl("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: {
        "x-api-key": opts.apiKey,
        "anthropic-version": "2023-06-01",
        "content-type": "application/json",
      },
      body: JSON.stringify({
        model: opts.model ?? MODEL,
        max_tokens: MAX_TOKENS,
        temperature: TEMPERATURE,
        system: opts.systemPrompt,
        messages: [{ role: "user", content: buildUserMessage(opts.context, opts.format) }],
      }),
    })
    if (!res.ok) return { line: null, usage: null }
    const data = await res.json()
    const usage = data.usage
      ? { input_tokens: data.usage.input_tokens ?? 0, output_tokens: data.usage.output_tokens ?? 0 }
      : null
    const text = (data.content ?? [])
      .filter((b: any) => b.type === "text")
      .map((b: any) => b.text)
      .join("")
      .trim()
    return { line: validateLine(text), usage }
  } catch {
    return { line: null, usage: null }
  }
}

/** Non-empty and card-sized, else null. */
function validateLine(text: string): string | null {
  const line = text.trim()
  if (line.length === 0 || line.length > MAX_LINE_CHARS) return null
  return line
}

/**
 * Which curated field-note places the line actually named — stored as places_mentioned
 * so the anti-repetition ledger can exclude them for the next 7 days. Matches the
 * canonical candidate name (leading "the" tolerated), returns the canonical spelling.
 */
export function extractPlaces(line: string, context: AlmanacContext): string[] {
  const hay = line.toLowerCase()
  const named: string[] = []
  for (const cand of context.field_note_candidates) {
    const name = cand.name.toLowerCase()
    const bare = name.replace(/^the\s+/, "")
    if (hay.includes(name) || hay.includes(bare)) named.push(cand.name)
  }
  return named
}
