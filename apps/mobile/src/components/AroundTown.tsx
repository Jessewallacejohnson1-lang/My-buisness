import { useEffect, useRef } from 'react'
import { Pressable, ScrollView, Text, View, type NativeSyntheticEvent, type NativeScrollEvent } from 'react-native'
import { Image } from 'expo-image'
import { LinearGradient } from 'expo-linear-gradient'
import * as Haptics from 'expo-haptics'
import { COLLECTIONS } from '../theme'
import { C, F } from '../theme'
import { CheckIcon } from './icons'

const CARD_W = 208
const CARD_H = 196
const GAP = 12
const STEP = CARD_W + GAP

/** "Around town" — auto-playing photo carousel of real St. Joe places (mirrors web). */
export function AroundTown({
  selected,
  onSelect,
}: {
  selected: number | null
  onSelect: (i: number) => void
}) {
  const scrollRef = useRef<ScrollView>(null)
  const idx = useRef(0)
  const paused = useRef(false)

  // Drift the carousel forward on its own; pause while the user is touching it.
  useEffect(() => {
    const id = setInterval(() => {
      if (paused.current) return
      idx.current = (idx.current + 1) % COLLECTIONS.length
      scrollRef.current?.scrollTo({ x: idx.current * STEP, animated: true })
    }, 3200)
    return () => clearInterval(id)
  }, [])

  const onMomentumEnd = (e: NativeSyntheticEvent<NativeScrollEvent>) => {
    idx.current = Math.round(e.nativeEvent.contentOffset.x / STEP)
    paused.current = false
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
        onTouchStart={() => { paused.current = true }}
        onScrollBeginDrag={() => { paused.current = true }}
        onMomentumScrollEnd={onMomentumEnd}
        contentContainerStyle={{ gap: GAP, paddingHorizontal: 20, paddingTop: 12, paddingBottom: 6 }}
      >
        {COLLECTIONS.map((c, i) => {
          const active = selected === i
          return (
            // Outer = shadow host (no clipping, so the soft drop shadow shows).
            <View
              key={c.name}
              style={{
                width: CARD_W, height: CARD_H, borderRadius: 24,
                shadowColor: '#1f3022',
                shadowOpacity: active ? 0.22 : 0.12,
                shadowRadius: active ? 22 : 16,
                shadowOffset: { width: 0, height: active ? 8 : 6 },
                elevation: active ? 8 : 4,
              }}
            >
              <Pressable
                onPress={() => { Haptics.selectionAsync(); onSelect(i) }}
                style={({ pressed }) => ({
                  flex: 1, borderRadius: 24, overflow: 'hidden',
                  justifyContent: 'flex-end', padding: 18,
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
                <Text style={{ fontFamily: F.sansBold, fontSize: 22, color: '#fbfaf5', letterSpacing: -0.4, textShadowColor: 'rgba(0,0,0,0.45)', textShadowOffset: { width: 0, height: 1 }, textShadowRadius: 8 }}>
                  {c.name}
                </Text>
                <Text style={{ fontFamily: F.sans, fontSize: 13, color: 'rgba(251,250,245,0.92)', marginTop: 5, textShadowColor: 'rgba(0,0,0,0.45)', textShadowOffset: { width: 0, height: 1 }, textShadowRadius: 6 }}>
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
