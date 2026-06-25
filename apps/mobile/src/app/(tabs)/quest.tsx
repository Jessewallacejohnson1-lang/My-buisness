import { useEffect, useState } from 'react'
import { ActivityIndicator, Pressable, ScrollView, Text, TextInput, View } from 'react-native'
import { SafeAreaView } from 'react-native-safe-area-context'
import * as Haptics from 'expo-haptics'
import { isAdminEmail, localDate, type DailyQuest } from '@hygge/core'
import { api } from '../../lib/api'
import { CheckIcon } from '../../components/icons'
import { C, F, HAIRLINE } from '../../theme'

export default function Quest() {
  const [quest, setQuest_] = useState<DailyQuest | null>(null)
  const [count, setCount] = useState(0)
  const [done, setDone] = useState(false)
  const [loading, setLoading] = useState(true)
  const [completing, setCompleting] = useState(false)
  const [isAdmin, setIsAdmin] = useState(false)
  // admin form
  const [aTitle, setATitle] = useState('')
  const [aDesc, setADesc] = useState('')
  const [aDate, setADate] = useState(localDate())
  const [aSaving, setASaving] = useState(false)
  const [aMsg, setAMsg] = useState<string | null>(null)

  useEffect(() => {
    (async () => {
      const [q, user] = await Promise.all([api.getTodayQuest(), api.getCurrentUser()])
      setQuest_(q)
      setIsAdmin(isAdminEmail(user?.email))
      if (q) {
        const [c] = await Promise.all([api.getQuestCompletionCount(q.id)])
        setCount(c)
        if (user) setDone(await api.hasUserCompletedQuest(q.id, user.id))
      }
      setLoading(false)
    })()
  }, [])

  const complete = async () => {
    if (!quest || done || completing) return
    setCompleting(true)
    try {
      await api.completeQuest(quest.id)
      Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success)
      setDone(true); setCount((c) => c + 1)
    } catch { /* ignore */ } finally { setCompleting(false) }
  }

  const saveQuest = async () => {
    if (!aTitle.trim() || !aDate) return
    setASaving(true); setAMsg(null)
    try {
      await api.setQuest(aTitle.trim(), aDesc.trim(), aDate)
      setAMsg('Quest saved.'); setATitle(''); setADesc('')
    } catch { setAMsg('Could not save — try again.') } finally { setASaving(false) }
  }

  if (loading) {
    return <SafeAreaView style={{ flex: 1, backgroundColor: C.paper, alignItems: 'center', justifyContent: 'center' }}><ActivityIndicator color={C.ink3} /></SafeAreaView>
  }

  return (
    <SafeAreaView edges={['top']} style={{ flex: 1, backgroundColor: C.paper }}>
      <ScrollView contentContainerStyle={{ paddingHorizontal: 18, paddingTop: 24, paddingBottom: 140 }}>
        {quest ? (
          <View>
            <Text style={{ fontFamily: F.sansMed, fontSize: 11, color: C.ink3, letterSpacing: 1.8, textTransform: 'uppercase', marginBottom: 14 }}>Today&rsquo;s quest</Text>
            <Text style={{ fontFamily: F.display, fontSize: 33, color: C.ink, lineHeight: 38, marginBottom: 14 }}>{quest.title}</Text>
            {!!quest.description && <Text style={{ fontFamily: F.sans, fontSize: 16, color: C.ink2, lineHeight: 25, marginBottom: 20 }}>{quest.description}</Text>}
            <Text style={{ fontFamily: F.mono, fontSize: 13, color: C.ink3, marginBottom: 22 }}>
              {count}<Text style={{ fontFamily: F.sans }}> {count === 1 ? 'neighbor' : 'neighbors'} did this today</Text>
            </Text>

            {done ? (
              <View style={{ flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: 6, paddingVertical: 15, borderRadius: 12, borderWidth: 1.5, borderColor: C.moss700 }}>
                <Text style={{ fontFamily: F.sansSemi, fontSize: 15, color: C.moss700 }}>Done for today</Text>
                <CheckIcon size={16} color={C.moss700} />
              </View>
            ) : (
              <Pressable onPress={complete} disabled={completing}
                style={({ pressed }) => ({ paddingVertical: 15, borderRadius: 12, backgroundColor: C.moss700, alignItems: 'center', opacity: pressed ? 0.85 : 1 })}>
                <Text style={{ fontFamily: F.sansSemi, fontSize: 15, color: C.paper }}>{completing ? '…' : 'Mark done'}</Text>
              </Pressable>
            )}
          </View>
        ) : (
          <View style={{ paddingVertical: 64, alignItems: 'center' }}>
            <Text style={{ fontFamily: F.sans, fontSize: 16, color: C.ink2 }}>No quest today.</Text>
            <Text style={{ fontFamily: F.sans, fontSize: 14, color: C.ink3, marginTop: 6 }}>Check back tomorrow.</Text>
          </View>
        )}

        {isAdmin && (
          <View style={{ borderTopWidth: 1, borderTopColor: HAIRLINE, marginTop: 28, paddingTop: 22 }}>
            <Text style={{ fontFamily: F.sansMed, fontSize: 11, color: C.ink3, letterSpacing: 1.2, textTransform: 'uppercase', marginBottom: 14 }}>Set a quest · admin</Text>
            <AdminField label="Date" value={aDate} onChangeText={setADate} placeholder="2026-06-25" autoCapitalize="none" />
            <View style={{ height: 12 }} />
            <AdminField label="Title" value={aTitle} onChangeText={setATitle} placeholder="Walk to the park" />
            <View style={{ height: 12 }} />
            <AdminField label="Description" value={aDesc} onChangeText={setADesc} placeholder="Optional details…" multiline />
            {aMsg && <Text style={{ fontFamily: F.sans, fontSize: 13, color: aMsg.startsWith('Quest saved') ? C.moss700 : C.clay700, marginTop: 12 }}>{aMsg}</Text>}
            <Pressable onPress={saveQuest} disabled={aSaving}
              style={({ pressed }) => ({ marginTop: 14, paddingVertical: 12, borderRadius: 10, backgroundColor: aSaving ? C.paper200 : C.ink, alignItems: 'center', opacity: pressed ? 0.85 : 1 })}>
              <Text style={{ fontFamily: F.sansSemi, fontSize: 14, color: aSaving ? C.ink3 : C.paper }}>{aSaving ? 'Saving…' : 'Save quest'}</Text>
            </Pressable>
          </View>
        )}
      </ScrollView>
    </SafeAreaView>
  )
}

function AdminField({ label, multiline, ...props }: { label: string; multiline?: boolean } & React.ComponentProps<typeof TextInput>) {
  return (
    <View>
      <Text style={{ fontFamily: F.sansMed, fontSize: 11, color: C.ink3, letterSpacing: 1.2, textTransform: 'uppercase', marginBottom: 6 }}>{label}</Text>
      <TextInput
        placeholderTextColor={C.ink3}
        multiline={multiline}
        style={{ minHeight: multiline ? 72 : 46, borderRadius: 8, paddingHorizontal: 13, paddingTop: multiline ? 11 : 0, backgroundColor: C.paper, borderWidth: 1, borderColor: HAIRLINE, fontFamily: F.sans, fontSize: 15, color: C.ink, textAlignVertical: multiline ? 'top' : 'center' }}
        {...props}
      />
    </View>
  )
}
