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
      <Tabs.Screen name="add" />
    </Tabs>
  )
}
