import { useCallback, useEffect, useState } from 'react'
import { ActivityIndicator, Modal, Pressable, RefreshControl, ScrollView, Text, TextInput, View } from 'react-native'
import { SafeAreaView } from 'react-native-safe-area-context'
import * as Haptics from 'expo-haptics'
import type { ClubView } from '@hygge/core'
import { api } from '../../lib/api'
import { SearchIcon, PlusIcon, CloseIcon } from '../../components/icons'
import { C, F, HAIRLINE } from '../../theme'

export default function Clubs() {
  const [clubs, setClubs] = useState<ClubView[]>([])
  const [query, setQuery] = useState('')
  const [loading, setLoading] = useState(true)
  const [refreshing, setRefreshing] = useState(false)
  const [showForm, setShowForm] = useState(false)
  const [selected, setSelected] = useState<ClubView | null>(null)

  // start-a-club form
  const [name, setName] = useState('')
  const [host, setHost] = useState('')
  const [schedule, setSchedule] = useState('')
  const [location, setLocation] = useState('')
  const [vibe, setVibe] = useState('')
  const [description, setDescription] = useState('')
  const [expectations, setExpectations] = useState('')
  const [saving, setSaving] = useState(false)
  const [msg, setMsg] = useState<string | null>(null)

  const load = useCallback(async () => {
    const list = await api.getApprovedClubs()
    setClubs(list)
  }, [])

  useEffect(() => { load().finally(() => setLoading(false)) }, [load])
  const onRefresh = async () => { setRefreshing(true); await load(); setRefreshing(false) }

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

  const create = async () => {
    if (!name.trim()) { setMsg('Give your club a name.'); return }
    setSaving(true); setMsg(null)
    try {
      await api.submitClub({
        name: name.trim(),
        host: host.trim() || undefined,
        schedule: schedule.trim() || undefined,
        location: location.trim() || undefined,
        vibe: vibe.trim() || undefined,
        description: description.trim() || undefined,
        expectations: expectations.trim() || undefined,
      })
      Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success)
      setName(''); setHost(''); setSchedule(''); setLocation(''); setVibe(''); setDescription(''); setExpectations('')
      setShowForm(false)
      await load()
      setMsg('Club added!')
    } catch {
      setMsg('Could not save — try again.')
    } finally { setSaving(false) }
  }

  const q = query.trim().toLowerCase()
  const filtered = clubs.filter((c) => !q ||
    `${c.name} ${c.host ?? ''} ${c.vibe ?? ''} ${c.schedule ?? ''} ${c.location ?? ''} ${c.description ?? ''}`.toLowerCase().includes(q))

  return (
    <SafeAreaView edges={['top']} style={{ flex: 1, backgroundColor: C.paper }}>
      <ScrollView contentContainerStyle={{ paddingBottom: 130 }} keyboardShouldPersistTaps="handled"
        refreshControl={<RefreshControl refreshing={refreshing} onRefresh={onRefresh} tintColor={C.ink3} />}>
        <View style={{ paddingHorizontal: 20, paddingTop: 14 }}>
          <Text style={{ fontFamily: F.sansMed, fontSize: 11, color: C.ink3, letterSpacing: 1.8, textTransform: 'uppercase', marginBottom: 3 }}>Find your people</Text>
          <Text style={{ fontFamily: F.display, fontSize: 26, color: C.ink, marginBottom: 16 }}>Clubs &amp; activities</Text>

          {/* Search */}
          <View style={{ flexDirection: 'row', alignItems: 'center', gap: 10, height: 48, borderRadius: 12, paddingHorizontal: 14, backgroundColor: C.paper100, borderWidth: 1, borderColor: HAIRLINE }}>
            <SearchIcon color={C.ink3} />
            <TextInput value={query} onChangeText={setQuery} placeholder="Search clubs & activities…" placeholderTextColor={C.ink3}
              style={{ flex: 1, fontFamily: F.sans, fontSize: 15, color: C.ink }} autoCapitalize="none" />
          </View>

          {/* Start a club toggle */}
          <Pressable onPress={() => { Haptics.selectionAsync(); setShowForm((s) => !s); setMsg(null) }}
            style={{ flexDirection: 'row', alignItems: 'center', gap: 8, marginTop: 14 }}>
            <View style={{ width: 26, height: 26, borderRadius: 8, backgroundColor: C.paper100, alignItems: 'center', justifyContent: 'center' }}>
              <PlusIcon />
            </View>
            <Text style={{ fontFamily: F.sansMed, fontSize: 14, color: C.ink2 }}>{showForm ? 'Close' : 'Start a club'}</Text>
          </Pressable>

          {showForm && (
            <View style={{ marginTop: 14, gap: 10, padding: 14, borderRadius: 14, backgroundColor: C.paper100, borderWidth: 1, borderColor: HAIRLINE }}>
              <CField label="Name" value={name} onChangeText={setName} placeholder="Tuesday Trail Walkers" />
              <CField label="Host" value={host} onChangeText={setHost} placeholder="Your name" />
              <CField label="When" value={schedule} onChangeText={setSchedule} placeholder="Tuesdays, 6pm" />
              <CField label="Where" value={location} onChangeText={setLocation} placeholder="Millstream Park trailhead" />
              <CField label="Vibe · short" value={vibe} onChangeText={setVibe} placeholder="Easygoing, all paces welcome" />
              <CField label="About" value={description} onChangeText={setDescription} placeholder="What the club is, who it's for…" multiline />
              <CField label="What to expect / bring" value={expectations} onChangeText={setExpectations} placeholder="Good shoes, water, ~3 miles at a chatty pace" multiline />
              {msg && <Text style={{ fontFamily: F.sans, fontSize: 13, color: msg.includes('added') ? C.moss700 : C.clay700 }}>{msg}</Text>}
              <Pressable onPress={create} disabled={saving}
                style={({ pressed }) => ({ marginTop: 2, paddingVertical: 12, borderRadius: 10, backgroundColor: C.moss700, alignItems: 'center', opacity: pressed ? 0.85 : 1 })}>
                <Text style={{ fontFamily: F.sansSemi, fontSize: 14, color: C.paper }}>{saving ? 'Saving…' : 'Add club'}</Text>
              </Pressable>
            </View>
          )}
        </View>

        {/* List */}
        <View style={{ paddingHorizontal: 20, paddingTop: 18, gap: 12 }}>
          {loading ? (
            <ActivityIndicator color={C.ink3} style={{ marginTop: 20 }} />
          ) : filtered.length === 0 ? (
            <View style={{ borderRadius: 16, borderWidth: 1.5, borderStyle: 'dashed', borderColor: 'rgba(0,0,0,0.13)', padding: 18 }}>
              <Text style={{ fontFamily: F.sans, fontSize: 13, color: C.ink2 }}>
                {clubs.length === 0 ? 'No clubs yet — be the first to start one.' : 'No clubs match your search.'}
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
      </ScrollView>

      <ClubDetail club={selected} onClose={() => setSelected(null)} onToggleJoin={toggleJoin} />
    </SafeAreaView>
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
                {!!club.location && <MetaRow label="Where" value={club.location} />}
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
            </ScrollView>
          )}
        </Pressable>
      </Pressable>
    </Modal>
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
