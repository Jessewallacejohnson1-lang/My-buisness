import { useEffect, useRef, useState } from 'react'
import { Modal, Pressable, ScrollView, Text, View } from 'react-native'
import { SafeAreaView } from 'react-native-safe-area-context'
import { Gesture, GestureDetector } from 'react-native-gesture-handler'
import Animated, {
  interpolate, runOnJS, useAnimatedStyle, useSharedValue, withSpring, withTiming,
  SlideInDown, type SharedValue,
} from 'react-native-reanimated'
import * as Haptics from 'expo-haptics'
import type { TimelineEvent } from '@hygge/core'
import { localDate } from '@hygge/core'
import { api } from '../../lib/api'
import { useRsvp } from '../../lib/useRsvp'
import { EventRow } from '../../components/EventRow'
import { ExpandedWeek, type WeekDay } from '../../components/ExpandedWeek'
import { CloseIcon } from '../../components/icons'
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

function DayCell({ day, year, month, eventDates, selectedDate, todayYmd, onSelect }: {
  day: number | null; year: number; month: number; eventDates: Set<string>; selectedDate: string | null; todayYmd: string; onSelect: (d: string) => void
}) {
  if (!day) return <View style={{ flex: 1, height: 54 }} />
  const date = ymd(year, month, day)
  const hasEvent = eventDates.has(date)
  const isSelected = date === selectedDate
  const isToday = date === todayYmd
  const isPast = date < todayYmd
  return (
    <Pressable onPress={() => onSelect(date)} style={{ flex: 1, height: 54, alignItems: 'center', justifyContent: 'center' }}>
      {/* circle + reserved dot space below, stacked and centered (no overlap) */}
      <View style={{ width: 40, height: 40, borderRadius: 20, alignItems: 'center', justifyContent: 'center', backgroundColor: isSelected ? C.moss700 : 'transparent', borderWidth: 1.5, borderColor: isToday && !isSelected ? C.moss700 : 'transparent' }}>
        <Text style={{ fontFamily: F.sansSemi, fontSize: 17, lineHeight: 20, color: isSelected ? C.paper : isPast ? C.ink3 : C.ink }}>{day}</Text>
      </View>
      <View style={{ width: 5, height: 5, borderRadius: 2.5, marginTop: 4, backgroundColor: hasEvent && !isSelected ? C.moss500 : 'transparent' }} />
    </Pressable>
  )
}

/** One week of a month, wrapped in a pinch gesture that zooms it into a week view. */
function WeekRow({ week, year, month, eventDates, selectedDate, todayYmd, onSelect, progress, onExpandStart, onAbort, onCommit }: {
  week: (number | null)[]; year: number; month: number; eventDates: Set<string>; selectedDate: string | null; todayYmd: string
  onSelect: (d: string) => void; progress: SharedValue<number>
  onExpandStart: (days: WeekDay[]) => void; onAbort: () => void; onCommit: () => void
}) {
  const days = weekDatesFrom(year, month, week)

  // Pinch out → drive progress; release past the threshold commits the zoom.
  const pinch = Gesture.Pinch()
    .onStart(() => { 'worklet'; runOnJS(onExpandStart)(days) })
    .onUpdate((e) => { 'worklet'; progress.value = Math.max(0, Math.min(1, (e.scale - 1) / 0.6)) })
    .onEnd(() => {
      'worklet'
      if (progress.value > 0.4) { progress.value = withSpring(1, SPRING); runOnJS(onCommit)() }
      else { progress.value = withTiming(0, { duration: 160 }, (f) => { if (f) runOnJS(onAbort)() }) }
    })

  // Press-and-hold fallback (works on web/desktop, where pinch isn't available).
  const longPress = Gesture.LongPress().minDuration(360)
    .onStart(() => { 'worklet'; runOnJS(onExpandStart)(days); progress.value = withSpring(1, SPRING); runOnJS(onCommit)() })

  return (
    <GestureDetector gesture={Gesture.Race(pinch, longPress)}>
      <View style={{ flexDirection: 'row' }}>
        {week.map((day, di) => (
          <DayCell key={di} day={day} year={year} month={month} eventDates={eventDates} selectedDate={selectedDate} todayYmd={todayYmd} onSelect={onSelect} />
        ))}
      </View>
    </GestureDetector>
  )
}

function MonthBlock({ year, month, eventDates, selectedDate, todayYmd, onSelect, progress, onExpandStart, onAbort, onCommit }: {
  year: number; month: number; eventDates: Set<string>; selectedDate: string | null; todayYmd: string
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
      <Text style={{ fontFamily: F.sansBold, fontSize: 26, color: C.ink, letterSpacing: -0.4, marginTop: 22, marginBottom: 6 }}>{label}</Text>
      {weeks.map((week, wi) => (
        <WeekRow
          key={wi} week={week} year={year} month={month} eventDates={eventDates} selectedDate={selectedDate} todayYmd={todayYmd}
          onSelect={onSelect} progress={progress} onExpandStart={onExpandStart} onAbort={onAbort} onCommit={onCommit}
        />
      ))}
    </View>
  )
}

