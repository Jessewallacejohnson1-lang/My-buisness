import { Pressable, ScrollView, Text, View } from 'react-native'
import { SafeAreaView } from 'react-native-safe-area-context'
import { useRouter } from 'expo-router'
import * as Haptics from 'expo-haptics'
import Svg, { Circle, Path, Rect } from 'react-native-svg'
import { useAuth } from '../lib/auth'
import { C, F, HAIRLINE } from '../theme'

// ─── inline icons ────────────────────────────────────────────────────────────
function MapPin({ size = 16, color = C.ink }: { size?: number; color?: string }) {
  return (
    <Svg viewBox="0 0 24 24" width={size} height={size} fill="none" stroke={color} strokeWidth={1.5} strokeLinecap="round" strokeLinejoin="round">
      <Path d="M12 21c4-4.5 7-7.6 7-11a7 7 0 1 0-14 0c0 3.4 3 6.5 7 11Z" />
      <Circle cx="12" cy="10" r="2.4" opacity={0.6} />
    </Svg>
  )
}
function Calendar({ size = 22, color = C.ink2 }: { size?: number; color?: string }) {
  return (
    <Svg viewBox="0 0 24 24" width={size} height={size} fill="none" stroke={color} strokeWidth={1.5} strokeLinecap="round" strokeLinejoin="round">
      <Rect x={3} y={5} width={18} height={16} rx={2.5} />
      <Path d="M3 10h18M8 3v4M16 3v4" />
    </Svg>
  )
}
function Sun({ size = 22, color = C.ink2 }: { size?: number; color?: string }) {
  return (
    <Svg viewBox="0 0 24 24" width={size} height={size} fill="none" stroke={color} strokeWidth={1.5} strokeLinecap="round" strokeLinejoin="round">
      <Circle cx={12} cy={12} r={4} />
      <Path d="M12 2v2M12 20v2M4.22 4.22l1.42 1.42M18.36 18.36l1.42 1.42M2 12h2M20 12h2M4.22 19.78l1.42-1.42M18.36 5.64l1.42-1.42" />
    </Svg>
  )
}
function People({ size = 22, color = C.ink2 }: { size?: number; color?: string }) {
  return (
    <Svg viewBox="0 0 24 24" width={size} height={size} fill="none" stroke={color} strokeWidth={1.5} strokeLinecap="round" strokeLinejoin="round">
      <Circle cx={9} cy={8} r={3.2} />
      <Path d="M3.5 19c0-3 2.5-5 5.5-5s5.5 2 5.5 5" />
      <Path d="M16 5.2a3.2 3.2 0 0 1 0 5.6M17 14.4c2.3.5 3.8 2.3 3.8 4.6" opacity={0.6} />
    </Svg>
  )
}

// ─── illustrative content (marketing preview — not live data) ────────────────
const EVENTS = [
  { weekday: 'Sat', date: '28', month: 'Jun', title: 'Saturday Run Club', where: 'Millstream Park · 8:00 AM' },
  { weekday: 'Sun', date: '29', month: 'Jun', title: 'Sunrise Yoga', where: 'Lake Wobegon Trail · 6:30 AM' },
  { weekday: 'Wed', date: '2', month: 'Jul', title: 'Farmers Market', where: 'Veterans Park · 9:00 AM' },
]
const PILLARS = [
  { Icon: Calendar, label: 'Get out', body: "A daily, chronological list of what's happening in town — run clubs, markets, yoga in the park. RSVP in one tap." },
  { Icon: Sun, label: 'Show up', body: 'A small daily quest — a gentle nudge to get outside and connect. Mark it done when you get back.' },
  { Icon: People, label: 'Find your people', body: 'A full calendar of everything in St. Joe. Add your own event. Find the club that fits your pace.' },
]

const MAXW = 460

