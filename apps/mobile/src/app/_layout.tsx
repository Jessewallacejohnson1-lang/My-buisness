import '../global.css'
import { useEffect, useState } from 'react'
import { AppState, View } from 'react-native'
import { Stack, useRouter, useSegments } from 'expo-router'
import { GestureHandlerRootView } from 'react-native-gesture-handler'
import { SafeAreaProvider } from 'react-native-safe-area-context'
import { StatusBar } from 'expo-status-bar'
import * as SplashScreen from 'expo-splash-screen'
import { useFonts } from 'expo-font'
import { AtkinsonHyperlegible_700Bold } from '@expo-google-fonts/atkinson-hyperlegible'

import { AuthProvider, useAuth } from '../lib/auth'
import { supabase } from '../lib/supabase'
import { isOnboarded, isOnboardedSync } from '../lib/interests'
import { C } from '../theme'

SplashScreen.preventAutoHideAsync()

// Keep the Supabase session fresh while the app is foregrounded.
AppState.addEventListener('change', (state) => {
  if (state === 'active') supabase.auth.startAutoRefresh()
  else supabase.auth.stopAutoRefresh()
})

function RootNav() {
  const { session, loading } = useAuth()
  const segments = useSegments()
  const router = useRouter()
  // Bump once the onboarded flag is primed so the gate below re-runs with a real value.
  const [primed, setPrimed] = useState(false)

  useEffect(() => { isOnboarded().then(() => setPrimed(true)) }, [session])

  useEffect(() => {
    if (loading) return
    const onboarded = isOnboardedSync()
    if (onboarded === null) return // not primed yet
    const loc = segments[0]
    // `place` is an authed full-screen route (the Around Town showcase). Treat it
    // as in-app so this gate doesn't bounce it straight back to the tabs.
    const inApp = loc === '(tabs)' || loc === 'onboarding' || loc === 'place'
    if (!session && inApp) router.replace('/login')
    else if (session && !onboarded && loc !== 'onboarding') router.replace('/onboarding')
    else if (session && onboarded && !inApp) router.replace('/(tabs)')
  }, [session, loading, segments, router, primed])

  return (
    <Stack screenOptions={{ headerShown: false, contentStyle: { backgroundColor: C.paper } }}>
      <Stack.Screen name="index" />
      <Stack.Screen name="(tabs)" />
      <Stack.Screen name="login" />
      <Stack.Screen name="onboarding" />
      {/* Full-screen place showcase — crossfades in; the screen drives its own
          scale-bloom entrance, so we keep the native transition a plain fade. */}
      <Stack.Screen name="place/[slug]" options={{ presentation: 'transparentModal', animation: 'fade' }} />
    </Stack>
  )
}

export default function RootLayout() {
  // The app's only bundled font is the logo face (see HyggeLogoBadge). Every
  // other surface uses the platform system font (SF Pro / Roboto), so nothing
  // else needs loading here.
  const [fontsLoaded] = useFonts({ AtkinsonHyperlegible_700Bold })

  useEffect(() => {
    if (fontsLoaded) SplashScreen.hideAsync()
  }, [fontsLoaded])

  if (!fontsLoaded) return <View style={{ flex: 1, backgroundColor: C.paper }} />

  return (
    <GestureHandlerRootView style={{ flex: 1 }}>
      <SafeAreaProvider>
        <StatusBar style="dark" />
        <AuthProvider>
          <RootNav />
        </AuthProvider>
      </SafeAreaProvider>
    </GestureHandlerRootView>
  )
}
