import { Pressable, Text, View } from 'react-native'
import { Image } from 'expo-image'
import { LinearGradient } from 'expo-linear-gradient'
import * as Haptics from 'expo-haptics'
import Animated, {
  scrollTo, useAnimatedRef, useFrameCallback, useReducedMotion, useSharedValue,
} from 'react-native-reanimated'
import { useRouter } from 'expo-router'
import { PLACES } from '../data/places'
import { C, F } from '../theme'

// Large floating square tiles that continuously carousel across the screen.
// Motion runs on the UI thread (reanimated useFrameCallback + scrollTo) so it
// stays smooth on iOS. It scrolls AFTER first paint and never touches the
// initial layout (no contentOffset / onContentSizeChange) — that init pattern is
// what blanked the tiles on iPhone before. Worst case the drift no-ops; tiles
// still render. A constant size is used on purpose (module-scope Dimensions
// returns 0 on iOS → invisible).
const CARD = 184
const GAP = 16
const STEP = CARD + GAP
const N = PLACES.length
const COPY_W = N * STEP // width of one full pass; wrap here for a seamless loop
const SPEED = 0.022 // px per ms ≈ 22px/s — a slow, calm drift

// Two copies back-to-back so the wrap from COPY_W → 0 lands on identical tiles.
const LOOP = [...PLACES, ...PLACES]

/** "Around town" — floating square photo tiles of real St. Joe places that
 *  slowly carousel across the screen. Tap a tile to open its showcase. */
export function AroundTown() {
  const router = useRouter()
  const aref = useAnimatedRef<Animated.ScrollView>()
  const x = useSharedValue(0)
  const paused = useSharedValue(false)
  const reduce = useReducedMotion()

  useFrameCallback((frame) => {
    if (reduce || paused.value) return
    const dt = frame.timeSincePreviousFrame ?? 16
    let nx = x.value + dt * SPEED
    if (nx >= COPY_W) nx -= COPY_W
    x.value = nx
    scrollTo(aref, nx, 0, false)
  })

  return (
    <View style={{ paddingTop: 28 }}>
      <View style={{ paddingHorizontal: 20, marginBottom: 18 }}>
        <Text style={{ fontFamily: F.sansBold, fontSize: 24, color: C.ink, letterSpacing: -0.6 }}>Around town</Text>
        <Text style={{ fontFamily: F.sans, fontSize: 14, color: C.ink3, marginTop: 3 }}>A few corners of St. Joe worth a wander.</Text>
      </View>

      <Animated.ScrollView
        ref={aref}
        horizontal
        scrollEnabled={reduce}
        showsHorizontalScrollIndicator={false}
        contentContainerStyle={{ paddingHorizontal: 20, gap: GAP }}
      >
        {LOOP.map((p, i) => (
          // Outer = shadow host (not clipped) → the tile floats off the page.
          <View
            key={`${p.slug}-${i}`}
            style={{
              width: CARD, height: CARD, borderRadius: 26,
              shadowColor: '#1c2a1e', shadowOpacity: 0.22, shadowRadius: 18,
              shadowOffset: { width: 0, height: 12 }, elevation: 8,
            }}
          >
            <Pressable
              onPressIn={() => { paused.value = true }}
              onPressOut={() => { paused.value = false }}
              onPress={() => { Haptics.selectionAsync(); router.push(`/place/${p.slug}`) }}
              style={({ pressed }) => ({
                flex: 1, borderRadius: 26, overflow: 'hidden',
                justifyContent: 'flex-end', padding: 16,
                transform: [{ scale: pressed ? 0.97 : 1 }],
              })}
            >
              <Image source={p.image} style={{ position: 'absolute', top: 0, left: 0, right: 0, bottom: 0 }} contentFit="cover" transition={280} />
              <LinearGradient
                colors={['rgba(16,14,10,0)', 'rgba(16,14,10,0.18)', 'rgba(16,14,10,0.82)']}
                locations={[0, 0.5, 1]}
                style={{ position: 'absolute', top: 0, left: 0, right: 0, bottom: 0 }}
              />
              <Text numberOfLines={1} style={{ fontFamily: F.display, fontSize: 20, color: '#fdfcf8', letterSpacing: -0.3, textShadowColor: 'rgba(0,0,0,0.5)', textShadowOffset: { width: 0, height: 1 }, textShadowRadius: 8 }}>
                {p.name}
              </Text>
              <Text numberOfLines={1} style={{ fontFamily: F.sans, fontSize: 13, color: 'rgba(253,252,248,0.92)', marginTop: 4, textShadowColor: 'rgba(0,0,0,0.5)', textShadowOffset: { width: 0, height: 1 }, textShadowRadius: 6 }}>
                {p.tagline}
              </Text>
            </Pressable>
          </View>
        ))}
      </Animated.ScrollView>
    </View>
  )
}
