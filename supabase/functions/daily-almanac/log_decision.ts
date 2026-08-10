// log_decision.ts — Control Room · Panel 1: record what the almanac considered
// and rejected, per run, into content_decisions + content_candidates.
//
// Write rules honored here (from the Control Room build spec):
//   - one run_id per execution; every candidate logged, not just the winner
//   - score_breakdown keys sum to score
//   - rejection_reason is specific ("no RSVP within ~48h (soonest is in 4 days)"),
//     never "lower score"
//   - rule_version bumps on every selection-weight change
//
// This module must NEVER break the almanac: it is called behind a .catch and
// throws only inside its own async body. A logging failure costs a log row,
// not the user's line.

import type { AlmanacContext } from "./context.ts"
import type { FormatCandidate, FormatPick } from "./variety.ts"

/** Bump whenever variety.ts weights/rules change. */
export const ALMANAC_RULE_VERSION = "almanac-variety-v1"

type Rest = (path: string, init?: RequestInit) => Promise<Response>

export interface DecisionLogArgs {
  rest: Rest
  context: AlmanacContext
  pick: FormatPick
  userId: string
  seed: string
  line: string
  places: string[]
  /** True when this run rewrote an existing same-day line (facts changed). */
  wasRegen: boolean
  factsHash: string
}

export async function logFormatDecision(args: DecisionLogArgs): Promise<void> {
  const { rest, context: c, pick } = args
  const decisionId = crypto.randomUUID()
  const runId = crypto.randomUUID()

  // Rank the field by the weight each format carried into the draw. The chosen
  // format keeps its natural rank — a weighted draw can and does pick a
  // lower-scored qualifier, and the log should show that honestly.
  const ranked = [...pick.candidates].sort((a, b) => b.effective_weight - a.effective_weight)
  const chosenEffective =
    pick.candidates.find((k) => k.format === pick.format)?.effective_weight ?? 0

  const candidateRows = ranked.map((k, i) => {
    const isChosen = k.format === pick.format
    return {
      id: crypto.randomUUID(),
      decision_id: decisionId,
      rank: i + 1,
      source_url: null,
      source_name: "variety.ts",
      // Format selection is internal, derived content — the evergreen tier.
      trust_tier: "evergreen",
      corroboration_ct: 0,
      score: k.effective_weight,
      score_breakdown: scoreBreakdown(k),
      outcome: isChosen ? "chosen" : "rejected",
      rejection_reason: isChosen ? null : rejectionReason(k, pick, chosenEffective, args.seed),
      payload: payloadFor(k, c, isChosen ? args : null),
    }
  })

  const chosenRow = candidateRows.find((r) => r.outcome === "chosen")

  const decisionRow = {
    id: decisionId,
    run_id: runId,
    surface: "almanac",
    target_user_id: args.userId,
    chosen_candidate_id: chosenRow?.id ?? null,
    rule_version: ALMANAC_RULE_VERSION,
    inputs: {
      // Spec-minimum keys first. Interests and the knows-St-Joe level are not
      // signals the almanac reads yet — logged as null rather than fetched
      // just to fill a column, so the log reflects what the routine SAW.
      user_rsvps: c.my_events,
      user_interests: null,
      knows_st_joe_level: null,
      day_of_week: c.calendar.weekday,
      weather: c.weather,
      seeded_pool_size: c.field_note_candidates.length,
      // The signals the selection actually turns on.
      field_note_candidates: c.field_note_candidates.map((p) => p.name),
      town_pulse: c.town_pulse,
      nothing_planned: c.nothing_planned,
      last_attended: c.last_attended,
      recent_formats: c.recent_history.formats,
      recent_places: c.recent_history.places,
      season_markers: c.calendar.season_markers.map((m) => m.key),
      moon_phase: c.moon_phase.name,
      seed: args.seed,
      facts_hash: args.factsHash,
    },
    notes:
      `${args.wasRegen ? "regen — the day's facts changed" : "first line of the day"}; ` +
      pick.reason,
  }

  await insert(rest, "content_decisions", [decisionRow])
  await insert(rest, "content_candidates", candidateRows)
}

/** Keys sum to score: base + recency_penalty (+ removal) = effective weight. */
function scoreBreakdown(k: FormatCandidate): Record<string, number> {
  if (!k.qualified) return { base_weight: 0 }
  if (k.blocked_by_repeat) {
    return { base_weight: k.base_weight, no_repeat_block: -k.base_weight }
  }
  const penalty = k.effective_weight - k.base_weight
  return penalty === 0
    ? { base_weight: k.base_weight }
    : { base_weight: k.base_weight, recency_penalty: penalty }
}

function rejectionReason(
  k: FormatCandidate,
  pick: FormatPick,
  chosenEffective: number,
  seed: string,
): string {
  if (!k.qualified) return k.disqualified_because ?? "did not qualify"
  if (k.blocked_by_repeat) return "no-repeat rule: this was yesterday's format"
  if (pick.format === "countdown") {
    return "an imminent RSVP hard-wins: countdown trumps the weighted pool"
  }
  return (
    `lost the seeded weighted draw: weight ${round3(k.effective_weight)} vs ` +
    `${round3(chosenEffective)} for ${pick.format} (seed ${seed})`
  )
}

/** What each candidate WOULD have rendered from — its qualifying evidence. */
function payloadFor(
  k: FormatCandidate,
  c: AlmanacContext,
  chosen: DecisionLogArgs | null,
): Record<string, unknown> {
  const evidence: Record<string, unknown> = { format: k.format }
  switch (k.format) {
    case "countdown":
      evidence.soonest_event = c.my_events[0] ?? null
      break
    case "field_note":
      evidence.places_offered = c.field_note_candidates.map((p) => p.name)
      break
    case "town_pulse":
      evidence.new_posts_24h = c.town_pulse.new_posts_24h
      evidence.newest_event = c.town_pulse.newest_event
      break
    case "almanac_fact":
      evidence.moon = c.moon_phase.name
      evidence.day_length_change_minutes_vs_week_ago =
        c.sun.day_length_change_minutes_vs_week_ago
      evidence.season_markers = c.calendar.season_markers.map((m) => m.key)
      break
    case "nudge":
      evidence.weekday = c.calendar.weekday
      evidence.nothing_planned = c.nothing_planned
      break
    case "callback":
      evidence.last_attended = c.last_attended
      break
  }
  if (chosen !== null) {
    evidence.line = chosen.line
    evidence.places_mentioned = chosen.places
  }
  return evidence
}

function round3(n: number): number {
  return Math.round(n * 1000) / 1000
}

async function insert(rest: Rest, table: string, rows: unknown[]): Promise<void> {
  const res = await rest(table, {
    method: "POST",
    headers: { Prefer: "return=minimal" },
    body: JSON.stringify(rows),
  })
  if (!res.ok) {
    const detail = await res.text().catch(() => "")
    throw new Error(`decision log insert into ${table} failed: ${res.status} ${detail}`)
  }
}
