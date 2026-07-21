// moon.ts — local moon-phase computation. No API, no dependencies.
// Uses the standard synodic-month approximation against a known new moon.

const MS_PER_DAY = 86_400_000
const SYNODIC_MONTH_DAYS = 29.53058867
// Reference new moon: 2000-01-06 18:14 UTC (a widely used epoch).
const REFERENCE_NEW_MOON_MS = Date.UTC(2000, 0, 6, 18, 14)

export type MoonName =
  | "new moon"
  | "waxing crescent"
  | "first quarter"
  | "waxing gibbous"
  | "full moon"
  | "waning gibbous"
  | "last quarter"
  | "waning crescent"

export interface MoonPhase {
  name: MoonName
  /** Illuminated fraction, 0.0 (new) .. 1.0 (full), rounded to 2 dp. */
  illumination: number
  /** Age in days since the last new moon, 0 .. ~29.53. */
  age_days: number
}

const PHASE_NAMES: readonly MoonName[] = [
  "new moon",
  "waxing crescent",
  "first quarter",
  "waxing gibbous",
  "full moon",
  "waning gibbous",
  "last quarter",
  "waning crescent",
]

export function moonPhase(date: Date): MoonPhase {
  const daysSinceRef = (date.getTime() - REFERENCE_NEW_MOON_MS) / MS_PER_DAY
  let age = daysSinceRef % SYNODIC_MONTH_DAYS
  if (age < 0) age += SYNODIC_MONTH_DAYS

  const cycleFraction = age / SYNODIC_MONTH_DAYS // 0..1 around the lunation
  // Illumination follows a cosine: 0 at new, 1 at full.
  const illumination = (1 - Math.cos(2 * Math.PI * cycleFraction)) / 2

  return {
    name: nameForFraction(cycleFraction),
    illumination: Math.round(illumination * 100) / 100,
    age_days: Math.round(age * 10) / 10,
  }
}

/** Eight equal segments of the cycle, centered on the four principal phases. */
function nameForFraction(f: number): MoonName {
  const seg = Math.floor(f * 8 + 0.5) % 8
  return PHASE_NAMES[seg]
}
