import { createElement, useCallback, useEffect, useState } from 'react'
import { Modal, Platform, Pressable, RefreshControl, ScrollView, Text, TextInput, View } from 'react-native'
import { SafeAreaView } from 'react-native-safe-area-context'
import * as Haptics from 'expo-haptics'
import { Image } from 'expo-image'
import { isAdminEmail, localDate, type ClubView, type ClubRow, type NewEventInput, type Trail, type PendingPost, type UpcomingEvent } from '@hygge/core'
import { api } from '../../lib/api'
import { supabase } from '../../lib/supabase'
import { getInterests, matchesInterests } from '../../lib/interests'
import { SearchIcon, PlusIcon, PinIcon, EventIcon, ClubIcon, TrailIcon, SunArcIcon } from '../../components/icons'
import { ActivityTile, ActivityTileSkeleton } from '../../components/ActivityTile'
import { BottomSheet } from '../../components/ui/bottom-sheet'
import { openInMaps, copyAddress } from '../../lib/maps'
import { ScreenBadge } from '../../components/ScreenBadge'
import { C, F, HAIRLINE } from '../../theme'

// Native date/time picker — required only off-web so the web bundle never
// evaluates the native module (we render an HTML <input> on web instead).
const RNDateTimePicker: any = Platform.OS === 'web' ? null : require('@react-native-community/datetimepicker').default

type FilterId = 'all' | 'events' | 'clubs' | 'trails'
const FILTERS: { id: FilterId; label: string }[] = [
  { id: 'all', label: 'All' },
  { id: 'events', label: 'Events' },
  { id: 'clubs', label: 'Clubs' },
  { id: 'trails', label: 'Trails' },
]
/** First number found in the free-text length, e.g. "2.3–5.9 mi" → 2.3. Unparseable sorts last. */
function parseMiles(s: string | null): number {
  if (!s) return Infinity
  const m = s.match(/(\d+(?:\.\d+)?)/)
  return m ? parseFloat(m[1]) : Infinity
}
function formatEventDate(ymd: string): string {
  const [y, m, d] = ymd.split('-').map(Number)
  return new Date(y, m - 1, d).toLocaleDateString('en-US', { weekday: 'short', month: 'short', day: 'numeric' })
}

