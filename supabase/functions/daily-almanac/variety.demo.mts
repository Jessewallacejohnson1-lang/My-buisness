// variety.demo.mts — dry-run the deterministic variety engine (no AI, no network).
// Run: node variety.demo.mts
//
// Part 1: a handful of representative days — prints qualifiers + the pick + why.
// Part 2: a 7-day run over a rich (no-countdown) context — shows no-repeat + rotation.
import { buildAlmanacContext, type AlmanacContext, type AlmanacDeps } from "./context.ts"
import { pickFormat, type AlmanacFormat } from "./variety.ts"
import type { DataSource } from "./datasource.ts"
import type { WeatherData } from "./weather.ts"

const WEATHER: WeatherData = {
  condition: "Partly cloudy",
  high: 82,
  low: 61,
  sunrise: "5:52",
  sunset: "8:52",
  day_length_minutes: 900,
  day_length_change_minutes_vs_week_ago: -2,
}

function fakeData(over: Partial<DataSource>): DataSource {
  const base: DataSource = {
    upcomingEvents: async () => [],
    lastAttendedEvent: async () => null,
    newPostCount24h: async () => 0,
    newestEvent: async () => null,
    recentHistory: async () => [],
  }
  return { ...base, ...over }
}

function ctx(nowISO: string, data: DataSource): Promise<AlmanacContext> {
  const deps: AlmanacDeps = {
    userId: "demo-user",
    now: new Date(nowISO),
    tz: "America/Chicago",
    data,
    fetchWeather: async () => WEATHER,
  }
  return buildAlmanacContext(deps)
}

function line(label: string, c: AlmanacContext, yesterday: AlmanacFormat | null, seed: string): AlmanacFormat {
  const pick = pickFormat(c, { yesterdayFormat: yesterday, seed })
  const blocked = pick.blocked_by_repeat ? `  (no-repeat blocked: ${pick.blocked_by_repeat})` : ""
  console.log(
    `${label.padEnd(34)} qualified=[${pick.qualified.join(", ")}]\n` +
      `${" ".repeat(34)} -> ${pick.format.toUpperCase()}  — ${pick.reason}${blocked}`,
  )
  return pick.format
}

// ---- Part 1: representative days ------------------------------------------------
console.log("\n=== Part 1 — representative days ===\n")

// Tue 2026-07-21 19:00Z (2pm CDT). Rich context: RSVP tomorrow → countdown must win.
const countdownCtx = await ctx("2026-07-21T19:00:00Z", fakeData({
  upcomingEvents: async () => [
    { title: "St. Joe Farmers Market", event_date: "2026-07-22", start_time: "3pm", location: "Resurrection Lutheran", going_count: 6 },
  ],
  lastAttendedEvent: async () => ({ title: "Trivia Night", event_date: "2026-07-17", location: "Bello Cucina", recurs: true }),
  newPostCount24h: async () => 4,
  newestEvent: async () => ({ title: "Sunset paddle", going_count: 5 }),
}))
line("Tue — RSVP tomorrow", countdownCtx, "field_note", "demo-user:2026-07-21")

// Wed 2026-07-22 15:00Z (10am CDT). Nothing planned, Wednesday → nudge qualifies.
const nudgeCtx = await ctx("2026-07-22T15:00:00Z", fakeData({
  newPostCount24h: async () => 0,
}))
line("Wed — nothing planned", nudgeCtx, null, "demo-user:2026-07-22")

// Thu 2026-07-23. Town buzzing: 5 new posts, newest event 4 going → town_pulse qualifies.
const pulseCtx = await ctx("2026-07-23T15:00:00Z", fakeData({
  newPostCount24h: async () => 5,
  newestEvent: async () => ({ title: "Community garden work night", going_count: 4 }),
  lastAttendedEvent: async () => ({ title: "Farmers Market", event_date: "2026-07-19", location: "Resurrection Lutheran", recurs: true }),
}))
line("Thu — town buzzing + recent visit", pulseCtx, null, "demo-user:2026-07-23")

// Sun 2026-07-26. Truly quiet: no events, no posts, weekend → only field_note + almanac_fact.
const quietCtx = await ctx("2026-07-26T15:00:00Z", fakeData({}))
line("Sun — quiet day", quietCtx, null, "demo-user:2026-07-26")

// ---- Part 2: a 7-day run, threading yesterday's pick ---------------------------
console.log("\n=== Part 2 — 7 consecutive days (rich context, no countdown) ===\n")

// A steady context where several formats qualify every day; the seed varies per day,
// and yesterday's pick is fed back so no format repeats back-to-back.
const richData = fakeData({
  newPostCount24h: async () => 3,
  newestEvent: async () => ({ title: "Music in the Park", going_count: 3 }),
  lastAttendedEvent: async () => ({ title: "Music in the Park", event_date: "2026-07-14", location: "Millstream Park", recurs: true }),
})

const dates = [
  "2026-07-15", "2026-07-16", "2026-07-17", "2026-07-18",
  "2026-07-19", "2026-07-20", "2026-07-21",
]
let yesterday: AlmanacFormat | null = null
const sequence: AlmanacFormat[] = []
for (const d of dates) {
  const c = await ctx(`${d}T15:00:00Z`, richData)
  yesterday = line(`${d}`, c, yesterday, `demo-user:${d}`)
  sequence.push(yesterday)
}
console.log(`\nsequence: ${sequence.join(" -> ")}`)
console.log(`distinct formats used: ${new Set(sequence).size}`)
console.log(`any back-to-back repeat: ${sequence.some((f, i) => i > 0 && f === sequence[i - 1])}`)
