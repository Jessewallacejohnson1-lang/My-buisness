// generate.demo.mts — show the Phase-3 generation pipeline with NO Anthropic API key.
// Assembles the real system + user prompt, injects a fake Claude response, then runs
// validation + place extraction + the row that would be stored. (Weather is fetched
// live from Open-Meteo — no key needed — so the numbers reflect today's real St. Joe day.)
// Run: node generate.demo.mts
import { readFileSync } from "node:fs"
import { fileURLToPath } from "node:url"
import { dirname, join } from "node:path"
import { buildAlmanacContext, type AlmanacContext } from "./context.ts"
import { pickFormat } from "./variety.ts"
import { buildUserMessage, generateLine, extractPlaces } from "./generate.ts"
import type { DataSource } from "./datasource.ts"
import type { WeatherData } from "./weather.ts"

const HERE = dirname(fileURLToPath(import.meta.url))
const SYSTEM_PROMPT = readFileSync(join(HERE, "prompts/almanac.md"), "utf8")

const WEATHER: WeatherData = {
  condition: "Partly cloudy", high: 82, low: 61,
  sunrise: "5:52", sunset: "8:52", day_length_minutes: 900, day_length_change_minutes: -2,
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

// A fake Claude that echoes a plausible line for the assigned format, in the API's
// response shape — so we exercise the real generateLine() parse/validate path.
function fakeAnthropic(cannedLine: string): typeof fetch {
  return (async () =>
    new Response(
      JSON.stringify({
        content: [{ type: "text", text: cannedLine }],
        usage: { input_tokens: 1180, output_tokens: 96 },
      }),
      { status: 200, headers: { "content-type": "application/json" } },
    )) as unknown as typeof fetch
}

const context: AlmanacContext = await buildAlmanacContext({
  userId: "demo-user",
  now: new Date("2026-07-21T19:00:00Z"),
  tz: "America/Chicago",
  data: fakeData({
    upcomingEvents: async () => [
      { title: "St. Joe Farmers Market", event_date: "2026-07-22", start_time: "3pm", location: "Resurrection Lutheran", going_count: 6 },
    ],
    newPostCount24h: async () => 4,
    newestEvent: async () => ({ title: "Sunset paddle on the Sauk", going_count: 5 }),
    recentHistory: async () => [
      { body_text: "The light stretches past 8:52 now.", places_mentioned: ["Millstream Park"], date: "2026-07-20", format_used: "almanac_fact" },
    ],
  }),
})

const pick = pickFormat(context, { yesterdayFormat: "almanac_fact", seed: "demo-user:2026-07-21" })

console.log("=== SYSTEM PROMPT (prompts/almanac.md) ===\n")
console.log(SYSTEM_PROMPT)
console.log("\n=== ASSIGNED FORMAT ===\n" + pick.format + "  (" + pick.reason + ")")
console.log("\n=== USER MESSAGE SENT TO CLAUDE ===\n")
console.log(buildUserMessage(context, pick.format))

// The countdown format should win here (RSVP tomorrow). Simulate Claude's reply.
const cannedLine = "The **St. Joe Farmers Market** lands on Wednesday, and 6 neighbors are already going. Long light after — the sun holds till 8:52."
const gen = await generateLine({
  systemPrompt: SYSTEM_PROMPT, context, format: pick.format,
  apiKey: "fake", fetchImpl: fakeAnthropic(cannedLine),
})

console.log("\n=== GENERATED LINE (validated) ===\n" + gen.line)
console.log("\n=== TOKEN USAGE (logged per call) ===\n" + JSON.stringify(gen.usage))
console.log("\n=== ROW WRITTEN TO almanac_daily ===")
console.log(JSON.stringify({
  user_id: "demo-user",
  date: context.calendar.date,
  body_text: gen.line,
  format_used: pick.format,
  places_mentioned: extractPlaces(gen.line ?? "", context),
}, null, 2))
