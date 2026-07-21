// verify.mts — Phase 5: fake the date, run 10 consecutive days for one test user,
// threading each day's result into the next day's history (the real anti-repetition
// ledger). Prints all 10, then checks: 4+ formats, no place repeated within 7 days,
// no back-to-back format, and (LIVE only) no repeated opening phrase.
//
// LIVE run (real Haiku messages):   ANTHROPIC_API_KEY=sk-ant-... node verify.mts
// Offline run (engine-only):        node verify.mts
import { readFileSync } from "node:fs"
import { fileURLToPath } from "node:url"
import { dirname, join } from "node:path"
import { buildAlmanacContext, type AlmanacContext } from "./context.ts"
import { pickFormat, type AlmanacFormat } from "./variety.ts"
import { generateLine, extractPlaces } from "./generate.ts"
import { addDaysISO } from "./dates.ts"
import type { DataSource, HistoryRow, UpcomingEvent } from "./datasource.ts"
import type { WeatherData } from "./weather.ts"

const KEY = process.env.ANTHROPIC_API_KEY ?? ""
const LIVE = KEY.length > 0
const USER = "verify-user"
const HERE = dirname(fileURLToPath(import.meta.url))
const SYSTEM_PROMPT = readFileSync(join(HERE, "prompts/almanac.md"), "utf8")

const WEATHER: WeatherData = {
  condition: "Partly cloudy", high: 79, low: 62,
  sunrise: "5:50", sunset: "8:56", day_length_minutes: 906, day_length_change_minutes_vs_week_ago: -9,
}

const DATES = Array.from({ length: 10 }, (_, i) => addDaysISO("2026-07-15", i))
// A realistic 10-day town, so the qualifier set genuinely varies day to day (rather
// than a static town where town_pulse always wins). Two days carry an imminent RSVP
// (countdown); the town's post activity ebbs and flows (quiet days → no town_pulse);
// the reader's last recurring visit was 2026-07-14, so the callback window fades out
// after ~8 days. field_note + almanac_fact are always available; nudge needs an open
// midweek day. The seeded weighted-random + no-repeat rule does the rest.
const COUNTDOWN_DAYS = new Set([DATES[2], DATES[6]])
const POSTS_24H = [4, 0, 0, 3, 0, 5, 0, 2, 0, 3]
const NEWEST_GOING = [3, 2, 1, 4, 2, 3, 1, 3, 0, 4]
const LAST_ATTENDED_DATE = "2026-07-14" // days_ago grows 1..10 across the run

let ledger: HistoryRow[] = [] // most-recent-first, capped at 7

function dataSource(): DataSource {
  return {
    async upcomingEvents(_uid, today): Promise<UpcomingEvent[]> {
      if (!COUNTDOWN_DAYS.has(today)) return []
      return [{
        title: "Trivia at Bello Cucina",
        event_date: addDaysISO(today, 1),
        start_time: "7pm",
        location: "Bello Cucina",
        going_count: 5,
      }]
    },
    async lastAttendedEvent(_uid) {
      return { title: "Music in the Park", event_date: LAST_ATTENDED_DATE, location: "Millstream Park", recurs: true }
    },
    async newPostCount24h(_since) { return POSTS_24H[DATES.indexOf(currentDate)] ?? 0 },
    async newestEvent() {
      const g = NEWEST_GOING[DATES.indexOf(currentDate)] ?? 0
      return { title: "Music in the Park", going_count: g }
    },
    async recentHistory(_uid, limit) { return ledger.slice(0, limit) },
  }
}

let currentDate = DATES[0] // set each iteration so the per-day town data resolves

interface DayResult { date: string; format: AlmanacFormat; line: string; places: string[] }
const results: DayResult[] = []

for (const date of DATES) {
  currentDate = date // so the per-day town data (posts, newest) resolves for `date`
  const now = new Date(`${date}T15:00:00Z`) // ~10am CDT
  const ctx: AlmanacContext = await buildAlmanacContext({
    userId: USER, now, tz: "America/Chicago", data: dataSource(), fetchWeather: async () => WEATHER,
  })
  const yesterday = ledger[0]?.format_used ?? null
  const pick = pickFormat(ctx, { yesterdayFormat: yesterday, seed: `${USER}:${date}` })

  let line: string
  let places: string[]
  if (LIVE) {
    const gen = await generateLine({ systemPrompt: SYSTEM_PROMPT, context: ctx, format: pick.format, apiKey: KEY })
    line = gen.line ?? "(generation failed — fell open)"
    places = gen.line ? extractPlaces(gen.line, ctx) : []
    if (gen.usage) console.error(`  [tokens] ${date} in=${gen.usage.input_tokens} out=${gen.usage.output_tokens}`)
  } else {
    // Engine-only: no model text, but simulate the place a field_note would name
    // (the top fresh candidate) so the anti-repetition ledger is exercised for real.
    line = `(offline — a ${pick.format} line)`
    places = pick.format === "field_note" && ctx.field_note_candidates[0]
      ? [ctx.field_note_candidates[0].name] : []
  }

  results.push({ date, format: pick.format, line, places })
  ledger.unshift({ body_text: line, places_mentioned: places, date, format_used: pick.format })
  ledger = ledger.slice(0, 7)
}

// ---- Print the 10 days ----------------------------------------------------------
console.log(`\n=== 10 consecutive days for ${USER} (${LIVE ? "LIVE Haiku" : "OFFLINE / engine-only"}) ===\n`)
for (const r of results) {
  const wd = new Date(`${r.date}T12:00:00Z`).toLocaleDateString("en-US", { weekday: "short", timeZone: "UTC" })
  console.log(`${r.date} ${wd}  [${r.format.toUpperCase()}]`)
  console.log(`  ${r.line}`)
  if (r.places.length) console.log(`  places: ${r.places.join(", ")}`)
  console.log("")
}

// ---- Checks ---------------------------------------------------------------------
const formats = new Set(results.map((r) => r.format))
const distinctFormatsOk = formats.size >= 4

let backToBack = false
for (let i = 1; i < results.length; i++) if (results[i].format === results[i - 1].format) backToBack = true

let placeRepeatWithin7: string | null = null
for (let i = 0; i < results.length; i++) {
  for (const p of results[i].places) {
    for (let j = Math.max(0, i - 7); j < i; j++) {
      if (results[j].places.includes(p)) placeRepeatWithin7 = `${p} (days ${results[j].date} & ${results[i].date})`
    }
  }
}

const norm = (s: string) => s.toLowerCase().split(/\s+/).slice(0, 4).join(" ")
let openingRepeat: string | null = null
if (LIVE) {
  const seen = new Map<string, string>()
  for (const r of results) {
    const key = norm(r.line)
    if (seen.has(key)) openingRepeat = `"${key}…" (${seen.get(key)} & ${r.date})`
    seen.set(key, r.date)
  }
}

console.log("=== CHECKS ===")
console.log(`  4+ distinct formats ............ ${distinctFormatsOk ? "PASS" : "FAIL"}  (${formats.size}: ${[...formats].join(", ")})`)
console.log(`  no back-to-back format ......... ${backToBack ? "FAIL" : "PASS"}`)
console.log(`  no place repeated within 7 days  ${placeRepeatWithin7 ? "FAIL — " + placeRepeatWithin7 : "PASS"}`)
console.log(`  no repeated opening phrase ..... ${LIVE ? (openingRepeat ? "FAIL — " + openingRepeat : "PASS") : "SKIPPED (needs ANTHROPIC_API_KEY for real message text)"}`)