export default function Calendar() {
  const today = new Date()
  const todayYmd = ymd(today.getFullYear(), today.getMonth() + 1, today.getDate())
  const [selectedDate, setSelectedDate] = useState<string | null>(null)
  const [eventDates, setEventDates] = useState<Set<string>>(new Set())
  const [dayEvents, setDayEvents] = useState<TimelineEvent[]>([])
  const [sheetOpen, setSheetOpen] = useState(false)
  const [loadingEvents, setLoadingEvents] = useState(false)
  const [expanded, setExpanded] = useState<WeekDay[] | null>(null)
  const progress = useSharedValue(0)
  const reqRef = useRef<string | null>(null)
  const scrollRef = useRef<ScrollView>(null)
  const didScroll = useRef(false)
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
    Promise.all(months.map((m) => api.getMonthEventDates(m.year, m.month).catch(() => [] as string[])))
      .then((res) => { if (alive) setEventDates(new Set(res.flat())) })
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
    progress.value = withTiming(0, { duration: 200 }, (f) => { if (f) runOnJS(clearExpanded)() })
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
      <Animated.View style={[{ flex: 1 }, gridStyle]}>
        <Text style={{ fontFamily: F.sansBold, fontSize: 28, color: C.ink, letterSpacing: -0.5, marginTop: 16, marginBottom: 10, paddingHorizontal: 20 }}>What&rsquo;s coming up?</Text>
        {/* Weekday header — a fixed row of 7 even columns, pinned above the scroll */}
        <View style={{ flexDirection: 'row', width: '100%', paddingHorizontal: 20, paddingBottom: 8, borderBottomWidth: 1, borderBottomColor: HAIRLINE }}>
          {WEEKDAYS.map((d) => (
            <Text key={d} style={{ flexGrow: 1, flexBasis: 0, textAlign: 'center', fontFamily: F.sansSemi, fontSize: 13, color: C.ink2 }}>{d}</Text>
          ))}
        </View>
        <ScrollView ref={scrollRef} contentContainerStyle={{ paddingHorizontal: 20, paddingBottom: 120 }}>
          {months.map((m) => {
            const isCurrent = m.year === today.getFullYear() && m.month === today.getMonth() + 1
            return (
              <View
                key={`${m.year}-${m.month}`}
                onLayout={isCurrent ? (e) => {
                  const y = e.nativeEvent.layout.y
                  if (!didScroll.current && y > 0) { didScroll.current = true; scrollRef.current?.scrollTo({ y, animated: false }) }
                } : undefined}
              >
                <MonthBlock
                  year={m.year} month={m.month} eventDates={eventDates} selectedDate={selectedDate} todayYmd={todayYmd}
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

      <Modal visible={sheetOpen} transparent animationType="fade" onRequestClose={() => setSheetOpen(false)}>
        <Pressable style={{ flex: 1, backgroundColor: 'rgba(0,0,0,0.28)' }} onPress={() => setSheetOpen(false)} />
        <Animated.View entering={SlideInDown.duration(320)} style={{ position: 'absolute', bottom: 0, left: 0, right: 0, maxHeight: '62%', backgroundColor: C.paper, borderTopLeftRadius: 18, borderTopRightRadius: 18, borderTopWidth: 1, borderColor: HAIRLINE, paddingHorizontal: 18, paddingTop: 10, paddingBottom: 28 }}>
          <View style={{ alignItems: 'center', paddingBottom: 8 }}>
            <View style={{ width: 36, height: 4, borderRadius: 2, backgroundColor: 'rgba(0,0,0,0.14)' }} />
          </View>
          <View style={{ flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', marginBottom: 4 }}>
            <Text style={{ fontFamily: F.display, fontSize: 18, color: C.ink }}>{sheetTitle}</Text>
            <Pressable onPress={() => setSheetOpen(false)} hitSlop={8}><CloseIcon /></Pressable>
          </View>
          <ScrollView>
            {loadingEvents ? (
              <Text style={{ fontFamily: F.sans, fontSize: 14, color: C.ink3, paddingVertical: 12 }}>Loading…</Text>
            ) : dayEvents.length === 0 ? (
              <Text style={{ fontFamily: F.sans, fontSize: 14, color: C.ink3, paddingVertical: 12 }}>No events this day.</Text>
            ) : (
              dayEvents.map((e, i) => <EventRow key={e.id} event={e} onRsvp={handleRsvp} last={i === dayEvents.length - 1} />)
            )}
          </ScrollView>
        </Animated.View>
      </Modal>
    </SafeAreaView>
  )
}
