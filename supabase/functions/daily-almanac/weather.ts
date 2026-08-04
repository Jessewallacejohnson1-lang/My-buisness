// weather.ts — St. Joseph, MN weather + sun from Open-Meteo (no API key).
// Pinned to America/Chicago so sunrise/sunset return as offset-less local wall-clock.
// PRIVACY: coordinates are the town's, fixed — never the device's location.
import { clock, minutesFromISO } from "./dates.ts"

const LAT = 45.565
const LON = -94.3186
const TZ = "America/Chicago"
const DAYS_AGO_FOR_DELTA = 7

export interface WeatherData {
  condition: string
  high: number | null
  low: number | null
  sunrise: string | null // today, "h:mm"
  sunset: string | null // today, "h:mm"
  day_length_minutes: number | null
  // Today's day length minus the day length 7 days ago (see DAYS_AGO_FOR_DELTA).
  // The name carries the baseline because this object is serialized straight into
  // the model's prompt — an unqualified "change" reads as "since yesterday" and
  // gets reported as such, which is ~7x wrong.
  day_length_change_minutes_vs_week_ago: number | null
}

const EMPTY: WeatherData = {
  condition: "",
  high: null,
  low: null,
  sunrise: null,
  sunset: null,
  day_length_minutes: null,
  day_length_change_minutes_vs_week_ago: null,
}

// WMO weather code -> human label (day-aware). Mirrors WeatherService.label in the app.
export function weatherLabel(code: number, isDay: boolean): string {
  if (code === 0) return isDay ? "Clear" : "Clear night"
  if (code === 1 || code === 2) return "Partly cloudy"
  if (code === 3) return "Overcast"
  if (code === 45 || code === 48) return "Foggy"
  if ((code >= 51 && code <= 67) || (code >= 80 && code <= 82)) return "Rain"
  if ((code >= 71 && code <= 77) || code === 85 || code === 86) return "Snow"
  if (code === 95 || code === 96 || code === 99) return "Storms"
  return isDay ? "Clear" : "Clear night"
}

type FetchLike = (url: string) => Promise<Response>

/**
 * Fetch current weather + today's high/low/sun, plus the sun 7 days ago so we can
 * report the day-length delta. Returns nulls on any partial failure — never throws.
 * `past_days=7&forecast_days=1` yields an 8-entry daily array: index 0 = 7 days ago,
 * last index = today.
 */
export async function fetchWeather(fetchImpl: FetchLike = fetch): Promise<WeatherData> {
  try {
    const url =
      `https://api.open-meteo.com/v1/forecast?latitude=${LAT}&longitude=${LON}` +
      `&current=temperature_2m,weather_code,is_day` +
      `&daily=temperature_2m_max,temperature_2m_min,sunrise,sunset` +
      `&temperature_unit=fahrenheit&timezone=${encodeURIComponent(TZ)}` +
      `&past_days=${DAYS_AGO_FOR_DELTA}&forecast_days=1`
    const res = await fetchImpl(url)
    if (!res.ok) return EMPTY
    const wd = await res.json()

    const sunriseArr: string[] = wd.daily?.sunrise ?? []
    const sunsetArr: string[] = wd.daily?.sunset ?? []
    const highArr: number[] = wd.daily?.temperature_2m_max ?? []
    const lowArr: number[] = wd.daily?.temperature_2m_min ?? []

    const todayIdx = sunriseArr.length - 1 // today
    if (todayIdx < 0) return EMPTY

    const todayLen = lengthMinutes(sunriseArr[todayIdx], sunsetArr[todayIdx])
    const pastLen = sunriseArr.length > 1 ? lengthMinutes(sunriseArr[0], sunsetArr[0]) : null
    const delta = todayLen != null && pastLen != null ? todayLen - pastLen : null

    return {
      condition: weatherLabel(wd.current?.weather_code ?? 0, (wd.current?.is_day ?? 1) === 1),
      high: highArr[todayIdx] != null ? Math.round(highArr[todayIdx]) : null,
      low: lowArr[todayIdx] != null ? Math.round(lowArr[todayIdx]) : null,
      sunrise: clock(sunriseArr[todayIdx]),
      sunset: clock(sunsetArr[todayIdx]),
      day_length_minutes: todayLen,
      day_length_change_minutes_vs_week_ago: delta,
    }
  } catch {
    return EMPTY
  }
}

function lengthMinutes(sunriseISO: string | null, sunsetISO: string | null): number | null {
  const r = minutesFromISO(sunriseISO)
  const s = minutesFromISO(sunsetISO)
  if (r == null || s == null) return null
  return s - r
}
