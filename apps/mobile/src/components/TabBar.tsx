import { Pressable, Text, View } from 'react-native'
import { BlurView } from 'expo-blur'
import { useSafeAreaInsets } from 'react-native-safe-area-context'
import * as Haptics from 'expo-haptics'
import type { BottomTabBarProps } from '@react-navigation/bottom-tabs'
import { C, F } from '../theme'
import { TabIcon, type TabId } from './icons'

const ICON_FOR: Record<string, TabId> = { index: 'home', clubs: 'clubs', calendar: 'calendar', add: 'add', quest: 'quest' }
const LABEL_FOR: Record<string, string> = { index: 'Home', clubs: 'Clubs', calendar: 'Calendar', add: 'Add', quest: 'Quest' }

/** Floating frosted-glass pill nav (mirrors the web bottom nav). */
export function TabBar({ state, navigation }: BottomTabBarProps) {
  const insets = useSafeAreaInsets()
  return (
    <View style={{ position: 'absolute', left: 16, right: 16, bottom: Math.max(16, insets.bottom), alignItems: 'center' }}>
      <BlurView
        intensity={40}
        tint="light"
        style={{
          width: '100%', maxWidth: 448, borderRadius: 28, overflow: 'hidden',
          flexDirection: 'row', paddingVertical: 7, paddingHorizontal: 4,
          backgroundColor: 'rgba(251,250,245,0.55)',
          borderWidth: 1, borderColor: 'rgba(0,0,0,0.06)',
          shadowColor: '#1f3022', shadowOpacity: 0.18, shadowRadius: 34, shadowOffset: { width: 0, height: 10 }, elevation: 12,
        }}
      >
        {state.routes.map((route, i) => {
          const focused = state.index === i
          const icon = ICON_FOR[route.name] ?? 'home'
          const label = LABEL_FOR[route.name] ?? route.name
          return (
            <Pressable
              key={route.key}
              onPress={() => {
                Haptics.selectionAsync()
                const event = navigation.emit({ type: 'tabPress', target: route.key, canPreventDefault: true })
                if (!focused && !event.defaultPrevented) navigation.navigate(route.name)
              }}
              style={{ flex: 1, alignItems: 'center' }}
            >
              <View style={{ alignItems: 'center', gap: 3, paddingVertical: 6, paddingHorizontal: 6, borderRadius: 14, backgroundColor: focused ? 'rgba(45,69,48,0.10)' : 'transparent' }}>
                <TabIcon id={icon} active={focused} />
                <Text style={{ fontFamily: focused ? F.sansSemi : F.sans, fontSize: 10, letterSpacing: 0.4, color: focused ? C.moss700 : C.ink3 }}>
                  {label}
                </Text>
              </View>
            </Pressable>
          )
        })}
      </BlurView>
    </View>
  )
}
