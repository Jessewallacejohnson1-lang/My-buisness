// A day on the Town's calendar, `days` from today, as 'YYYY-MM-DD': the date the functions count
// with (now() at time zone 'America/Chicago')::date. Days are counted on the calendar, never as
// 24-hour steps: the day the clocks fall back has 25 hours, so at 11:58 PM on Nov 1 2026 a step
// of -24 hours was still Nov 1, and "yesterday's" meeting read as today's (city_pages, 2026-11-01).
// A UTC date is no good either: it runs a day ahead from 7 PM Central.
export function townDay(days = 0) {
  const today = new Date().toLocaleDateString('en-CA', { timeZone: 'America/Chicago' });
  const d = new Date(`${today}T00:00:00Z`);
  d.setUTCDate(d.getUTCDate() + days);
  return d.toISOString().slice(0, 10);
}