export default function Activities() {
  const [clubs, setClubs] = useState<ClubView[]>([])
  const [trails, setTrails] = useState<Trail[]>([])
  const [pendingPosts, setPendingPosts] = useState<PendingPost[]>([])
  const [pendingClubs, setPendingClubs] = useState<ClubRow[]>([])
  const [query, setQuery] = useState('')
  const [loading, setLoading] = useState(true)
  const [refreshing, setRefreshing] = useState(false)
  const [selected, setSelected] = useState<ClubView | null>(null)
  const [selectedTrail, setSelectedTrail] = useState<Trail | null>(null)
  const [selectedEvent, setSelectedEvent] = useState<UpcomingEvent | null>(null)
  const [isAdmin, setIsAdmin] = useState(false)
  const [interests, setInterestsState] = useState<string[]>([])
  const [events, setEvents] = useState<UpcomingEvent[]>([])
  const [filter, setFilter] = useState<FilterId>('all')

  const pickFilter = (f: FilterId) => { Haptics.selectionAsync(); setFilter(f) }

  const load = useCallback(async (admin: boolean) => {
    const [list, trailList, eventList] = await Promise.all([api.getApprovedClubs(), api.getTrails(), api.getUpcomingEvents()])
    setClubs(list)
    setTrails(trailList)
    setEvents(eventList)
    if (admin) {
      const [pp, pc] = await Promise.all([api.getPendingPosts(), api.getPendingClubs()])
      setPendingPosts(pp)
      setPendingClubs(pc)
    }
  }, [])

  useEffect(() => {
    (async () => {
      const user = await api.getCurrentUser()
      const admin = isAdminEmail(user?.email)
      setIsAdmin(admin)
      setInterestsState(await getInterests())
      await load(admin)
      setLoading(false)
    })()
  }, [load])

  const onRefresh = async () => {
    setRefreshing(true)
    await load(isAdmin)
    setRefreshing(false)
  }

  const toggleJoin = async (club: ClubView) => {
    Haptics.selectionAsync()
    const next = !club.joined
    const apply = (c: ClubView): ClubView => c.id === club.id ? { ...c, joined: next, member_count: c.member_count + (next ? 1 : -1) } : c
    setClubs((l) => l.map(apply))
    setSelected((s) => (s && s.id === club.id ? apply(s) : s))
    try { next ? await api.joinClub(club.id) : await api.leaveClub(club.id) }
    catch {
      const revert = (c: ClubView): ClubView => c.id === club.id ? { ...c, joined: !next, member_count: c.member_count + (next ? -1 : 1) } : c
      setClubs((l) => l.map(revert))
      setSelected((s) => (s && s.id === club.id ? revert(s) : s))
    }
  }

  const approvePost = async (id: string) => {
    Haptics.selectionAsync()
    await api.approvePost(id)
    setPendingPosts((l) => l.filter((p) => p.id !== id))
    const [trailList] = await Promise.all([api.getTrails()])
    setTrails(trailList)
  }

  const rejectPost = async (id: string) => {
    Haptics.selectionAsync()
    await api.rejectPost(id)
    setPendingPosts((l) => l.filter((p) => p.id !== id))
  }

  const approveClub = async (id: string) => {
    Haptics.selectionAsync()
    await api.setClubStatus(id, 'approved')
    setPendingClubs((l) => l.filter((c) => c.id !== id))
    setClubs(await api.getApprovedClubs())
  }

  const rejectClub = async (id: string) => {
    Haptics.selectionAsync()
    await api.setClubStatus(id, 'rejected')
    setPendingClubs((l) => l.filter((c) => c.id !== id))
  }

  const q = query.trim().toLowerCase()
  const matchQ = (s: string) => !q || s.toLowerCase().includes(q)

  const clubsF = clubs.filter((c) => matchQ(`${c.name} ${c.host ?? ''} ${c.vibe ?? ''} ${c.schedule ?? ''} ${c.location ?? ''} ${c.description ?? ''}`))
  const trailsF = trails.filter((t) => matchQ(`${t.title} ${t.location ?? ''} ${t.length ?? ''} ${t.difficulty ?? ''} ${t.description ?? ''}`))
  const eventsF = events.filter((e) => matchQ(`${e.title} ${e.location ?? ''}`))

  const matchClub = (c: ClubView) => matchesInterests(`${c.name} ${c.host ?? ''} ${c.vibe ?? ''} ${c.schedule ?? ''} ${c.description ?? ''}`, interests)
  const matchTrail = (t: Trail) => matchesInterests(`${t.title} ${t.location ?? ''} ${t.description ?? ''}`, interests, true)
  // Smart per-filter defaults (no visible sort control): events by date, clubs
  // A–Z, trails by distance. In the All view, quietly float the viewer's
  // interest-matches to the top of the clubs & trails groups — personalization
  // without an algorithmic-feed label.
  const flt = filter === 'all'
  const shownEvents = [...eventsF].sort((a, b) => a.event_date.localeCompare(b.event_date))
  const shownClubs = [...clubsF].sort((a, b) => (flt ? (matchClub(b) ? 1 : 0) - (matchClub(a) ? 1 : 0) : 0) || a.name.localeCompare(b.name))
  const shownTrails = [...trailsF].sort((a, b) => (flt ? (matchTrail(b) ? 1 : 0) - (matchTrail(a) ? 1 : 0) : 0) || parseMiles(a.length) - parseMiles(b.length))
  const visibleCount = filter === 'events' ? shownEvents.length
    : filter === 'clubs' ? shownClubs.length
    : filter === 'trails' ? shownTrails.length
    : shownEvents.length + shownClubs.length + shownTrails.length

  const hasPending = isAdmin && (pendingPosts.length > 0 || pendingClubs.length > 0)

  return (
    <SafeAreaView edges={['top']} style={{ flex: 1, backgroundColor: C.paper }}>
      <ScreenBadge />
      <ScrollView contentContainerStyle={{ paddingBottom: 130 }} keyboardShouldPersistTaps="handled"
        refreshControl={<RefreshControl refreshing={refreshing} onRefresh={onRefresh} tintColor={C.ink3} />}>
        <View style={{ paddingHorizontal: 20, paddingTop: 14, paddingBottom: 16, borderBottomWidth: 1, borderBottomColor: HAIRLINE }}>
          <Text style={{ fontWeight: F.display, fontSize: 26, color: C.ink }}>Activities</Text>
          <Text style={{ fontWeight: F.sans, fontSize: 14, color: C.ink2, marginTop: 3, marginBottom: 16 }}>Clubs, events, and trails around St. Joe.</Text>

          {/* Search */}
          <View style={{ flexDirection: 'row', alignItems: 'center', gap: 10, height: 48, borderRadius: 12, paddingHorizontal: 14, backgroundColor: C.paper100, borderWidth: 1, borderColor: HAIRLINE }}>
            <SearchIcon color={C.ink3} />
            <TextInput value={query} onChangeText={setQuery} placeholder="Search St. Joe…" placeholderTextColor={C.ink3}
              style={{ flex: 1, fontWeight: F.sans, fontSize: 15, color: C.ink }} autoCapitalize="none" />
          </View>

          {/* Filter pills */}
          <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={{ gap: 8, paddingTop: 14 }}>
            {FILTERS.map((f) => {
              const active = f.id === filter
              return (
                <Pressable key={f.id} onPress={() => pickFilter(f.id)} hitSlop={6}
                  accessibilityRole="button" accessibilityState={{ selected: active }}
                  style={{ minHeight: 44, paddingHorizontal: 16, justifyContent: 'center', borderRadius: 22, borderWidth: active ? 0 : 1, borderColor: HAIRLINE, backgroundColor: active ? C.ink : 'transparent' }}>
                  <Text style={{ fontWeight: active ? F.sansSemi : F.sansMed, fontSize: 13.5, color: active ? C.paper : C.ink2 }}>{f.label}</Text>
                </Pressable>
              )
            })}
          </ScrollView>
        </View>

        {/* Admin: Waiting for review */}
        {hasPending && (
          <View style={{ marginHorizontal: 20, marginTop: 22, padding: 14, borderRadius: 14, backgroundColor: C.paper100, borderWidth: 1, borderColor: HAIRLINE }}>
            <Text style={{ fontWeight: F.sansMed, fontSize: 11, color: C.ink3, letterSpacing: 1.2, textTransform: 'uppercase', marginBottom: 12 }}>Waiting for review · admin</Text>

            {pendingPosts.map((p) => (
              <View key={p.id} style={{ paddingVertical: 12, borderTopWidth: 1, borderTopColor: HAIRLINE }}>
                <Text style={{ fontWeight: F.sansBold, fontSize: 14, color: C.ink }}>{p.title}</Text>
                <Text style={{ fontWeight: F.mono, fontSize: 11, color: C.ink3, marginTop: 3 }}>
                  {p.kind} {p.location ? `· ${p.location}` : ''}
                </Text>
                <View style={{ flexDirection: 'row', gap: 10, marginTop: 10 }}>
                  <Pressable onPress={() => approvePost(p.id)}
                    style={({ pressed }) => ({ flex: 1, paddingVertical: 9, borderRadius: 8, backgroundColor: C.moss700, alignItems: 'center', opacity: pressed ? 0.85 : 1 })}>
                    <Text style={{ fontWeight: F.sansSemi, fontSize: 13, color: C.paper }}>Approve</Text>
                  </Pressable>
                  <Pressable onPress={() => rejectPost(p.id)}
                    style={({ pressed }) => ({ flex: 1, paddingVertical: 9, borderRadius: 8, borderWidth: 1.5, borderColor: C.clay700, alignItems: 'center', opacity: pressed ? 0.85 : 1 })}>
                    <Text style={{ fontWeight: F.sansSemi, fontSize: 13, color: C.clay700 }}>Decline</Text>
                  </Pressable>
                </View>
              </View>
            ))}

            {pendingClubs.map((c) => (
              <View key={c.id} style={{ paddingVertical: 12, borderTopWidth: 1, borderTopColor: HAIRLINE }}>
                <Text style={{ fontWeight: F.sansBold, fontSize: 14, color: C.ink }}>{c.name}</Text>
                {!!c.host && <Text style={{ fontWeight: F.sans, fontSize: 12, color: C.ink2, marginTop: 2 }}>with {c.host}</Text>}
                <Text style={{ fontWeight: F.mono, fontSize: 11, color: C.ink3, marginTop: 3 }}>club</Text>
                <View style={{ flexDirection: 'row', gap: 10, marginTop: 10 }}>
                  <Pressable onPress={() => approveClub(c.id)}
                    style={({ pressed }) => ({ flex: 1, paddingVertical: 9, borderRadius: 8, backgroundColor: C.moss700, alignItems: 'center', opacity: pressed ? 0.85 : 1 })}>
                    <Text style={{ fontWeight: F.sansSemi, fontSize: 13, color: C.paper }}>Approve</Text>
                  </Pressable>
                  <Pressable onPress={() => rejectClub(c.id)}
                    style={({ pressed }) => ({ flex: 1, paddingVertical: 9, borderRadius: 8, borderWidth: 1.5, borderColor: C.clay700, alignItems: 'center', opacity: pressed ? 0.85 : 1 })}>
                    <Text style={{ fontWeight: F.sansSemi, fontSize: 13, color: C.clay700 }}>Decline</Text>
                  </Pressable>
                </View>
              </View>
            ))}
          </View>
        )}

        {/* Loading: calm skeleton tiles at the true tile silhouette (no spinner, no shimmer). */}
        {loading && (
          <View style={{ paddingHorizontal: 20, paddingTop: 22, gap: 14 }}>
            {[0, 1, 2].map((i) => (
              <ActivityTileSkeleton key={i} />
            ))}
          </View>
        )}

        {/* Events */}
        {!loading && (filter === 'all' || filter === 'events') && shownEvents.length > 0 && (
          <View style={{ paddingHorizontal: 20, paddingTop: 22, gap: 14 }}>
            {shownEvents.map((e, i) => (
              <ActivityTile key={e.id} kind="event" title={e.title} imageUrl={e.image_url} index={i}
                onPress={() => { Haptics.selectionAsync(); setSelectedEvent(e) }} />
            ))}
          </View>
        )}

        {/* Clubs — Join floats on the tile as a SIBLING of the open-details face
            (never nested), so edge taps on Join don't fall through to the sheet. */}
        {!loading && (filter === 'all' || filter === 'clubs') && shownClubs.length > 0 && (
          <View style={{ paddingHorizontal: 20, paddingTop: 22, gap: 14 }}>
            {shownClubs.map((c, i) => (
              <ActivityTile key={c.id} kind="club" title={c.name} index={i}
                onPress={() => { Haptics.selectionAsync(); setSelected(c) }}
                join={{ joined: c.joined, onToggle: () => toggleJoin(c) }} />
            ))}
          </View>
        )}

        {/* Trails */}
        {!loading && (filter === 'all' || filter === 'trails') && shownTrails.length > 0 && (
          <View style={{ paddingHorizontal: 20, paddingTop: 22, gap: 14 }}>
            {shownTrails.map((t, i) => (
              <ActivityTile key={t.id} kind="trail" title={t.title} imageUrl={t.image_url} index={i}
                onPress={() => { Haptics.selectionAsync(); setSelectedTrail(t) }} />
            ))}
          </View>
        )}

        {/* Empty — a calm centered state, not a form-placeholder box. */}
        {!loading && visibleCount === 0 && (
          <View style={{ alignItems: 'center', paddingHorizontal: 32, paddingVertical: 48, gap: 12 }}>
            <View style={{ opacity: 0.4 }}>
              {q || filter === 'all' ? <SunArcIcon size={30} color={C.ink3} />
                : filter === 'events' ? <EventIcon size={30} color={C.ink3} />
                : filter === 'clubs' ? <ClubIcon size={30} color={C.ink3} />
                : <TrailIcon size={30} color={C.ink3} />}
            </View>
            <Text style={{ fontWeight: F.sans, fontSize: 15, lineHeight: 21, color: C.ink2, textAlign: 'center' }}>
              {q ? `Nothing matches "${query.trim()}".`
                : filter === 'events' ? 'No upcoming events yet — post one from the + tab.'
                : filter === 'clubs' ? 'No clubs yet — start one from the + tab.'
                : filter === 'trails' ? 'No trails yet.'
                : 'Nothing here yet — add something from the + tab.'}
            </Text>
          </View>
        )}
      </ScrollView>

      <ClubDetail club={selected} onClose={() => setSelected(null)} onToggleJoin={toggleJoin} />
      <TrailDetail trail={selectedTrail} onClose={() => setSelectedTrail(null)} />
      <EventDetail event={selectedEvent} onClose={() => setSelectedEvent(null)} />
    </SafeAreaView>
  )
}

