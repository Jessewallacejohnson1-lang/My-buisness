import { useEffect, useRef, useState } from 'react'
import { Pressable, ScrollView, Text, View } from 'react-native'
import { useSafeAreaInsets } from 'react-native-safe-area-context'
import { Gesture, GestureDetector } from 'react-native-gesture-handler'
import Animated, {
  interpolate, runOnJS, useAnimatedStyle, withTiming, type SharedValue,
} from 'react-native-reanimated'
import type { AgendaEvent } from '@hygge/core'
import { api } from '../lib/api'
import { C, F, HAIRLINE } from '../theme'
import { CloseIcon } from './icons'

/** One day of the pinched week, with enough context to render the gutter. */
export type WeekDay = { ymd: string; day: number; weekday: string; inMonth: boolean }

function rangeLabel(week: WeekDay[]): string {
  const a = new Date(week[0].ymd + 'T00:00:00')
  const b = new Date(week[6].ymd + 'T00:00:00')
  const mA = a.toLocaleDateString('en-US', { month: 'short' })
  const mB = b.toLocaleDateString('en-US', { month: 'short' })
  return mA === mB
    ? `${mA} ${a.getDate()} – ${b.getDate()}`
    : `${mA} ${a.getDate()} – ${mB} ${b.getDate()}`
}

/**
 * The week you pinched into — a page from a paper planner. A left date gutter
 * (mono numerals) divided by a hairline rule from each day's events. `progress`
 * (0 closed → 1 open) is driven by the pinch on the parent; this view just maps
 * it to opacity + scale so the zoom tracks your fingers.
 */
