import { useEffect, useState } from 'react'
import { Pressable, Text, useWindowDimensions, View } from 'react-native'
import Animated, {
  Easing, Extrapolation, FadeInDown, interpolate, runOnJS, useAnimatedScrollHandler,
  useAnimatedStyle, useReducedMotion, useSharedValue, withRepeat, withTiming,
} from 'react-native-reanimated'
import { Image } from 'expo-image'
import { LinearGradient } from 'expo-linear-gradient'
import { BlurView } from 'expo-blur'
import { StatusBar } from 'expo-status-bar'
import { useSafeAreaInsets } from 'react-native-safe-area-context'
import { useLocalSearchParams, useRouter } from 'expo-router'
import * as Haptics from 'expo-haptics'
import { weekdayLabel, type UpcomingEvent } from '@hygge/core'
import { api } from '../../lib/api'
import { placeBySlug, matchesKw, type Place } from '../../data/places'
import { openInMaps } from '../../lib/maps'
import { BackIcon, PinIcon } from '../../components/icons'
import { C, F } from '../../theme'

export default function PlaceShowcase() {
  const { slug } = useLocalSearchParams<{ slug: string }>()
  const place = placeBySlug(slug)
  // Keep all hooks in <Showcase> unconditional by gating on `place` out here.
  return place ? <Showcase place={place} /> : <NotFound />
}

/** Always lands somewhere: pop if we can, otherwise fall back to the tabs so the
 *  user is never stranded (deep link, a reload on this route, or collapsed history). */
function leaveTo(router: ReturnType<typeof useRouter>) {
  if (router.canGoBack()) router.back()
  else router.replace('/(tabs)')
}

function NotFound() {
  const router = useRouter()
  return (
    <View style={{ flex: 1, backgroundColor: C.paper, alignItems: 'center', justifyContent: 'center', gap: 14 }}>
      <Text style={{ fontFamily: F.sans, fontSize: 15, color: C.ink2 }}>That place isn’t here.</Text>
      <Pressable onPress={() => leaveTo(router)} style={{ paddingHorizontal: 18, paddingVertical: 10, borderRadius: 12, backgroundColor: C.ink }}>
        <Text style={{ fontFamily: F.sansSemi, fontSize: 14, color: C.paper }}>Go back</Text>
      </Pressable>
    </View>
  )
}

