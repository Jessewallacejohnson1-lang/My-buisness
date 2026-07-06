import { Pressable, Text, View } from 'react-native'
import { useRouter } from 'expo-router'
import { C, F, HAIRLINE } from '../theme'
import { ScreenBadge } from './ScreenBadge'
import { PinIcon } from './icons'

/** Web fallback — react-native-maps is native-only, so the website points
 *  people at the calendar instead of shipping a broken map. */
export function TownMap() {
  const router = useRouter()
  return (
    <View style={{ flex: 1, backgroundColor: C.canvas, alignItems: 'center', justifyContent: 'center', padding: 32 }}>
      <ScreenBadge />
      <View style={{ alignItems: 'center', gap: 12, maxWidth: 360 }}>
        <PinIcon size={28} color={C.ink3} />
        <Text style={{ fontWeight: F.mono, fontSize: 10.5, color: C.ink3, letterSpacing: 1.6 }}>THE TOWN MAP</Text>
        <Text style={{ fontWeight: F.display, fontSize: 22, color: C.ink, letterSpacing: -0.3, textAlign: 'center' }}>
          The map lives in the app
        </Text>
        <Text style={{ fontWeight: F.sans, fontSize: 14, color: C.ink2, lineHeight: 21, textAlign: 'center' }}>
          On the web, the calendar has everything happening around St. Joe — every event lists its place.
        </Text>
        <Pressable
          onPress={() => router.push('/(tabs)/calendar')}
          style={({ pressed }) => ({
            marginTop: 6, paddingVertical: 10, paddingHorizontal: 18, borderRadius: 20,
            borderWidth: 1, borderColor: HAIRLINE, backgroundColor: C.paper, opacity: pressed ? 0.7 : 1,
          })}
        >
          <Text style={{ fontWeight: F.sansSemi, fontSize: 13.5, color: C.ink }}>Open the calendar</Text>
        </Pressable>
      </View>
    </View>
  )
}
