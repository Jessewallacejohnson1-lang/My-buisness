import { useCallback, useEffect, useRef, useState } from 'react'
import { Pressable, Text, View, ActivityIndicator } from 'react-native'
import MapView, { Marker, type Region } from 'react-native-maps'
import * as Location from 'expo-location'
import * as Haptics from 'expo-haptics'
import Animated, {
  Easing, FadeInUp, SlideInDown, SlideOutDown,
  useAnimatedStyle, useReducedMotion, useSharedValue, withRepeat, withTiming,
} from 'react-native-reanimated'
import { useRouter } from 'expo-router'
import { useSafeAreaInsets } from 'react-native-safe-area-context'
import type { TimelineEvent, Trail } from '@hygge/core'
import { api } from '../lib/api'
import { venueCoords } from '../lib/geo'
import { isLiveNow } from '../lib/time'
import { C, F, GRAPH, HAIRLINE, CARD_SHADOW } from '../theme'
import { ScreenBadge } from './ScreenBadge'
import { PlusIcon, PinIcon, TrailIcon, EventIcon, CloseIcon } from './icons'

// St. Joseph, MN
const ST_JOE: Region = {
  latitude: 45.5658,
  longitude: -94.3178,
  latitudeDelta: 0.04,
  longitudeDelta: 0.04,
}

type PinnedEvent = TimelineEvent & { lat: number; lng: number }
type PinnedTrail = Trail & { lat: number; lng: number }
type PinnedItem =
  | { kind: 'event'; data: PinnedEvent }
  | { kind: 'trail'; data: PinnedTrail }

async function geocode(locationStr: string | null): Promise<{ lat: number; lng: number } | null> {
  if (!locationStr) return null
  // Known venues resolve from the curated table (lib/geo.ts) — device geocoding
  // drops pins on the wrong building. Only unknown locations fall through.
  const known = venueCoords(locationStr)
  if (known) return known
  try {
    const query = locationStr.includes('MN') || locationStr.includes('Minnesota')
      ? locationStr
      : `${locationStr}, St. Joseph, MN`
    const results = await Location.geocodeAsync(query)
    if (results.length > 0) {
      return { lat: results[0].latitude, lng: results[0].longitude }
    }
  } catch {}
  return null
}

