import { useState } from 'react'
import { KeyboardAvoidingView, Platform, Pressable, ScrollView, Text, TextInput, View } from 'react-native'
import { SafeAreaView } from 'react-native-safe-area-context'
import { Image } from 'expo-image'
import * as ImagePicker from 'expo-image-picker'
import { useRouter } from 'expo-router'
import * as Haptics from 'expo-haptics'
import { localDate, type ClubInput, type NewEventInput, type NewTrailInput } from '@hygge/core'
import { api } from '../../lib/api'
import { supabase } from '../../lib/supabase'
import { uploadEventImage } from '../../lib/uploadImage'
import { PlusIcon, CloseIcon } from '../../components/icons'
import { C, F, HAIRLINE } from '../../theme'

type PostKind = 'event' | 'club' | 'trail'

type FormState = {
  // shared
  title: string
  location: string
  description: string
  // event
  event_date: string
  start_time: string
  // trail
  length: string
  difficulty: string
  // club
  host: string
  schedule: string
  vibe: string
  expectations: string
}

const EMPTY_FORM: FormState = {
  title: '',
  location: '',
  description: '',
  event_date: localDate(),
  start_time: '',
  length: '',
  difficulty: '',
  host: '',
  schedule: '',
  vibe: '',
  expectations: '',
}

