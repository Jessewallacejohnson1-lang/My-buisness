import { useEffect, useRef, useState } from 'react'
import { ActivityIndicator, Pressable, Text, TextInput, View } from 'react-native'
import * as Haptics from 'expo-haptics'
import { useReducedMotion } from 'react-native-reanimated'
import { isAdminEmail, localDate, type DailyQuest } from '@hygge/core'
import { api } from '../lib/api'
import { CheckIcon } from './icons'
import { C, F, HAIRLINE, CARD_SHADOW } from '../theme'

// The count-up plays once a session — not every time you return to Home. After
// the first sweep this stays true and the number updates instantly.
let questCounted = false

/** Count up to `target` with an ease-out curve, once per session; instant after. */
function useCountUp(target: number, enabled: boolean, ms = 650) {
  const [n, setN] = useState(target)
  const swept = useRef(false)
  useEffect(() => {
    if (!enabled || target <= 0 || questCounted || swept.current) { setN(target); return }
    swept.current = true; questCounted = true
    const start = Date.now()
    let id: ReturnType<typeof setTimeout>
    const tick = () => {
      const t = Math.min(1, (Date.now() - start) / ms)
      setN(Math.round(target * (1 - Math.pow(1 - t, 3))))
      if (t < 1) id = setTimeout(tick, 16)
    }
    tick()
    return () => clearTimeout(id)
  }, [target, enabled, ms])
  return n
}

