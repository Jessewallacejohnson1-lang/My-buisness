import { useState } from 'react'
import { KeyboardAvoidingView, Platform, Pressable, ScrollView, Text, TextInput, View } from 'react-native'
import { SafeAreaView } from 'react-native-safe-area-context'
import Animated, { FadeIn, FadeInDown, useReducedMotion } from 'react-native-reanimated'
import { Image } from 'expo-image'
import * as ImagePicker from 'expo-image-picker'
import { useRouter } from 'expo-router'
import * as Haptics from 'expo-haptics'
import { localDate } from '@hygge/core'
import { api } from '../../lib/api'
import { supabase } from '../../lib/supabase'
import { uploadEventImage } from '../../lib/uploadImage'
import { PlusIcon, CloseIcon, EventIcon, ClubIcon, TrailIcon, ChevronRightIcon, BackIcon } from '../../components/icons'
import { C, F, HAIRLINE } from '../../theme'

type PostKind = 'event' | 'club' | 'trail'
type Phase = 'choose' | 'form'

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

// The one decision the chooser asks for. Voice is a neighbor, not a brand.
const KINDS: { id: PostKind; title: string; sub: string; Icon: typeof EventIcon; heading: string }[] = [
  { id: 'event', title: 'Event', sub: 'A one-time happening', Icon: EventIcon, heading: 'Add an event' },
  { id: 'club', title: 'Club', sub: 'A group that meets regularly', Icon: ClubIcon, heading: 'Start a club' },
  { id: 'trail', title: 'Trail', sub: 'A walk or ride worth sharing', Icon: TrailIcon, heading: 'Add a trail' },
]

