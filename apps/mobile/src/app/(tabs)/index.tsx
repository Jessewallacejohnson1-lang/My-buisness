import { useCallback, useEffect, useRef, useState } from 'react'
import { RefreshControl, ScrollView, TextInput, View } from 'react-native'
import { SafeAreaView } from 'react-native-safe-area-context'
import { useRouter } from 'expo-router'
import * as Haptics from 'expo-haptics'
import Animated, { FadeInDown, useReducedMotion } from 'react-native-reanimated'
import { firstNameFromEmail, localDate, type TimelineEvent, type UpcomingEvent } from '@hygge/core'
import { api } from '../../lib/api'
import { useAuth } from '../../lib/auth'
import { byTime } from '../../lib/time'
import { WeekStrip, type WeekDay } from '../../components/WeekStrip'
import { TodayBar } from '../../components/TodayBar'
import { DayTimeline, type TimelineRow } from '../../components/DayTimeline'
import { AroundTown } from '../../components/AroundTown'
import { QuestSection } from '../../components/QuestSection'
import { ScreenBadge } from '../../components/ScreenBadge'
import { C, F, HAIRLINE, CARD_SHADOW } from '../../theme'

// The page-load entrance plays once a session — returning to Home shouldn't
// re-orchestrate the whole screen. This flips true after the first mount.
let homeEntered = false

/** The Sun–Sat week containing `todayStr`, flagged with which days hold events. */
function buildWeek(todayStr: string, eventDates: Set<string>): WeekDay[] {
  const [y, m, d] = todayStr.split('-').map(Number)
  const dow = new Date(y, m - 1, d).getDay()
  const out: WeekDay[] = []
  for (let i = 0; i < 7; i++) {
    const dt = new Date(y, m - 1, d - dow + i)
    const ds = localDate(dt)
    out.push({ date: ds, day: dt.getDate(), letter: 'SMTWTFS'[i], isToday: ds === todayStr, isPast: ds < todayStr, hasEvents: eventDates.has(ds) })
  }
  return out
}

/** "SCHEDULE · FRI JUL 4" header for a non-today day. */
function scheduleTitle(ds: string): string {
  const [y, m, d] = ds.split('-').map(Number)
  const label = new Date(y, m - 1, d)
    .toLocaleDateString('en-US', { weekday: 'short', month: 'short', day: 'numeric' })
    .replace(',', '')
    .toUpperCase()
  return `SCHEDULE · ${label}`
}

