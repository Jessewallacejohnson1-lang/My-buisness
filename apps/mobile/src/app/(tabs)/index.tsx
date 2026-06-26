import { useCallback, useEffect, useState } from 'react'
import { ActivityIndicator, Pressable, RefreshControl, ScrollView, Text, TextInput, View } from 'react-native'
import { SafeAreaView } from 'react-native-safe-area-context'
import { BlurView } from 'expo-blur'
import { useRouter } from 'expo-router'
import * as Haptics from 'expo-haptics'
import { firstNameFromEmail, type TimelineEvent, type WeekEvent } from '@hygge/core'
import { api } from '../../lib/api'
import { useAuth } from '../../lib/auth'
import { WeatherBar } from '../../components/WeatherBar'
import { AroundTown } from '../../components/AroundTown'
import { AccountMenu } from '../../components/AccountMenu'
import { QuestSection } from '../../components/QuestSection'
import { SearchIcon, ScopeIcon, PlusIcon } from '../../components/icons'
import { C, F, HAIRLINE, COLLECTIONS, matchesKw as kwMatch } from '../../theme'

type Scope = 'today' | 'week' | 'going'
const SCOPES: { id: Scope; label: string }[] = [
  { id: 'today', label: 'Today' },
  { id: 'week', label: 'This week' },
  { id: 'going', label: 'Going' },
]

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

