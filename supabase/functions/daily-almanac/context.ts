// context.ts — buildAlmanacContext(): the canonical, personalized "today" for one
// user, assembled server-side from in-app signals + weather / sun / moon / season.
//
// Pure orchestration over injected deps (DataSource + weather fetch) so it runs the
// same in the edge function (Deno) and the local demo / verify harness (Node).
import { addDaysISO, daysBetween, localDateISO, weekdayOf } from "./dates.ts"
import { moonPhase, type MoonPhase } from "./moon.ts"
import { seasonMarkersFor, type SeasonMarker } from "./seasons_mn.ts"
import { fetchWeather, type WeatherData } from "./weather.ts"
import { PLACES_STJOE } from "./places_stjoe.ts"
import { hashString, seededShuffle } from "./rng.ts"
import type { DataSource } from "./datasource.ts"

const RSVP_WINDOW_DAYS = 7
const HISTORY_DEPTH = 7
const FIELD_NOTE_OFFER = 6 // how many fresh places to offer the generator
const MS_PER_DAY = 86_400_000

export interface AlmanacEvent {
  name: string
  day: string // weekday of the event, e.g. "Saturday"
  time: string | null // display string, e.g. "7pm"
  place: string | null
  days_until: number
  going_count: number
}

export interface AlmanacContext {
  weather: { condition: string; high: number | null; low: number | null }
  sun: {
    sunrise: string | null
    sunset: string | null
    day_length_minutes: number | null
    day_length_change_minutes: number | null
  }
  moon_phase: MoonPhase
  calendar: { weekday: string; date: string; season_markers: SeasonMarker[] }
  my_events: AlmanacEvent[]
  last_attended: { name: string; days_ago: number; place: string | null; recurs: boolean } | null
  town_pulse: {
    new_posts_24h: number
    newest_event: { title: string; going_count: number } | null
  }
  nothing_planned: boolean
  recent_history: { texts: string[]; places: string[]; formats: string[] }
  /** Fresh local places (recent ones excluded, day-rotated) the generator may name. */
  field_note_candidates: { name: string; hook: string }[]
}

export interface AlmanacDeps {
  userId: string
  now: Date // current instant
  tz: string // IANA zone, e.g. 'America/Chicago'
  data: DataSource
  fetchWeather?: () => Promise<WeatherData> // defaults to the real Open-Meteo call
}

export async function buildAlmanacContext(deps: AlmanacDeps): Promise<AlmanacContext> {
  const { userId, now, tz, data } = deps
  const getWeather = deps.fetchWeather ?? (() => fetchWeather())

  const today = localDateISO(now, tz)
  const windowEnd = addDaysISO(today, RSVP_WINDOW_DAYS)
  const since24h = new Date(now.getTime() - MS_PER_DAY).toISOString()

  // Fetch everything concurrently — the reads are independent.
  const [weather, upcoming, attended, newPosts, newest, history] = await Promise.all([
    getWeather(),
    data.upcomingEvents(userId, today, windowEnd),
    data.lastAttendedEvent(userId, today),
    data.newPostCount24h(since24h),
    data.newestEvent(),
    data.recentHistory(userId, HISTORY_DEPTH + 1), // +1 in case today's row is already written
  ])

  const [, month, day] = today.split("-").map(Number)

  const myEvents: AlmanacEvent[] = upcoming.map((e) => ({
    name: e.title,
    day: weekdayOf(e.event_date),
    time: e.start_time,
    place: e.location,
    days_until: daysBetween(today, e.event_date),
    going_count: e.going_count,
  }))

  // Strictly PRIOR days: strip today's own row so a mid-day rewrite doesn't treat this
  // morning's line as "yesterday" (no-repeat) or exclude its own place from candidates.
  const priorHistory = history.filter((h) => h.date < today).slice(0, HISTORY_DEPTH)
  const historyPlaces = Array.from(
    new Set(priorHistory.flatMap((h) => h.places_mentioned).filter(Boolean)),
  )

  // Fresh field-note places: curated local spots not named in recent history,
  // day-rotated per user so the highlighted place moves around over time.
  const recentPlaceKeys = new Set(historyPlaces.map(normalizePlace))
  const freshPlaces = PLACES_STJOE.filter((p) => !recentPlaceKeys.has(normalizePlace(p.name)))
  const fieldNoteCandidates = seededShuffle(freshPlaces, hashString(`${userId}:${today}:places`))
    .slice(0, FIELD_NOTE_OFFER)
    .map((p) => ({ name: p.name, hook: p.hook }))

  return {
    weather: { condition: weather.condition, high: weather.high, low: weather.low },
    sun: {
      sunrise: weather.sunrise,
      sunset: weather.sunset,
      day_length_minutes: weather.day_length_minutes,
      day_length_change_minutes: weather.day_length_change_minutes,
    },
    moon_phase: moonPhase(now),
    calendar: {
      weekday: weekdayOf(today),
      date: today,
      season_markers: seasonMarkersFor(month, day),
    },
    my_events: myEvents,
    last_attended: attended
      ? {
          name: attended.title,
          days_ago: daysBetween(attended.event_date, today),
          place: attended.location,
          recurs: attended.recurs,
        }
      : null,
    town_pulse: {
      new_posts_24h: newPosts,
      newest_event: newest ? { title: newest.title, going_count: newest.going_count } : null,
    },
    nothing_planned: myEvents.length === 0,
    recent_history: {
      texts: priorHistory.map((h) => h.body_text),
      places: historyPlaces,
      formats: priorHistory.map((h) => h.format_used ?? "").filter(Boolean),
    },
    field_note_candidates: fieldNoteCandidates,
  }
}

/** Normalize a place name for anti-repetition matching (lowercase, drop leading "the "). */
function normalizePlace(name: string): string {
  return name.trim().toLowerCase().replace(/^the\s+/, "")
}
