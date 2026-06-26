import { useEffect, useState } from 'react'
import { Pressable, ScrollView, Text, View } from 'react-native'
import { SafeAreaView } from 'react-native-safe-area-context'
import { useRouter } from 'expo-router'
import * as Haptics from 'expo-haptics'
import type { ClubView, Trail } from '@hygge/core'
import { api } from '../lib/api'
import { INTERESTS, getInterests, setInterests, isOnboarded, setOnboarded, matchesInterests } from '../lib/interests'
import { C, F, HAIRLINE } from '../theme'

type Step = 'hello' | 'interests' | 'suggest'

export default function Onboarding() {
  const router = useRouter()
  const [step, setStep] = useState<Step>('hello')
  const [selected, setSelected] = useState<string[]>([])
  const [clubs, setClubs] = useState<ClubView[]>([])
  const [trails, setTrails] = useState<Trail[]>([])

  useEffect(() => {
    (async () => {
      // Re-entry from "Edit interests" (already onboarded): skip the hello step, prefill.
      if (await isOnboarded()) {
        setSelected(await getInterests())
        setStep('interests')
      }
      const [c, t] = await Promise.all([api.getApprovedClubs(), api.getTrails()])
      setClubs(c)
      setTrails(t)
    })()
  }, [])

  const toggle = (id: string) => {
    Haptics.selectionAsync()
    setSelected((s) => (s.includes(id) ? s.filter((x) => x !== id) : [...s, id]))
  }

  const finish = async () => {
    await setInterests(selected)
    await setOnboarded()
    Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success)
    router.replace('/(tabs)')
  }

  const skip = async () => {
    await setOnboarded()
    router.replace('/(tabs)')
  }

  const suggestedClubs = clubs.filter((c) =>
    matchesInterests(`${c.name} ${c.host ?? ''} ${c.vibe ?? ''} ${c.schedule ?? ''} ${c.description ?? ''}`, selected))
  const suggestedTrails = trails.filter((t) =>
    matchesInterests(`${t.title} ${t.location ?? ''} ${t.description ?? ''}`, selected, true))
  const nothingMatched = suggestedClubs.length === 0 && suggestedTrails.length === 0

  return (
    <SafeAreaView style={{ flex: 1, backgroundColor: C.paper }}>
      <ScrollView contentContainerStyle={{ flexGrow: 1, paddingHorizontal: 24, paddingTop: 28, paddingBottom: 36 }}>
        {step === 'hello' && (
          <View style={{ flex: 1, justifyContent: 'center' }}>
            <Text style={{ fontFamily: F.sansMed, fontSize: 12, color: C.ink3, letterSpacing: 1.8, textTransform: 'uppercase', marginBottom: 10 }}>Welcome</Text>
            <Text style={{ fontFamily: F.display, fontSize: 34, color: C.ink, lineHeight: 40, marginBottom: 14 }}>
              One calm place for everything happening in St. Joe.
            </Text>
            <Text style={{ fontFamily: F.sans, fontSize: 16, color: C.ink2, lineHeight: 24, marginBottom: 36 }}>
              Tell us what you're into and we'll point you to a few clubs and trails to start with. Takes ten seconds.
            </Text>
            <Pressable onPress={() => { Haptics.selectionAsync(); setStep('interests') }}
              style={({ pressed }) => ({ paddingVertical: 16, borderRadius: 14, backgroundColor: C.moss700, alignItems: 'center', opacity: pressed ? 0.9 : 1 })}>
              <Text style={{ fontFamily: F.sansSemi, fontSize: 16, color: C.paper }}>Get started</Text>
            </Pressable>
            <Pressable onPress={skip} style={{ paddingVertical: 14, alignItems: 'center' }}>
              <Text style={{ fontFamily: F.sansMed, fontSize: 14, color: C.ink3 }}>Skip for now</Text>
            </Pressable>
          </View>
        )}

        {step === 'interests' && (
          <View style={{ flex: 1 }}>
            <Text style={{ fontFamily: F.display, fontSize: 28, color: C.ink, marginBottom: 6 }}>What are you into?</Text>
            <Text style={{ fontFamily: F.sans, fontSize: 15, color: C.ink2, marginBottom: 22 }}>Pick a few — we'll suggest matches.</Text>
            <View style={{ flexDirection: 'row', flexWrap: 'wrap', gap: 10 }}>
              {INTERESTS.map((it) => {
                const on = selected.includes(it.id)
                return (
                  <Pressable key={it.id} onPress={() => toggle(it.id)}
                    style={({ pressed }) => ({
                      paddingHorizontal: 16, paddingVertical: 11, borderRadius: 22,
                      borderWidth: 1.5, borderColor: on ? 'transparent' : 'rgba(0,0,0,0.14)',
                      backgroundColor: on ? C.moss700 : 'transparent', opacity: pressed ? 0.85 : 1,
                    })}>
                    <Text style={{ fontFamily: F.sansMed, fontSize: 14, color: on ? C.paper : C.ink2 }}>{it.label}</Text>
                  </Pressable>
                )
              })}
            </View>
            <View style={{ flex: 1 }} />
            <Pressable onPress={() => { Haptics.selectionAsync(); setStep('suggest') }} disabled={selected.length === 0}
              style={({ pressed }) => ({ marginTop: 28, paddingVertical: 16, borderRadius: 14, backgroundColor: selected.length === 0 ? C.paper200 : C.moss700, alignItems: 'center', opacity: pressed ? 0.9 : 1 })}>
              <Text style={{ fontFamily: F.sansSemi, fontSize: 16, color: selected.length === 0 ? C.ink3 : C.paper }}>Continue</Text>
            </Pressable>
            <Pressable onPress={skip} style={{ paddingVertical: 14, alignItems: 'center' }}>
              <Text style={{ fontFamily: F.sansMed, fontSize: 14, color: C.ink3 }}>Skip for now</Text>
            </Pressable>
          </View>
        )}

        {step === 'suggest' && (
          <View style={{ flex: 1 }}>
            <Text style={{ fontFamily: F.display, fontSize: 28, color: C.ink, marginBottom: 6 }}>A few to check out</Text>
            <Text style={{ fontFamily: F.sans, fontSize: 15, color: C.ink2, marginBottom: 22 }}>Based on what you picked.</Text>

            {nothingMatched ? (
              <View style={{ borderRadius: 16, borderWidth: 1.5, borderStyle: 'dashed', borderColor: 'rgba(0,0,0,0.13)', padding: 20 }}>
                <Text style={{ fontFamily: F.sans, fontSize: 14, color: C.ink2, lineHeight: 21 }}>
                  Nothing matches just yet — more neighbors are adding clubs and trails every week. We'll keep an eye out for you.
                </Text>
              </View>
            ) : (
              <View style={{ gap: 12 }}>
                {suggestedClubs.map((c) => (
                  <View key={c.id} style={{ borderRadius: 16, backgroundColor: C.paper100, borderWidth: 1, borderColor: HAIRLINE, padding: 16 }}>
                    <Text style={{ fontFamily: F.mono, fontSize: 10, color: C.ink3, letterSpacing: 1, textTransform: 'uppercase', marginBottom: 4 }}>Club</Text>
                    <Text style={{ fontFamily: F.sansBold, fontSize: 17, color: C.ink, letterSpacing: -0.2 }}>{c.name}</Text>
                    {!!c.vibe && <Text style={{ fontFamily: F.sans, fontSize: 13, color: C.ink2, marginTop: 4, lineHeight: 18 }}>{c.vibe}</Text>}
                  </View>
                ))}
                {suggestedTrails.map((t) => {
                  const meta = [t.location, t.length, t.difficulty].filter(Boolean).join(' · ')
                  return (
                    <View key={t.id} style={{ borderRadius: 16, backgroundColor: C.paper100, borderWidth: 1, borderColor: HAIRLINE, padding: 16 }}>
                      <Text style={{ fontFamily: F.mono, fontSize: 10, color: C.ink3, letterSpacing: 1, textTransform: 'uppercase', marginBottom: 4 }}>Trail</Text>
                      <Text style={{ fontFamily: F.sansBold, fontSize: 17, color: C.ink, letterSpacing: -0.2 }}>{t.title}</Text>
                      {!!meta && <Text style={{ fontFamily: F.mono, fontSize: 12, color: C.ink3, marginTop: 6 }}>{meta}</Text>}
                    </View>
                  )
                })}
              </View>
            )}

            <View style={{ flex: 1 }} />
            <Pressable onPress={finish}
              style={({ pressed }) => ({ marginTop: 28, paddingVertical: 16, borderRadius: 14, backgroundColor: C.moss700, alignItems: 'center', opacity: pressed ? 0.9 : 1 })}>
              <Text style={{ fontFamily: F.sansSemi, fontSize: 16, color: C.paper }}>Take me in</Text>
            </Pressable>
          </View>
        )}
      </ScrollView>
    </SafeAreaView>
  )
}