export default function Landing() {
  const router = useRouter()
  const { session } = useAuth()
  const ctaLabel = session ? 'Open the app' : 'Get the app'
  const go = () => { Haptics.selectionAsync(); router.push(session ? '/(tabs)' : '/login') }

  return (
    <View style={{ flex: 1, backgroundColor: C.paper300 }}>
      {/* nav */}
      <SafeAreaView edges={['top']} style={{ backgroundColor: C.paper300, borderBottomWidth: 1, borderBottomColor: HAIRLINE }}>
        <View style={{ height: 56, flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', paddingHorizontal: 20 }}>
          <View style={{ flexDirection: 'row', alignItems: 'center', gap: 7 }}>
            <MapPin size={15} />
            <Text style={{ fontWeight: F.displaySemi, fontSize: 17, color: C.ink, letterSpacing: 0.5 }}>Hygge</Text>
            <Text style={{ fontWeight: F.sans, fontSize: 12, color: C.ink3, marginLeft: 2 }}>· St. Joseph, MN</Text>
          </View>
          <Pressable onPress={go} style={({ pressed }) => ({ backgroundColor: C.moss700, paddingHorizontal: 16, paddingVertical: 8, borderRadius: 8, opacity: pressed ? 0.85 : 1 })}>
            <Text style={{ fontWeight: F.sansSemi, fontSize: 13, color: C.paper }}>{ctaLabel}</Text>
          </Pressable>
        </View>
      </SafeAreaView>

      <ScrollView contentContainerStyle={{ paddingBottom: 40 }} showsVerticalScrollIndicator={false}>
        <View style={{ width: '100%', maxWidth: MAXW, alignSelf: 'center', paddingHorizontal: 22 }}>

          {/* hero */}
          <View style={{ paddingTop: 44, paddingBottom: 12 }}>
            <View style={{ flexDirection: 'row', alignItems: 'center', gap: 6, marginBottom: 18 }}>
              <MapPin size={12} color={C.ink2} />
              <Text style={{ fontWeight: F.sansMed, fontSize: 11, letterSpacing: 2, textTransform: 'uppercase', color: C.ink2 }}>Saint Joseph, Minnesota</Text>
            </View>
            <Text style={{ fontWeight: F.display, fontSize: 52, lineHeight: 54, color: C.ink, letterSpacing: -1 }}>Your town,{'\n'}every day.</Text>
            <Text style={{ fontWeight: F.sans, fontSize: 17, lineHeight: 26, color: C.ink2, marginTop: 20 }}>
              Hygge is a quiet place to see what's happening in St. Joe, join a neighbor for a walk, and make the place you live feel a little smaller.
            </Text>
            <View style={{ flexDirection: 'row', alignItems: 'center', gap: 18, marginTop: 26 }}>
              <Pressable onPress={go} style={({ pressed }) => ({ backgroundColor: C.moss700, paddingHorizontal: 26, paddingVertical: 14, borderRadius: 9, opacity: pressed ? 0.85 : 1 })}>
                <Text style={{ fontWeight: F.sansSemi, fontSize: 14, color: C.paper }}>{ctaLabel}</Text>
              </Pressable>
              {!session && (
                <Pressable onPress={() => router.push('/login')}>
                  <Text style={{ fontWeight: F.sans, fontSize: 14, color: C.ink2 }}>Sign in</Text>
                </Pressable>
              )}
            </View>
            <Text style={{ fontWeight: F.sans, fontSize: 13, color: C.ink3, marginTop: 18 }}>
              <Text style={{ fontWeight: F.mono }}>$2</Text> / month — less than a cup of coffee at Covenant Cup.
            </Text>
          </View>

          {/* event card stack */}
          <View style={{ paddingTop: 28 }}>
            <Text style={{ fontWeight: F.sansMed, fontSize: 11, letterSpacing: 1.8, textTransform: 'uppercase', color: C.ink3, marginBottom: 12 }}>Coming up in St. Joe</Text>
            <View style={{ gap: 10 }}>
              {EVENTS.map((e) => (
                <View key={e.title} style={{ flexDirection: 'row', alignItems: 'flex-start', gap: 14, backgroundColor: C.paper, borderWidth: 1, borderColor: HAIRLINE, borderRadius: 14, paddingHorizontal: 16, paddingVertical: 13 }}>
                  <View style={{ width: 40, alignItems: 'center', paddingTop: 2 }}>
                    <Text style={{ fontWeight: F.sans, fontSize: 10, letterSpacing: 0.6, textTransform: 'uppercase', color: C.ink3 }}>{e.weekday}</Text>
                    <Text style={{ fontWeight: F.mono, fontSize: 20, color: C.ink, lineHeight: 24 }}>{e.date}</Text>
                    <Text style={{ fontWeight: F.sans, fontSize: 10, color: C.ink3 }}>{e.month}</Text>
                  </View>
                  <View style={{ width: 1, alignSelf: 'stretch', backgroundColor: HAIRLINE, marginTop: 2 }} />
                  <View style={{ flex: 1 }}>
                    <Text style={{ fontWeight: F.sans, fontSize: 14, color: C.ink, lineHeight: 19 }}>{e.title}</Text>
                    <Text style={{ fontWeight: F.sans, fontSize: 12, color: C.ink2, marginTop: 2 }}>{e.where}</Text>
                  </View>
                </View>
              ))}
            </View>
          </View>

          {/* three pillars */}
          <View style={{ paddingTop: 48 }}>
            <Text style={{ fontWeight: F.sansMed, fontSize: 11, letterSpacing: 2, textTransform: 'uppercase', color: C.ink3, marginBottom: 8 }}>What Hygge does</Text>
            {PILLARS.map(({ Icon, label, body }) => (
              <View key={label} style={{ paddingVertical: 26, borderTopWidth: 1, borderTopColor: HAIRLINE }}>
                <View style={{ marginBottom: 14 }}><Icon size={22} /></View>
                <Text style={{ fontWeight: F.displaySemi, fontSize: 24, color: C.ink, letterSpacing: -0.3, marginBottom: 10 }}>{label}</Text>
                <Text style={{ fontWeight: F.sans, fontSize: 14, lineHeight: 22, color: C.ink2 }}>{body}</Text>
              </View>
            ))}
          </View>

          {/* daily quest */}
          <View style={{ paddingTop: 38 }}>
            <Text style={{ fontWeight: F.sansMed, fontSize: 11, letterSpacing: 2, textTransform: 'uppercase', color: C.ink3, marginBottom: 16 }}>The daily quest</Text>
            <Text style={{ fontWeight: F.display, fontSize: 30, lineHeight: 38, color: C.ink, letterSpacing: -0.5, marginBottom: 16 }}>A small reason{'\n'}to step outside.</Text>
            <Text style={{ fontWeight: F.sans, fontSize: 14, lineHeight: 22, color: C.ink2, marginBottom: 24 }}>
              Each morning, Hygge offers a single, quiet prompt — a short walk, a wave to someone at the trail, a stop at the market. You mark it done when you're back. That's the whole thing.
            </Text>
            <View style={{ backgroundColor: C.paper, borderWidth: 1, borderColor: HAIRLINE, borderRadius: 18, padding: 24 }}>
              <View style={{ flexDirection: 'row', justifyContent: 'space-between', marginBottom: 22 }}>
                <Text style={{ fontWeight: F.sansMed, fontSize: 11, letterSpacing: 1.6, textTransform: 'uppercase', color: C.ink3 }}>Today's quest</Text>
                <Text style={{ fontWeight: F.sans, fontSize: 11, color: C.ink3 }}>For example</Text>
              </View>
              <Text style={{ fontWeight: F.display, fontSize: 23, lineHeight: 30, fontStyle: 'italic', color: C.ink, letterSpacing: -0.3, marginBottom: 26 }}>
                Walk to the trailhead before 9 in the morning.
              </Text>
              <View style={{ flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: 8, backgroundColor: C.paper100, paddingVertical: 12, borderRadius: 9 }}>
                <View style={{ width: 16, height: 16, borderRadius: 8, borderWidth: 1.5, borderColor: C.ink3 }} />
                <Text style={{ fontWeight: F.sansSemi, fontSize: 14, color: C.ink3 }}>Mark as done</Text>
              </View>
            </View>
          </View>
        </View>

        {/* founder voice — full-bleed dark */}
        <View style={{ backgroundColor: C.ink, marginTop: 48, paddingVertical: 52 }}>
          <View style={{ width: '100%', maxWidth: MAXW, alignSelf: 'center', paddingHorizontal: 22 }}>
            <View style={{ flexDirection: 'row', alignItems: 'center', gap: 7, marginBottom: 26, opacity: 0.6 }}>
              <MapPin size={14} color={C.paper} />
              <Text style={{ fontWeight: F.displaySemi, fontSize: 14, color: C.paper, letterSpacing: 0.5 }}>Hygge</Text>
            </View>
            <Text style={{ fontWeight: F.display, fontSize: 25, lineHeight: 34, fontStyle: 'italic', color: C.paper, letterSpacing: -0.3, marginBottom: 22 }}>
              "I built Hygge because none of the apps I tried felt like they were made for anyone on my actual street."
            </Text>
            <Text style={{ fontWeight: F.sans, fontSize: 14, color: 'rgba(251,250,245,0.5)' }}>— Jesse, Saint Joseph, Minnesota</Text>
          </View>
        </View>

        {/* final cta */}
        <View style={{ width: '100%', maxWidth: MAXW, alignSelf: 'center', paddingHorizontal: 22, paddingTop: 52, alignItems: 'center' }}>
          <Text style={{ fontWeight: F.sansMed, fontSize: 11, letterSpacing: 2, textTransform: 'uppercase', color: C.ink3, marginBottom: 16 }}>Join St. Joe</Text>
          <Text style={{ fontWeight: F.display, fontSize: 30, lineHeight: 36, color: C.ink, letterSpacing: -0.5, textAlign: 'center', marginBottom: 14 }}>See what's happening{'\n'}in your town.</Text>
          <Text style={{ fontWeight: F.sans, fontSize: 14, lineHeight: 22, color: C.ink2, textAlign: 'center', marginBottom: 26 }}>
            Hygge is built for the people on your street — no global leaderboard, no feed to scroll. Just your town.
          </Text>
          <Pressable onPress={go} style={({ pressed }) => ({ backgroundColor: C.moss700, paddingHorizontal: 36, paddingVertical: 16, borderRadius: 9, opacity: pressed ? 0.85 : 1 })}>
            <Text style={{ fontWeight: F.sansSemi, fontSize: 15, color: C.paper }}>{ctaLabel}</Text>
          </Pressable>
          <Text style={{ fontWeight: F.sans, fontSize: 12, color: C.ink3, marginTop: 14 }}>
            <Text style={{ fontWeight: F.mono }}>$2</Text> / month. Cancel any time.
          </Text>
        </View>

        {/* footer */}
        <View style={{ width: '100%', maxWidth: MAXW, alignSelf: 'center', paddingHorizontal: 22, paddingTop: 40, marginTop: 36, borderTopWidth: 1, borderTopColor: HAIRLINE, flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between' }}>
          <View style={{ flexDirection: 'row', alignItems: 'center', gap: 7 }}>
            <MapPin size={14} />
            <Text style={{ fontWeight: F.displaySemi, fontSize: 14, color: C.ink, letterSpacing: 0.5 }}>Hygge</Text>
          </View>
          <Text style={{ fontWeight: F.mono, fontSize: 11, color: C.ink3 }}>© 2026 Hygge · St. Joseph, MN</Text>
        </View>
      </ScrollView>
    </View>
  )
}