function Showcase({ place }: { place: Place }) {
  const router = useRouter()
  const insets = useSafeAreaInsets()
  const reduce = useReducedMotion()

  // Read the screen height at render time — NOT at module load. Dimensions.get()
  // at module scope returns 0 on iOS before native layout, which collapsed the
  // hero to zero height (blank showcase).
  const { height: SCREEN_H } = useWindowDimensions()
  const HERO_H = Math.round(SCREEN_H * 0.62)
  const PAPER_TOP = Math.round(SCREEN_H * 0.46) // where the paper card begins (overlaps hero)
  const PEEK = HERO_H - PAPER_TOP // hero height hidden behind the paper

  const close = () => { Haptics.selectionAsync(); leaveTo(router) }

  // --- motion drivers ---
  const enter = useSharedValue(0) // 0→1 bloom + fade on mount
  const ken = useSharedValue(0)   // slow Ken-Burns drift
  const scrollY = useSharedValue(0)

  useEffect(() => {
    if (reduce) { enter.value = 1; return }
    enter.value = withTiming(1, { duration: 380, easing: Easing.out(Easing.cubic) })
    ken.value = withRepeat(withTiming(1, { duration: 30000, easing: Easing.inOut(Easing.ease) }), -1, true)
  }, [reduce, enter, ken])

  // Pull-down-to-dismiss (Apple-sheet feel): release past the bounce threshold
  // closes. close() is a JS function, so cross the worklet boundary via runOnJS.
  const onScroll = useAnimatedScrollHandler({
    onScroll: (e) => { scrollY.value = e.contentOffset.y },
    onEndDrag: (e) => { if (e.contentOffset.y < -110) runOnJS(close)() },
  })

  const screenStyle = useAnimatedStyle(() => ({ opacity: enter.value }))

  // Outer hero: parallax up on scroll + rubber-band scale on pull-down.
  const heroStyle = useAnimatedStyle(() => {
    const pull = scrollY.value < 0 ? scrollY.value : 0
    const pullScale = interpolate(pull, [-220, 0], [1.2, 1], Extrapolation.CLAMP)
    const ty = reduce ? 0 : interpolate(scrollY.value, [0, HERO_H], [0, -HERO_H * 0.32], Extrapolation.CLAMP)
    return { transform: [{ translateY: ty }, { scale: pullScale }] }
  })

  // Inner image: Ken-Burns drift, multiplied by the entrance bloom.
  const imgStyle = useAnimatedStyle(() => {
    const drift = reduce ? 0 : ken.value
    const bloom = interpolate(enter.value, [0, 1], [1.06, 1], Extrapolation.CLAMP)
    return {
      transform: [
        { scale: (1.05 + drift * 0.08) * bloom },
        { translateX: drift * -10 },
        { translateY: drift * -6 },
      ],
    }
  })

  return (
    <Animated.View style={[{ flex: 1, backgroundColor: C.paper }, screenStyle]}>
      <StatusBar style="light" />

      {/* Hero (pinned behind the scroll) */}
      <Animated.View style={[{ position: 'absolute', top: 0, left: 0, right: 0, height: HERO_H }, heroStyle]}>
        <Animated.View style={[{ position: 'absolute', top: -10, left: -10, right: -10, bottom: -10 }, imgStyle]}>
          <Image source={place.image} style={{ flex: 1 }} contentFit="cover" transition={reduce ? 0 : 280} />
        </Animated.View>
        <LinearGradient
          colors={['rgba(20,18,14,0.05)', 'rgba(20,18,14,0.12)', 'rgba(20,18,14,0.62)']}
          locations={[0, 0.55, 1]}
          style={{ position: 'absolute', top: 0, left: 0, right: 0, bottom: 0 }}
        />
        <View style={{ position: 'absolute', left: 22, right: 22, bottom: PEEK + 16 }}>
          <Text style={{ fontFamily: F.display, fontSize: 36, lineHeight: 40, color: '#fbfaf5', letterSpacing: -0.6, textShadowColor: 'rgba(0,0,0,0.4)', textShadowOffset: { width: 0, height: 1 }, textShadowRadius: 10 }}>
            {place.name}
          </Text>
          <Text style={{ fontFamily: F.sansMed, fontSize: 15, color: 'rgba(251,250,245,0.92)', marginTop: 6, textShadowColor: 'rgba(0,0,0,0.4)', textShadowOffset: { width: 0, height: 1 }, textShadowRadius: 6 }}>
            {place.tagline}
          </Text>
        </View>
      </Animated.View>

      {/* Scrolling body — a paper card that rises over the hero */}
      <Animated.ScrollView
        onScroll={onScroll}
        scrollEventThrottle={16}
        showsVerticalScrollIndicator={false}
        contentContainerStyle={{ paddingTop: PAPER_TOP }}
      >
        <View style={{ minHeight: SCREEN_H, backgroundColor: C.paper, borderTopLeftRadius: 24, borderTopRightRadius: 24, paddingHorizontal: 22, paddingTop: 24, paddingBottom: insets.bottom + 56 }}>
          {/* grab handle — signals pull-down-to-close */}
          <View style={{ alignSelf: 'center', width: 38, height: 4, borderRadius: 2, backgroundColor: 'rgba(0,0,0,0.12)', marginBottom: 18 }} />

          <Body place={place} reduce={reduce} onMaps={() => place.where && openInMaps(place.where)} />
        </View>
      </Animated.ScrollView>

      {/* Back affordance — always available */}
      <Pressable
        onPress={close}
        hitSlop={8}
        style={({ pressed }) => ({ position: 'absolute', top: insets.top + 8, left: 16, width: 40, height: 40, borderRadius: 20, overflow: 'hidden', borderWidth: 1, borderColor: 'rgba(255,255,255,0.35)', opacity: pressed ? 0.8 : 1 })}
      >
        <BlurView intensity={20} tint="dark" style={{ flex: 1, alignItems: 'center', justifyContent: 'center', backgroundColor: 'rgba(20,18,14,0.42)' }}>
          <BackIcon size={20} color="#fff" />
        </BlurView>
      </Pressable>
    </Animated.View>
  )
}

