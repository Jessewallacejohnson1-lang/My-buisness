/**
 * Returns a date as a YYYY-MM-DD string in the user's local timezone.
 * Always use this for calendar/event dates — never `toISOString()`, which is
 * UTC and rolls over a day early for evening times in US timezones.
 */
export function localDate(d: Date = new Date()): string {
  return d.toLocaleDateString('en-CA')
}

export function addDays(n: number): Date {
  const d = new Date()
  d.setDate(d.getDate() + n)
  return d
}

/** "Sat" from a YYYY-MM-DD string, parsed in local time. */
export function weekdayLabel(ymd: string): string {
  const [y, m, d] = ymd.split('-').map(Number)
  return new Date(y, m - 1, d).toLocaleDateString('en-US', { weekday: 'short' })
}
