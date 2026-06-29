// Pure, dependency-free helpers for turning a community event into a calendar
// entry. `start_time` is a human display string ('7pm', '7:00p', '19:00'), so we
// best-effort parse it and fall back to an all-day event when we can't.

export type CalendarEventInput = {
  title: string
  event_date: string // 'YYYY-MM-DD'
  start_time?: string | null
  location?: string | null
  description?: string | null
  url?: string | null
}

/** Best-effort parse of a display time into 24h {h, m}. null when unparseable. */
export function parseStartTime(input?: string | null): { h: number; m: number } | null {
  if (!input) return null
  const m = input.trim().toLowerCase().match(/^(\d{1,2})(?::(\d{2}))?\s*(am|pm|a|p)?/)
  if (!m) return null
  let h = parseInt(m[1], 10)
  const min = m[2] ? parseInt(m[2], 10) : 0
  const mer = m[3]?.[0] // 'a' | 'p' | undefined
  if (h > 23 || min > 59) return null
  if (mer === 'p' && h < 12) h += 12
  if (mer === 'a' && h === 12) h = 0
  return { h, m: min }
}

const pad = (n: number) => String(n).padStart(2, '0')
const esc = (v: string) =>
  v.replace(/\\/g, '\\\\').replace(/;/g, '\\;').replace(/,/g, '\\,').replace(/\n/g, '\\n')

/** Build a single-event VCALENDAR string. Timed when start_time parses (2h
 *  default duration), else an all-day event on event_date. Floating local time. */
export function buildIcs(ev: CalendarEventInput): string {
  const [y, mo, d] = ev.event_date.split('-').map((x) => parseInt(x, 10))
  const t = parseStartTime(ev.start_time)
  const uid =
    `${ev.event_date}-${ev.title}`.replace(/[^a-z0-9]+/gi, '-').toLowerCase() + '@hygge.stjoe'
  const lines = [
    'BEGIN:VCALENDAR',
    'VERSION:2.0',
    'PRODID:-//Hygge//St. Joe//EN',
    'BEGIN:VEVENT',
    `UID:${uid}`,
    `SUMMARY:${esc(ev.title)}`,
  ]
  if (t) {
    const start = new Date(y, mo - 1, d, t.h, t.m)
    const end = new Date(start.getTime() + 2 * 60 * 60 * 1000)
    const fmt = (x: Date) =>
      `${x.getFullYear()}${pad(x.getMonth() + 1)}${pad(x.getDate())}T${pad(x.getHours())}${pad(x.getMinutes())}00`
    lines.push(`DTSTART:${fmt(start)}`, `DTEND:${fmt(end)}`)
  } else {
    lines.push(`DTSTART;VALUE=DATE:${y}${pad(mo)}${pad(d)}`)
  }
  if (ev.location) lines.push(`LOCATION:${esc(ev.location)}`)
  const desc = [ev.description, ev.url].filter(Boolean).join('\n')
  if (desc) lines.push(`DESCRIPTION:${esc(desc)}`)
  lines.push('END:VEVENT', 'END:VCALENDAR')
  return lines.join('\r\n')
}
