// Display-time parsing for the Today timeline. start_time is a free-text display
// string ("7am", "noon", "7:30pm", null) — we parse it to minutes-from-midnight
// only for SORTING and for placing the live "now" marker. Never for a to-scale axis.

/** Free-text display time ("7am", "noon") → minutes from midnight; undated last. */
export function minutesOf(s: string | null | undefined): number {
  if (!s) return 24 * 60 // all-day / undated sorts to the end
  const t = s.trim().toLowerCase()
  if (t.includes('noon')) return 12 * 60
  if (t.includes('midnight')) return 0
  const m = t.match(/(\d{1,2})(?::(\d{2}))?\s*(a|p)/)
  if (!m) return 24 * 60
  let h = parseInt(m[1], 10)
  const min = m[2] ? parseInt(m[2], 10) : 0
  if (m[3] === 'p' && h < 12) h += 12
  if (m[3] === 'a' && h === 12) h = 0
  return h * 60 + min
}

export const byTime = (a: { start_time: string | null }, b: { start_time: string | null }) =>
  minutesOf(a.start_time) - minutesOf(b.start_time)

/** Current wall-clock minutes from midnight, in the user's timezone. */
export function nowMinutes(d: Date = new Date()): number {
  return d.getHours() * 60 + d.getMinutes()
}

// Live right now: the event's start time has arrived and it's within the last
// two hours — not just "some time today." Untimed (all-day) events are never live.
const LIVE_WINDOW_MIN = 120
export function isLiveNow(startTime: string | null, nowM: number = nowMinutes()): boolean {
  if (!startTime) return false
  const startM = minutesOf(startTime)
  if (startM >= 24 * 60) return false // unparseable / all-day
  return nowM >= startM && nowM <= startM + LIVE_WINDOW_MIN
}

/** Minutes-from-midnight → a compact 12-hour label with no suffix ("2:14"). */
export function clockLabel(mins: number): string {
  const h24 = Math.floor(mins / 60) % 24
  const m = mins % 60
  const h = ((h24 + 11) % 12) + 1
  return `${h}:${String(m).padStart(2, '0')}`
}
