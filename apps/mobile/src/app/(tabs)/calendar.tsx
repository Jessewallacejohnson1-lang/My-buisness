import { useEffect, useRef, useState } from 'react'
import { Pressable, ScrollView, Text, View } from 'react-native'
import { SafeAreaView } from 'react-native-safe-area-context'
import { Gesture, GestureDetector } from 'react-native-gesture-handler'
import Animated, {
  Easing, interpolate, runOnJS, useAnimatedStyle, useReducedMotion, useSharedValue,
  withRepeat, withSpring, withTiming, type SharedValue,
} from 'react-native-reanimated'
import * as Haptics from 'expo-haptics'
import { useRouter } from 'expo-router'
import type { TimelineEvent } from '@hygge/core'
import { localDate } from '@hygge/core'
import { api } from '../../lib/api'
import { useRsvp } from '../../lib/useRsvp'
import { EventRow } from '../../components/EventRow'
import { EventActions } from '../../components/EventActions'
import { ExpandedWeek, type WeekDay } from '../../components/ExpandedWeek'
import { PlusIcon } from '../../components/icons'
import { BottomSheet } from '../../components/ui/bottom-sheet'
import { ScreenBadge } from '../../components/ScreenBadge'
import { C, F, HAIRLINE } from '../../theme'

const WEEKDAYS = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat']
const SPRING = { damping: 18, stiffness: 200, mass: 0.7 }

function ymd(y: number, m: number, d: number) {
  return `${y}-${String(m).padStart(2, '0')}-${String(d).padStart(2, '0')}`
}

function tick() { Haptics.selectionAsync().catch(() => {}) }

/** The real Sun–Sat dates of a week chunk, incl. spillover into adjacent months. */
function weekDatesFrom(year: number, month: number, week: (number | null)[]): WeekDay[] {
  const firstReal = week.find((d): d is number => d != null) ?? 1
  const anchor = new Date(year, month - 1, firstReal)
  const sunday = new Date(anchor)
  sunday.setDate(anchor.getDate() - anchor.getDay())
  return Array.from({ length: 7 }, (_, i) => {
    const dt = new Date(sunday); dt.setDate(sunday.getDate() + i)
    return { ymd: localDate(dt), day: dt.getDate(), weekday: WEEKDAYS[i], inMonth: dt.getMonth() === month - 1 }
  })
}

function DayCell({ day, year, month, counts, selectedDate, todayYmd, onSelect }: {
  day: number | null; year: number; month: number; counts: Record<string, number>; selectedDate: string | null; todayYmd: string; onSelect: (d: string) => void
}) {
  if (!day) return <View style={{ flex: 1, height: 54 }} />
  const date = ymd(year, month, day)
  const count = counts[date] ?? 0
  const isSelected = date === selectedDate
  const isToday = date === todayYmd
  const isPast = date < todayYmd
  return (
    <Pressable onPress={() => onSelect(date)} style={{ flex: 1, height: 54, alignItems: 'center', justifyContent: 'center' }}>
      {/* circle + reserved dot space below, stacked and centered (no overlap) */}
      <View style={{ width: 40, height: 40, borderRadius: 20, alignItems: 'center', justifyContent: 'center', backgroundColor: isSelected ? C.moss700 : 'transparent', borderWidth: 1.5, borderColor: isToday && !isSelected ? C.moss700 : 'transparent' }}>
        <Text style={{ fontWeight: F.sansSemi, fontSize: 17, lineHeight: 20, color: isSelected ? C.paper : isPast ? C.ink3 : C.ink }}>{day}</Text>
      </View>
      <View style={{ flexDirection: 'row', alignItems: 'center', gap: 2, height: 5, marginTop: 4 }}>
        {!isSelected && Array.from({ length: Math.min(count, 3) }).map((_, i) => (
          <View key={i} style={{ width: 5, height: 5, borderRadius: 2.5, backgroundColor: C.moss500 }} />
        ))}
        {!isSelected && count > 3 && (
          <Text style={{ fontWeight: F.mono, fontSize: 9, lineHeight: 9, color: C.moss500 }}>+</Text>
        )}
      </View>
    </Pressable>
  )
}

