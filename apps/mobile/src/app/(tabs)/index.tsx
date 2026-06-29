import { useCallback, useEffect, useState } from 'react'
import { ActivityIndicator, Pressable, RefreshControl, ScrollView, Text, TextInput, View } from 'react-native'
import { SafeAreaView } from 'react-native-safe-area-context'
import { useRouter } from 'expo-router'
import * as Haptics from 'expo-haptics'
import Animated, { FadeInDown, useReducedMotion } from 'react-native-reanimated'
import { firstNameFromEmail, localDate, type TimelineEvent, type UpcomingEvent } from '@hygge/core'
import { api } from '../../lib/api'
import { useAuth } from '../../lib/auth'
import { WeatherBar } from '../../components/WeatherBar'
import { WeekStrip, type WeekDay } from '../../components/WeekStrip'
import { Ring } from '../../components/Ring'
import { AroundTown } from '../../components/AroundTown'
import { AccountMenu } from '../../components/AccountMenu'
import { QuestSection } from '../../components/QuestSection'
import { SearchIcon, PlusIcon, CheckIcon } from '../../components/icons'
import { C, F, HAIRLINE, CARD_SHADOW, GRAPH } from '../../theme'

/** Free-text display time ("7am", "noon") → minutes from midnight; undated last. */
function minutesOf(s: string | null): number {
  if (!s) return 24 * 60
  const t = s.trim().toLowerCase()
  if (t.includes('noon')) return 12 * 60
  if (t.includes('midnight')) return 0
  const m = t.match(/(\d{1,2})(?::(\d{2}))?\s*(a|p)/)
  if (!m) return 24 * 60
  let h = parseInt(m[1], 10)
  const min = m[2] ? parseInt(m[2], 10) : 0
  if (m[3] === 'p' && h < 12) h += 12
  if (m[3] === 'a' && h === 12) h = 0
  return h * 60 + min
}

const byTime = (a: { start_time: string | null }, b: { start_time: string | null }) =>
  minutesOf(a.start_time) - minutesOf(b.start_time)

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

function friendlyDay(ds: string): string {
  const [y, m, d] = ds.split('-').map(Number)
  return new Date(y, m - 1, d).toLocaleDateString('en-US', { weekday: 'long', month: 'short', day: 'numeric' })
}

