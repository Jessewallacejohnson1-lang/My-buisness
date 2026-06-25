import { Linking, Platform } from 'react-native'
import * as Clipboard from 'expo-clipboard'
import * as Haptics from 'expo-haptics'

/** Open an address / place name in the platform's maps app (Apple on iOS, Google elsewhere). */
export async function openInMaps(query: string) {
  const q = encodeURIComponent(query.trim())
  if (!q) return
  const url = Platform.select({
    ios: `http://maps.apple.com/?q=${q}`,
    android: `geo:0,0?q=${q}`,
    default: `https://www.google.com/maps/search/?api=1&query=${q}`,
  })!
  Haptics.selectionAsync()
  try {
    const ok = await Linking.canOpenURL(url)
    await Linking.openURL(ok ? url : `https://www.google.com/maps/search/?api=1&query=${q}`)
  } catch {
    await Linking.openURL(`https://www.google.com/maps/search/?api=1&query=${q}`)
  }
}

/** Copy an address to the clipboard (used on long-press). */
export async function copyAddress(query: string) {
  await Clipboard.setStringAsync(query.trim())
  Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success)
}
