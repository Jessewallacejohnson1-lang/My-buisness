// Live weather for the almanac readout + sky strip on the Today bar. One fetch
// (open-meteo, St. Joseph MN) returns current conditions, the day's range, and
// today's sunrise/sunset. Mirrors the mapping the old WeatherBar used.
import { WEATHER_IMAGES, type WeatherKey } from '../theme'

export type Weather = {
  temp: number
  code: number
  day: boolean
  hi: number
  lo: number
  sunrise: string | null // "5:29"
  sunset: string | null // "8:58"
}

/** WMO weather code + day/night → the bundled real-photo backdrop key. */
export function wxKey(code: number, day: boolean): WeatherKey {
  if (code >= 95) return 'storm'
  if ((code >= 71 && code <= 77) || (code >= 85 && code <= 86)) return 'snow'
  if ((code >= 51 && code <= 67) || (code >= 80 && code <= 82)) return 'rain'
  if (code >= 45 && code <= 48) return 'fog'
  if (code === 3) return 'overcast'
  if (code === 2) return 'clouds'
  return day ? 'clearDay' : 'clearNight'
}

/** WMO weather code → a short human sky word ("Overcast", "Rain"). */
export function wmoText(code: number): string {
  if (code === 0) return 'Clear'
  if (code <= 2) return 'Partly cloudy'
  if (code === 3) return 'Overcast'
  if (code <= 48) return 'Fog'
  if (code <= 57) return 'Drizzle'
  if (code <= 67) return 'Rain'
  if (code <= 77) return 'Snow'
  if (code <= 82) return 'Showers'
  if (code <= 86) return 'Snow showers'
  return 'Storms'
}

/** open-meteo ISO stamp ("2026-06-30T21:10") → a compact 12-hour clock ("9:10"). */
function isoClock(s: string | undefined): string | null {
  if (!s) return null
  const t = s.split('T')[1]
  if (!t) return null
  const [hh, m] = t.split(':')
  const h = ((parseInt(hh, 10) + 11) % 12) + 1
  return `${h}:${m}`
}

const URL =
  'https://api.open-meteo.com/v1/forecast?latitude=45.5647&longitude=-94.3208' +
  '&current=temperature_2m,weather_code,is_day' +
  '&daily=temperature_2m_max,temperature_2m_min,sunrise,sunset' +
  '&temperature_unit=fahrenheit&timezone=auto&forecast_days=1'

export async function fetchWeather(): Promise<Weather | null> {
  try {
    const r = await fetch(URL)
    const d = await r.json()
    if (!d?.current) return null
    return {
      temp: d.current.temperature_2m,
      code: d.current.weather_code,
      day: d.current.is_day === 1,
      hi: d.daily.temperature_2m_max[0],
      lo: d.daily.temperature_2m_min[0],
      sunrise: isoClock(d.daily.sunrise?.[0]),
      sunset: isoClock(d.daily.sunset?.[0]),
    }
  } catch {
    return null
  }
}

export { WEATHER_IMAGES }