export default function Home() {
  const router = useRouter()
  const reduce = useReducedMotion()
  const { signOut } = useAuth()
  const today0 = localDate()
  const [today, setToday] = useState<TimelineEvent[]>([])
  const [upcoming, setUpcoming] = useState<UpcomingEvent[]>([])
  const [name, setName] = useState<string | null>(null)
  const [selectedDate, setSelectedDate] = useState<string>(today0)
  const [query, setQuery] = useState('')
  const [searchOpen, setSearchOpen] = useState(false)
  const [loading, setLoading] = useState(true)
  const [refreshing, setRefreshing] = useState(false)

  const load = useCallback(async () => {
    const [t, u, me] = await Promise.all([api.getTodayEvents(), api.getUpcomingEvents(), api.getCurrentUser()])
    setToday(t); setUpcoming(u); setName(firstNameFromEmail(me?.email))
  }, [])

  useEffect(() => { load().finally(() => setLoading(false)) }, [load])
  const onRefresh = async () => { setRefreshing(true); await load(); setRefreshing(false) }

  const toggleRsvp = async (ev: { id: string; rsvpd?: boolean }) => {
    const next = !ev.rsvpd
    Haptics.notificationAsync(next ? Haptics.NotificationFeedbackType.Success : Haptics.NotificationFeedbackType.Warning)
    setToday((l) => l.map((e) => e.id === ev.id ? { ...e, rsvpd: next, going_count: e.going_count + (next ? 1 : -1) } : e))
    try { next ? await api.rsvpEvent(ev.id) : await api.unRsvpEvent(ev.id) }
    catch { setToday((l) => l.map((e) => e.id === ev.id ? { ...e, rsvpd: !next, going_count: e.going_count + (next ? -1 : 1) } : e)) }
  }

  const q = query.trim().toLowerCase()
  const keep = (text: string) => !q || text.toLowerCase().includes(q)

  const isToday = selectedDate === today0
  const eventDates = new Set(upcoming.map((e) => e.event_date))
  const week = buildWeek(today0, eventDates)

  // The day's rows: today carries rsvp/club state; other days are the lighter
  // upcoming shape (no RSVP toggle — they're future).
  const todayRows: TimelineRow[] = today.filter((e) => keep(`${e.title} ${e.location ?? ''}`)).sort(byTime)
  const dayRows: TimelineRow[] = upcoming
    .filter((e) => e.event_date === selectedDate && keep(`${e.title} ${e.location ?? ''}`))
    .sort(byTime)
  const rows = isToday ? todayRows : dayRows

  // When today is clear, surface the next real gatherings this week.
  const comingUp: TimelineRow[] = [...upcoming]
    .filter((e) => e.event_date > today0 && keep(`${e.title} ${e.location ?? ''}`))
    .sort((a, b) => (a.event_date === b.event_date ? byTime(a, b) : a.event_date < b.event_date ? -1 : 1))

  const title = isToday ? "TODAY'S SCHEDULE" : scheduleTitle(selectedDate)

  // The entrance plays once a session; gate on the module flag.
  const firstLoad = useRef(!homeEntered)
  useEffect(() => { homeEntered = true }, [])
  const enter = (i: number) =>
    reduce || !firstLoad.current ? undefined : FadeInDown.delay(i * 50).duration(380)

  return (
    <SafeAreaView edges={['top']} style={{ flex: 1, backgroundColor: C.canvas }}>
      <ScreenBadge />
      <ScrollView
        contentContainerStyle={{ paddingBottom: 120 }}
        refreshControl={<RefreshControl refreshing={refreshing} onRefresh={onRefresh} tintColor={C.ink3} />}
      >
        <TodayBar
          name={name}
          onSignOut={signOut}
          searchOpen={searchOpen}
          onToggleSearch={() => { Haptics.selectionAsync(); setQuery(''); setSearchOpen((o) => !o) }}
          enter={enter}
        />

        {searchOpen && (
          <View style={{ paddingHorizontal: 20, paddingTop: 12 }}>
            <TextInput
              autoFocus
              value={query}
              onChangeText={setQuery}
              placeholder="Search events…"
              placeholderTextColor={C.ink2}
              style={{ height: 46, borderRadius: 12, paddingHorizontal: 13, backgroundColor: C.paper, fontWeight: F.sans, fontSize: 15, color: C.ink, borderWidth: 1, borderColor: HAIRLINE, ...CARD_SHADOW }}
            />
          </View>
        )}

        <Animated.View entering={enter(3)} style={{ marginTop: 22 }}>
          <WeekStrip days={week} selected={selectedDate} onSelect={setSelectedDate} />
        </Animated.View>

        <Animated.View entering={enter(4)} style={{ marginTop: 22 }}>
          <DayTimeline
            title={title}
            rows={rows}
            interactive={isToday}
            loading={loading}
            comingUp={comingUp}
            onToggleRsvp={toggleRsvp}
            onSelectDate={setSelectedDate}
            onAdd={() => { Haptics.selectionAsync(); router.push('/(tabs)/add') }}
          />
        </Animated.View>

        <Animated.View entering={enter(5)}>
          <AroundTown />
        </Animated.View>

        <Animated.View entering={enter(6)}>
          <QuestSection />
        </Animated.View>
      </ScrollView>
    </SafeAreaView>
  )
}