export function TownMap() {
  const router = useRouter()
  const reduce = useReducedMotion()
  const insets = useSafeAreaInsets()
  const mapRef = useRef<MapView>(null)
  const [events, setEvents] = useState<PinnedEvent[]>([])
  const [trails, setTrails] = useState<PinnedTrail[]>([])
  const [loading, setLoading] = useState(true)
  const [selected, setSelected] = useState<PinnedItem | null>(null)

  const load = useCallback(async () => {
    setLoading(true)
    const [todayEvts, allTrails] = await Promise.all([api.getTodayEvents(), api.getTrails()])

    // Geocode in parallel — skip items with no location
    const [pinnedEvts, pinnedTrails] = await Promise.all([
      Promise.all(
        todayEvts.map(async (e) => {
          const coords = await geocode(e.location)
          return coords ? { ...e, lat: coords.lat, lng: coords.lng } : null
        })
      ),
      Promise.all(
        allTrails.map(async (t) => {
          const coords = await geocode(t.location)
          return coords ? { ...t, lat: coords.lat, lng: coords.lng } : null
        })
      ),
    ])

    setEvents(pinnedEvts.filter(Boolean) as PinnedEvent[])
    setTrails(pinnedTrails.filter(Boolean) as PinnedTrail[])
    setLoading(false)
  }, [])

  useEffect(() => { load() }, [load])

  const selectEvent = (e: PinnedEvent) => {
    Haptics.selectionAsync()
    setSelected({ kind: 'event', data: e })
    mapRef.current?.animateToRegion({ latitude: e.lat, longitude: e.lng, latitudeDelta: 0.015, longitudeDelta: 0.015 }, 400)
  }

  const selectTrail = (t: PinnedTrail) => {
    Haptics.selectionAsync()
    setSelected({ kind: 'trail', data: t })
    mapRef.current?.animateToRegion({ latitude: t.lat, longitude: t.lng, latitudeDelta: 0.015, longitudeDelta: 0.015 }, 400)
  }

  const liveCount = events.filter((e) => isLiveNow(e.start_time)).length

  return (
    <View style={{ flex: 1 }}>
      <MapView
        ref={mapRef}
        style={{ flex: 1 }}
        initialRegion={ST_JOE}
        mapType="standard"
        showsUserLocation
        showsMyLocationButton={false}
        showsCompass={false}
        onPress={() => setSelected(null)}
      >
        {events.map((e) => (
          <Marker
            key={`event-${e.id}`}
            coordinate={{ latitude: e.lat, longitude: e.lng }}
            onPress={() => selectEvent(e)}
          >
            <EventPin
              live={isLiveNow(e.start_time)}
              selected={selected?.kind === 'event' && selected.data.id === e.id}
            />
          </Marker>
        ))}

        {trails.map((t) => (
          <Marker
            key={`trail-${t.id}`}
            coordinate={{ latitude: t.lat, longitude: t.lng }}
            onPress={() => selectTrail(t)}
          >
            <View style={{
              width: 36, height: 36, borderRadius: 18,
              backgroundColor: selected?.kind === 'trail' && selected.data.id === t.id ? C.ink : C.paper200,
              alignItems: 'center', justifyContent: 'center',
              borderWidth: 2, borderColor: selected?.kind === 'trail' && selected.data.id === t.id ? C.paper : C.ink2,
              shadowColor: '#000', shadowOpacity: 0.15, shadowRadius: 4, shadowOffset: { width: 0, height: 2 },
            }}>
              <TrailIcon size={16} color={selected?.kind === 'trail' && selected.data.id === t.id ? C.paper : C.ink2} />
            </View>
          </Marker>
        ))}
      </MapView>

      {/* Brand mark — pinned top-right, identical across every screen */}
      <ScreenBadge />

      {/* Top pill — today's count (top-left, aligned to the badge's safe inset) */}
      <Animated.View
        entering={reduce ? undefined : FadeInUp.delay(200).duration(300)}
        style={{
          position: 'absolute', top: insets.top + 8, left: 16,
          backgroundColor: 'rgba(255,255,255,0.92)',
          borderRadius: 20, paddingVertical: 8, paddingHorizontal: 14,
          borderWidth: 1, borderColor: HAIRLINE,
          ...CARD_SHADOW,
        }}
      >
        {loading ? (
          <ActivityIndicator size="small" color={C.ink3} />
        ) : (
          <View style={{ flexDirection: 'row', alignItems: 'center', gap: 8 }}>
            {liveCount > 0 && (
              <>
                <View style={{ flexDirection: 'row', alignItems: 'center', gap: 5 }}>
                  <View style={{ width: 8, height: 8, borderRadius: 4, backgroundColor: GRAPH.amber }} />
                  <Text style={{ fontWeight: F.sansSemi, fontSize: 13, color: C.ink }}>
                    {liveCount} now
                  </Text>
                </View>
                <View style={{ width: 1, height: 12, backgroundColor: HAIRLINE }} />
              </>
            )}
            <View style={{ flexDirection: 'row', alignItems: 'center', gap: 5 }}>
              <View style={{ width: 8, height: 8, borderRadius: 4, backgroundColor: C.ink3 }} />
              <Text style={{ fontWeight: F.sansSemi, fontSize: 13, color: C.ink }}>
                {events.length} today
              </Text>
            </View>
            {trails.length > 0 && (
              <>
                <View style={{ width: 1, height: 12, backgroundColor: HAIRLINE }} />
                <View style={{ flexDirection: 'row', alignItems: 'center', gap: 5 }}>
                  <View style={{ width: 8, height: 8, borderRadius: 4, backgroundColor: C.ink3 }} />
                  <Text style={{ fontWeight: F.sans, fontSize: 13, color: C.ink2 }}>
                    {trails.length} trails
                  </Text>
                </View>
              </>
            )}
          </View>
        )}
      </Animated.View>

      {/* Floating + button — opens add flow. Sits just under the brand mark. */}
      <Animated.View
        entering={reduce ? undefined : FadeInUp.delay(300).duration(300)}
        style={{ position: 'absolute', top: insets.top + 46, right: 16 }}
      >
        <Pressable
          onPress={() => { Haptics.selectionAsync(); router.push('/(tabs)/add') }}
          style={({ pressed }) => ({
            width: 44, height: 44, borderRadius: 22,
            backgroundColor: C.ink, alignItems: 'center', justifyContent: 'center',
            opacity: pressed ? 0.8 : 1,
            ...CARD_SHADOW,
          })}
        >
          <PlusIcon size={18} color={C.paper} />
        </Pressable>
      </Animated.View>

      {/* Bottom detail card */}
      {selected && (
        <Animated.View
          entering={reduce ? undefined : SlideInDown.duration(320).springify().damping(18)}
          exiting={reduce ? undefined : SlideOutDown.duration(200)}
          style={{
            position: 'absolute', left: 16, right: 16, bottom: 110,
            backgroundColor: C.paper, borderRadius: 20,
            borderWidth: 1, borderColor: HAIRLINE,
            padding: 18, ...CARD_SHADOW,
          }}
        >
          <Pressable
            onPress={() => setSelected(null)}
            hitSlop={12}
            accessibilityRole="button"
            accessibilityLabel="Close"
            style={({ pressed }) => ({ position: 'absolute', top: 12, right: 12, width: 30, height: 30, borderRadius: 15, backgroundColor: C.paper100, alignItems: 'center', justifyContent: 'center', opacity: pressed ? 0.6 : 1 })}
          >
            <CloseIcon size={16} color={C.ink2} />
          </Pressable>

          {selected.kind === 'event' && (
            <EventCard event={selected.data} />
          )}
          {selected.kind === 'trail' && (
            <TrailCard trail={selected.data} />
          )}
        </Animated.View>
      )}
    </View>
  )
}

