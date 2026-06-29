import { Platform, Share } from 'react-native'
import { buildIcs, type CalendarEventInput } from './ics'
import { openInMaps } from './maps'

const fmtWhen = (ev: CalendarEventInput) => {
  const d = new Date(ev.event_date + 'T00:00:00')
  const day = d.toLocaleDateString('en-US', { weekday: 'short', month: 'short', day: 'numeric' })
  return ev.start_time ? `${day} · ${ev.start_time}` : day
}

/** Add to calendar: web downloads an .ics; native writes it then opens the share sheet. */
export async function addEventToCalendar(ev: CalendarEventInput): Promise<void> {
  const ics = buildIcs(ev)
  if (Platform.OS === 'web') {
    const blob = new Blob([ics], { type: 'text/calendar;charset=utf-8' })
    const url = URL.createObjectURL(blob)
    const a = document.createElement('a')
    a.href = url
    a.download = `${ev.title.replace(/[^a-z0-9]+/gi, '-').toLowerCase() || 'event'}.ics`
    document.body.appendChild(a)
    a.click()
    a.remove()
    URL.revokeObjectURL(url)
    return
  }
  // native: write to cache, hand to the OS share sheet ("Add to Calendar")
  const FileSystem = await import('expo-file-system/legacy')
  const Sharing = await import('expo-sharing')
  const uri = `${FileSystem.cacheDirectory}event.ics`
  await FileSystem.writeAsStringAsync(uri, ics, { encoding: FileSystem.EncodingType.UTF8 })
  if (await Sharing.isAvailableAsync()) {
    await Sharing.shareAsync(uri, {
      mimeType: 'text/calendar',
      UTI: 'com.apple.ical.ics',
      dialogTitle: 'Add to calendar',
    })
  }
}

/** Tell a neighbor: OS share sheet on native; navigator.share/clipboard on web. */
export async function shareEvent(ev: CalendarEventInput): Promise<void> {
  const message = [ev.title, fmtWhen(ev), ev.location].filter(Boolean).join(' · ') + (ev.url ? `\n${ev.url}` : '')
  if (Platform.OS === 'web') {
    const nav: any = (globalThis as any).navigator
    if (nav?.share) {
      try { await nav.share({ title: ev.title, text: message }); return } catch { return /* user cancelled */ }
    }
    const Clipboard = await import('expo-clipboard')
    await Clipboard.setStringAsync(message)
    return
  }
  await Share.share({ message })
}

export { openInMaps as openDirections }