/** Slide-up detail sheet for a single trail. */
function TrailDetail({ trail, onClose }: { trail: Trail | null; onClose: () => void }) {
  const meta = trail ? [trail.length, trail.difficulty].filter(Boolean).join(' · ') : ''
  return (
    <BottomSheet open={!!trail} onClose={onClose} maxHeight="88%">
      {trail && (
        <ScrollView contentContainerStyle={{ paddingHorizontal: 22, paddingTop: 8, paddingBottom: 36 }} showsVerticalScrollIndicator={false}>
          {!!trail.image_url && (
            <Image source={{ uri: trail.image_url }} style={{ width: '100%', height: 180, borderRadius: 14, marginBottom: 14 }} contentFit="cover" />
          )}
          <Text style={{ fontWeight: F.display, fontSize: 26, color: C.ink, letterSpacing: -0.4, paddingRight: 40 }}>{trail.title}</Text>

          {!!meta && <Text style={{ fontWeight: F.mono, fontSize: 13, color: C.ink3, marginTop: 8 }}>{meta}</Text>}
          {!!trail.description && (
            <Text style={{ fontWeight: F.sans, fontSize: 15, color: C.ink2, lineHeight: 22, marginTop: 14 }}>{trail.description}</Text>
          )}

          {!!trail.location && (
            <View style={{ marginTop: 18, flexDirection: 'row', alignItems: 'baseline', gap: 12 }}>
              <Text style={{ width: 78, fontWeight: F.sansMed, fontSize: 11, color: C.ink3, letterSpacing: 1, textTransform: 'uppercase' }}>Where</Text>
              <Pressable onPress={() => openInMaps(trail.location!)} onLongPress={() => copyAddress(trail.location!)}
                style={{ flex: 1, flexDirection: 'row', alignItems: 'center', gap: 5 }}>
                <PinIcon size={14} color={C.sky600} />
                <Text style={{ flex: 1, fontWeight: F.sans, fontSize: 14, color: C.sky600, textDecorationLine: 'underline' }}>{trail.location}</Text>
              </Pressable>
            </View>
          )}

          {!!trail.location && (
            <Pressable onPress={() => openInMaps(trail.location!)}
              style={({ pressed }) => ({ marginTop: 22, paddingVertical: 14, borderRadius: 12, backgroundColor: C.moss700, alignItems: 'center', opacity: pressed ? 0.9 : 1 })}>
              <Text style={{ fontWeight: F.sansSemi, fontSize: 15, color: C.paper }}>Open in Maps</Text>
            </Pressable>
          )}
        </ScrollView>
      )}
    </BottomSheet>
  )
}

