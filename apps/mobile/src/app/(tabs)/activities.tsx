import { useCallback, useEffect, useState } from 'react'
import { ActivityIndicator, Modal, Pressable, RefreshControl, ScrollView, Text, TextInput, View } from 'react-native'
import { SafeAreaView } from 'react-native-safe-area-context'
import * as Haptics from 'expo-haptics'
import { Image } from 'expo-image'
import { isAdminEmail, localDate, type ClubView, type ClubRow, type NewEventInput, type Trail, type PendingPost } from '@hygge/core'
import { api } from '../../lib/api'
import { supabase } from '../../lib/supabase'
import { getInterests, matchesInterests } from '../../lib/interests'
import { SearchIcon, PlusIcon, CloseIcon, PinIcon } from '../../components/icons'
import { openInMaps, copyAddress } from '../../lib/maps'
import { C, F, HAIRLINE } from '../../theme'

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
  const [isAdmin, setIsAdmin] = useState(false)
  const [interests, setInterestsState] = useState<string[]>([])

  const load = useCallback(async (admin: boolean) => {
    const [list, trailList] = await Promise.all([api.getApprovedClubs(), api.getTrails()])
    setClubs(list)
    setTrails(trailList)
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
  const filtered = clubs.filter((c) => !q ||
    `${c.name} ${c.host ?? ''} ${c.vibe ?? ''} ${c.schedule ?? ''} ${c.location ?? ''} ${c.description ?? ''}`.toLowerCase().includes(q))

  const hasPending = isAdmin && (pendingPosts.length > 0 || pendingClubs.length > 0)

  // "Suggested for you" — keyword-match the viewer's onboarding interests (real matches only).
  const suggestedClubs = clubs.filter((c) =>
    matchesInterests(`${c.name} ${c.host ?? ''} ${c.vibe ?? ''} ${c.schedule ?? ''} ${c.description ?? ''}`, interests))
  const suggestedTrails = trails.filter((t) =>
    matchesInterests(`${t.title} ${t.location ?? ''} ${t.description ?? ''}`, interests, true))
  const hasSuggested = !loading && (suggestedClubs.length > 0 || suggestedTrails.length > 0)

  return (
    <SafeAreaView edges={['top']} style={{ flex: 1, backgroundColor: C.paper }}>
      <ScrollView contentContainerStyle={{ paddingBottom: 130 }} keyboardShouldPersistTaps="handled"
        refreshControl={<RefreshControl refreshing={refreshing} onRefresh={onRefresh} tintColor={C.ink3} />}>
        <View style={{ paddingHorizontal: 20, paddingTop: 14 }}>
          <Text style={{ fontFamily: F.sansMed, fontSize: 11, color: C.ink3, letterSpacing: 1.8, textTransform: 'uppercase', marginBottom: 3 }}>Find your people</Text>
          <Text style={{ fontFamily: F.display, fontSize: 26, color: C.ink, marginBottom: 16 }}>Activities</Text>

          {/* Search */}
          <View style={{ flexDirection: 'row', alignItems: 'center', gap: 10, height: 48, borderRadius: 12, paddingHorizontal: 14, backgroundColor: C.paper100, borderWidth: 1, borderColor: HAIRLINE }}>
            <SearchIcon color={C.ink3} />
            <TextInput value={query} onChangeText={setQuery} placeholder="Search clubs & activities…" placeholderTextColor={C.ink3}
              style={{ flex: 1, fontFamily: F.sans, fontSize: 15, color: C.ink }} autoCapitalize="none" />
          </View>
        </View>

        {/* Admin: Waiting for review */}
        {hasPending && (
          <View style={{ marginHorizontal: 20, marginTop: 22, padding: 14, borderRadius: 14, backgroundColor: C.paper100, borderWidth: 1, borderColor: HAIRLINE }}>
            <Text style={{ fontFamily: F.sansMed, fontSize: 11, color: C.ink3, letterSpacing: 1.2, textTransform: 'uppercase', marginBottom: 12 }}>Waiting for review · admin</Text>

            {pendingPosts.map((p) => (
              <View key={p.id} style={{ paddingVertical: 12, borderTopWidth: 1, borderTopColor: HAIRLINE }}>
                <Text style={{ fontFamily: F.sansBold, fontSize: 14, color: C.ink }}>{p.title}</Text>
                <Text style={{ fontFamily: F.mono, fontSize: 11, color: C.ink3, marginTop: 3 }}>
                  {p.kind} {p.location ? `· ${p.location}` : ''}
                </Text>
                <View style={{ flexDirection: 'row', gap: 10, marginTop: 10 }}>
                  <Pressable onPress={() => approvePost(p.id)}
                    style={({ pressed }) => ({ flex: 1, paddingVertical: 9, borderRadius: 8, backgroundColor: C.moss700, alignItems: 'center', opacity: pressed ? 0.85 : 1 })}>
                    <Text style={{ fontFamily: F.sansSemi, fontSize: 13, color: C.paper }}>Approve</Text>
                  </Pressable>
                  <Pressable onPress={() => rejectPost(p.id)}
                    style={({ pressed }) => ({ flex: 1, paddingVertical: 9, borderRadius: 8, borderWidth: 1.5, borderColor: C.clay700, alignItems: 'center', opacity: pressed ? 0.85 : 1 })}>
                    <Text style={{ fontFamily: F.sansSemi, fontSize: 13, color: C.clay700 }}>Decline</Text>
                  </Pressable>
                </View>
              </View>
            ))}

            {pendingClubs.map((c) => (
              <View key={c.id} style={{ paddingVertical: 12, borderTopWidth: 1, borderTopColor: HAIRLINE }}>
                <Text style={{ fontFamily: F.sansBold, fontSize: 14, color: C.ink }}>{c.name}</Text>
                {!!c.host && <Text style={{ fontFamily: F.sans, fontSize: 12, color: C.ink2, marginTop: 2 }}>with {c.host}</Text>}
                <Text style={{ fontFamily: F.mono, fontSize: 11, color: C.ink3, marginTop: 3 }}>club</Text>
                <View style={{ flexDirection: 'row', gap: 10, marginTop: 10 }}>
                  <Pressable onPress={() => approveClub(c.id)}
                    style={({ pressed }) => ({ flex: 1, paddingVertical: 9, borderRadius: 8, backgroundColor: C.moss700, alignItems: 'center', opacity: pressed ? 0.85 : 1 })}>
                    <Text style={{ fontFamily: F.sansSemi, fontSize: 13, color: C.paper }}>Approve</Text>
                  </Pressable>
                  <Pressable onPress={() => rejectClub(c.id)}
                    style={({ pressed }) => ({ flex: 1, paddingVertical: 9, borderRadius: 8, borderWidth: 1.5, borderColor: C.clay700, alignItems: 'center', opacity: pressed ? 0.85 : 1 })}>
                    <Text style={{ fontFamily: F.sansSemi, fontSize: 13, color: C.clay700 }}>Decline</Text>
                  </Pressable>
                </View>
              </View>
            ))}
          </View>
        )}

        {/* Suggested for you — from onboarding interests */}
        {hasSuggested && (
          <View style={{ paddingHorizontal: 20, paddingTop: 22, gap: 12 }}>
            <Text style={{ fontFamily: F.sansMed, fontSize: 11, color: C.moss700, letterSpacing: 1.2, textTransform: 'uppercase', marginBottom: 2 }}>Suggested for you</Text>
            {suggestedClubs.map((c) => (
              <Pressable key={`s-${c.id}`} onPress={() => { Haptics.selectionAsync(); setSelected(c) }}
                style={({ pressed }) => ({ borderRadius: 16, backgroundColor: C.paper100, borderWidth: 1, borderColor: HAIRLINE, padding: 16, opacity: pressed ? 0.92 : 1 })}>
                <Text style={{ fontFamily: F.mono, fontSize: 10, color: C.ink3, letterSpacing: 1, textTransform: 'uppercase', marginBottom: 4 }}>Club</Text>
                <Text style={{ fontFamily: F.sansBold, fontSize: 17, color: C.ink, letterSpacing: -0.2 }}>{c.name}</Text>
                {!!c.vibe && <Text style={{ fontFamily: F.sans, fontSize: 13, color: C.ink2, marginTop: 4, lineHeight: 18 }}>{c.vibe}</Text>}
              </Pressable>
            ))}
            {suggestedTrails.map((t) => {
              const meta = [t.location, t.length, t.difficulty].filter(Boolean).join(' · ')
              return (
                <Pressable key={`s-${t.id}`} onPress={() => { Haptics.selectionAsync(); setSelectedTrail(t) }}
                  style={({ pressed }) => ({ borderRadius: 16, backgroundColor: C.paper100, borderWidth: 1, borderColor: HAIRLINE, padding: 16, opacity: pressed ? 0.92 : 1 })}>
                  <Text style={{ fontFamily: F.mono, fontSize: 10, color: C.ink3, letterSpacing: 1, textTransform: 'uppercase', marginBottom: 4 }}>Trail</Text>
                  <Text style={{ fontFamily: F.sansBold, fontSize: 17, color: C.ink, letterSpacing: -0.2 }}>{t.title}</Text>
                  {!!meta && <Text style={{ fontFamily: F.mono, fontSize: 12, color: C.ink3, marginTop: 6 }}>{meta}</Text>}
                </Pressable>
              )
            })}
          </View>
        )}

        {/* Clubs list */}
        <View style={{ paddingHorizontal: 20, paddingTop: 18, gap: 12 }}>
          <Text style={{ fontFamily: F.sansMed, fontSize: 11, color: C.ink3, letterSpacing: 1.2, textTransform: 'uppercase', marginBottom: 2 }}>Clubs</Text>
          {loading ? (
            <ActivityIndicator color={C.ink3} style={{ marginTop: 20 }} />
          ) : filtered.length === 0 ? (
            <View style={{ borderRadius: 16, borderWidth: 1.5, borderStyle: 'dashed', borderColor: 'rgba(0,0,0,0.13)', padding: 18 }}>
              <Text style={{ fontFamily: F.sans, fontSize: 13, color: C.ink2 }}>
                {clubs.length === 0 ? 'No clubs yet — start one via the + tab.' : 'No clubs match your search.'}
              </Text>
            </View>
          ) : (
            filtered.map((c) => (
              <Pressable key={c.id} onPress={() => { Haptics.selectionAsync(); setSelected(c) }}
                style={({ pressed }) => ({ borderRadius: 16, backgroundColor: C.paper100, borderWidth: 1, borderColor: HAIRLINE, padding: 16, opacity: pressed ? 0.92 : 1 })}>
                <View style={{ flexDirection: 'row', alignItems: 'flex-start', justifyContent: 'space-between', gap: 12 }}>
                  <View style={{ flex: 1 }}>
                    <Text style={{ fontFamily: F.sansBold, fontSize: 17, color: C.ink, letterSpacing: -0.2 }}>{c.name}</Text>
                    {!!c.host && <Text style={{ fontFamily: F.sans, fontSize: 13, color: C.ink2, marginTop: 2 }}>with {c.host}</Text>}
                    {!!c.schedule && <Text style={{ fontFamily: F.mono, fontSize: 12, color: C.ink3, marginTop: 6 }}>{c.schedule}</Text>}
                    {!!c.vibe && <Text style={{ fontFamily: F.sans, fontSize: 13, color: C.ink2, marginTop: 6, lineHeight: 18 }}>{c.vibe}</Text>}
                    <Text style={{ fontFamily: F.mono, fontSize: 11, color: C.ink3, marginTop: 8 }}>{c.member_count} {c.member_count === 1 ? 'member' : 'members'} · tap for details</Text>
                  </View>
                  <Pressable onPress={() => toggleJoin(c)} hitSlop={8}
                    style={({ pressed }) => ({ paddingHorizontal: 16, paddingVertical: 8, borderRadius: 20, borderWidth: 1.5, borderColor: c.joined ? 'transparent' : 'rgba(0,0,0,0.14)', backgroundColor: c.joined ? C.moss700 : 'transparent', opacity: pressed ? 0.85 : 1 })}>
                    <Text style={{ fontFamily: F.sansMed, fontSize: 13, color: c.joined ? C.paper : C.ink2 }}>{c.joined ? 'Joined' : 'Join'}</Text>
                  </Pressable>
                </View>
              </Pressable>
            ))
          )}
        </View>

        {/* Trails section */}
        {!loading && trails.length > 0 && (
          <View style={{ paddingHorizontal: 20, paddingTop: 28, gap: 12 }}>
            <Text style={{ fontFamily: F.sansMed, fontSize: 11, color: C.ink3, letterSpacing: 1.2, textTransform: 'uppercase', marginBottom: 2 }}>Trails</Text>
            {trails.map((t) => {
              const meta = [t.location, t.length, t.difficulty].filter(Boolean).join(' · ')
              return (
                <Pressable key={t.id} onPress={() => { Haptics.selectionAsync(); setSelectedTrail(t) }}
                  style={({ pressed }) => ({ borderRadius: 16, backgroundColor: C.paper100, borderWidth: 1, borderColor: HAIRLINE, overflow: 'hidden', opacity: pressed ? 0.92 : 1 })}>
                  {!!t.image_url && (
                    <Image source={{ uri: t.image_url }} style={{ width: '100%', height: 160 }} contentFit="cover" />
                  )}
                  <View style={{ padding: 16 }}>
                    <Text style={{ fontFamily: F.sansBold, fontSize: 17, color: C.ink, letterSpacing: -0.2 }}>{t.title}</Text>
                    {!!meta && <Text style={{ fontFamily: F.mono, fontSize: 12, color: C.ink3, marginTop: 6 }}>{meta}</Text>}
                    {!!t.description && <Text numberOfLines={2} style={{ fontFamily: F.sans, fontSize: 13, color: C.ink2, marginTop: 8, lineHeight: 19 }}>{t.description}</Text>}
                    <Text style={{ fontFamily: F.mono, fontSize: 11, color: C.ink3, marginTop: 8 }}>tap for details</Text>
                  </View>
                </Pressable>
              )
            })}
          </View>
        )}
      </ScrollView>

      <ClubDetail club={selected} onClose={() => setSelected(null)} onToggleJoin={toggleJoin} />
      <TrailDetail trail={selectedTrail} onClose={() => setSelectedTrail(null)} />
    </SafeAreaView>
  )
}

/** Slide-up detail sheet for a single trail. */
function TrailDetail({ trail, onClose }: { trail: Trail | null; onClose: () => void }) {
  const meta = trail ? [trail.length, trail.difficulty].filter(Boolean).join(' · ') : ''
  return (
    <Modal visible={!!trail} transparent animationType="slide" onRequestClose={onClose}>
      <Pressable onPress={onClose} style={{ flex: 1, backgroundColor: 'rgba(20,18,14,0.38)', justifyContent: 'flex-end' }}>
        <Pressable onPress={(e) => e.stopPropagation()} style={{ backgroundColor: C.paper, borderTopLeftRadius: 22, borderTopRightRadius: 22, paddingTop: 8, paddingBottom: 36, maxHeight: '88%' }}>
          <View style={{ alignSelf: 'center', width: 38, height: 4, borderRadius: 2, backgroundColor: 'rgba(0,0,0,0.14)', marginBottom: 6 }} />
          {trail && (
            <ScrollView contentContainerStyle={{ paddingHorizontal: 22, paddingTop: 8 }} showsVerticalScrollIndicator={false}>
              {!!trail.image_url && (
                <Image source={{ uri: trail.image_url }} style={{ width: '100%', height: 180, borderRadius: 14, marginBottom: 14 }} contentFit="cover" />
              )}
              <View style={{ flexDirection: 'row', alignItems: 'flex-start', justifyContent: 'space-between', gap: 12 }}>
                <Text style={{ flex: 1, fontFamily: F.display, fontSize: 26, color: C.ink, letterSpacing: -0.4 }}>{trail.title}</Text>
                <Pressable onPress={onClose} hitSlop={8} style={{ width: 32, height: 32, borderRadius: 16, backgroundColor: C.paper100, alignItems: 'center', justifyContent: 'center' }}>
                  <CloseIcon size={16} color={C.ink2} />
                </Pressable>
              </View>

              {!!meta && <Text style={{ fontFamily: F.mono, fontSize: 13, color: C.ink3, marginTop: 8 }}>{meta}</Text>}
              {!!trail.description && (
                <Text style={{ fontFamily: F.sans, fontSize: 15, color: C.ink2, lineHeight: 22, marginTop: 14 }}>{trail.description}</Text>
              )}

              {!!trail.location && (
                <View style={{ marginTop: 18, flexDirection: 'row', alignItems: 'baseline', gap: 12 }}>
                  <Text style={{ width: 78, fontFamily: F.sansMed, fontSize: 11, color: C.ink3, letterSpacing: 1, textTransform: 'uppercase' }}>Where</Text>
                  <Pressable onPress={() => openInMaps(trail.location!)} onLongPress={() => copyAddress(trail.location!)}
                    style={{ flex: 1, flexDirection: 'row', alignItems: 'center', gap: 5 }}>
                    <PinIcon size={14} color={C.moss700} />
                    <Text style={{ flex: 1, fontFamily: F.sans, fontSize: 14, color: C.moss700 }}>{trail.location}</Text>
                  </Pressable>
                </View>
              )}

              {!!trail.location && (
                <Pressable onPress={() => openInMaps(trail.location!)}
                  style={({ pressed }) => ({ marginTop: 22, paddingVertical: 14, borderRadius: 12, backgroundColor: C.moss700, alignItems: 'center', opacity: pressed ? 0.9 : 1 })}>
                  <Text style={{ fontFamily: F.sansSemi, fontSize: 15, color: C.paper }}>Open in Maps</Text>
                </Pressable>
              )}
            </ScrollView>
          )}
        </Pressable>
      </Pressable>
    </Modal>
  )
}

/** Slide-up detail sheet for a single club. */
function ClubDetail({ club, onClose, onToggleJoin }: { club: ClubView | null; onClose: () => void; onToggleJoin: (c: ClubView) => void }) {
  return (
    <Modal visible={!!club} transparent animationType="slide" onRequestClose={onClose}>
      <Pressable onPress={onClose} style={{ flex: 1, backgroundColor: 'rgba(20,18,14,0.38)', justifyContent: 'flex-end' }}>
        <Pressable onPress={(e) => e.stopPropagation()} style={{ backgroundColor: C.paper, borderTopLeftRadius: 22, borderTopRightRadius: 22, paddingTop: 8, paddingBottom: 36, maxHeight: '88%' }}>
          {/* grab handle */}
          <View style={{ alignSelf: 'center', width: 38, height: 4, borderRadius: 2, backgroundColor: 'rgba(0,0,0,0.14)', marginBottom: 6 }} />
          {club && (
            <ScrollView contentContainerStyle={{ paddingHorizontal: 22, paddingTop: 8 }} showsVerticalScrollIndicator={false}>
              <View style={{ flexDirection: 'row', alignItems: 'flex-start', justifyContent: 'space-between', gap: 12 }}>
                <View style={{ flex: 1 }}>
                  <Text style={{ fontFamily: F.display, fontSize: 26, color: C.ink, letterSpacing: -0.4 }}>{club.name}</Text>
                  {!!club.host && <Text style={{ fontFamily: F.sans, fontSize: 14, color: C.ink2, marginTop: 4 }}>with {club.host}</Text>}
                </View>
                <Pressable onPress={onClose} hitSlop={8} style={{ width: 32, height: 32, borderRadius: 16, backgroundColor: C.paper100, alignItems: 'center', justifyContent: 'center' }}>
                  <CloseIcon size={16} color={C.ink2} />
                </Pressable>
              </View>

              {!!club.vibe && (
                <Text style={{ fontFamily: F.sans, fontSize: 15, color: C.ink2, lineHeight: 22, marginTop: 14 }}>{club.vibe}</Text>
              )}

              {/* meta rows */}
              <View style={{ marginTop: 18, gap: 12 }}>
                {!!club.schedule && <MetaRow label="When" value={club.schedule} mono />}
                {!!club.location && (
                  <View style={{ flexDirection: 'row', alignItems: 'baseline', gap: 12 }}>
                    <Text style={{ width: 78, fontFamily: F.sansMed, fontSize: 11, color: C.ink3, letterSpacing: 1, textTransform: 'uppercase' }}>Where</Text>
                    <Pressable onPress={() => openInMaps(club.location!)} onLongPress={() => copyAddress(club.location!)}
                      style={{ flex: 1, flexDirection: 'row', alignItems: 'center', gap: 5 }}>
                      <PinIcon size={13} color={C.sky600} />
                      <Text style={{ flex: 1, fontFamily: F.sans, fontSize: 14, color: C.sky600, textDecorationLine: 'underline' }}>{club.location}</Text>
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
                <Text style={{ fontFamily: F.sansSemi, fontSize: 15, color: club.joined ? C.paper : C.ink }}>{club.joined ? 'Joined — tap to leave' : 'Join this club'}</Text>
              </Pressable>

              <ClubEventComposer clubId={club.id} />
            </ScrollView>
          )}
        </Pressable>
      </Pressable>
    </Modal>
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
        <Text style={{ fontFamily: F.sansMed, fontSize: 14, color: C.ink2 }}>{open ? 'Close' : 'Add an event for this club'}</Text>
      </Pressable>

      {open && (
        <View style={{ marginTop: 12, gap: 10 }}>
          <CField label="Title" value={form.title} onChangeText={set('title')} placeholder="Saturday morning run" />
          <View style={{ flexDirection: 'row', gap: 10 }}>
            <View style={{ flex: 1 }}><CField label="Date" value={form.event_date} onChangeText={set('event_date')} placeholder={localDate()} autoCapitalize="none" /></View>
            <View style={{ flex: 1 }}><CField label="Time" value={form.start_time ?? ''} onChangeText={set('start_time')} placeholder="7am" /></View>
          </View>
          <CField label="Where · opens in Maps" value={form.location ?? ''} onChangeText={set('location')} placeholder="Place or full address, St. Joseph, MN" />
          {msg && <Text style={{ fontFamily: F.sans, fontSize: 13, color: msg.includes('Could not') ? C.clay700 : C.moss700 }}>{msg}</Text>}
          <Pressable onPress={post} disabled={saving}
            style={({ pressed }) => ({ paddingVertical: 12, borderRadius: 10, backgroundColor: C.moss700, alignItems: 'center', opacity: pressed ? 0.85 : 1 })}>
            <Text style={{ fontFamily: F.sansSemi, fontSize: 14, color: C.paper }}>{saving ? 'Posting…' : 'Post event'}</Text>
          </Pressable>
        </View>
      )}
      {!open && msg && <Text style={{ fontFamily: F.sans, fontSize: 13, color: C.moss700, marginTop: 10 }}>{msg}</Text>}
    </View>
  )
}

function MetaRow({ label, value, mono }: { label: string; value: string; mono?: boolean }) {
  return (
    <View style={{ flexDirection: 'row', alignItems: 'baseline', gap: 12 }}>
      <Text style={{ width: 78, fontFamily: F.sansMed, fontSize: 11, color: C.ink3, letterSpacing: 1, textTransform: 'uppercase' }}>{label}</Text>
      <Text style={{ flex: 1, fontFamily: mono ? F.mono : F.sans, fontSize: 14, color: C.ink }}>{value}</Text>
    </View>
  )
}

function Section({ title, children }: { title: string; children: string }) {
  return (
    <View style={{ marginTop: 22 }}>
      <Text style={{ fontFamily: F.sansMed, fontSize: 11, color: C.ink3, letterSpacing: 1, textTransform: 'uppercase', marginBottom: 7 }}>{title}</Text>
      <Text style={{ fontFamily: F.sans, fontSize: 15, color: C.ink2, lineHeight: 23 }}>{children}</Text>
    </View>
  )
}

function CField({ label, multiline, ...props }: { label: string; multiline?: boolean } & React.ComponentProps<typeof TextInput>) {
  return (
    <View>
      <Text style={{ fontFamily: F.sansMed, fontSize: 11, color: C.ink3, letterSpacing: 1, textTransform: 'uppercase', marginBottom: 5 }}>{label}</Text>
      <TextInput placeholderTextColor={C.ink3} multiline={multiline}
        style={{ minHeight: multiline ? 66 : 44, borderRadius: 8, paddingHorizontal: 12, paddingTop: multiline ? 11 : 0, backgroundColor: C.paper, borderWidth: 1, borderColor: HAIRLINE, fontFamily: F.sans, fontSize: 15, color: C.ink, textAlignVertical: multiline ? 'top' : 'center' }}
        {...props} />
    </View>
  )
}
