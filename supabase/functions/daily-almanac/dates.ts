// dates.ts — small date/time helpers for the Almanac context builder.
// Pure functions, no Deno/Node globals — safe under Deno (edge) or Node (demo/verify).

const MS_PER_DAY = 86_400_000

/** YYYY-MM-DD for `date` in the given IANA timezone (e.g. 'America/Chicago'). */
export function localDateISO(date: Date, tz: string): string {
  // en-CA yields YYYY-MM-DD
  return new Intl.DateTimeFormat("en-CA", {
    timeZone: tz,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(date)
}

/** Long weekday name ('Saturday') for a YYYY-MM-DD string, timezone-independent. */
export function weekdayOf(ymd: string): string {
  const [y, m, d] = ymd.split("-").map(Number)
  // noon UTC avoids any rollover when formatting the weekday
  return new Intl.DateTimeFormat("en-US", { weekday: "long", timeZone: "UTC" })
    .format(new Date(Date.UTC(y, m - 1, d, 12)))
}

/** Parse a YYYY-MM-DD string to a UTC-noon Date (stable for whole-day arithmetic). */
export function ymdToUTC(ymd: string): Date {
  const [y, m, d] = ymd.split("-").map(Number)
  return new Date(Date.UTC(y, m - 1, d, 12))
}

/** Whole-day difference b - a (both YYYY-MM-DD). Positive when b is later. */
export function daysBetween(aYmd: string, bYmd: string): number {
  return Math.round((ymdToUTC(bYmd).getTime() - ymdToUTC(aYmd).getTime()) / MS_PER_DAY)
}

/** Add `n` days to a YYYY-MM-DD string, returning YYYY-MM-DD. */
export function addDaysISO(ymd: string, n: number): string {
  const d = ymdToUTC(ymd)
  d.setUTCDate(d.getUTCDate() + n)
  return d.toISOString().slice(0, 10)
}

/** "2026-07-05T20:58" (offset-less local) -> "8:52"; null when unparseable. */
export function clock(iso: string | null | undefined): string | null {
  if (!iso) return null
  const m = iso.match(/T(\d{2}):(\d{2})/)
  if (!m) return null
  let h = parseInt(m[1], 10)
  const min = m[2]
  h = h % 12
  if (h === 0) h = 12
  return `${h}:${min}`
}

/** Minutes-since-midnight from an offset-less local ISO ("...T20:58" -> 1252). */
export function minutesFromISO(iso: string | null | undefined): number | null {
  if (!iso) return null
  const m = iso.match(/T(\d{2}):(\d{2})/)
  if (!m) return null
  return parseInt(m[1], 10) * 60 + parseInt(m[2], 10)
}
