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
import type { AlmanacContext } from "./context.ts"
import { hashString, mulberry32, weightedPick } from "./rng.ts"

export type AlmanacFormat =
  | "countdown"
  | "field_note"
  | "town_pulse"
  | "almanac_fact"
  | "nudge"
  | "callback"

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

export interface FormatPick {
  format: AlmanacFormat
  qualified: AlmanacFormat[]
  /** Yesterday's format, suppressed by the no-repeat rule (null if none). */
  blocked_by_repeat: AlmanacFormat | null
  reason: string
}

/** Every format whose qualifying predicate holds for this context. */
export function qualifies(c: AlmanacContext): AlmanacFormat[] {
  const q: AlmanacFormat[] = []
  if (c.my_events.some((e) => e.days_until <= COUNTDOWN_WITHIN_DAYS)) q.push("countdown")
  if (c.field_note_candidates.length > 0) q.push("field_note")
  if (c.town_pulse.new_posts_24h > 0 && (c.town_pulse.newest_event?.going_count ?? 0) >= TOWN_PULSE_MIN_GOING) {
    q.push("town_pulse")
  }
  if (almanacFactQualifies(c)) q.push("almanac_fact")
  if (c.nothing_planned && NUDGE_WEEKDAYS.has(c.calendar.weekday)) q.push("nudge")
  if (c.last_attended && c.last_attended.days_ago <= CALLBACK_MAX_DAYS_AGO && c.last_attended.recurs) {
    q.push("callback")
  }
  return q
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

  // Countdown hard-wins when still available (an imminent RSVP trumps everything).
  if (available.includes("countdown")) {
    return {
      format: "countdown",
      qualified,
      blocked_by_repeat: yesterday && !repeatRelaxed ? yesterday : null,
      reason: "countdown hard-wins (RSVP within ~48h)",
    }
  }

  const rand = mulberry32(hashString(opts.seed))
  const recent = c.recent_history.formats.slice(0, RECENCY_WINDOW)
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
  }
}

function almanacFactQualifies(c: AlmanacContext): boolean {
  // Moon is always present, so this is the guaranteed fallback qualifier.
  return (
    c.sun.day_length_change_minutes_vs_week_ago != null ||
    c.calendar.season_markers.length > 0 ||
    c.moon_phase != null
  )
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