/** Slide-up detail sheet for a single event — where the card's dropped detail
 *  (date/time, location, going count) now lives. Events had no sheet before. */
function EventDetail({ event, onClose }: { event: UpcomingEvent | null; onClose: () => void }) {
  return (
    <BottomSheet open={!!event} onClose={onClose} maxHeight="88%">
      {event && (
        <ScrollView contentContainerStyle={{ paddingHorizontal: 22, paddingTop: 8, paddingBottom: 36 }} showsVerticalScrollIndicator={false}>
          {/* Photo-or-coral hero carries the title, so no repeated black heading. */}
          <View style={{ marginBottom: 14 }}>
            <ActivityTile kind="event" title={event.title} imageUrl={event.image_url} height={140} />
          </View>
          <Text style={{ fontWeight: F.mono, fontSize: 13, color: C.moss700 }}>{formatEventDate(event.event_date)}{event.start_time ? ` · ${event.start_time}` : ''}</Text>

          {!!event.location && (
            <View style={{ marginTop: 18, flexDirection: 'row', alignItems: 'baseline', gap: 12 }}>
              <Text style={{ width: 78, fontWeight: F.sansMed, fontSize: 11, color: C.ink3, letterSpacing: 1, textTransform: 'uppercase' }}>Where</Text>
              <Pressable onPress={() => openInMaps(event.location!)} onLongPress={() => copyAddress(event.location!)}
                style={{ flex: 1, flexDirection: 'row', alignItems: 'center', gap: 5 }}>
                <PinIcon size={14} color={C.sky600} />
                <Text style={{ flex: 1, fontWeight: F.sans, fontSize: 14, color: C.sky600, textDecorationLine: 'underline' }}>{event.location}</Text>
              </Pressable>
            </View>
          )}

          <Text style={{ fontWeight: F.mono, fontSize: 13, color: C.ink3, marginTop: 18 }}>{event.going_count} going</Text>

          {!!event.location && (
            <Pressable onPress={() => openInMaps(event.location!)}
              style={({ pressed }) => ({ marginTop: 22, paddingVertical: 14, borderRadius: 12, backgroundColor: C.moss700, alignItems: 'center', opacity: pressed ? 0.9 : 1 })}>
              <Text style={{ fontWeight: F.sansSemi, fontSize: 15, color: C.paper }}>Open in Maps</Text>
            </Pressable>
          )}
        </ScrollView>
      )}
    </BottomSheet>
  )
}