export default function Home() {
  const router = useRouter()
  const { signOut } = useAuth()
  const [today, setToday] = useState<TimelineEvent[]>([])
  const [week, setWeek] = useState<WeekEvent[]>([])
  const [name, setName] = useState<string | null>(null)
  const [scope, setScope] = useState<Scope>('today')
  const [collection, setCollection] = useState<number | null>(null)
  const [query, setQuery] = useState('')
  const [searchOpen, setSearchOpen] = useState(false)
  const [loading, setLoading] = useState(true)
  const [refreshing, setRefreshing] = useState(false)

  const load = useCallback(async () => {
    const [t, w, u] = await Promise.all([api.getTodayEvents(), api.getWeekEvents(), api.getCurrentUser()])
    setToday(t); setWeek(w); setName(firstNameFromEmail(u?.email))
  }, [])

  useEffect(() => { load().finally(() => setLoading(false)) }, [load])
  const onRefresh = async () => { setRefreshing(true); await load(); setRefreshing(false) }

  const toggleRsvp = async (ev: TimelineEvent) => {
    Haptics.selectionAsync()
    const next = !ev.rsvpd
    setToday((l) => l.map((e) => e.id === ev.id ? { ...e, rsvpd: next, going_count: e.going_count + (next ? 1 : -1) } : e))
    try { next ? await api.rsvpEvent(ev.id) : await api.unRsvpEvent(ev.id) }
    catch { setToday((l) => l.map((e) => e.id === ev.id ? { ...e, rsvpd: !next, going_count: e.going_count + (next ? -1 : 1) } : e)) }
  }

  const selectCollection = (i: number) => { setCollection((c) => (c === i ? null : i)) }

  const dateLine = new Date().toLocaleDateString('en-US', { weekday: 'long', month: 'long', day: 'numeric' })
  const activeKw = collection !== null ? COLLECTIONS[collection].kw : null
  const q = query.trim().toLowerCase()
  const keep = (text: string) => kwMatch(text, activeKw) && (!q || text.toLowerCase().includes(q))

  const todayList = today.filter((e) => keep(`${e.title} ${e.location ?? ''}`)).sort((a, b) => minutesOf(a.start_time) - minutesOf(b.start_time))
  const goingList = todayList.filter((e) => e.rsvpd)
  const weekList = week.filter((e) => keep(e.title))

  const stripEmpty = scope === 'week' ? 'Nothing on the calendar this week.' : scope === 'going' ? "You haven't joined anything yet." : 'Nothing scheduled — a clear day.'

  return (
    <SafeAreaView edges={['top']} style={{ flex: 1, backgroundColor: C.paper }}>
      <ScrollView
        contentContainerStyle={{ paddingBottom: 120 }}
        refreshControl={<RefreshControl refreshing={refreshing} onRefresh={onRefresh} tintColor={C.ink3} />}
      >
        {/* Masthead */}
        <View style={{ paddingHorizontal: 20, paddingTop: 8, paddingBottom: 4, flexDirection: 'row', alignItems: 'flex-start', justifyContent: 'space-between' }}>
          <View>
            <View style={{ flexDirection: 'row', alignItems: 'center', gap: 11 }}>
              <View style={{ height: 32, width: 32, borderRadius: 9, backgroundColor: C.moss700, alignItems: 'center', justifyContent: 'center' }}>
                <Text style={{ fontFamily: F.displaySemi, fontSize: 19, color: C.paper }}>H</Text>
              </View>
              <Text style={{ fontFamily: F.sansBold, fontSize: 30, color: C.ink, letterSpacing: -0.7 }}>Joetown</Text>
            </View>
            <Text style={{ fontFamily: F.sans, fontSize: 13, color: C.ink3, marginTop: 8, marginLeft: 1 }}>{dateLine}</Text>
          </View>
          <View style={{ flexDirection: 'row', gap: 10 }}>
            <Pressable
              onPress={() => { Haptics.selectionAsync(); setSearchOpen((o) => !o) }}
              style={({ pressed }) => ({ width: 44, height: 44, borderRadius: 22, overflow: 'hidden', borderWidth: 1, borderColor: 'rgba(255,255,255,0.55)', opacity: pressed ? 0.85 : 1 })}
            >
              <BlurView intensity={28} tint="light" style={{ flex: 1, alignItems: 'center', justifyContent: 'center', backgroundColor: searchOpen ? 'rgba(45,69,48,0.16)' : 'rgba(255,255,255,0.42)' }}>
                <SearchIcon />
              </BlurView>
            </Pressable>
            <AccountMenu name={name} onSignOut={signOut} />
          </View>
        </View>

        <View style={{ height: 12 }} />
        <WeatherBar />

        {/* Search field */}
        {searchOpen && (
          <View style={{ paddingHorizontal: 20, paddingTop: 12 }}>
            <TextInput
              autoFocus
              value={query}
              onChangeText={setQuery}
              placeholder="Search events…"
              placeholderTextColor={C.ink3}
              style={{ height: 46, borderRadius: 10, paddingHorizontal: 13, backgroundColor: C.paper100, borderWidth: 1, borderColor: HAIRLINE, fontFamily: F.sans, fontSize: 15, color: C.ink }}
            />
          </View>
        )}

        {/* Scope pills */}
        <View style={{ flexDirection: 'row', gap: 8, paddingHorizontal: 20, paddingTop: 14, paddingBottom: 2 }}>
          {SCOPES.map((s) => {
            const active = s.id === scope
            return (
              <Pressable key={s.id} onPress={() => { Haptics.selectionAsync(); setScope(s.id) }}
                style={{ flexDirection: 'row', alignItems: 'center', gap: 6, paddingHorizontal: 15, paddingVertical: 8, borderRadius: 20, borderWidth: active ? 0 : 1, borderColor: HAIRLINE, backgroundColor: active ? C.ink : 'transparent' }}>
                <ScopeIcon id={s.id} active={active} />
                <Text style={{ fontFamily: active ? F.sansSemi : F.sansMed, fontSize: 13.5, color: active ? C.paper : C.ink2 }}>{s.label}</Text>
              </Pressable>
            )
          })}
        </View>

        {/* Your day — horizontal schedule strip */}
        <View style={{ paddingTop: 18, paddingBottom: 4 }}>
          <View style={{ flexDirection: 'row', alignItems: 'center', gap: 8, paddingHorizontal: 20 }}>
            <Text style={{ fontFamily: F.sansBold, fontSize: 20, color: C.ink, letterSpacing: -0.3 }}>
              {scope === 'today' ? 'Your day' : scope === 'week' ? 'This week' : "You're going"}
            </Text>
            {collection !== null && (
              <Pressable onPress={() => { Haptics.selectionAsync(); setCollection(null) }}
                style={{ flexDirection: 'row', alignItems: 'center', gap: 5, paddingHorizontal: 10, paddingVertical: 3, borderRadius: 20, borderWidth: 1, borderColor: HAIRLINE, backgroundColor: C.paper100 }}>
                <Text style={{ fontFamily: F.sans, fontSize: 12, color: C.ink2 }}>{COLLECTIONS[collection].name}</Text>
                <Text style={{ fontFamily: F.sans, fontSize: 13, color: C.ink2 }}>✕</Text>
              </Pressable>
            )}
          </View>

          {loading ? (
            <ActivityIndicator color={C.ink3} style={{ marginTop: 18, alignSelf: 'flex-start', marginLeft: 20 }} />
          ) : (
            <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={{ gap: 12, paddingHorizontal: 20, paddingTop: 14, paddingBottom: 6 }}>
              {scope === 'week' ? (
                weekList.length === 0 ? <EmptyCard text={stripEmpty} />
                  : weekList.map((e) => <ScheduleCard key={e.id} time={e.date_label} title={e.title} meta={`${e.going_count} going`} />)
              ) : (
                (scope === 'going' ? goingList : todayList).length === 0 ? <EmptyCard text={stripEmpty} />
                  : (scope === 'going' ? goingList : todayList).map((e) => (
                    <ScheduleCard key={e.id} time={e.start_time || 'All day'} title={e.title} location={e.location} meta={`${e.going_count} going`} accent onPress={() => toggleRsvp(e)} rsvpd={e.rsvpd} />
                  ))
              )}
              {/* Add event card */}
              <Pressable onPress={() => { Haptics.selectionAsync(); router.push('/(tabs)/add') }}
                style={{ width: 116, alignItems: 'center', justifyContent: 'center', gap: 8, borderRadius: 16, borderWidth: 1.5, borderColor: 'rgba(0,0,0,0.13)', borderStyle: 'dashed' }}>
                <View style={{ width: 30, height: 30, borderRadius: 9, backgroundColor: C.paper100, alignItems: 'center', justifyContent: 'center' }}>
                  <PlusIcon />
                </View>
                <Text style={{ fontFamily: F.sansMed, fontSize: 12, color: C.ink2 }}>Add event</Text>
              </Pressable>
            </ScrollView>
          )}
        </View>

        {/* Around town carousel */}
        <AroundTown selected={collection} onSelect={selectCollection} />

        {/* Daily quest */}
        <QuestSection />
      </ScrollView>
    </SafeAreaView>
  )
}