export function ExpandedWeek({ week, progress, todayYmd, onClose, onSelectDay }: {
  week: WeekDay[]
  progress: SharedValue<number>
  todayYmd: string
  onClose: () => void
  onSelectDay: (ymd: string) => void
}) {
  const insets = useSafeAreaInsets()
  const [byDate, setByDate] = useState<Map<string, AgendaEvent[]>>(new Map())
  const reqRef = useRef('')

  useEffect(() => {
    const key = week[0].ymd + week[6].ymd
    reqRef.current = key
    api.getEventsForRange(week[0].ymd, week[6].ymd)
      .then((evs) => {
        if (reqRef.current !== key) return
        const m = new Map<string, AgendaEvent[]>()
        evs.forEach((e) => { const a = m.get(e.event_date) ?? []; a.push(e); m.set(e.event_date, a) })
        setByDate(m)
      })
      .catch(() => {})
  }, [week])

  const backdropStyle = useAnimatedStyle(() => ({ opacity: progress.value }))
  const cardStyle = useAnimatedStyle(() => ({
    opacity: progress.value,
    transform: [
      { scale: interpolate(progress.value, [0, 1], [0.94, 1]) },
      { translateY: interpolate(progress.value, [0, 1], [28, 0]) },
    ],
  }))

  // Pinch back in to collapse (matches "pinch to zoom" — two fingers, so it
  // never fights the agenda's single-finger scroll).
  const pinchClose = Gesture.Pinch()
    .onUpdate((e) => {
      'worklet'
      if (e.scale < 1) progress.value = Math.max(0, Math.min(1, 1 - (1 - e.scale) / 0.6))
    })
    .onEnd(() => {
      'worklet'
      if (progress.value < 0.5) runOnJS(onClose)()
      else progress.value = withTiming(1, { duration: 160 })
    })

  // Drag the handle down to collapse — the one-finger / mouse exit (pinch needs
  // two fingers and doesn't exist on the web build). Lives on the handle only,
  // so it never fights the agenda's scroll.
  const dragClose = Gesture.Pan()
    .activeOffsetY(8)
    .onUpdate((e) => { 'worklet'; if (e.translationY > 0) progress.value = Math.max(0, 1 - e.translationY / 260) })
    .onEnd((e) => {
      'worklet'
      if (progress.value < 0.6 || e.velocityY > 700) runOnJS(onClose)()
      else progress.value = withTiming(1, { duration: 160 })
    })

  return (
    <View style={{ position: 'absolute', top: 0, left: 0, right: 0, bottom: 0 }}>
      <Animated.View style={[{ position: 'absolute', top: 0, left: 0, right: 0, bottom: 0, backgroundColor: 'rgba(20,20,18,0.28)' }, backdropStyle]}>
        <Pressable style={{ flex: 1 }} onPress={onClose} accessibilityRole="button" accessibilityLabel="Close week" />
      </Animated.View>

      <GestureDetector gesture={pinchClose}>
        <Animated.View style={[{
          position: 'absolute', top: insets.top + 6, left: 0, right: 0, bottom: 0,
          backgroundColor: C.paper, borderTopLeftRadius: 24, borderTopRightRadius: 24,
          borderTopWidth: 1, borderColor: HAIRLINE, overflow: 'hidden',
        }, cardStyle]}>
          {/* grab handle — drag down to close */}
          <GestureDetector gesture={dragClose}>
            <View style={{ alignItems: 'center', paddingTop: 10, paddingBottom: 6 }}>
              <View style={{ width: 40, height: 5, borderRadius: 2.5, backgroundColor: 'rgba(0,0,0,0.16)' }} />
            </View>
          </GestureDetector>

          {/* header — week range in the data face */}
          <View style={{ flexDirection: 'row', justifyContent: 'space-between', alignItems: 'flex-start', paddingHorizontal: 20, paddingTop: 6, paddingBottom: 12 }}>
            <View style={{ flex: 1 }}>
              <Text style={{ fontWeight: F.mono, fontSize: 11, color: C.ink3, letterSpacing: 1.6 }}>THE WEEK OF</Text>
              <Text style={{ fontWeight: F.display, fontSize: 24, color: C.ink, marginTop: 3, letterSpacing: -0.3 }}>{rangeLabel(week)}</Text>
            </View>
            <Pressable
              onPress={onClose}
              hitSlop={10}
              accessibilityRole="button"
              accessibilityLabel="Close week"
              style={({ pressed }) => ({ width: 32, height: 32, borderRadius: 16, backgroundColor: C.paper100, alignItems: 'center', justifyContent: 'center', opacity: pressed ? 0.6 : 1 })}
            >
              <CloseIcon size={16} color={C.ink2} />
            </Pressable>
          </View>

          <ScrollView contentContainerStyle={{ paddingBottom: insets.bottom + 28 }} showsVerticalScrollIndicator={false}>
            {week.map((d) => {
              const isToday = d.ymd === todayYmd
              const isPast = d.ymd < todayYmd
              const events = byDate.get(d.ymd) ?? []
              const numColor = isToday ? C.moss700 : (isPast || !d.inMonth) ? C.ink3 : C.ink
              return (
                <Pressable
                  key={d.ymd}
                  onPress={() => onSelectDay(d.ymd)}
                  style={({ pressed }) => ({
                    flexDirection: 'row', minHeight: 66, paddingHorizontal: 20,
                    borderTopWidth: 1, borderTopColor: HAIRLINE,
                    backgroundColor: pressed ? 'rgba(0,0,0,0.02)' : 'transparent',
                  })}
                >
                  {/* date gutter */}
                  <View style={{ width: 50, paddingTop: 14, alignItems: 'center' }}>
                    <Text style={{ fontWeight: F.sansMed, fontSize: 11, color: isToday ? C.moss700 : C.ink3, letterSpacing: 0.4 }}>{d.weekday}</Text>
                    <View style={{ width: 34, height: 34, borderRadius: 17, marginTop: 4, alignItems: 'center', justifyContent: 'center', borderWidth: isToday ? 1.5 : 0, borderColor: isToday ? C.moss700 : 'transparent' }}>
                      <Text style={{ fontWeight: F.monoMed, fontSize: 19, color: numColor }}>{d.day}</Text>
                    </View>
                  </View>

                  {/* hairline rule — the planner's date gutter */}
                  <View style={{ width: 1, backgroundColor: HAIRLINE, marginLeft: 8, marginRight: 16 }} />

                  {/* events for the day */}
                  <View style={{ flex: 1, paddingVertical: 14, justifyContent: events.length ? 'flex-start' : 'center' }}>
                    {events.length === 0 ? (
                      <View style={{ width: 18, height: 1, backgroundColor: 'rgba(0,0,0,0.10)' }} />
                    ) : (
                      events.map((e, i) => (
                        <View key={e.id} style={{ marginTop: i === 0 ? 0 : 12 }}>
                          <Text style={{ fontWeight: F.sansSemi, fontSize: 15, color: C.ink, lineHeight: 20 }}>{e.title}</Text>
                          {(!!e.start_time || !!e.location) && (
                            <View style={{ flexDirection: 'row', alignItems: 'center', gap: 8, marginTop: 2 }}>
                              {!!e.start_time && <Text style={{ fontWeight: F.mono, fontSize: 12, color: C.ink2 }}>{e.start_time}</Text>}
                              {!!e.location && <Text style={{ fontWeight: F.sans, fontSize: 12, color: C.sky600 }} numberOfLines={1}>{e.location}</Text>}
                            </View>
                          )}
                        </View>
                      ))
                    )}
                  </View>
                </Pressable>
              )
            })}
          </ScrollView>
        </Animated.View>
      </GestureDetector>
    </View>
  )
}
