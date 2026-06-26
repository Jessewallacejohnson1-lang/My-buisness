import '../global.css'
import { useEffect, useState } from 'react'
import { AppState, View } from 'react-native'
import { Stack, useRouter, useSegments } from 'expo-router'
import { SafeAreaProvider } from 'react-native-safe-area-context'
import { StatusBar } from 'expo-status-bar'
import * as SplashScreen from 'expo-splash-screen'
import { useFonts } from 'expo-font'
import { Spectral_600SemiBold, Spectral_700Bold } from '@expo-google-fonts/spectral'
import {
  SchibstedGrotesk_400Regular, SchibstedGrotesk_500Medium,
  SchibstedGrotesk_600SemiBold, SchibstedGrotesk_700Bold,
} from '@expo-google-fonts/schibsted-grotesk'
import { GeistMono_400Regular, GeistMono_500Medium } from '@expo-google-fonts/geist-mono'

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
    const inApp = loc === '(tabs)' || loc === 'onboarding'
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
    </Stack>
  )
}

export default function RootLayout() {
  const [fontsLoaded] = useFonts({
    Spectral: Spectral_700Bold,
    SpectralSemi: Spectral_600SemiBold,
    Schibsted: SchibstedGrotesk_400Regular,
    SchibstedMed: SchibstedGrotesk_500Medium,
    SchibstedSemi: SchibstedGrotesk_600SemiBold,
    SchibstedBold: SchibstedGrotesk_700Bold,
    GeistMono: GeistMono_400Regular,
    GeistMonoMed: GeistMono_500Medium,
  })

  useEffect(() => {
    if (fontsLoaded) SplashScreen.hideAsync()
  }, [fontsLoaded])

  if (!fontsLoaded) return <View style={{ flex: 1, backgroundColor: C.paper }} />

  return (
    <SafeAreaProvider>
      <StatusBar style="dark" />
      <AuthProvider>
        <RootNav />
      </AuthProvider>
    </SafeAreaProvider>
  )
}