/** Slide-up detail sheet for a single club. */
function ClubDetail({ club, onClose, onToggleJoin }: { club: ClubView | null; onClose: () => void; onToggleJoin: (c: ClubView) => void }) {
  return (
    <BottomSheet open={!!club} onClose={onClose} maxHeight="88%">
      {club && (
        <ScrollView contentContainerStyle={{ paddingHorizontal: 22, paddingTop: 8, paddingBottom: 36 }} showsVerticalScrollIndicator={false}>
          {/* Coral hero echoes the tapped tile (clubs have no photo). */}
          <View style={{ marginBottom: 14 }}>
            <ActivityTile kind="club" title={club.name} height={140} />
          </View>
          {!!club.host && <Text style={{ fontWeight: F.sans, fontSize: 14, color: C.ink2 }}>with {club.host}</Text>}

          {!!club.vibe && (
            <Text style={{ fontWeight: F.sans, fontSize: 15, color: C.ink2, lineHeight: 22, marginTop: club.host ? 10 : 0 }}>{club.vibe}</Text>
          )}

          {/* meta rows */}
          <View style={{ marginTop: 18, gap: 12 }}>
            {!!club.schedule && <MetaRow label="When" value={club.schedule} mono />}
            {!!club.location && (
              <View style={{ flexDirection: 'row', alignItems: 'baseline', gap: 12 }}>
                <Text style={{ width: 78, fontWeight: F.sansMed, fontSize: 11, color: C.ink3, letterSpacing: 1, textTransform: 'uppercase' }}>Where</Text>
                <Pressable onPress={() => openInMaps(club.location!)} onLongPress={() => copyAddress(club.location!)}
                  style={{ flex: 1, flexDirection: 'row', alignItems: 'center', gap: 5 }}>
                  <PinIcon size={13} color={C.sky600} />
                  <Text style={{ flex: 1, fontWeight: F.sans, fontSize: 14, color: C.sky600, textDecorationLine: 'underline' }}>{club.location}</Text>
                </Pressable>
              </View>
            )}
            <MetaRow label="Members" value={`${club.member_count} ${club.member_count === 1 ? 'neighbor' : 'neighbors'}`} mono />
          </View>

          {!!club.description && (
            <Section title="About">{club.description}</Section>
          )}
          {!!club.expectations && (
            <Section title="What to expect">{club.expectations}</Section>
          )}

          <Pressable onPress={() => onToggleJoin(club)}
            style={({ pressed }) => ({ marginTop: 26, paddingVertical: 15, borderRadius: 12, alignItems: 'center', borderWidth: 1.5, borderColor: club.joined ? 'transparent' : 'rgba(0,0,0,0.14)', backgroundColor: club.joined ? C.moss700 : 'transparent', opacity: pressed ? 0.85 : 1 })}>
            <Text style={{ fontWeight: F.sansSemi, fontSize: 15, color: club.joined ? C.paper : C.ink }}>{club.joined ? 'Joined — tap to leave' : 'Join this club'}</Text>
          </Pressable>

          <ClubEventComposer clubId={club.id} />
        </ScrollView>
      )}
    </BottomSheet>
  )
}

