import { useEffect, useState } from 'react'
import { Pressable, Text, View } from 'react-native'
import { Image } from 'expo-image'
import { LinearGradient } from 'expo-linear-gradient'
import Animated, { type AnimatedProps } from 'react-native-reanimated'
import type { TextStyle, ViewProps } from 'react-native'
import { AccountMenu } from './AccountMenu'
import { SearchIcon, ArrowUpIcon, ArrowDownIcon } from './icons'
import { fetchWeather, wxKey, wmoText, WEATHER_IMAGES, type Weather } from '../lib/weather'
import { C, F, HAIRLINE, HAIRLINE_LIGHT, CARD_SHADOW, GRAPH } from '../theme'

const TAB: TextStyle['fontVariant'] = ['tabular-nums']

type EnterFn = (i: number) => AnimatedProps<ViewProps>['entering']

const pad2 = (n: number) => String(n).padStart(2, '0')

function greeting(name: string | null): string {
  const h = new Date().getHours()
  const part = h < 12 ? 'Good morning' : h < 17 ? 'Good afternoon' : 'Good evening'
  return name ? `${part}, ${name}.` : `${part}.`
}

/** The "Today" bar — a printed almanac dateline. The weekday is the hero, dated
 *  in mono, placed in St. Joseph, under a masthead double-rule, with a mono
 *  weather/sun readout and today's real sky as a still photo plate. */
