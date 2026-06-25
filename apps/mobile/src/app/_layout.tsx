import '../global.css'
import { useEffect } from 'react'
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

  useEffect(() => {
    if (loading) return
    const inTabs = segments[0] === '(tabs)'
    if (!session && inTabs) router.replace('/login')
    else if (session && !inTabs) router.replace('/(tabs)')
  }, [session, loading, segments, router])

  return (
    <Stack screenOptions={{ headerShown: false, contentStyle: { backgroundColor: C.paper } }}>
      <Stack.Screen name="(tabs)" />
      <Stack.Screen name="login" />
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