export default function Add({ initialPhase = 'choose', initialKind = 'event' }: { initialPhase?: Phase; initialKind?: PostKind } = {}) {
  const router = useRouter()
  const reduce = useReducedMotion()
  const [phase, setPhase] = useState<Phase>(initialPhase)
  const [kind, setKind] = useState<PostKind>(initialKind)
  const [form, setForm] = useState<FormState>(EMPTY_FORM)
  const [photo, setPhoto] = useState<string | null>(null)
  const [submitting, setSubmitting] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [notice, setNotice] = useState<string | null>(null)

  const set = (field: keyof FormState) => (v: string) => { setNotice(null); return setForm((f) => ({ ...f, [field]: v })) }

  const resetForm = () => {
    setForm({ ...EMPTY_FORM, event_date: localDate() })
    setPhoto(null)
    setError(null)
  }

  const openKind = (k: PostKind) => {
    Haptics.selectionAsync()
    setKind(k)
    setError(null)
    setNotice(null)
    setPhase('form')
  }

  const backToChoose = () => {
    Haptics.selectionAsync()
    setError(null)
    setPhase('choose')
  }

  const pickPhoto = async () => {
    const res = await ImagePicker.launchImageLibraryAsync({
      mediaTypes: ImagePicker.MediaTypeOptions.Images,
      allowsEditing: true,
      aspect: [4, 3],
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
      if (status === 'pending') {
        resetForm()
        setPhase('choose')
        setNotice('Thanks! Your post is waiting for review before it shows up.')
      } else {
        resetForm()
        setPhase('choose')
        router.replace(kind === 'event' ? '/(tabs)' : '/(tabs)/activities')
      }
    } catch {
      setError('Could not post — try again.')
    } finally {
      setSubmitting(false)
    }
  }

  const active = KINDS.find((k) => k.id === kind)!

  return (
    <SafeAreaView edges={['top']} style={{ flex: 1, backgroundColor: C.paper }}>
      <KeyboardAvoidingView behavior={Platform.OS === 'ios' ? 'padding' : undefined} style={{ flex: 1 }}>
        {phase === 'choose' ? (
          /* ── Phase 1 · Chooser ───────────────────────────────── */
          <ScrollView contentContainerStyle={{ paddingHorizontal: 18, paddingTop: 22, paddingBottom: 140 }} keyboardShouldPersistTaps="handled">
            <Text style={{ fontFamily: F.sansMed, fontSize: 11, color: C.ink3, letterSpacing: 1.8, textTransform: 'uppercase', marginBottom: 4 }}>New</Text>
            <Text style={{ fontFamily: F.display, fontSize: 27, color: C.ink, lineHeight: 33 }}>What would you like to add?</Text>
            <Text style={{ fontFamily: F.sans, fontSize: 14, color: C.ink2, marginTop: 6, marginBottom: 24, lineHeight: 20 }}>Share something happening around St. Joe.</Text>

            {notice && (
              <Animated.View entering={reduce ? undefined : FadeIn.duration(260)} style={{ backgroundColor: C.paper100, borderRadius: 12, borderWidth: 1, borderColor: HAIRLINE, padding: 14, marginBottom: 18 }}>
                <Text style={{ fontFamily: F.sans, fontSize: 13.5, color: C.ink2, lineHeight: 20 }}>{notice}</Text>
              </Animated.View>
            )}

            {KINDS.map((k, i) => (
              <Animated.View key={k.id} entering={reduce ? undefined : FadeInDown.delay(i * 60).duration(360)}>
                <Pressable onPress={() => openKind(k.id)}
                  style={({ pressed }) => ({
                    flexDirection: 'row', alignItems: 'center', gap: 14,
                    paddingVertical: 16, paddingHorizontal: 16, marginBottom: 12,
                    borderRadius: 16, borderWidth: 1, borderColor: HAIRLINE,
                    backgroundColor: C.paper,
                    transform: [{ scale: pressed ? 0.985 : 1 }],
                    opacity: pressed ? 0.92 : 1,
                  })}>
                  <View style={{ width: 52, height: 52, borderRadius: 14, backgroundColor: C.paper100, alignItems: 'center', justifyContent: 'center' }}>
                    <k.Icon size={26} color={C.moss700} />
                  </View>
                  <View style={{ flex: 1 }}>
                    <Text style={{ fontFamily: F.sansSemi, fontSize: 17, color: C.ink, marginBottom: 2 }}>{k.title}</Text>
                    <Text style={{ fontFamily: F.sans, fontSize: 13.5, color: C.ink2 }}>{k.sub}</Text>
                  </View>
                  <ChevronRightIcon size={18} color={C.ink3} />
                </Pressable>
              </Animated.View>
            ))}
          </ScrollView>
        ) : (
          /* ── Phase 2 · Clean form ────────────────────────────── */
          <Animated.View key={kind} entering={reduce ? undefined : FadeIn.duration(240)} style={{ flex: 1 }}>
            <ScrollView contentContainerStyle={{ paddingHorizontal: 18, paddingTop: 12, paddingBottom: 140 }} keyboardShouldPersistTaps="handled">
              <Pressable onPress={backToChoose} hitSlop={10} style={({ pressed }) => ({ flexDirection: 'row', alignItems: 'center', gap: 8, alignSelf: 'flex-start', paddingVertical: 6, opacity: pressed ? 0.6 : 1 })}>
                <BackIcon size={20} color={C.ink2} />
                <Text style={{ fontFamily: F.sansMed, fontSize: 13, color: C.ink2 }}>{active.title}</Text>
              </Pressable>
              <Text style={{ fontFamily: F.display, fontSize: 25, color: C.ink, marginTop: 4, marginBottom: 18 }}>{active.heading}</Text>

              {/* Photo — leads the form, Marketplace-style. Optional. */}
              <PhotoZone photo={photo} onPick={pickPhoto} onClear={() => setPhoto(null)} />

              {/* Title — always first field */}
              <View style={{ marginTop: 18 }}>
                <Field label="Title" value={form.title} onChangeText={set('title')} placeholder={
                  kind === 'event' ? 'Saturday Farmers Market' :
                  kind === 'club' ? 'Tuesday Trail Walkers' :
                  'Millstream Trail'
                } />
              </View>

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
                    <Field label="About · optional" value={form.description} onChangeText={set('description')} placeholder="What the club is, who it's for…" multiline />
                  </View>
                  <View style={{ marginTop: 16 }}>
                    <Field label="What to expect / bring · optional" value={form.expectations} onChangeText={set('expectations')} placeholder="Good shoes, water, ~3 miles at a chatty pace" multiline />
                  </View>
                </>
              )}

              {/* Trail fields */}
              {kind === 'trail' && (
                <>
                  <View style={{ marginTop: 16 }}><Field label="Location / trailhead" value={form.location} onChangeText={set('location')} placeholder="Millstream Park, St. Joseph, MN" /></View>
                  <View style={{ flexDirection: 'row', gap: 12, marginTop: 16 }}>
                    <View style={{ flex: 1 }}><Field label="Length · optional" value={form.length} onChangeText={set('length')} placeholder="3.2 mi" /></View>
                    <View style={{ flex: 1 }}><Field label="Difficulty · optional" value={form.difficulty} onChangeText={set('difficulty')} placeholder="Easy" /></View>
                  </View>
                  <View style={{ marginTop: 16 }}>
                    <Field label="Description · optional" value={form.description} onChangeText={set('description')} placeholder="What the trail is like, highlights…" multiline />
                  </View>
                </>
              )}

              {error && <Text style={{ fontFamily: F.sans, fontSize: 13, color: C.clay700, marginTop: 14 }}>{error}</Text>}

              <Pressable onPress={submit} disabled={submitting}
                style={({ pressed }) => ({ marginTop: 24, paddingVertical: 15, borderRadius: 12, backgroundColor: submitting ? C.paper200 : C.moss700, alignItems: 'center', opacity: pressed ? 0.85 : 1 })}>
                <Text style={{ fontFamily: F.sansSemi, fontSize: 15, color: submitting ? C.ink3 : C.paper }}>{submitting ? 'Posting…' : 'Post'}</Text>
              </Pressable>
            </ScrollView>
          </Animated.View>
        )}
      </KeyboardAvoidingView>
    </SafeAreaView>
  )
}