/** One week of a month, wrapped in a pinch gesture that zooms it into a week view. */
function WeekRow({ week, year, month, counts, selectedDate, todayYmd, onSelect, progress, onExpandStart, onAbort, onCommit }: {
  week: (number | null)[]; year: number; month: number; counts: Record<string, number>; selectedDate: string | null; todayYmd: string
  onSelect: (d: string) => void; progress: SharedValue<number>
  onExpandStart: (days: WeekDay[]) => void; onAbort: () => void; onCommit: () => void
}) {
  const days = weekDatesFrom(year, month, week)
  const reduce = useReducedMotion()

  // Pinch out → drive progress; release past the threshold commits the zoom.
  const pinch = Gesture.Pinch()
    .onStart(() => { 'worklet'; runOnJS(onExpandStart)(days) })
    .onUpdate((e) => { 'worklet'; progress.value = Math.max(0, Math.min(1, (e.scale - 1) / 0.6)) })
    .onEnd(() => {
      'worklet'
      if (progress.value > 0.4) { progress.value = reduce ? 1 : withSpring(1, SPRING); runOnJS(onCommit)() }
      else { progress.value = withTiming(0, { duration: reduce ? 0 : 160 }, (f) => { if (f) runOnJS(onAbort)() }) }
    })

  // Press-and-hold fallback (works on web/desktop, where pinch isn't available).
  const longPress = Gesture.LongPress().minDuration(360)
    .onStart(() => { 'worklet'; runOnJS(onExpandStart)(days); progress.value = reduce ? 1 : withSpring(1, SPRING); runOnJS(onCommit)() })

  return (
    <GestureDetector gesture={Gesture.Race(pinch, longPress)}>
      <View style={{ flexDirection: 'row' }}>
        {week.map((day, di) => (
          <DayCell key={di} day={day} year={year} month={month} counts={counts} selectedDate={selectedDate} todayYmd={todayYmd} onSelect={onSelect} />
        ))}
      </View>
    </GestureDetector>
  )
}

function MonthBlock({ year, month, counts, selectedDate, todayYmd, onSelect, progress, onExpandStart, onAbort, onCommit }: {
  year: number; month: number; counts: Record<string, number>; selectedDate: string | null; todayYmd: string
  onSelect: (d: string) => void; progress: SharedValue<number>
  onExpandStart: (days: WeekDay[]) => void; onAbort: () => void; onCommit: () => void
}) {
  const label = new Date(year, month - 1, 1).toLocaleDateString('en-US', { month: 'long' })
  const firstDay = new Date(year, month - 1, 1).getDay()
  const daysInMonth = new Date(year, month, 0).getDate()
  const cells: (number | null)[] = [...Array(firstDay).fill(null), ...Array.from({ length: daysInMonth }, (_, i) => i + 1)]
  while (cells.length % 7 !== 0) cells.push(null)
  // chunk into weeks of 7 so every column lines up with the weekday header
  const weeks: (number | null)[][] = []
  for (let i = 0; i < cells.length; i += 7) weeks.push(cells.slice(i, i + 7))

  return (
    <View style={{ marginBottom: 4 }}>
      <Text style={{ fontWeight: F.sansBold, fontSize: 26, color: C.ink, letterSpacing: -0.4, marginTop: 22, marginBottom: 6 }}>{label}</Text>
      {weeks.map((week, wi) => (
        <WeekRow
          key={wi} week={week} year={year} month={month} counts={counts} selectedDate={selectedDate} todayYmd={todayYmd}
          onSelect={onSelect} progress={progress} onExpandStart={onExpandStart} onAbort={onAbort} onCommit={onCommit}
        />
      ))}
    </View>
  )
}

/** Event-row-shaped placeholder while a day's events load. Pulse confirms the
 *  wait; collapses to a steady opacity when reduce-motion is on. */
function SheetSkeleton({ reduce }: { reduce: boolean }) {
  const o = useSharedValue(0.5)
  useEffect(() => {
    if (reduce) { o.value = 0.6; return }
    o.value = withRepeat(withTiming(0.85, { duration: 900, easing: Easing.inOut(Easing.ease) }), -1, true)
  }, [reduce, o])
  const style = useAnimatedStyle(() => ({ opacity: o.value }))
  return (
    <Animated.View style={style} accessible accessibilityLabel="Looking…">
      {[0, 1].map((i) => (
        <View key={i} style={{ flexDirection: 'row', gap: 14, alignItems: 'flex-start', paddingVertical: 15, borderBottomWidth: i === 1 ? 0 : 1, borderBottomColor: HAIRLINE }}>
          <View style={{ width: 50, paddingTop: 2 }}>
            <View style={{ width: 34, height: 11, borderRadius: 5, backgroundColor: 'rgba(0,0,0,0.06)' }} />
          </View>
          <View style={{ flex: 1, gap: 8 }}>
            <View style={{ width: '66%', height: 14, borderRadius: 6, backgroundColor: 'rgba(0,0,0,0.06)' }} />
            <View style={{ width: '40%', height: 11, borderRadius: 5, backgroundColor: 'rgba(0,0,0,0.06)' }} />
          </View>
        </View>
      ))}
    </Animated.View>
  )
}

