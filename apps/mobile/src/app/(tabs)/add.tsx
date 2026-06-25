import { useState } from 'react'
import { KeyboardAvoidingView, Platform, Pressable, ScrollView, Text, TextInput, View } from 'react-native'
import { SafeAreaView } from 'react-native-safe-area-context'
import { Image } from 'expo-image'
import * as ImagePicker from 'expo-image-picker'
import { useRouter } from 'expo-router'
import * as Haptics from 'expo-haptics'
import { localDate, type NewEventInput } from '@hygge/core'
import { api } from '../../lib/api'
import { uploadEventImage } from '../../lib/uploadImage'
import { PlusIcon, CloseIcon } from '../../components/icons'
import { C, F, HAIRLINE } from '../../theme'

export default function Add() {
  const router = useRouter()
  const [form, setForm] = useState<NewEventInput>({ title: '', event_date: localDate(), start_time: '', location: '', description: '' })
  const [photo, setPhoto] = useState<string | null>(null)
  const [submitting, setSubmitting] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const set = (field: keyof NewEventInput) => (v: string) => setForm((f) => ({ ...f, [field]: v }))

  const pickPhoto = async () => {
    const res = await ImagePicker.launchImageLibraryAsync({
      mediaTypes: ImagePicker.MediaTypeOptions.Images,
      allowsEditing: true,
      aspect: [1, 1],
      quality: 0.7,
    })
    if (!res.canceled && res.assets[0]) setPhoto(res.assets[0].uri)
  }

  const submit = async () => {
    if (!form.title.trim() || !form.event_date || !form.start_time.trim() || !form.location.trim()) {
      setError('Add a title, date, time, and location.')
      return
    }
    setError(null); setSubmitting(true)
    try {
      const image_url = photo ? (await uploadEventImage(photo)) ?? undefined : undefined
      await api.addEvent({ ...form, title: form.title.trim(), location: form.location.trim(), image_url })
      Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success)
      setForm({ title: '', event_date: localDate(), start_time: '', location: '', description: '' })
      setPhoto(null)
      router.replace('/(tabs)')
    } catch {
      setError('Could not add the event — try again.')
    } finally {
      setSubmitting(false)
    }
  }

  return (
    <SafeAreaView edges={['top']} style={{ flex: 1, backgroundColor: C.paper }}>
      <KeyboardAvoidingView behavior={Platform.OS === 'ios' ? 'padding' : undefined} style={{ flex: 1 }}>
        <ScrollView contentContainerStyle={{ paddingHorizontal: 18, paddingTop: 18, paddingBottom: 140 }} keyboardShouldPersistTaps="handled">
          <Text style={{ fontFamily: F.sansMed, fontSize: 11, color: C.ink3, letterSpacing: 1.8, textTransform: 'uppercase', marginBottom: 3 }}>New</Text>
          <Text style={{ fontFamily: F.display, fontSize: 24, color: C.ink, marginBottom: 22 }}>Add an event</Text>

          <Field label="Title" value={form.title} onChangeText={set('title')} placeholder="Saturday Farmers Market" />
          <View style={{ flexDirection: 'row', gap: 12, marginTop: 16 }}>
            <View style={{ flex: 1 }}><Field label="Date" value={form.event_date} onChangeText={set('event_date')} placeholder="2026-06-25" autoCapitalize="none" /></View>
            <View style={{ flex: 1 }}><Field label="Time" value={form.start_time} onChangeText={set('start_time')} placeholder="7am" /></View>
          </View>
          <View style={{ marginTop: 16 }}><Field label="Location · opens in Maps" value={form.location} onChangeText={set('location')} placeholder="Place or full address, St. Joseph, MN" /></View>
          <View style={{ marginTop: 16 }}>
            <Field label="Description · optional" value={form.description ?? ''} onChangeText={set('description')} placeholder="Tell people what to expect…" multiline />
          </View>

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
            <Text style={{ fontFamily: F.sansSemi, fontSize: 15, color: submitting ? C.ink3 : C.paper }}>{submitting ? 'Adding…' : 'Add event'}</Text>
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