/** Full-width photo add zone — leads the form. */
function PhotoZone({ photo, onPick, onClear }: { photo: string | null; onPick: () => void; onClear: () => void }) {
  if (photo) {
    return (
      <View style={{ width: '100%', height: 190, borderRadius: 16, overflow: 'hidden', borderWidth: 1, borderColor: HAIRLINE }}>
        <Image source={{ uri: photo }} style={{ flex: 1 }} contentFit="cover" />
        <Pressable onPress={onClear} style={{ position: 'absolute', top: 8, right: 8, width: 28, height: 28, borderRadius: 14, backgroundColor: 'rgba(0,0,0,0.5)', alignItems: 'center', justifyContent: 'center' }}>
          <CloseIcon size={15} color="#fff" />
        </Pressable>
        <Pressable onPress={onPick} style={{ position: 'absolute', bottom: 0, left: 0, right: 0, paddingVertical: 9, backgroundColor: 'rgba(0,0,0,0.42)', alignItems: 'center' }}>
          <Text style={{ fontFamily: F.sansMed, fontSize: 12.5, color: '#fff' }}>Change photo</Text>
        </Pressable>
      </View>
    )
  }
  return (
    <Pressable onPress={onPick}
      style={({ pressed }) => ({ width: '100%', height: 150, borderRadius: 16, borderWidth: 1.5, borderColor: 'rgba(0,0,0,0.14)', borderStyle: 'dashed', backgroundColor: C.paper100, alignItems: 'center', justifyContent: 'center', gap: 9, opacity: pressed ? 0.85 : 1 })}>
      <View style={{ width: 38, height: 38, borderRadius: 11, backgroundColor: C.paper, alignItems: 'center', justifyContent: 'center' }}>
        <PlusIcon size={17} />
      </View>
      <Text style={{ fontFamily: F.sansMed, fontSize: 14, color: C.ink2 }}>Add a photo</Text>
      <Text style={{ fontFamily: F.sans, fontSize: 12, color: C.ink3 }}>Optional</Text>
    </Pressable>
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