function shortDay(ds: string): string {
  const [y, m, d] = ds.split('-').map(Number)
  return new Date(y, m - 1, d).toLocaleDateString('en-US', { weekday: 'short' })
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

  const toggleRsvp = async (ev: TimelineEvent) => {
    const next = !ev.rsvpd
    Haptics.notificationAsync(next ? Haptics.NotificationFeedbackType.Success : Haptics.NotificationFeedbackType.Warning)
    setToday((l) => l.map((e) => e.id === ev.id ? { ...e, rsvpd: next, going_count: e.going_count + (next ? 1 : -1) } : e))
    try { next ? await api.rsvpEvent(ev.id) : await api.unRsvpEvent(ev.id) }
    catch { setToday((l) => l.map((e) => e.id === ev.id ? { ...e, rsvpd: !next, going_count: e.going_count + (next ? -1 : 1) } : e)) }
  }

  const dateLine = new Date().toLocaleDateString('en-US', { weekday: 'long', month: 'long', day: 'numeric' })
  const q = query.trim().toLowerCase()
  const keep = (text: string) => !q || text.toLowerCase().includes(q)

  // Today-at-a-glance (drives the hero ring): how many of today's gatherings you're joining.
  const total = today.length
  const going = today.filter((e) => e.rsvpd).length
  const heroProgress = total > 0 ? going / total : 0

  // Week strip + the selected day's list.
  const eventDates = new Set(upcoming.map((e) => e.event_date))
  const week = buildWeek(today0, eventDates)
  const isToday = selectedDate === today0
  const todayShown = today.filter((e) => keep(`${e.title} ${e.location ?? ''}`)).sort(byTime)
  const dayShown = upcoming.filter((e) => e.event_date === selectedDate && keep(`${e.title} ${e.location ?? ''}`)).sort(byTime)
  const shown = isToday ? todayShown : dayShown

  // When today has nothing, surface what's coming up this week instead of dead
  // space — pulls neighbors toward the next real gathering.
  const comingUp = [...upcoming]
    .filter((e) => e.event_date > today0 && keep(`${e.title} ${e.location ?? ''}`))
    .sort((a, b) => (a.event_date === b.event_date ? byTime(a, b) : a.event_date < b.event_date ? -1 : 1))
  const todayEmpty = isToday && todayShown.length === 0
  const showComingUp = todayEmpty && comingUp.length > 0
  const hideDaySection = todayEmpty && comingUp.length === 0 // hero already owns the clear-day message

  const dayLabel = showComingUp ? 'Coming up' : isToday ? 'Today' : friendlyDay(selectedDate)

  const enter = (i: number) => (reduce ? undefined : FadeInDown.delay(i * 80).duration(460))

  return (
    <SafeAreaView edges={['top']} style={{ flex: 1, backgroundColor: C.canvas }}>
      <ScrollView
        contentContainerStyle={{ paddingBottom: 120 }}
        refreshControl={<RefreshControl refreshing={refreshing} onRefresh={onRefresh} tintColor={C.ink3} />}
      >
        {/* Masthead */}
        <View style={{ paddingHorizontal: 20, paddingTop: 12, paddingBottom: 8, flexDirection: 'row', alignItems: 'flex-start', justifyContent: 'space-between' }}>
          <View>
            <View style={{ flexDirection: 'row', alignItems: 'center', gap: 11 }}>
              <View style={{ height: 32, width: 32, borderRadius: 9, backgroundColor: C.moss700, alignItems: 'center', justifyContent: 'center' }}>
                <Text style={{ fontFamily: F.displaySemi, fontSize: 19, color: C.paper }}>H</Text>
              </View>
              <Text style={{ fontFamily: F.sansBold, fontSize: 30, color: C.ink, letterSpacing: -0.7 }}>Joetown</Text>
            </View>
            <Text style={{ fontFamily: F.sans, fontSize: 13, color: C.ink3, marginTop: 6, marginLeft: 1 }}>{name ? `Hi ${name} · ${dateLine}` : dateLine}</Text>
          </View>
          <View style={{ flexDirection: 'row', gap: 10 }}>
            <Pressable
              onPress={() => { Haptics.selectionAsync(); setSearchOpen((o) => !o) }}
              style={({ pressed }) => ({
                width: 42, height: 42, borderRadius: 21, alignItems: 'center', justifyContent: 'center',
                backgroundColor: searchOpen ? C.moss700 : C.paper,
                borderWidth: 1, borderColor: searchOpen ? 'transparent' : HAIRLINE,
                opacity: pressed ? 0.7 : 1, ...CARD_SHADOW,
              })}
            >
              <SearchIcon color={searchOpen ? C.paper : C.ink} />
            </Pressable>
            <AccountMenu name={name} onSignOut={signOut} />
          </View>
        </View>

        <Animated.View entering={enter(0)}>
          <WeatherBar />
        </Animated.View>

        {/* Search field */}
        {searchOpen && (
          <View style={{ paddingHorizontal: 20, paddingTop: 12 }}>
            <TextInput
              autoFocus
              value={query}
              onChangeText={setQuery}
              placeholder="Search events…"
              placeholderTextColor={C.ink3}
              style={{ height: 46, borderRadius: 12, paddingHorizontal: 13, backgroundColor: C.paper, fontFamily: F.sans, fontSize: 15, color: C.ink, ...CARD_SHADOW }}
            />
          </View>
        )}

        {/* Today hero — double-bezel ring card */}
        <Animated.View entering={enter(1)} style={{ marginHorizontal: 20, marginTop: 16, borderRadius: 30, backgroundColor: C.paper200, padding: 5, ...CARD_SHADOW }}>
          <View style={{ borderRadius: 25, backgroundColor: C.paper, paddingVertical: 20, paddingHorizontal: 20, flexDirection: 'row', alignItems: 'center', gap: 14, borderWidth: 1, borderColor: 'rgba(255,255,255,0.7)' }}>
            {total > 0 ? (
              <>
                <View style={{ flex: 1, gap: 10 }}>
                  <Eyebrow>Today</Eyebrow>
                  <Text style={{ fontFamily: F.sansBold, fontSize: 21, color: C.ink, letterSpacing: -0.5, lineHeight: 25 }}>
                    {total} {total === 1 ? 'thing' : 'things'}{'\n'}happening
                  </Text>
                  <Text style={{ fontFamily: F.sansSemi, fontSize: 13.5, color: going > 0 ? GRAPH.greenDeep : C.ink3 }}>
                    {going > 0 ? `You're going to ${going}` : 'Tap one to join in'}
                  </Text>
                </View>
                <Ring size={104} stroke={11} progress={heroProgress} gradient={[GRAPH.green, GRAPH.amber]} id="today">
                  <View style={{ alignItems: 'center' }}>
                    <Text style={{ fontFamily: F.monoMed, fontSize: 24, color: C.ink, letterSpacing: -0.5 }}>{going}</Text>
                    <Text style={{ fontFamily: F.mono, fontSize: 11, color: C.ink3, marginTop: -1 }}>of {total}</Text>
                  </View>
                </Ring>
              </>
            ) : (
              <View style={{ flex: 1, gap: 10 }}>
                <Eyebrow>Today</Eyebrow>
                <Text style={{ fontFamily: F.sansBold, fontSize: 23, color: C.ink, letterSpacing: -0.5 }}>A clear day in St. Joe</Text>
                <Text style={{ fontFamily: F.sansSemi, fontSize: 13.5, color: C.ink3, lineHeight: 20 }}>
                  Nothing on the calendar yet. Be the one who starts something — a walk, a coffee, a hello.
                </Text>
                <Pressable onPress={() => { Haptics.selectionAsync(); router.push('/(tabs)/add') }}
                  style={({ pressed }) => ({ flexDirection: 'row', alignItems: 'center', gap: 7, alignSelf: 'flex-start', paddingLeft: 16, paddingRight: 7, paddingVertical: 7, borderRadius: 22, backgroundColor: C.ink, opacity: pressed ? 0.9 : 1, marginTop: 4 })}>
                  <Text style={{ fontFamily: F.sansSemi, fontSize: 13, color: C.paper }}>Add an event</Text>
                  <View style={{ width: 24, height: 24, borderRadius: 12, backgroundColor: 'rgba(255,255,255,0.18)', alignItems: 'center', justifyContent: 'center' }}>
                    <PlusIcon size={13} color={C.paper} />
                  </View>
                </Pressable>
              </View>
            )}
          </View>
        </Animated.View>

        {/* Week strip */}
        <Animated.View entering={enter(2)} style={{ marginTop: 24 }}>
          <WeekStrip days={week} selected={selectedDate} onSelect={setSelectedDate} />
        </Animated.View>

        {/* Selected day — horizontal schedule strip. Hidden when today is clear
            and nothing is coming up (the hero already says so). */}
        {!hideDaySection && (
          <Animated.View entering={enter(3)} style={{ paddingTop: 28, paddingBottom: 4 }}>
            <Text style={{ fontFamily: F.sansBold, fontSize: 24, color: C.ink, letterSpacing: -0.6, paddingHorizontal: 20 }}>
              {dayLabel}
            </Text>

            {loading ? (
              <ActivityIndicator color={C.ink3} style={{ marginTop: 18, alignSelf: 'flex-start', marginLeft: 20 }} />
            ) : (
              <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={{ gap: 12, paddingHorizontal: 20, paddingTop: 14, paddingBottom: 10 }}>
                {showComingUp ? (
                  comingUp.slice(0, 6).map((e) => (
                    <ScheduleCard key={e.id} time={`${shortDay(e.event_date)} · ${e.start_time || 'all day'}`} title={e.title} location={e.location} meta={`${e.going_count} going`} accent onPress={() => { Haptics.selectionAsync(); setSelectedDate(e.event_date) }} />
                  ))
                ) : shown.length === 0 ? (
                  <EmptyCard text="Nothing scheduled this day." />
                ) : isToday ? (
                  todayShown.map((e) => (
                    <ScheduleCard key={e.id} time={e.start_time || 'All day'} title={e.title} location={e.location} meta={`${e.going_count} going`} accent onPress={() => toggleRsvp(e)} rsvpd={e.rsvpd} />
                  ))
                ) : (
                  dayShown.map((e) => (
                    <ScheduleCard key={e.id} time={e.start_time || 'All day'} title={e.title} location={e.location} meta={`${e.going_count} going`} accent />
                  ))
                )}
                {/* Add event card — button-in-button affordance */}
                <Pressable onPress={() => { Haptics.selectionAsync(); router.push('/(tabs)/add') }}
                  style={({ pressed }) => ({ width: 124, alignItems: 'center', justifyContent: 'center', gap: 10, borderRadius: 20, backgroundColor: C.paper, borderWidth: 1, borderColor: HAIRLINE, transform: [{ scale: pressed ? 0.97 : 1 }], ...CARD_SHADOW })}>
                  <View style={{ width: 36, height: 36, borderRadius: 18, backgroundColor: C.moss700, alignItems: 'center', justifyContent: 'center' }}>
                    <PlusIcon color={C.paper} />
                  </View>
                  <Text style={{ fontFamily: F.sansSemi, fontSize: 12.5, color: C.ink2 }}>Add event</Text>
                </Pressable>
              </ScrollView>
            )}
          </Animated.View>
        )}

        {/* Around town carousel */}
        <Animated.View entering={enter(4)}>
          <AroundTown />
        </Animated.View>

        {/* Daily quest */}
        <Animated.View entering={enter(5)}>
          <QuestSection />
        </Animated.View>
      </ScrollView>
    </SafeAreaView>
  )
}