export default function Add() {
  const router = useRouter()
  const [kind, setKind] = useState<PostKind>('event')
  const [form, setForm] = useState<FormState>(EMPTY_FORM)
  const [photo, setPhoto] = useState<string | null>(null)
  const [submitting, setSubmitting] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const set = (field: keyof FormState) => (v: string) => setForm((f) => ({ ...f, [field]: v }))

  const resetForm = () => {
    setForm({ ...EMPTY_FORM, event_date: localDate() })
    setPhoto(null)
    setError(null)
  }

  const pickPhoto = async () => {
    const res = await ImagePicker.launchImageLibraryAsync({
      mediaTypes: ImagePicker.MediaTypeOptions.Images,
      allowsEditing: true,
      aspect: [1, 1],
      quality: 0.7,
    })
    if (!res.canceled && res.assets[0]) setPhoto(res.assets[0].uri)
  }

  const validate = (): string | null => {
    if (!form.title.trim()) return 'Add a title.'
    if (kind === 'event') {
      if (!form.event_date || !form.start_time.trim() || !form.location.trim()) {
        return 'Add a title, date, time, and location.'
      }
    } else if (kind === 'trail') {
      if (!form.location.trim()) return 'Add a title and trailhead location.'
    } else if (kind === 'club') {
      if (!form.host.trim()) return 'Add a title and host name.'
    }
    return null
  }

  const submit = async () => {
    const v = validate()
    if (v) { setError(v); return }
    setError(null); setSubmitting(true)
    try {
      const image_url = photo ? (await uploadEventImage(photo)) ?? undefined : undefined
      // Run Claude moderation (fail-closed → pending).
      let pending = false
      try {
        const { data, error: modErr } = await supabase.functions.invoke('moderate-post', {
          body: { kind, title: form.title.trim(), location: form.location?.trim(), description: form.description?.trim(), length: form.length?.trim(), image_url },
        })
        if (modErr || !data) pending = true
        else if (!data.ok) {
          setError(data.reason || "That didn't pass review — tweak it and try again.")
          Haptics.notificationAsync(Haptics.NotificationFeedbackType.Warning)
          setSubmitting(false); return
        }
      } catch { pending = true }
      const status = pending ? 'pending' : 'approved'

      if (kind === 'event') {
        await api.addEvent({ title: form.title.trim(), event_date: form.event_date, start_time: form.start_time.trim(), location: form.location.trim(), description: form.description, image_url }, null, status)
      } else if (kind === 'trail') {
        await api.addTrail({ title: form.title.trim(), location: form.location.trim(), length: form.length, difficulty: form.difficulty, description: form.description, image_url }, status)
      } else {
        // club → existing clubs system (submitClub already sets pending for non-admins;
        // pass the moderation result through where the API allows). Reuse submitClub.
        await api.submitClub({ name: form.title.trim(), host: form.host, schedule: form.schedule, location: form.location, vibe: form.vibe, description: form.description, expectations: form.expectations })
      }
      Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success)
      resetForm()
      router.replace(kind === 'event' ? '/(tabs)' : '/(tabs)/activities')
    } catch {
      setError('Could not post — try again.')
    } finally {
      setSubmitting(false)
    }
  }

  return (
    <SafeAreaView edges={['top']} style={{ flex: 1, backgroundColor: C.paper }}>
      <KeyboardAvoidingView behavior={Platform.OS === 'ios' ? 'padding' : undefined} style={{ flex: 1 }}>
        <ScrollView contentContainerStyle={{ paddingHorizontal: 18, paddingTop: 18, paddingBottom: 140 }} keyboardShouldPersistTaps="handled">
          <Text style={{ fontFamily: F.sansMed, fontSize: 11, color: C.ink3, letterSpacing: 1.8, textTransform: 'uppercase', marginBottom: 3 }}>New</Text>
          <Text style={{ fontFamily: F.display, fontSize: 24, color: C.ink, marginBottom: 18 }}>New post</Text>

          {/* Kind picker */}
          <View style={{ flexDirection: 'row', gap: 8, marginBottom: 22 }}>
            {(['event', 'club', 'trail'] as PostKind[]).map((k) => {
              const active = kind === k
              return (
                <Pressable key={k} onPress={() => { Haptics.selectionAsync(); setKind(k); setError(null) }}
                  style={({ pressed }) => ({
                    paddingHorizontal: 16, paddingVertical: 8, borderRadius: 20,
                    borderWidth: 1.5,
                    borderColor: active ? 'transparent' : 'rgba(0,0,0,0.14)',
                    backgroundColor: active ? C.moss700 : C.paper100,
                    opacity: pressed ? 0.85 : 1,
                  })}>
                  <Text style={{ fontFamily: F.sansMed, fontSize: 13, color: active ? C.paper : C.ink2, textTransform: 'capitalize' }}>{k}</Text>
                </Pressable>
              )
            })}
          </View>

          {/* Title — always shown */}
          <Field label="Title" value={form.title} onChangeText={set('title')} placeholder={
            kind === 'event' ? 'Saturday Farmers Market' :
            kind === 'club' ? 'Tuesday Trail Walkers' :
            'Millstream Trail'
          } />

          {/* Event fields */}
          {kind === 'event' && (
            <>
              <View style={{ flexDirection: 'row', gap: 12, marginTop: 16 }}>
                <View style={{ flex: 1 }}><Field label="Date" value={form.event_date} onChangeText={set('event_date')} placeholder="2026-06-25" autoCapitalize="none" /></View>
                <View style={{ flex: 1 }}><Field label="Time" value={form.start_time} onChangeText={set('start_time')} placeholder="7am" /></View>
              </View>
              <View style={{ marginTop: 16 }}><Field label="Location · opens in Maps" value={form.location} onChangeText={set('location')} placeholder="Place or full address, St. Joseph, MN" /></View>
              <View style={{ marginTop: 16 }}>
                <Field label="Description · optional" value={form.description} onChangeText={set('description')} placeholder="Tell people what to expect…" multiline />
              </View>
            </>
          )}

          {/* Club fields */}
          {kind === 'club' && (
            <>
              <View style={{ marginTop: 16 }}><Field label="Host" value={form.host} onChangeText={set('host')} placeholder="Your name" /></View>
              <View style={{ marginTop: 16 }}><Field label="When" value={form.schedule} onChangeText={set('schedule')} placeholder="Tuesdays, 6pm" /></View>
              <View style={{ marginTop: 16 }}><Field label="Where · opens in Maps" value={form.location} onChangeText={set('location')} placeholder="Place or full address, St. Joseph, MN" /></View>
              <View style={{ marginTop: 16 }}><Field label="Vibe · short" value={form.vibe} onChangeText={set('vibe')} placeholder="Easygoing, all paces welcome" /></View>
              <View style={{ marginTop: 16 }}>
                <Field label="About" value={form.description} onChangeText={set('description')} placeholder="What the club is, who it's for…" multiline />
              </View>
              <View style={{ marginTop: 16 }}>
                <Field label="What to expect / bring" value={form.expectations} onChangeText={set('expectations')} placeholder="Good shoes, water, ~3 miles at a chatty pace" multiline />
              </View>
            </>
          )}

          {/* Trail fields */}
          {kind === 'trail' && (
            <>
              <View style={{ marginTop: 16 }}><Field label="Location / trailhead" value={form.location} onChangeText={set('location')} placeholder="Millstream Park, St. Joseph, MN" /></View>
              <View style={{ flexDirection: 'row', gap: 12, marginTop: 16 }}>
                <View style={{ flex: 1 }}><Field label="Length" value={form.length} onChangeText={set('length')} placeholder="3.2 mi" /></View>
                <View style={{ flex: 1 }}><Field label="Difficulty" value={form.difficulty} onChangeText={set('difficulty')} placeholder="Easy" /></View>
              </View>
              <View style={{ marginTop: 16 }}>
                <Field label="Description · optional" value={form.description} onChangeText={set('description')} placeholder="What the trail is like, highlights…" multiline />
              </View>
            </>
          )}

          {/* Photo upload square */}
          <View style={{ marginTop: 18 }}>
            <Text style={{ fontFamily: F.sansMed, fontSize: 11, color: C.ink3, letterSpacing: 1.2, textTransform: 'uppercase', marginBottom: 8 }}>Photo · optional</Text>
            {photo ? (
              <View style={{ width: 150, height: 150, borderRadius: 14, overflow: 'hidden', borderWidth: 1, borderColor: HAIRLINE }}>
                <Image source={{ uri: photo }} style={{ flex: 1 }} contentFit="cover" />
                <Pressable onPress={() => setPhoto(null)} style={{ position: 'absolute', top: 6, right: 6, width: 26, height: 26, borderRadius: 13, backgroundColor: 'rgba(0,0,0,0.5)', alignItems: 'center', justifyContent: 'center' }}>
                  <CloseIcon size={14} color="#fff" />
                </Pressable>
                <Pressable onPress={pickPhoto} style={{ position: 'absolute', bottom: 0, left: 0, right: 0, paddingVertical: 7, backgroundColor: 'rgba(0,0,0,0.45)', alignItems: 'center' }}>
                  <Text style={{ fontFamily: F.sansMed, fontSize: 12, color: '#fff' }}>Change</Text>
                </Pressable>
              </View>
            ) : (
              <Pressable onPress={pickPhoto}
                style={({ pressed }) => ({ width: 150, height: 150, borderRadius: 14, borderWidth: 1.5, borderColor: 'rgba(0,0,0,0.14)', borderStyle: 'dashed', backgroundColor: C.paper100, alignItems: 'center', justifyContent: 'center', gap: 8, opacity: pressed ? 0.8 : 1 })}>
                <View style={{ width: 34, height: 34, borderRadius: 10, backgroundColor: C.paper, alignItems: 'center', justifyContent: 'center' }}>
                  <PlusIcon size={16} />
                </View>
                <Text style={{ fontFamily: F.sansMed, fontSize: 13, color: C.ink2 }}>Add a photo</Text>
              </Pressable>
            )}
          </View>

          {error && <Text style={{ fontFamily: F.sans, fontSize: 13, color: C.clay700, marginTop: 14 }}>{error}</Text>}

          <Pressable onPress={submit} disabled={submitting}
            style={({ pressed }) => ({ marginTop: 22, paddingVertical: 15, borderRadius: 12, backgroundColor: submitting ? C.paper200 : C.moss700, alignItems: 'center', opacity: pressed ? 0.85 : 1 })}>
            <Text style={{ fontFamily: F.sansSemi, fontSize: 15, color: submitting ? C.ink3 : C.paper }}>{submitting ? 'Posting…' : 'Post'}</Text>
          </Pressable>
        </ScrollView>
      </KeyboardAvoidingView>
    </SafeAreaView>
  )
}

function Field({ label, multiline, ...props }: { label: string; multiline?: boolean } & React.ComponentProps<typeof TextInput>) {
  return (
    <View>
      <Text style={{ fontFamily: F.sansMed, fontSize: 11, color: C.ink3, letterSpacing: 1.2, textTransform: 'uppercase', marginBottom: 6 }}>{label}</Text>
      <TextInput
        placeholderTextColor={C.ink3}
        multiline={multiline}
        style={{ minHeight: multiline ? 84 : 46, borderRadius: 8, paddingHorizontal: 13, paddingTop: multiline ? 11 : 0, backgroundColor: C.paper, borderWidth: 1, borderColor: HAIRLINE, fontFamily: F.sans, fontSize: 15, color: C.ink, textAlignVertical: multiline ? 'top' : 'center' }}
        {...props}
      />
    </View>
  )
}
