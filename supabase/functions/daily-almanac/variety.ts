// variety.ts — deterministic format selection. No AI. Decides which of the six
// almanac "shapes" today's line takes, from the context alone.
//
// Rules (from the spec):
//   1. countdown    — an RSVP within ~48h → hard-wins.
//   2. field_note   — a specific real place not in recent history.
//   3. town_pulse   — new posts exist AND newest event going_count >= 2.
//   4. almanac_fact — day-length delta, moon, or a season-list match (always available).
//   5. nudge        — nothing planned AND today is Wed–Fri.
//   6. callback     — last attended <= 8 days ago AND that event/venue recurs.
// Never the same format two days in a row; when several qualify, weighted random
// (countdown 3x, others 1x). Seeded so a (user, day) always resolves the same pick.
//
// Control Room · Panel 1: pickFormat also returns the full scored field
// (`candidates`) — every format, why it was in or out, and the weight it carried
// into the draw — so the decision log can record what was considered and
// rejected, not just the winner. Pure bookkeeping: the seeded draw itself
// (pool order, weights, single weightedPick call) is unchanged from v8, so a
// (user, day) still resolves to the same pick it did before logging existed.
import type { AlmanacContext } from "./context.ts"
import { hashString, mulberry32, weightedPick } from "./rng.ts"

export type AlmanacFormat =
  | "countdown"
  | "field_note"
  | "town_pulse"
  | "almanac_fact"
  | "nudge"
  | "callback"

const ALL_FORMATS: AlmanacFormat[] = [
  "countdown",
  "field_note",
  "town_pulse",
  "almanac_fact",
  "nudge",
  "callback",
]

const COUNTDOWN_WITHIN_DAYS = 1 // day-granular stand-in for "48h" (start_time is a display string)
const CALLBACK_MAX_DAYS_AGO = 8
const TOWN_PULSE_MIN_GOING = 2
const NUDGE_WEEKDAYS = new Set(["Wednesday", "Thursday", "Friday"])

const WEIGHTS: Record<AlmanacFormat, number> = {
  countdown: 3,
  field_note: 1,
  town_pulse: 1,
  almanac_fact: 1,
  nudge: 1,
  callback: 1,
}

// Recency penalty: beyond the hard no-repeat (yesterday), softly down-weight a format
// for each time it appears in the last RECENCY_WINDOW days, so the spread stays varied
// across a week rather than the same qualifier winning every other day.
const RECENCY_WINDOW = 3
const RECENCY_DECAY = 0.3

/** One format's full scoring story, for the decision log. */
export interface FormatCandidate {
  format: AlmanacFormat
  qualified: boolean
  /** Why the format was out before scoring. Null when it qualified. */
  disqualified_because: string | null
  /** True when the no-repeat rule removed it (it was yesterday's format). */
  blocked_by_repeat: boolean
  base_weight: number
  /** Appearances in the last RECENCY_WINDOW days (drives the decay). */
  recency_hits: number
  /** The weight it carried into the draw. 0 when out of the pool. */
  effective_weight: number
}

export interface FormatPick {
  format: AlmanacFormat
  qualified: AlmanacFormat[]
  /** Yesterday's format, suppressed by the no-repeat rule (null if none). */
  blocked_by_repeat: AlmanacFormat | null
  reason: string
  /** The full scored field, one entry per format, in ALL_FORMATS order. */
  candidates: FormatCandidate[]
}

/** Every format whose qualifying predicate holds for this context. */
export function qualifies(c: AlmanacContext): AlmanacFormat[] {
  return ALL_FORMATS.filter((f) => disqualifyReason(c, f) === null)
}

/**
 * Why a format is out today, in words specific enough for the decision log —
 * "lower score" is banned; "no RSVP within ~48h (soonest is in 4 days)" is the bar.
 * Null means the format qualifies.
 */