function ScheduleCard({ time, title, location, meta, accent, onPress, rsvpd }: {
  time: string; title: string; location?: string | null; meta?: string; accent?: boolean; onPress?: () => void; rsvpd?: boolean
}) {
  return (
    <Pressable onPress={onPress} style={{ width: 170, padding: 14, borderRadius: 16, backgroundColor: C.paper100, borderWidth: 1, borderColor: HAIRLINE, gap: 7 }}>
      <Text style={{ fontFamily: F.monoMed, fontSize: 12, color: accent ? C.moss700 : C.ink2, letterSpacing: 0.2 }}>{time}</Text>
      <Text numberOfLines={2} style={{ fontFamily: F.sansSemi, fontSize: 14, color: C.ink, lineHeight: 18 }}>{title}</Text>
      {!!location && <Text numberOfLines={1} style={{ fontFamily: F.sans, fontSize: 12, color: C.ink2 }}>{location}</Text>}
      <View style={{ flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', marginTop: 2 }}>
        {!!meta && <Text style={{ fontFamily: F.mono, fontSize: 11, color: C.ink3 }}>{meta}</Text>}
        {onPress && <Text style={{ fontFamily: F.sansMed, fontSize: 11, color: rsvpd ? C.moss700 : C.ink3 }}>{rsvpd ? '✓ Going' : 'Join'}</Text>}
      </View>
    </Pressable>
  )
}

function EmptyCard({ text }: { text: string }) {
  return (
    <View style={{ justifyContent: 'center', paddingHorizontal: 18, paddingVertical: 16, borderRadius: 16, borderWidth: 1.5, borderStyle: 'dashed', borderColor: 'rgba(0,0,0,0.13)' }}>
      <Text style={{ fontFamily: F.sans, fontSize: 13, color: C.ink2 }}>{text}</Text>
    </View>
  )
}