export default function Calendar() {
  const today = new Date()
  const todayYmd = ymd(today.getFullYear(), today.getMonth() + 1, today.getDate())
  const [selectedDate, setSelectedDate] = useState<string | null>(null)
  const [counts, setCounts] = useState<Record<string, number>>({})
  const [dayEvents, setDayEvents] = useState<TimelineEvent[]>([])
  const [sheetOpen, setSheetOpen] = useState(false)
  const [loadingEvents, setLoadingEvents] = useState(false)
  const [expanded, setExpanded] = useState<WeekDay[] | null>(null)
  const progress = useSharedValue(0)
  const reduce = useReducedMotion()
  const reqRef = useRef<string | null>(null)
  const scrollRef = useRef<ScrollView>(null)
  const didScroll = useRef(false)
  const offsets = useRef<Record<string, number>>({})
  const [showToday, setShowToday] = useState(false)
  const todayKey = `${today.getFullYear()}-${today.getMonth() + 1}`

  const upcomingSaturday = (() => {
    const d = new Date(today)
    d.setDate(d.getDate() + ((6 - d.getDay() + 7) % 7)) // today if already Sat
    return localDate(d)
  })()

  const jumpToToday = () => scrollRef.current?.scrollTo({ y: Math.max(0, (offsets.current[todayKey] ?? 0) - 8), animated: true })
  const goThisWeekend = () => { jumpToToday(); selectDate(upcomingSaturday) }
  const router = useRouter()
  const handleRsvp = useRsvp(setDayEvents)

  // Current month forward, plus a few months back so you can scroll up into
  // history — past events are never deleted, they just drop off upcoming surfaces.
  const PAST_MONTHS = 4
  const monthBase = today.getFullYear() * 12 + today.getMonth()
  const months = Array.from({ length: PAST_MONTHS + 12 }, (_, k) => {
    const m = monthBase + k - PAST_MONTHS
    return { year: Math.floor(m / 12), month: (m % 12) + 1 }
  })

  useEffect(() => {
    let alive = true
    Promise.all(months.map((m) => api.getMonthEventCounts(m.year, m.month).catch(() => ({} as Record<string, number>))))
      .then((res) => { if (alive) setCounts(Object.assign({}, ...res)) })
    return () => { alive = false }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  const selectDate = async (d: string) => {
    setSelectedDate(d); setSheetOpen(true); setLoadingEvents(true); reqRef.current = d
    const evs = await api.getEventsByDate(d)
    if (reqRef.current === d) { setDayEvents(evs); setLoadingEvents(false) }
  }

  // Zoom-into-a-week wiring (driven by the pinch in WeekRow).
  const onExpandStart = (days: WeekDay[]) => setExpanded(days)
  const onAbort = () => setExpanded(null)
  const onCommit = () => tick()
  const clearExpanded = () => setExpanded(null)
  const closeExpand = () => {
    tick()
    progress.value = withTiming(0, { duration: reduce ? 0 : 200 }, (f) => { if (f) runOnJS(clearExpanded)() })
  }

  const sheetTitle = selectedDate
    ? new Date(selectedDate + 'T00:00:00').toLocaleDateString('en-US', { weekday: 'long', month: 'long', day: 'numeric' })
    : ''

  const gridStyle = useAnimatedStyle(() => ({
    transform: [{ scale: interpolate(progress.value, [0, 1], [1, 0.97]) }],
    opacity: interpolate(progress.value, [0, 1], [1, 0.5]),
  }))

  return (
    <SafeAreaView edges={['top']} style={{ flex: 1, backgroundColor: C.paper }}>
      <ScreenBadge />
      <Animated.View style={[{ flex: 1 }, gridStyle]}>
        <Text style={{ fontWeight: F.display, fontSize: 28, color: C.ink, letterSpacing: -0.5, marginTop: 16, marginBottom: 10, paddingHorizontal: 20 }}>What&rsquo;s coming up?</Text>
        <View style={{ flexDirection: 'row', gap: 8, paddingHorizontal: 20, marginBottom: 12 }}>
          <Pressable onPress={goThisWeekend} style={({ pressed }) => ({ paddingVertical: 7, paddingHorizontal: 14, borderRadius: 18, backgroundColor: C.moss700, opacity: pressed ? 0.85 : 1 })}>
            <Text style={{ fontWeight: F.sansMed, fontSize: 13, color: C.paper }}>This weekend</Text>
          </Pressable>
          {showToday && (
            <Pressable onPress={jumpToToday} style={({ pressed }) => ({ paddingVertical: 7, paddingHorizontal: 14, borderRadius: 18, borderWidth: 1, borderColor: HAIRLINE, opacity: pressed ? 0.6 : 1 })}>
              <Text style={{ fontWeight: F.sansMed, fontSize: 13, color: C.ink2 }}>Today</Text>
            </Pressable>
          )}
        </View>
        {/* Weekday header — a fixed row of 7 even columns, pinned above the scroll */}
        <View style={{ flexDirection: 'row', width: '100%', paddingHorizontal: 20, paddingBottom: 8, borderBottomWidth: 1, borderBottomColor: HAIRLINE }}>
          {WEEKDAYS.map((d) => (
            <Text key={d} style={{ flexGrow: 1, flexBasis: 0, textAlign: 'center', fontWeight: F.sansSemi, fontSize: 13, color: C.ink2 }}>{d}</Text>
          ))}
        </View>
        <ScrollView
          ref={scrollRef}
          scrollEventThrottle={16}
          onScroll={(e) => {
            const y = e.nativeEvent.contentOffset.y
            const t = offsets.current[todayKey] ?? 0
            setShowToday(Math.abs(y - t) > 200)
          }}
          contentContainerStyle={{ paddingHorizontal: 20, paddingBottom: 120 }}
        >
          {months.map((m) => {
            const isCurrent = m.year === today.getFullYear() && m.month === today.getMonth() + 1
            return (
              <View
                key={`${m.year}-${m.month}`}
                onLayout={(e) => {
                  const y = e.nativeEvent.layout.y
                  offsets.current[`${m.year}-${m.month}`] = y
                  if (isCurrent && !didScroll.current && y > 0) { didScroll.current = true; scrollRef.current?.scrollTo({ y, animated: false }) }
                }}
              >
                <MonthBlock
                  year={m.year} month={m.month} counts={counts} selectedDate={selectedDate} todayYmd={todayYmd}
                  onSelect={selectDate} progress={progress} onExpandStart={onExpandStart} onAbort={onAbort} onCommit={onCommit}
                />
              </View>
            )
          })}
        </ScrollView>
      </Animated.View>

      {expanded && (
        <ExpandedWeek week={expanded} progress={progress} todayYmd={todayYmd} onClose={closeExpand} onSelectDay={selectDate} />
      )}

      <BottomSheet open={sheetOpen} onClose={() => setSheetOpen(false)} title={sheetTitle} maxHeight="62%">
        <ScrollView contentContainerStyle={{ paddingHorizontal: 20, paddingTop: 6, paddingBottom: 28 }} showsVerticalScrollIndicator={false}>
          {loadingEvents ? (
            <SheetSkeleton reduce={reduce} />
          ) : dayEvents.length === 0 ? (
            <Pressable
              onPress={() => { setSheetOpen(false); router.push({ pathname: '/(tabs)/add', params: { date: selectedDate! } }) }}
              style={({ pressed }) => ({ flexDirection: 'row', alignItems: 'center', gap: 8, paddingVertical: 16, opacity: pressed ? 0.6 : 1 })}
            >
              <PlusIcon size={16} color={C.moss700} />
              <Text style={{ fontWeight: F.sansMed, fontSize: 14, color: C.moss700 }}>Add something on this day</Text>
            </Pressable>
          ) : (
            dayEvents.map((e) => (
              <View key={e.id}>
                <EventRow event={e} onRsvp={handleRsvp} last />
                <EventActions event={e} date={selectedDate!} />
              </View>
            ))
          )}
        </ScrollView>
      </BottomSheet>
    </SafeAreaView>
  )
}