function Eyebrow({ children }: { children: string }) {
  return (
    <View style={{ alignSelf: 'flex-start', paddingHorizontal: 10, paddingVertical: 4, borderRadius: 20, backgroundColor: 'rgba(0,0,0,0.05)' }}>
      <Text style={{ fontFamily: F.sansMed, fontSize: 10, letterSpacing: 1.8, color: C.ink2, textTransform: 'uppercase' }}>{children}</Text>
    </View>
  )
}

function ScheduleCard({ time, title, location, meta, accent, onPress, rsvpd }: {
  time: string; title: string; location?: string | null; meta?: string; accent?: boolean; onPress?: () => void; rsvpd?: boolean
}) {
  return (
    <Pressable onPress={onPress} style={({ pressed }) => ({ width: 174, padding: 15, borderRadius: 20, backgroundColor: C.paper, borderWidth: 1, borderColor: HAIRLINE, gap: 7, transform: [{ scale: pressed ? 0.97 : 1 }], ...CARD_SHADOW })}>
      <Text style={{ fontFamily: F.monoMed, fontSize: 12, color: accent ? GRAPH.greenDeep : C.ink2, letterSpacing: 0.2 }}>{time}</Text>
      <Text numberOfLines={2} style={{ fontFamily: F.sansSemi, fontSize: 14.5, color: C.ink, lineHeight: 18.5 }}>{title}</Text>
      {!!location && <Text numberOfLines={1} style={{ fontFamily: F.sans, fontSize: 12, color: C.ink2 }}>{location}</Text>}
      <View style={{ flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', marginTop: 2 }}>
        {!!meta && <Text style={{ fontFamily: F.mono, fontSize: 11, color: C.ink3 }}>{meta}</Text>}
        {onPress && (rsvpd ? (
          <View style={{ flexDirection: 'row', alignItems: 'center', gap: 4 }}>
            <CheckIcon size={11} color={GRAPH.greenDeep} />
            <Text style={{ fontFamily: F.sansSemi, fontSize: 11, color: GRAPH.greenDeep }}>Going</Text>
          </View>
        ) : (
          <Text style={{ fontFamily: F.sansMed, fontSize: 11, color: C.ink3 }}>Join</Text>
        ))}
      </View>
    </Pressable>
  )
}

function EmptyCard({ text }: { text: string }) {
  return (
    <View style={{ justifyContent: 'center', paddingHorizontal: 18, paddingVertical: 16, borderRadius: 18, borderWidth: 1.5, borderStyle: 'dashed', borderColor: 'rgba(0,0,0,0.13)' }}>
      <Text style={{ fontFamily: F.sans, fontSize: 13, color: C.ink2 }}>{text}</Text>
    </View>
  )
}