/** Post an event tied to this club — it lands on the Timeline & Calendar tagged with the club. */
function ClubEventComposer({ clubId }: { clubId: string }) {
  const [open, setOpen] = useState(false)
  const [form, setForm] = useState<NewEventInput>({ title: '', event_date: localDate(), start_time: '', location: '', description: '' })
  const [saving, setSaving] = useState(false)
  const [msg, setMsg] = useState<string | null>(null)
  const set = (k: keyof NewEventInput) => (v: string) => setForm((f) => ({ ...f, [k]: v }))

  const post = async () => {
    if (!form.title.trim() || !form.event_date || !form.start_time?.trim()) { setMsg('Add a title, date, and time.'); return }
    // Native blocks past dates at the picker; web's input `min` is advisory, so guard here too.
    if (form.event_date < localDate()) { setMsg("Pick a date that hasn't passed."); return }
    setSaving(true); setMsg(null)
    try {
      // Moderation -- fail-closed: if the function errors, save as pending.
      let status: 'approved' | 'pending' = 'approved'
      try {
        const { data, error: modErr } = await supabase.functions.invoke('moderate-post', {
          body: { kind: 'event', title: form.title.trim(), location: form.location.trim(), description: form.description?.trim() },
        })
        if (modErr || !data) {
          status = 'pending'
        } else if (!data.ok) {
          setMsg(data.reason || "That didn't pass review -- tweak it and try again.")
          Haptics.notificationAsync(Haptics.NotificationFeedbackType.Warning)
          setSaving(false); return
        }
      } catch { status = 'pending' }

      await api.addEvent({ ...form, title: form.title.trim(), location: form.location.trim() }, clubId, status)
      Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success)
      setForm({ title: '', event_date: localDate(), start_time: '', location: '', description: '' })
      setOpen(false)
      setMsg(status === 'pending' ? 'Thanks! Your post is waiting for review before it shows up.' : "Posted! It's on the timeline now.")
    } catch {
      setMsg('Could not post -- try again.')
    } finally { setSaving(false) }
  }

  return (
    <View style={{ marginTop: 22, paddingTop: 18, borderTopWidth: 1, borderTopColor: HAIRLINE }}>
      <Pressable onPress={() => { Haptics.selectionAsync(); setOpen((o) => !o); setMsg(null) }}
        style={{ flexDirection: 'row', alignItems: 'center', gap: 8 }}>
        <View style={{ width: 24, height: 24, borderRadius: 7, backgroundColor: C.paper100, alignItems: 'center', justifyContent: 'center' }}>
          <PlusIcon />
        </View>
        <Text style={{ fontWeight: F.sansMed, fontSize: 14, color: C.ink2 }}>{open ? 'Close' : 'Add an event for this club'}</Text>
      </Pressable>

      {open && (
        <View style={{ marginTop: 12, gap: 10 }}>
          <CField label="Title" value={form.title} onChangeText={set('title')} placeholder="Saturday morning run" />
          <View style={{ flexDirection: 'row', gap: 10 }}>
            <View style={{ flex: 1 }}><DateTimeField label="Date" mode="date" value={form.event_date} onChange={set('event_date')} minDate={today()} /></View>
            <View style={{ flex: 1 }}><DateTimeField label="Time" mode="time" value={form.start_time ?? ''} onChange={set('start_time')} /></View>
          </View>
          <CField label="Where · opens in Maps" value={form.location ?? ''} onChangeText={set('location')} placeholder="Place or full address, St. Joseph, MN" />
          {msg && <Text style={{ fontWeight: F.sans, fontSize: 13, color: msg.includes('Could not') ? C.clay700 : C.moss700 }}>{msg}</Text>}
          <Pressable onPress={post} disabled={saving}
            style={({ pressed }) => ({ paddingVertical: 12, borderRadius: 10, backgroundColor: C.moss700, alignItems: 'center', opacity: pressed ? 0.85 : 1 })}>
            <Text style={{ fontWeight: F.sansSemi, fontSize: 14, color: C.paper }}>{saving ? 'Posting…' : 'Post event'}</Text>
          </Pressable>
        </View>
      )}
      {!open && msg && <Text style={{ fontWeight: F.sans, fontSize: 13, color: C.moss700, marginTop: 10 }}>{msg}</Text>}
    </View>
  )
}

