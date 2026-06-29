import { useEffect, useState } from 'react'
import { Text, View } from 'react-native'
import { Image } from 'expo-image'
import { LinearGradient } from 'expo-linear-gradient'
import Animated, { Easing, useAnimatedStyle, useSharedValue, withRepeat, withTiming } from 'react-native-reanimated'
import { C, F, WEATHER_IMAGES, CARD_SHADOW, type WeatherKey } from '../theme'

type Weather = { temp: number; code: number; hi: number; lo: number; day: boolean }

function wxKey(code: number, day: boolean): WeatherKey {
  if (code >= 95) return 'storm'
  if ((code >= 71 && code <= 77) || (code >= 85 && code <= 86)) return 'snow'
  if ((code >= 51 && code <= 67) || (code >= 80 && code <= 82)) return 'rain'
  if (code >= 45 && code <= 48) return 'fog'
  if (code === 3) return 'overcast'
  if (code === 2) return 'clouds'
  return day ? 'clearDay' : 'clearNight'
}

function wmoText(code: number): string {
  if (code === 0) return 'Clear'
  if (code <= 2) return 'Partly cloudy'
  if (code === 3) return 'Cloudy'
  if (code <= 48) return 'Fog'
  if (code <= 57) return 'Drizzle'
  if (code <= 67) return 'Rain'
  if (code <= 77) return 'Snow'
  if (code <= 82) return 'Showers'
  if (code <= 86) return 'Snow showers'
  return 'Storms'
}

const SHADOW = { textShadowColor: 'rgba(0,0,0,0.55)', textShadowOffset: { width: 0, height: 1 }, textShadowRadius: 3 }

export function WeatherBar() {
  const [w, setW] = useState<Weather | null>(null)

  // Slow Ken-Burns drift on the photo.
  const t = useSharedValue(0)
  useEffect(() => {
    t.value = withRepeat(withTiming(1, { duration: 30000, easing: Easing.inOut(Easing.ease) }), -1, true)
  }, [t])
  const kenStyle = useAnimatedStyle(() => ({
    transform: [
      { scale: 1.06 + t.value * 0.1 },
      { translateX: t.value * -10 },
      { translateY: t.value * -6 },
    ],
  }))

  useEffect(() => {
    fetch('https://api.open-meteo.com/v1/forecast?latitude=45.5647&longitude=-94.3208&current=temperature_2m,weather_code,is_day&daily=temperature_2m_max,temperature_2m_min&temperature_unit=fahrenheit&timezone=auto&forecast_days=1')
      .then((r) => r.json())
      .then((d) => {
        if (d?.current) setW({
          temp: d.current.temperature_2m, code: d.current.weather_code,
          hi: d.daily.temperature_2m_max[0], lo: d.daily.temperature_2m_min[0], day: d.current.is_day === 1,
        })
      })
      .catch(() => {})
  }, [])

  const key = w ? wxKey(w.code, w.day) : null

  return (
    <View style={{ marginHorizontal: 20, marginTop: 6, height: 52, borderRadius: 20, backgroundColor: C.paper100, ...CARD_SHADOW }}>
      <View style={{ flex: 1, borderRadius: 20, overflow: 'hidden' }}>
      {key && (
        <Animated.View style={[{ position: 'absolute', top: -8, left: -8, right: -8, bottom: -8 }, kenStyle]}>
          <Image
            source={WEATHER_IMAGES[key]}
            style={{ flex: 1 }}
            contentFit="cover"
            contentPosition={key === 'clearNight' ? 'top' : 'center'}
            transition={300}
          />
        </Animated.View>
      )}
      <LinearGradient
        colors={['rgba(0,0,0,0.52)', 'rgba(0,0,0,0.10)', 'rgba(0,0,0,0.10)', 'rgba(0,0,0,0.48)']}
        locations={[0, 0.36, 0.62, 1]}
        start={{ x: 0, y: 0 }} end={{ x: 1, y: 0 }}
        style={{ position: 'absolute', top: 0, left: 0, right: 0, bottom: 0 }}
      />
      <View style={{ flex: 1, flexDirection: 'row', alignItems: 'center', paddingHorizontal: 18, gap: 10 }}>
        {w ? (
          <>
            <Text style={{ fontFamily: F.monoMed, fontSize: 19, color: '#fff', ...SHADOW }}>{Math.round(w.temp)}°</Text>
            <Text style={{ fontFamily: F.sansMed, fontSize: 15.5, color: '#fff', ...SHADOW }}>{wmoText(w.code)} in St. Joseph</Text>
            <View style={{ flex: 1 }} />
            <Text style={{ fontFamily: F.mono, fontSize: 14, color: 'rgba(255,255,255,0.9)', ...SHADOW }}>H {Math.round(w.hi)}°</Text>
            <Text style={{ fontFamily: F.mono, fontSize: 14, color: 'rgba(255,255,255,0.9)', ...SHADOW }}>L {Math.round(w.lo)}°</Text>
          </>
        ) : (
          <Text style={{ fontFamily: F.sansMed, fontSize: 14.5, color: C.ink3 }}>Loading today&rsquo;s weather…</Text>
        )}
      </View>
      </View>
    </View>
  )
}