export function TodayBar({
  name,
  onSignOut,
  searchOpen,
  onToggleSearch,
  enter,
}: {
  name: string | null
  onSignOut: () => void
  searchOpen: boolean
  onToggleSearch: () => void
  enter: EnterFn
}) {
  const [w, setW] = useState<Weather | null>(null)
  const [failed, setFailed] = useState(false)

  useEffect(() => {
    fetchWeather().then((res) => (res ? setW(res) : setFailed(true)))
  }, [])

  const now = new Date()
  const weekday = now.toLocaleDateString('en-US', { weekday: 'long' })
  const dateStamp = `${pad2(now.getMonth() + 1)} · ${pad2(now.getDate())} · ${pad2(now.getFullYear() % 100)}`
  const skyKey = w ? wxKey(w.code, w.day) : null

  return (
    <View style={{ paddingHorizontal: 20, paddingTop: 12 }}>
      {/* (1) micro-masthead: wordmark lockup + glass circles */}
      <View style={{ height: 32, flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between' }}>
        <View style={{ flexDirection: 'row', alignItems: 'center', gap: 8 }}>
          <View style={{ height: 26, width: 26, borderRadius: 8, backgroundColor: C.moss700, alignItems: 'center', justifyContent: 'center' }}>
            <Text style={{ fontFamily: F.displaySemi, fontSize: 16, color: C.paper }}>H</Text>
          </View>
          <Text style={{ fontFamily: F.mono, fontSize: 10.5, color: C.ink3, letterSpacing: 1.6 }}>THE ST. JOE ALMANAC</Text>
        </View>
        <View style={{ flexDirection: 'row', gap: 10 }}>
          <Pressable
            onPress={onToggleSearch}
            style={({ pressed }) => ({
              width: 38, height: 38, borderRadius: 19, alignItems: 'center', justifyContent: 'center',
              backgroundColor: searchOpen ? C.moss700 : C.paper,
              borderWidth: 1, borderColor: searchOpen ? 'transparent' : HAIRLINE,
              opacity: pressed ? 0.7 : 1, ...CARD_SHADOW,
            })}
          >
            <SearchIcon color={searchOpen ? C.paper : C.ink} />
          </Pressable>
          <AccountMenu name={name} onSignOut={onSignOut} />
        </View>
      </View>

      {/* (2) placeline */}
      <Animated.View entering={enter(0)}>
        <Text style={{ fontFamily: F.mono, fontSize: 11, color: C.ink2, letterSpacing: 2.2, marginTop: 16 }}>
          ST. JOSEPH, MINNESOTA
        </Text>
      </Animated.View>

      {/* (3) the date — hero weekday + mono stamp on the baseline */}
      <Animated.View entering={enter(1)} style={{ flexDirection: 'row', alignItems: 'flex-end', marginTop: 2 }}>
        <Text
          numberOfLines={1}
          adjustsFontSizeToFit
          minimumFontScale={0.7}
          style={{ flex: 1, fontFamily: F.display, fontSize: 44, lineHeight: 46, color: C.ink, letterSpacing: -1 }}
        >
          {weekday}
        </Text>
        <Text style={{ fontFamily: F.monoMed, fontSize: 16, color: C.ink3, letterSpacing: 0.3, marginBottom: 6, marginLeft: 10, fontVariant: TAB }}>
          {dateStamp}
        </Text>
      </Animated.View>

      {/* (4) greeting whisper */}
      <Animated.View entering={enter(1)}>
        <Text style={{ fontFamily: F.sans, fontSize: 13, color: C.ink3, marginTop: 6 }}>{greeting(name)}</Text>
      </Animated.View>

      {/* (5) masthead double-rule + (6) almanac readout + sky plate */}
      <Animated.View entering={enter(2)}>
        <View style={{ height: 1, backgroundColor: HAIRLINE, marginTop: 14 }} />
        <View style={{ height: 1, backgroundColor: HAIRLINE_LIGHT, marginTop: 3 }} />

        <View style={{ flexDirection: 'row', alignItems: 'center', marginTop: 12 }}>
          {/* SKY flexes so the row can never grow wider than the page */}
          <ReadoutCell label="SKY" style={{ flex: 1, minWidth: 0 }}>
            {w ? (
              <Text numberOfLines={1} style={{ fontFamily: F.monoMed, fontSize: 13.5, color: C.ink, fontVariant: TAB }}>
                {Math.round(w.temp)}° {wmoText(w.code)}
              </Text>
            ) : failed ? (
              <Text style={{ fontFamily: F.sans, fontSize: 12, color: C.ink3 }}>Weather&rsquo;s out</Text>
            ) : (
              <SkeletonBar width={92} />
            )}
          </ReadoutCell>

          {(w || !failed) && (
            <>
              <Divider />
              <ReadoutCell label="HI · LO">
                {w ? (
                  <Text style={{ fontFamily: F.monoMed, fontSize: 13.5, color: C.ink2, fontVariant: TAB }}>
                    {Math.round(w.hi)}° / {Math.round(w.lo)}°
                  </Text>
                ) : (
                  <SkeletonBar width={58} />
                )}
              </ReadoutCell>

              <Divider />
              <ReadoutCell label="SUN">
                {w ? (
                  <View style={{ flexDirection: 'row', alignItems: 'center', gap: 3 }}>
                    <ArrowUpIcon size={11} color={GRAPH.amber} />
                    <Text style={{ fontFamily: F.monoMed, fontSize: 13, color: C.ink2, fontVariant: TAB }}>{w.sunrise ?? '—'}</Text>
                    <ArrowDownIcon size={11} color={C.ink3} />
                    <Text style={{ fontFamily: F.monoMed, fontSize: 13, color: C.ink2, fontVariant: TAB }}>{w.sunset ?? '—'}</Text>
                  </View>
                ) : (
                  <SkeletonBar width={74} />
                )}
              </ReadoutCell>
            </>
          )}
        </View>

        {/* today's real sky — a still photo plate, sealed to the page (no drift) */}
        {skyKey && (
          <View style={{ height: 64, borderRadius: 16, overflow: 'hidden', marginTop: 14, backgroundColor: C.paper100 }}>
            <Image
              source={WEATHER_IMAGES[skyKey]}
              style={{ flex: 1 }}
              contentFit="cover"
              contentPosition={skyKey === 'clearNight' ? 'top' : 'center'}
              transition={300}
            />
            <LinearGradient
              colors={['rgba(0,0,0,0.10)', 'rgba(0,0,0,0)', 'rgba(0,0,0,0.14)']}
              locations={[0, 0.5, 1]}
              style={{ position: 'absolute', left: 0, right: 0, top: 0, bottom: 0 }}
            />
          </View>
        )}
      </Animated.View>
    </View>
  )
}

function ReadoutCell({ label, children, style }: { label: string; children: React.ReactNode; style?: ViewProps['style'] }) {
  return (
    <View style={[{ gap: 3 }, style]}>
      <Text style={{ fontFamily: F.mono, fontSize: 9, color: C.ink3, letterSpacing: 1.2 }}>{label}</Text>
      {children}
    </View>
  )
}

function Divider() {
  return <View style={{ width: 1, height: 22, backgroundColor: HAIRLINE_LIGHT, marginHorizontal: 12 }} />
}

function SkeletonBar({ width }: { width: number }) {
  return <View style={{ width, height: 13, borderRadius: 4, backgroundColor: C.paper200 }} />
}
