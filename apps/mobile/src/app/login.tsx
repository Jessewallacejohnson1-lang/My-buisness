import { useState } from 'react'
import {
  ActivityIndicator, KeyboardAvoidingView, Platform, Pressable,
  ScrollView, Text, TextInput, View,
} from 'react-native'
import { SafeAreaView } from 'react-native-safe-area-context'
import { useRouter } from 'expo-router'
import { useAuth } from '../lib/auth'
import { C, F } from '../theme'

export default function Login() {
  const router = useRouter()
  const { signIn, signUp } = useAuth()
  const [mode, setMode] = useState<'in' | 'up'>('in')
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [busy, setBusy] = useState(false)
  const [msg, setMsg] = useState<string | null>(null)
  const [ok, setOk] = useState(false) // green (success) vs red (error) message

  const submit = async () => {
    setMsg(null); setOk(false)
    if (!email.trim() || !password) {
      setMsg('Enter your email and password first.')
      return
    }
    setBusy(true)
    if (mode === 'in') {
      const { error } = await signIn(email.trim(), password)
      if (error) setMsg(error)
      else router.replace('/(tabs)')
    } else {
      const { error, needsConfirm } = await signUp(email.trim(), password)
      if (error) setMsg(error)
      else if (needsConfirm) {
        setMode('in'); setOk(true)
        setMsg('Account created! Check your email to confirm, then log in.')
      } else {
        router.replace('/(tabs)')
      }
    }
    setBusy(false)
  }

  return (
    <SafeAreaView className="flex-1 bg-paper">
      <KeyboardAvoidingView behavior={Platform.OS === 'ios' ? 'padding' : undefined} className="flex-1">
        <ScrollView
          contentContainerStyle={{ flexGrow: 1, justifyContent: 'center', paddingHorizontal: 28 }}
          keyboardShouldPersistTaps="handled"
          showsVerticalScrollIndicator={false}
        >
          {/* Wordmark */}
          <View className="mb-8 flex-row items-center gap-3">
            <View className="h-9 w-9 items-center justify-center rounded-[10px] bg-moss-700">
              <Text style={{ fontFamily: F.displaySemi, color: C.paper, fontSize: 20 }}>H</Text>
            </View>
            <Text style={{ fontFamily: F.sansBold, fontSize: 30, color: C.ink, letterSpacing: -0.5 }}>Joetown</Text>
          </View>

          {/* Mode toggle — Log in / Sign up */}
          <View style={{ flexDirection: 'row', backgroundColor: C.paper100, borderRadius: 12, padding: 4, marginBottom: 20 }}>
            {(['in', 'up'] as const).map((m) => {
              const active = mode === m
              return (
                <Pressable key={m} onPress={() => { setMode(m); setMsg(null) }}
                  style={{ flex: 1, paddingVertical: 10, borderRadius: 9, backgroundColor: active ? C.paper : 'transparent', alignItems: 'center' }}>
                  <Text style={{ fontFamily: active ? F.sansSemi : F.sansMed, fontSize: 14, color: active ? C.ink : C.ink2 }}>
                    {m === 'in' ? 'Log in' : 'Sign up'}
                  </Text>
                </Pressable>
              )
            })}
          </View>

          <Field label="Email" value={email} onChangeText={setEmail}
            autoCapitalize="none" autoCorrect={false} keyboardType="email-address" textContentType="emailAddress" placeholder="you@email.com" />
          <View className="h-3" />
          <Field label="Password" value={password} onChangeText={setPassword}
            secureTextEntry textContentType="password" placeholder="••••••••" />

          {msg && (
            <Text style={{ fontFamily: F.sans, fontSize: 13, color: ok ? C.moss700 : C.clay700, marginTop: 14, lineHeight: 18 }}>{msg}</Text>
          )}

          {/* Primary action — label matches the mode */}
          <Pressable
            onPress={submit}
            disabled={busy}
            style={({ pressed }) => ({
              marginTop: 20, height: 54, borderRadius: 14, backgroundColor: C.moss700,
              alignItems: 'center', justifyContent: 'center', opacity: busy ? 0.6 : pressed ? 0.85 : 1,
            })}
          >
            {busy ? <ActivityIndicator color={C.paper} />
              : <Text style={{ fontFamily: F.sansSemi, fontSize: 16, color: C.paper }}>
                  {mode === 'in' ? 'Log in' : 'Create account'}
                </Text>}
          </Pressable>
        </ScrollView>
      </KeyboardAvoidingView>
    </SafeAreaView>
  )
}

function Field({ label, ...props }: { label: string } & React.ComponentProps<typeof TextInput>) {
  return (
    <View>
      <Text style={{ fontFamily: F.sansMed, fontSize: 12, color: C.ink2, marginBottom: 6 }}>{label}</Text>
      <TextInput
        placeholderTextColor={C.ink3}
        style={{
          height: 50, borderRadius: 12, paddingHorizontal: 14,
          backgroundColor: C.paper100, borderWidth: 1, borderColor: C.hairline,
          fontFamily: F.sans, fontSize: 16, color: C.ink,
        }}
        {...props}
      />
    </View>
  )
}