function disqualifyReason(c: AlmanacContext, f: AlmanacFormat): string | null {
  switch (f) {
    case "countdown": {
      if (c.my_events.some((e) => e.days_until <= COUNTDOWN_WITHIN_DAYS)) return null
      if (c.my_events.length === 0) return "no upcoming RSVPs at all"
      const soonest = Math.min(...c.my_events.map((e) => e.days_until))
      return `no RSVP within ~48h (soonest is in ${soonest} days)`
    }
    case "field_note":
      return c.field_note_candidates.length > 0
        ? null
        : "no fresh place candidates (every curated place appears in recent history)"
    case "town_pulse": {
      if (c.town_pulse.new_posts_24h === 0) return "no new posts in the last 24h"
      const going = c.town_pulse.newest_event?.going_count ?? 0
      return going >= TOWN_PULSE_MIN_GOING
        ? null
        : `newest event has ${going} going < ${TOWN_PULSE_MIN_GOING}`
    }
    case "almanac_fact":
      // Moon is always present, so this is the guaranteed fallback qualifier.
      return c.sun.day_length_change_minutes_vs_week_ago != null ||
          c.calendar.season_markers.length > 0 ||
          c.moon_phase != null
        ? null
        : "no day-length delta, season marker, or moon phase available"
    case "nudge": {
      if (!c.nothing_planned) return "the reader has plans on the calendar"
      return NUDGE_WEEKDAYS.has(c.calendar.weekday)
        ? null
        : `${c.calendar.weekday} is outside the Wed–Fri nudge window`
    }
    case "callback": {
      if (!c.last_attended) return "no past attended event on record"
      if (c.last_attended.days_ago > CALLBACK_MAX_DAYS_AGO) {
        return `last attended was ${c.last_attended.days_ago} days ago > ${CALLBACK_MAX_DAYS_AGO}`
      }
      return c.last_attended.recurs ? null : "the attended event does not recur"
    }
  }
}

export function pickFormat(
  c: AlmanacContext,
  opts: { yesterdayFormat?: string | null; seed: string },
): FormatPick {
  const qualified = qualifies(c)
  const yesterday = normalizeYesterday(opts.yesterdayFormat, qualified)

  // No-repeat: drop yesterday's format. almanac_fact + field_note always qualify, so
  // with >= 2 qualifiers this only ever removes one. If it would empty the set, allow
  // the repeat rather than fail.
  let available = qualified.filter((f) => f !== yesterday)
  let repeatRelaxed = false
  if (available.length === 0) {
    available = qualified
    repeatRelaxed = true
  }

  const recent = c.recent_history.formats.slice(0, RECENCY_WINDOW)
  const candidates: FormatCandidate[] = ALL_FORMATS.map((f) => {
    const disqualified = disqualifyReason(c, f)
    const isBlocked = disqualified === null && !repeatRelaxed && f === yesterday
    const inPool = disqualified === null && !isBlocked
    const recencyHits = recent.filter((r) => r === f).length
    return {
      format: f,
      qualified: disqualified === null,
      disqualified_because: disqualified,
      blocked_by_repeat: isBlocked,
      base_weight: WEIGHTS[f],
      recency_hits: recencyHits,
      effective_weight: inPool ? WEIGHTS[f] * Math.pow(RECENCY_DECAY, recencyHits) : 0,
    }
  })

  // Countdown hard-wins when still available (an imminent RSVP trumps everything).
  if (available.includes("countdown")) {
    return {
      format: "countdown",
      qualified,
      blocked_by_repeat: yesterday && !repeatRelaxed ? yesterday : null,
      reason: "countdown hard-wins (RSVP within ~48h)",
      candidates,
    }
  }

  const rand = mulberry32(hashString(opts.seed))
  const pool = available.map((f) => ({
    item: f,
    weight: WEIGHTS[f] * Math.pow(RECENCY_DECAY, recent.filter((r) => r === f).length),
  }))
  const format = weightedPick(pool, rand)
  return {
    format,
    qualified,
    blocked_by_repeat: yesterday && !repeatRelaxed ? yesterday : null,
    reason: `weighted pick among {${available.join(", ")}}${repeatRelaxed ? " (repeat allowed — no alternative)" : ""}`,
    candidates,
  }
}

/** Yesterday's format only counts for no-repeat if it's a real format that also qualifies today. */
function normalizeYesterday(
  raw: string | null | undefined,
  qualified: AlmanacFormat[],
): AlmanacFormat | null {
  if (!raw) return null
  const f = raw as AlmanacFormat
  return qualified.includes(f) ? f : null
}
