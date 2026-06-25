/**
 * Returns a date as a YYYY-MM-DD string in the user's local timezone.
 * Always use this for calendar/event dates — never `toISOString()`, which is
 * UTC and rolls over a day early for evening times in US timezones.
 */
export function localDate(d: Date = new Date()): string {
  return d.toLocaleDateString('en-CA')
}
