import { useEffect, useRef } from 'react'
import { Pressable, ScrollView, Text, View, type NativeSyntheticEvent, type NativeScrollEvent } from 'react-native'
import { Image } from 'expo-image'
import { LinearGradient } from 'expo-linear-gradient'
import * as Haptics from 'expo-haptics'
import { COLLECTIONS } from '../theme'
import { C, F } from '../theme'
import { CheckIcon } from './icons'

const CARD_W = 220
const CARD_H = 200
const GAP = 14
const STEP = CARD_W + GAP
const N = COLLECTIONS.length

// Triple the list so the carousel scrolls forever in either direction: we keep
// the viewport parked in the *middle* copy and recenter invisibly at the seams,
// so the user never reaches an end or sees a snap-back.
const LOOP = [...COLLECTIONS, ...COLLECTIONS, ...COLLECTIONS]
const MID = N // index where the middle copy starts

/** "Around town" — endlessly-looping photo carousel of real St. Joe places. */
export function AroundTown({
  selected,
  onSelect,
}: {
  selected: number | null
  onSelect: (i: number) => void
}) {
  const scrollRef = useRef<ScrollView>(null)
  const idx = useRef(MID)
  const paused = useRef(false)
  const ready = useRef(false)

  // Park on the middle copy once the content is sized, so there's always a copy
  // of every card to the left and right to scroll into.
  const onContentSizeChange = () => {
    if (ready.current) return
    ready.current = true
    scrollRef.current?.scrollTo({ x: MID * STEP, animated: false })
  }

  // Whenever idx drifts out of the middle band [N, 2N), hop the identical card
  // one copy back/forward with no animation — same image, surroundings, and
  // offset-within-step, so the seam is invisible.
  const recenter = () => {
    if (idx.current >= 2 * N) {
      idx.current -= N
      scrollRef.current?.scrollTo({ x: idx.current * STEP, animated: false })
    } else if (idx.current < N) {
      idx.current += N
      scrollRef.current?.scrollTo({ x: idx.current * STEP, animated: false })
    }
  }

  // Drift forward on its own; pause while the user is touching it.
  useEffect(() => {
    const id = setInterval(() => {
      if (paused.current || !ready.current) return
      const next = idx.current + 1
      if (next >= 2 * N) {
        // About to enter the last copy — silently hop back one copy to the
        // identical card, then animate one step forward so motion stays smooth.
        const here = next - 1 - N
        scrollRef.current?.scrollTo({ x: here * STEP, animated: false })
        idx.current = here + 1
        scrollRef.current?.scrollTo({ x: (here + 1) * STEP, animated: true })
      } else {
        idx.current = next
        scrollRef.current?.scrollTo({ x: next * STEP, animated: true })
      }
    }, 3200)
    return () => clearInterval(id)
  }, [])

  const onMomentumEnd = (e: NativeSyntheticEvent<NativeScrollEvent>) => {
    idx.current = Math.round(e.nativeEvent.contentOffset.x / STEP)
    paused.current = false
    recenter()
  }

  return (
    <View style={{ paddingTop: 14, paddingBottom: 4 }}>
      <Text style={{ fontFamily: F.sansBold, fontSize: 20, color: C.ink, letterSpacing: -0.3, paddingHorizontal: 20 }}>
        Around town
      </Text>
      <ScrollView
        ref={scrollRef}
        horizontal
        showsHorizontalScrollIndicator={false}
        decelerationRate="fast"
        snapToInterval={STEP}
        snapToAlignment="start"
        contentOffset={{ x: MID * STEP, y: 0 }}
        onContentSizeChange={onContentSizeChange}
        onTouchStart={() => { paused.current = true }}
        onScrollBeginDrag={() => { paused.current = true }}
        onMomentumScrollEnd={onMomentumEnd}
        contentContainerStyle={{ gap: GAP, paddingHorizontal: 20, paddingTop: 12, paddingBottom: 6 }}
      >
        {LOOP.map((c, i) => {
          const ci = i % N
          const active = selected === ci
          return (
            // Outer = shadow host (no clipping, so the soft drop shadow shows).
            <View
              key={i}
              style={{
                width: CARD_W, height: CARD_H, borderRadius: 28,
                shadowColor: '#1f3022',
                shadowOpacity: active ? 0.22 : 0.12,
                shadowRadius: active ? 22 : 16,
                shadowOffset: { width: 0, height: active ? 8 : 6 },
                elevation: active ? 8 : 4,
              }}
            >
              <Pressable
                onPress={() => { Haptics.selectionAsync(); onSelect(ci) }}
                style={({ pressed }) => ({
                  flex: 1, borderRadius: 28, overflow: 'hidden',
                  justifyContent: 'flex-end', paddingHorizontal: 16, paddingBottom: 18, paddingTop: 18,
                  transform: [{ scale: pressed ? 0.985 : 1 }],
                  borderWidth: active ? 2.5 : 0, borderColor: active ? C.ink : 'transparent',
                })}
              >
                <Image source={c.image} style={{ position: 'absolute', top: 0, left: 0, right: 0, bottom: 0 }} contentFit="cover" transition={250} />
                <LinearGradient
                  colors={['rgba(20,18,14,0.06)', 'rgba(20,18,14,0.30)', 'rgba(20,18,14,0.74)']}
                  locations={[0, 0.55, 1]}
                  style={{ position: 'absolute', top: 0, left: 0, right: 0, bottom: 0 }}
                />
                {active && (
                  <View style={{ position: 'absolute', top: 12, right: 12, width: 22, height: 22, borderRadius: 11, backgroundColor: 'rgba(255,255,255,0.92)', alignItems: 'center', justifyContent: 'center' }}>
                    <CheckIcon size={12} color={C.ink} />
                  </View>
                )}
                <Text numberOfLines={1} style={{ fontFamily: F.sansBold, fontSize: 17, color: '#fbfaf5', letterSpacing: -0.3, textShadowColor: 'rgba(0,0,0,0.45)', textShadowOffset: { width: 0, height: 1 }, textShadowRadius: 8 }}>
                  {c.name}
                </Text>
                <Text numberOfLines={1} style={{ fontFamily: F.sans, fontSize: 13, color: 'rgba(251,250,245,0.92)', marginTop: 4, textShadowColor: 'rgba(0,0,0,0.45)', textShadowOffset: { width: 0, height: 1 }, textShadowRadius: 6 }}>
                  {c.blurb}
                </Text>
              </Pressable>
            </View>
          )
        })}
      </ScrollView>
    </View>
  )
}
