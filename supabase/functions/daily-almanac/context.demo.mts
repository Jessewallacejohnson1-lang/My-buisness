// context.demo.mts — local, network-free demonstration of buildAlmanacContext.
// Run: node context.demo.mts   (Node 24 strips the TS types natively)
//
// Prints the context JSON for two seeded scenarios so the shape + logic can be
// reviewed without live Supabase secrets. Dev harness only — never deployed.
import { buildAlmanacContext, type AlmanacDeps } from "./context.ts"
import type { DataSource } from "./datasource.ts"
import type { WeatherData } from "./weather.ts"

const NOW = new Date("2026-07-21T19:00:00Z") // Tue 2pm CDT

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

async function run(label: string, deps: AlmanacDeps): Promise<void> {
  const ctx = await buildAlmanacContext(deps)
  console.log(`\n=== ${label} ===`)
  console.log(JSON.stringify(ctx, null, 2))
}

const common = {
  userId: "demo-user",
  now: NOW,
  tz: "America/Chicago",
  fetchWeather: async () => WEATHER,
}

await run("Scenario A — RSVP tomorrow (Farmers Market)", {
  ...common,
  data: fakeData({
    upcomingEvents: async () => [
      {
        title: "St. Joe Farmers Market",
        event_date: "2026-07-22",
        start_time: "3pm",
        location: "Resurrection Lutheran",
        going_count: 6,
      },
      {
        title: "Trivia at Bello Cucina",
        event_date: "2026-07-24",
        start_time: "7pm",
        location: "Bello Cucina",
        going_count: 3,
      },
    ],
    lastAttendedEvent: async () => ({
      title: "Music in Millstream Park",
      event_date: "2026-07-16",
      location: "Millstream Park",
      recurs: true,
    }),
    newPostCount24h: async () => 4,
    newestEvent: async () => ({ title: "Sunset paddle on the Sauk", going_count: 5 }),
    recentHistory: async () => [
      {
        body_text: "Long light tonight — the sun holds past 8:52.",
        places_mentioned: ["Millstream Park"],
        date: "2026-07-20",
        format_used: "almanac_fact",
      },
      {
        body_text: "Warm and quiet. A good morning for the Lake Wobegon Trail.",
        places_mentioned: ["the Lake Wobegon Trail"],
        date: "2026-07-19",
        format_used: "field_note",
      },
    ],
  }),
})

await run("Scenario B — nothing planned", {
  ...common,
  data: fakeData({
    newPostCount24h: async () => 1,
    newestEvent: async () => ({ title: "Community garden work night", going_count: 2 }),
    recentHistory: async () => [
      {
        body_text: "The days are just past their peak now.",
        places_mentioned: [],
        date: "2026-07-20",
        format_used: "almanac_fact",
      },
    ],
  }),
})
