import { Pressable, ScrollView, StyleSheet, Text, View } from 'react-native'
import { Image } from 'expo-image'
import { LinearGradient } from 'expo-linear-gradient'
import * as Haptics from 'expo-haptics'
import Animated, {
  useAnimatedStyle, useFrameCallback, useReducedMotion, useSharedValue,
} from 'react-native-reanimated'
import { useRouter } from 'expo-router'
import { PLACES, type Place } from '../data/places'
import { C, F } from '../theme'

// Calm marquee of real St. Joe places. The drift is a `translateX` TRANSFORM on
// a plain row (not scrollTo on a ScrollView) — transforms don't fight the touch
// system, so every tile stays tappable while it glides. Two copies back-to-back
// make the wrap from COPY_W → 0 land on identical tiles for a seamless loop.
const CARD = 188
const GAP = 14
const STEP = CARD + GAP
const COPY_W = PLACES.length * STEP
const SPEED = 0.018 // px/ms ≈ 18px/s — a slow, calm drift
const LOOP = [...PLACES, ...PLACES]

// Soft, warm, single-direction lift (Cal-AI-clean — not a hard green shadow).
const TILE_SHADOW = {
  shadowColor: '#1a1813',
  shadowOpacity: 0.16,
  shadowRadius: 16,
  shadowOffset: { width: 0, height: 9 },
  elevation: 7,
} as const

const TEXT_SHADOW = { textShadowColor: 'rgba(0,0,0,0.45)', textShadowOffset: { width: 0, height: 1 }, textShadowRadius: 8 }

/** "Around town" — floating photo tiles that slowly glide across the screen.
 *  Tap a tile to open its showcase; touching pauses the drift so you can aim. */
export function AroundTown() {
  const router = useRouter()
  const reduce = useReducedMotion()
  const x = useSharedValue(0)
  const paused = useSharedValue(false)

  useFrameCallback((frame) => {
    if (reduce || paused.value) return
    const dt = frame.timeSincePreviousFrame ?? 16
    let nx = x.value + dt * SPEED
    if (nx >= COPY_W) nx -= COPY_W
    x.value = nx
  })

  const rowStyle = useAnimatedStyle(() => ({ transform: [{ translateX: -x.value }] }))

  const open = (slug: string) => { Haptics.selectionAsync(); router.push(`/place/${slug}`) }

  const tile = (p: Place, key: string) => (
    // Outer = shadow host (not clipped) so the tile floats off the page.
    <View key={key} style={{ width: CARD, height: CARD, marginRight: GAP, borderRadius: 28, ...TILE_SHADOW }}>
      <Pressable
        onPress={() => open(p.slug)}
        onPressIn={() => { paused.value = true }}
        onPressOut={() => { paused.value = false }}
        style={({ pressed }) => ({
          flex: 1, borderRadius: 28, overflow: 'hidden',
          justifyContent: 'flex-end', padding: 16,
          transform: [{ scale: pressed ? 0.96 : 1 }],
        })}
      >
        <Image source={p.image} style={StyleSheet.absoluteFill} contentFit="cover" transition={280} />
        <LinearGradient
          colors={['rgba(16,14,10,0)', 'rgba(16,14,10,0.16)', 'rgba(16,14,10,0.78)']}
          locations={[0, 0.48, 1]}
          style={StyleSheet.absoluteFill}
        />
        <Text numberOfLines={1} style={{ fontWeight: F.display, fontSize: 21, color: '#fdfcf8', letterSpacing: -0.3, ...TEXT_SHADOW }}>
          {p.name}
        </Text>
        <Text numberOfLines={1} style={{ fontWeight: F.sans, fontSize: 13, color: 'rgba(253,252,248,0.92)', marginTop: 4, ...TEXT_SHADOW }}>
          {p.tagline}
        </Text>
      </Pressable>
    </View>
  )

  return (
    <View style={{ paddingTop: 32 }}>
      <View style={{ paddingHorizontal: 20, marginBottom: 16 }}>
        <Text style={{ fontWeight: F.display, fontSize: 24, color: C.ink, letterSpacing: -0.3 }}>Around town</Text>
        <Text style={{ fontWeight: F.sans, fontSize: 14, color: C.ink2, marginTop: 3 }}>A few corners of St. Joe worth a wander.</Text>
      </View>

      {reduce ? (
        // Reduced motion: a plain, swipeable, tappable row — no auto-drift.
        <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={{ paddingHorizontal: 20, paddingVertical: 6 }}>
          {PLACES.map((p) => tile(p, p.slug))}
        </ScrollView>
      ) : (
        <View style={{ overflow: 'visible' }}>
          <Animated.View style={[{ flexDirection: 'row', paddingLeft: 20, paddingVertical: 6 }, rowStyle]}>
            {LOOP.map((p, i) => tile(p, `${p.slug}-${i}`))}
          </Animated.View>
        </View>
      )}
    </View>
  )
}