function Body({ place, reduce, onMaps }: { place: Place; reduce: boolean; onMaps: () => void }) {
  const [events, setEvents] = useState<UpcomingEvent[] | null>(null)

  useEffect(() => {
    let alive = true
    api.getUpcomingEvents()
      .then((all) => { if (alive) setEvents(all.filter((e) => matchesKw(`${e.title} ${e.location ?? ''}`, place.kw))) })
      .catch(() => { if (alive) setEvents([]) })
    return () => { alive = false }
  }, [place.slug])

  const enter = (i: number) => (reduce ? undefined : FadeInDown.delay(80 + i * 70).duration(380))

  return (
    <>
      {/* About */}
      <Animated.View entering={enter(0)}>
        <SectionLabel>About</SectionLabel>
        {place.description.map((p, i) => (
          <Text key={i} style={{ fontFamily: F.sans, fontSize: 15.5, color: C.ink2, lineHeight: 24, marginBottom: i < place.description.length - 1 ? 12 : 0 }}>{p}</Text>
        ))}
      </Animated.View>

      {/* Good to know */}
      <Animated.View entering={enter(1)} style={{ marginTop: 26 }}>
        <SectionLabel>Good to know</SectionLabel>
        <View style={{ gap: 11 }}>
          {place.facts.map((f) => (
            <View key={f.label} style={{ flexDirection: 'row', alignItems: 'baseline', gap: 12 }}>
              <Text style={{ width: 92, fontFamily: F.sansMed, fontSize: 11, color: C.ink3, letterSpacing: 1, textTransform: 'uppercase' }}>{f.label}</Text>
              <Text style={{ flex: 1, fontFamily: isNumeric(f.value) ? F.mono : F.sans, fontSize: 14.5, color: C.ink }}>{f.value}</Text>
            </View>
          ))}
        </View>
      </Animated.View>

      {/* Happening here */}
      <Animated.View entering={enter(2)} style={{ marginTop: 28 }}>
        <SectionLabel>Happening here</SectionLabel>
        {events === null ? (
          <Text style={{ fontFamily: F.sans, fontSize: 14, color: C.ink3 }}>Looking…</Text>
        ) : events.length === 0 ? (
          <View style={{ paddingHorizontal: 16, paddingVertical: 16, borderRadius: 14, borderWidth: 1.5, borderStyle: 'dashed', borderColor: 'rgba(0,0,0,0.12)' }}>
            <Text style={{ fontFamily: F.sans, fontSize: 13.5, color: C.ink2 }}>Nothing scheduled here yet.</Text>
          </View>
        ) : (
          <View style={{ gap: 2 }}>
            {events.map((e) => <EventRow key={e.id} e={e} />)}
          </View>
        )}
      </Animated.View>

      {/* Where → Maps */}
      {!!place.where && (
        <Animated.View entering={enter(3)} style={{ marginTop: 28 }}>
          <Pressable onPress={onMaps} style={({ pressed }) => ({ flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: 7, paddingVertical: 14, borderRadius: 12, backgroundColor: C.moss700, opacity: pressed ? 0.9 : 1 })}>
            <PinIcon size={14} color={C.paper} />
            <Text style={{ fontFamily: F.sansSemi, fontSize: 15, color: C.paper }}>Open in Maps</Text>
          </Pressable>
        </Animated.View>
      )}
    </>
  )
}

function EventRow({ e }: { e: UpcomingEvent }) {
  const when = `${weekdayLabel(e.event_date)}${e.start_time ? ' · ' + e.start_time : ''}`
  return (
    <View style={{ flexDirection: 'row', alignItems: 'center', gap: 12, paddingVertical: 12, borderBottomWidth: 1, borderBottomColor: 'rgba(0,0,0,0.06)' }}>
      <Text style={{ width: 92, fontFamily: F.monoMed, fontSize: 12, color: C.moss700, letterSpacing: 0.2 }}>{when}</Text>
      <View style={{ flex: 1 }}>
        <Text numberOfLines={1} style={{ fontFamily: F.sansSemi, fontSize: 14.5, color: C.ink }}>{e.title}</Text>
        {!!e.location && <Text numberOfLines={1} style={{ fontFamily: F.sans, fontSize: 12.5, color: C.ink2, marginTop: 2 }}>{e.location}</Text>}
      </View>
      {e.going_count > 0 && <Text style={{ fontFamily: F.mono, fontSize: 11, color: C.ink3 }}>{e.going_count} going</Text>}
    </View>
  )
}

function SectionLabel({ children }: { children: string }) {
  return <Text style={{ fontFamily: F.sansMed, fontSize: 11, color: C.ink3, letterSpacing: 1, textTransform: 'uppercase', marginBottom: 10 }}>{children}</Text>
}

/** Treat values like "1887" or "2,700 acres" as numeric → render in mono (tabular). */
function isNumeric(s: string): boolean {
  return /\d/.test(s)
}