function MetaRow({ label, value, mono }: { label: string; value: string; mono?: boolean }) {
  return (
    <View style={{ flexDirection: 'row', alignItems: 'baseline', gap: 12 }}>
      <Text style={{ width: 78, fontWeight: F.sansMed, fontSize: 11, color: C.ink3, letterSpacing: 1, textTransform: 'uppercase' }}>{label}</Text>
      <Text style={{ flex: 1, fontWeight: mono ? F.mono : F.sans, fontSize: 14, color: C.ink }}>{value}</Text>
    </View>
  )
}

function Section({ title, children }: { title: string; children: string }) {
  return (
    <View style={{ marginTop: 22 }}>
      <Text style={{ fontWeight: F.sansMed, fontSize: 11, color: C.ink3, letterSpacing: 1, textTransform: 'uppercase', marginBottom: 7 }}>{title}</Text>
      <Text style={{ fontWeight: F.sans, fontSize: 15, color: C.ink2, lineHeight: 23 }}>{children}</Text>
    </View>
  )
}

function CField({ label, multiline, ...props }: { label: string; multiline?: boolean } & React.ComponentProps<typeof TextInput>) {
  return (
    <View>
      <FieldLabel>{label}</FieldLabel>
      <TextInput placeholderTextColor={C.ink2} multiline={multiline}
        style={{ minHeight: multiline ? 66 : 44, borderRadius: 8, paddingHorizontal: 12, paddingTop: multiline ? 11 : 0, backgroundColor: C.paper, borderWidth: 1, borderColor: HAIRLINE, fontWeight: F.sans, fontSize: 15, color: C.ink, textAlignVertical: multiline ? 'top' : 'center' }}
        {...props} />
    </View>
  )
}

/** Sentence-case form label (not an uppercase eyebrow). */
function FieldLabel({ children }: { children: string }) {
  return <Text style={{ fontWeight: F.sansMed, fontSize: 13, color: C.ink2, marginBottom: 5 }}>{children}</Text>
}

// ── Date / time picker ─────────────────────────────────────────────
// Real pickers (no free-text). Dates stored YYYY-MM-DD via localDate(); times
// as a friendly display string ("7:00 AM"). A picked value is always valid.

function today(): Date { const d = new Date(); d.setHours(0, 0, 0, 0); return d }
function ymdToDate(ymd: string): Date {
  const [y, m, d] = (ymd || '').split('-').map(Number)
  if (!y || !m || !d) return today()
  return new Date(y, m - 1, d)
}
function prettyDate(ymd: string): string {
  const [y, m, d] = (ymd || '').split('-').map(Number)
  if (!y || !m || !d) return ''
  return new Date(y, m - 1, d).toLocaleDateString('en-US', { weekday: 'short', month: 'short', day: 'numeric' })
}
function timeToDate(s: string): Date {
  const base = new Date(); base.setSeconds(0, 0)
  const m = (s || '').match(/(\d{1,2})(?::(\d{2}))?\s*([ap]\.?m\.?)?/i)
  if (m) {
    let h = parseInt(m[1], 10)
    const min = m[2] ? parseInt(m[2], 10) : 0
    const ap = m[3]?.toLowerCase().replace(/\./g, '')
    if (ap === 'pm' && h < 12) h += 12
    if (ap === 'am' && h === 12) h = 0
    base.setHours(h, min)
  } else { base.setHours(9, 0) }
  return base
}
function fmtTime(d: Date): string {
  return d.toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit' })
}
const pad2 = (n: number) => String(n).padStart(2, '0')
const toInputTime = (display: string) => { const d = timeToDate(display); return `${pad2(d.getHours())}:${pad2(d.getMinutes())}` }
const fromInputTime = (hhmm: string) => { const [h, mi] = hhmm.split(':').map(Number); const d = new Date(); d.setHours(h || 0, mi || 0, 0, 0); return fmtTime(d) }

