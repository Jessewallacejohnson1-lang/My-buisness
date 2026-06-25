import { useCallback, useEffect, useState } from 'react'
import { ActivityIndicator, Pressable, RefreshControl, ScrollView, Text, TextInput, View } from 'react-native'
import { SafeAreaView } from 'react-native-safe-area-context'
import * as Haptics from 'expo-haptics'
import type { ClubView } from '@hygge/core'
import { api } from '../../lib/api'
import { SearchIcon, PlusIcon } from '../../components/icons'
import { C, F, HAIRLINE } from '../../theme'

export default function Clubs() {
  const [clubs, setClubs] = useState<ClubView[]>([])
  const [query, setQuery] = useState('')
  const [loading, setLoading] = useState(true)
  const [refreshing, setRefreshing] = useState(false)
  const [showForm, setShowForm] = useState(false)

  // start-a-club form
  const [name, setName] = useState('')
  const [host, setHost] = useState('')
  const [schedule, setSchedule] = useState('')
  const [vibe, setVibe] = useState('')
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
    setClubs((l) => l.map((c) => c.id === club.id ? { ...c, joined: next, member_count: c.member_count + (next ? 1 : -1) } : c))
    try { next ? await api.joinClub(club.id) : await api.leaveClub(club.id) }
    catch { setClubs((l) => l.map((c) => c.id === club.id ? { ...c, joined: !next, member_count: c.member_count + (next ? -1 : 1) } : c)) }
  }

  const create = async () => {
    if (!name.trim()) { setMsg('Give your club a name.'); return }
    setSaving(true); setMsg(null)
    try {
      await api.submitClub({ name: name.trim(), host: host.trim() || undefined, schedule: schedule.trim() || undefined, vibe: vibe.trim() || undefined })
      Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success)
      setName(''); setHost(''); setSchedule(''); setVibe('')
      setShowForm(false)
      await load()
      setMsg('Club added!')
    } catch {
      setMsg('Could not save — try again.')
    } finally { setSaving(false) }
  }

  const q = query.trim().toLowerCase()
  const filtered = clubs.filter((c) => !q || `${c.name} ${c.host ?? ''} ${c.vibe ?? ''} ${c.schedule ?? ''}`.toLowerCase().includes(q))

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
              <CField label="Vibe" value={vibe} onChangeText={setVibe} placeholder="Easygoing, all paces welcome" />
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
              <View key={c.id} style={{ borderRadius: 16, backgroundColor: C.paper100, borderWidth: 1, borderColor: HAIRLINE, padding: 16 }}>
                <View style={{ flexDirection: 'row', alignItems: 'flex-start', justifyContent: 'space-between', gap: 12 }}>
                  <View style={{ flex: 1 }}>
                    <Text style={{ fontFamily: F.sansBold, fontSize: 17, color: C.ink, letterSpacing: -0.2 }}>{c.name}</Text>
                    {!!c.host && <Text style={{ fontFamily: F.sans, fontSize: 13, color: C.ink2, marginTop: 2 }}>with {c.host}</Text>}
                    {!!c.schedule && <Text style={{ fontFamily: F.mono, fontSize: 12, color: C.ink3, marginTop: 6 }}>{c.schedule}</Text>}
                    {!!c.vibe && <Text style={{ fontFamily: F.sans, fontSize: 13, color: C.ink2, marginTop: 6, lineHeight: 18 }}>{c.vibe}</Text>}
                    <Text style={{ fontFamily: F.mono, fontSize: 11, color: C.ink3, marginTop: 8 }}>{c.member_count} {c.member_count === 1 ? 'member' : 'members'}</Text>
                  </View>
                  <Pressable onPress={() => toggleJoin(c)}
                    style={({ pressed }) => ({ paddingHorizontal: 16, paddingVertical: 8, borderRadius: 20, borderWidth: 1.5, borderColor: c.joined ? 'transparent' : 'rgba(0,0,0,0.14)', backgroundColor: c.joined ? C.moss700 : 'transparent', opacity: pressed ? 0.85 : 1 })}>
                    <Text style={{ fontFamily: F.sansMed, fontSize: 13, color: c.joined ? C.paper : C.ink2 }}>{c.joined ? 'Joined' : 'Join'}</Text>
                  </Pressable>
                </View>
              </View>
            ))
          )}
        </View>
      </ScrollView>
    </SafeAreaView>
  )
}

function CField({ label, ...props }: { label: string } & React.ComponentProps<typeof TextInput>) {
  return (
    <View>
      <Text style={{ fontFamily: F.sansMed, fontSize: 11, color: C.ink3, letterSpacing: 1, textTransform: 'uppercase', marginBottom: 5 }}>{label}</Text>
      <TextInput placeholderTextColor={C.ink3}
        style={{ height: 44, borderRadius: 8, paddingHorizontal: 12, backgroundColor: C.paper, borderWidth: 1, borderColor: HAIRLINE, fontFamily: F.sans, fontSize: 15, color: C.ink }}
        {...props} />
    </View>
  )
}
