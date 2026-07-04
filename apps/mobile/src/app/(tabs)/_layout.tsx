import { Tabs } from 'expo-router'
import { TabBar } from '../../components/TabBar'

export default function TabsLayout() {
  return (
    <Tabs
      screenOptions={{ headerShown: false }}
      tabBar={(props) => <TabBar {...props} />}
    >
      <Tabs.Screen name="index" />
      <Tabs.Screen name="activities" />
      <Tabs.Screen name="calendar" />
      <Tabs.Screen name="map" />
      {/* add is not in the tab bar — reached via the + button on the map screen */}
      <Tabs.Screen name="add" options={{ href: null }} />
    </Tabs>
  )
}