function DateTimeField({ label, mode, value, onChange, minDate }: {
  label: string
  mode: 'date' | 'time'
  value: string
  onChange: (v: string) => void
  minDate?: Date
}) {
  const [show, setShow] = useState(false)
  const [temp, setTemp] = useState<Date | null>(null) // iOS: pending until "Done"
  const current = mode === 'date' ? ymdToDate(value) : timeToDate(value)
  const displayText = mode === 'date' ? prettyDate(value) : value
  const commit = (d: Date) => onChange(mode === 'date' ? localDate(d) : fmtTime(d))

  // Web: real HTML <input>, via createElement to skip RN's JSX intrinsics.
  if (Platform.OS === 'web') {
    return (
      <View>
        <FieldLabel>{label}</FieldLabel>
        {createElement('input', {
          type: mode === 'date' ? 'date' : 'time',
          value: mode === 'date' ? value : (value ? toInputTime(value) : ''),
          min: mode === 'date' && minDate ? localDate(minDate) : undefined,
          onChange: (e: any) => {
            const v = e.target.value
            onChange(!v ? '' : mode === 'date' ? v : fromInputTime(v))
          },
          style: {
            height: 44, width: '100%', boxSizing: 'border-box',
            borderRadius: 8, padding: '0 12px',
            background: C.paper, border: `1px solid ${HAIRLINE}`,
            fontWeight: F.mono, fontSize: 15, color: value ? C.ink : C.ink2,
            outline: 'none',
          },
        })}
      </View>
    )
  }

  return (
    <View>
      <FieldLabel>{label}</FieldLabel>
      <Pressable
        onPress={() => { Haptics.selectionAsync(); setTemp(current); setShow(true) }}
        style={({ pressed }) => ({ minHeight: 44, borderRadius: 8, paddingHorizontal: 12, justifyContent: 'center', backgroundColor: C.paper, borderWidth: 1, borderColor: HAIRLINE, opacity: pressed ? 0.85 : 1 })}>
        <Text style={{ fontWeight: displayText ? F.mono : F.sans, fontSize: 15, color: displayText ? C.ink : C.ink2 }}>
          {displayText || (mode === 'date' ? 'Pick a date' : 'Pick a time')}
        </Text>
      </Pressable>

      {/* Android shows its own dialog when mounted. */}
      {show && Platform.OS === 'android' && (
        <RNDateTimePicker
          value={current} mode={mode}
          minimumDate={mode === 'date' ? minDate : undefined}
          onChange={(e: any, d?: Date) => { setShow(false); if (e.type === 'set' && d) commit(d) }}
        />
      )}

      {/* iOS: a calm bottom sheet with a spinner + Done. */}
      {Platform.OS === 'ios' && (
        <Modal visible={show} transparent animationType="slide" onRequestClose={() => setShow(false)}>
          <Pressable onPress={() => setShow(false)} style={{ flex: 1, backgroundColor: 'rgba(20,18,14,0.38)', justifyContent: 'flex-end' }}>
            <Pressable onPress={(e) => e.stopPropagation()} style={{ backgroundColor: C.paper, borderTopLeftRadius: 22, borderTopRightRadius: 22, paddingBottom: 28 }}>
              <View style={{ flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', paddingHorizontal: 18, paddingTop: 14, paddingBottom: 4 }}>
                <Pressable onPress={() => setShow(false)} hitSlop={10}><Text style={{ fontWeight: F.sansMed, fontSize: 15, color: C.ink2 }}>Cancel</Text></Pressable>
                <Text style={{ fontWeight: F.sansSemi, fontSize: 14, color: C.ink }}>{label}</Text>
                <Pressable onPress={() => { if (temp) commit(temp); setShow(false) }} hitSlop={10}><Text style={{ fontWeight: F.sansSemi, fontSize: 15, color: C.moss700 }}>Done</Text></Pressable>
              </View>
              <RNDateTimePicker
                value={temp ?? current} mode={mode} display="spinner" themeVariant="light"
                minimumDate={mode === 'date' ? minDate : undefined}
                onChange={(_e: any, d?: Date) => d && setTemp(d)}
                style={{ alignSelf: 'stretch' }}
              />
            </Pressable>
          </Pressable>
        </Modal>
      )}
    </View>
  )
}