/** Quest UI embedded in the Home ScrollView — no SafeAreaView/ScrollView wrapper. */
export function QuestSection() {
  const [quest, setQuest_] = useState<DailyQuest | null>(null)
  const [count, setCount] = useState(0)
  const [done, setDone] = useState(false)
  const [loading, setLoading] = useState(true)
  const [completing, setCompleting] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [isAdmin, setIsAdmin] = useState(false)
  // admin form
  const [aTitle, setATitle] = useState('')
  const [aDesc, setADesc] = useState('')
  const [aDate, setADate] = useState(localDate())
  const [aSaving, setASaving] = useState(false)
  const [aMsg, setAMsg] = useState<string | null>(null)
  const [showForm, setShowForm] = useState(false)
  const reduce = useReducedMotion()
  const shownCount = useCountUp(count, !reduce)

  useEffect(() => {
    (async () => {
      try {
        const [q, user] = await Promise.all([api.getTodayQuest(), api.getCurrentUser()])
        setQuest_(q)
        setIsAdmin(isAdminEmail(user?.email))
        if (q) {
          setCount(await api.getQuestCompletionCount(q.id))
          if (user) setDone(await api.hasUserCompletedQuest(q.id, user.id))
        }
      } catch {
        // Leave quest null → falls through to the calm "No quest today" state
        // instead of spinning forever on a failed fetch.
      } finally {
        setLoading(false)
      }
    })()
  }, [])

  const complete = async () => {
    if (!quest || done || completing) return
    setCompleting(true); setError(null)
    setDone(true); setCount((c) => c + 1) // optimistic — feels instant
    try {
      await api.completeQuest(quest.id)
      Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success)
    } catch {
      setDone(false); setCount((c) => Math.max(0, c - 1)) // revert
      setError("Couldn't save — try again.")
      Haptics.notificationAsync(Haptics.NotificationFeedbackType.Warning)
    } finally { setCompleting(false) }
  }

  const saveQuest = async () => {
    if (!aTitle.trim() || !aDate) return
    setASaving(true); setAMsg(null)
    try {
      await api.setQuest(aTitle.trim(), aDesc.trim(), aDate)
      setAMsg('Quest saved.'); setATitle(''); setADesc('')
    } catch { setAMsg('Could not save — try again.') } finally { setASaving(false) }
  }

  return (
    <View style={{ marginHorizontal: 20, marginTop: 28 }}>
      <Text style={{ fontFamily: F.display, fontSize: 24, color: C.ink, letterSpacing: -0.3, marginBottom: 14 }}>Today's quest</Text>

      <View style={{ padding: 16, borderRadius: 20, backgroundColor: C.paper, borderWidth: 1, borderColor: HAIRLINE, ...CARD_SHADOW }}>
        {loading ? (
          <ActivityIndicator color={C.ink3} style={{ alignSelf: 'flex-start' }} />
        ) : quest ? (
          <>
            <View style={{ flexDirection: 'row', alignItems: 'center', gap: 14 }}>
              <View style={{ flex: 1 }}>
                <Text style={{ fontFamily: F.display, fontSize: 18, color: C.ink, lineHeight: 24 }}>{quest.title}</Text>
                <Text style={{ fontFamily: F.mono, fontSize: 12, color: C.ink2, marginTop: 8 }}>
                  {shownCount}<Text style={{ fontFamily: F.sans }}> {count === 1 ? 'neighbor' : 'neighbors'} did this</Text>
                </Text>
              </View>
              {done ? (
                <View style={{ flexDirection: 'row', alignItems: 'center', gap: 6, paddingVertical: 9, paddingHorizontal: 14, borderRadius: 18, borderWidth: 1.5, borderColor: C.moss700 }}>
                  <CheckIcon size={14} color={C.moss700} />
                  <Text style={{ fontFamily: F.sansSemi, fontSize: 13, color: C.moss700 }}>Done</Text>
                </View>
              ) : (
                <Pressable onPress={complete} disabled={completing}
                  style={({ pressed }) => ({ paddingVertical: 11, paddingHorizontal: 18, borderRadius: 18, backgroundColor: C.moss700, opacity: pressed ? 0.85 : 1 })}>
                  <Text style={{ fontFamily: F.sansSemi, fontSize: 13.5, color: C.paper }}>{completing ? '…' : 'Mark done'}</Text>
                </Pressable>
              )}
            </View>
            {error && <Text style={{ fontFamily: F.sans, fontSize: 12.5, color: C.clay700, marginTop: 12 }}>{error}</Text>}
          </>
        ) : (
          <Text style={{ fontFamily: F.sans, fontSize: 15, color: C.ink2, lineHeight: 22 }}>
            No quest today — a fresh one lands tomorrow.
          </Text>
        )}
      </View>

      {isAdmin && (
        showForm ? (
          <View style={{ marginTop: 12, padding: 16, borderRadius: 20, backgroundColor: C.paper, borderWidth: 1, borderColor: HAIRLINE }}>
            <View style={{ flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', marginBottom: 14 }}>
              <Text style={{ fontFamily: F.sansMed, fontSize: 11, color: C.ink3, letterSpacing: 1.2, textTransform: 'uppercase' }}>Set a quest · admin</Text>
              <Pressable onPress={() => setShowForm(false)} hitSlop={10}><Text style={{ fontFamily: F.sansMed, fontSize: 13, color: C.ink3 }}>Close</Text></Pressable>
            </View>
            <AdminField label="Date" value={aDate} onChangeText={setADate} placeholder="2026-06-25" autoCapitalize="none" />
            <View style={{ height: 12 }} />
            <AdminField label="Quest" value={aTitle} onChangeText={setATitle} placeholder="Say hi to one new neighbor." />
            <View style={{ height: 12 }} />
            <AdminField label="Note (optional)" value={aDesc} onChangeText={setADesc} placeholder="A wave on the trail counts." multiline />
            {aMsg && <Text style={{ fontFamily: F.sans, fontSize: 13, color: aMsg.startsWith('Quest saved') ? C.moss700 : C.clay700, marginTop: 12 }}>{aMsg}</Text>}
            <Pressable onPress={saveQuest} disabled={aSaving}
              style={({ pressed }) => ({ marginTop: 14, paddingVertical: 12, borderRadius: 12, backgroundColor: aSaving ? C.paper200 : C.ink, alignItems: 'center', opacity: pressed ? 0.85 : 1 })}>
              <Text style={{ fontFamily: F.sansSemi, fontSize: 14, color: aSaving ? C.ink3 : C.paper }}>{aSaving ? 'Saving…' : 'Save quest'}</Text>
            </Pressable>
          </View>
        ) : (
          <Pressable onPress={() => setShowForm(true)} style={({ pressed }) => ({ alignSelf: 'flex-start', marginTop: 12, opacity: pressed ? 0.6 : 1 })}>
            <Text style={{ fontFamily: F.sansMed, fontSize: 13, color: C.ink3 }}>Set today's quest · admin</Text>
          </Pressable>
        )
      )}
    </View>
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