/** An event pin. Live-now events glow — a breathing moss halo says "this is
 *  happening as you look at the map." Everything else sits quiet on the paper. */
function EventPin({ live, selected }: { live: boolean; selected: boolean }) {
  const reduce = useReducedMotion()
  const halo = useSharedValue(0)
  useEffect(() => {
    if (!live || reduce) return
    halo.value = withRepeat(withTiming(1, { duration: 1600, easing: Easing.out(Easing.ease) }), -1, false)
  }, [live, reduce, halo])
  const haloStyle = useAnimatedStyle(() => ({
    transform: [{ scale: 1 + halo.value * 0.9 }],
    opacity: 0.45 * (1 - halo.value),
  }))

  // Live = the timeline's "now" amber, breathing. Everything else sits quiet.
  const bg = selected ? C.ink : live ? GRAPH.amber : C.paper
  const fg = selected || live ? C.paper : C.ink2
  return (
    <View style={{ width: 56, height: 56, alignItems: 'center', justifyContent: 'center' }}>
      {live && (
        <Animated.View
          style={[
            { position: 'absolute', width: 36, height: 36, borderRadius: 18, backgroundColor: GRAPH.amber },
            reduce ? { opacity: 0.2, transform: [{ scale: 1.35 }] } : haloStyle,
          ]}
        />
      )}
      <View style={{
        width: 36, height: 36, borderRadius: 18,
        backgroundColor: bg,
        alignItems: 'center', justifyContent: 'center',
        borderWidth: 2, borderColor: selected || live ? C.paper : C.ink2,
        shadowColor: '#000', shadowOpacity: live ? 0.2 : 0.15, shadowRadius: 4, shadowOffset: { width: 0, height: 2 },
      }}>
        <EventIcon size={16} color={fg} />
      </View>
    </View>
  )
}

function EventCard({ event }: { event: PinnedEvent }) {
  const live = isLiveNow(event.start_time)
  return (
    <View style={{ gap: 6, paddingRight: 24 }}>
      <View style={{ flexDirection: 'row', alignItems: 'center', gap: 6, marginBottom: 2 }}>
        <View style={{ width: 6, height: 6, borderRadius: 3, backgroundColor: live ? GRAPH.amber : C.ink3 }} />
        <Text style={{ fontWeight: F.mono, fontSize: 10, color: live ? C.ink : C.ink3, letterSpacing: 1.2, textTransform: 'uppercase' }}>
          {live ? 'Happening now' : 'Today'}{event.start_time ? ` · ${event.start_time}` : ''}
        </Text>
      </View>
      <Text style={{ fontWeight: F.sansBold, fontSize: 18, color: C.ink, letterSpacing: -0.3 }}>{event.title}</Text>
      {event.location && (
        <View style={{ flexDirection: 'row', alignItems: 'center', gap: 5, marginTop: 2 }}>
          <PinIcon size={12} color={C.sky600} />
          <Text style={{ fontWeight: F.sans, fontSize: 13, color: C.sky600 }}>{event.location}</Text>
        </View>
      )}
      {event.club_name && (
        <Text style={{ fontWeight: F.sansMed, fontSize: 12, color: C.ink3, marginTop: 2 }}>
          {event.club_name}
        </Text>
      )}
      <Text style={{ fontWeight: F.mono, fontSize: 12, color: C.ink2, marginTop: 4 }}>
        {event.going_count} going
      </Text>
    </View>
  )
}

function TrailCard({ trail }: { trail: PinnedTrail }) {
  const meta = [trail.length, trail.difficulty].filter(Boolean).join(' · ')
  return (
    <View style={{ gap: 6, paddingRight: 24 }}>
      <View style={{ flexDirection: 'row', alignItems: 'center', gap: 6, marginBottom: 2 }}>
        <View style={{ width: 6, height: 6, borderRadius: 3, backgroundColor: C.ink3 }} />
        <Text style={{ fontWeight: F.mono, fontSize: 10, color: C.ink3, letterSpacing: 1.2, textTransform: 'uppercase' }}>
          Trail
        </Text>
      </View>
      <Text style={{ fontWeight: F.sansBold, fontSize: 18, color: C.ink, letterSpacing: -0.3 }}>{trail.title}</Text>
      {trail.location && (
        <View style={{ flexDirection: 'row', alignItems: 'center', gap: 5, marginTop: 2 }}>
          <PinIcon size={12} color={C.sky600} />
          <Text style={{ fontWeight: F.sans, fontSize: 13, color: C.sky600 }}>{trail.location}</Text>
        </View>
      )}
      {meta ? (
        <Text style={{ fontWeight: F.mono, fontSize: 12, color: C.ink2, marginTop: 2 }}>{meta}</Text>
      ) : null}
      {trail.description && (
        <Text numberOfLines={2} style={{ fontWeight: F.sans, fontSize: 13, color: C.ink2, lineHeight: 18, marginTop: 4 }}>
          {trail.description}
        </Text>
      )}
    </View>
  )
}
