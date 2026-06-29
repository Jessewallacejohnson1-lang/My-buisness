import { Platform, Share } from 'react-native'
import { buildIcs, parseStartTime, type CalendarEventInput } from './ics'
import { openInMaps } from './maps'

const fmtWhen = (ev: CalendarEventInput) => {
  const d = new Date(ev.event_date + 'T00:00:00')
  const day = d.toLocaleDateString('en-US', { weekday: 'short', month: 'short', day: 'numeric' })
  return ev.start_time ? `${day} · ${ev.start_time}` : day
}

/**
 * Add to calendar. Native opens the OS calendar editor prefilled (the event
 * lands in the user's Calendar app on save); web downloads an .ics file.
 */
export async function addEventToCalendar(ev: CalendarEventInput): Promise<void> {
  if (Platform.OS === 'web') {
    const ics = buildIcs(ev)
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
  // native: launch the system "new event" sheet prefilled — saving it puts the
  // event straight into the device Calendar (no file, no share sheet).
  const Calendar = await import('expo-calendar')
  const [y, mo, d] = ev.event_date.split('-').map((x) => parseInt(x, 10))
  const t = parseStartTime(ev.start_time)
  const start = t ? new Date(y, mo - 1, d, t.h, t.m) : new Date(y, mo - 1, d)
  const end = t ? new Date(start.getTime() + 2 * 60 * 60 * 1000) : new Date(y, mo - 1, d, 23, 59)
  await Calendar.createEventInCalendarAsync({
    title: ev.title,
    startDate: start,
    endDate: end,
    allDay: !t,
    location: ev.location ?? undefined,
    notes: ev.description ?? undefined,
  })
}

/** Tell a neighbor: OS share sheet on native; navigator.share/clipboard on web. */
export async function shareEvent(ev: CalendarEventInput): Promise<void> {
  const message = [ev.title, fmtWhen(ev), ev.location].filter(Boolean).join(' · ') + (ev.url ? `\n${ev.url}` : '')
  if (Platform.OS === 'web') {
    const nav: any = (globalThis as any).navigator
    if (nav?.share) {
      try { await nav.share({ title: ev.title, text: message }); return }
      catch (e) { if ((e as any)?.name === 'AbortError') return /* user cancelled — don't fall back */ }
    }
    const Clipboard = await import('expo-clipboard')
    await Clipboard.setStringAsync(message)
    return
  }
  await Share.share({ message })
}

export { openInMaps as openDirections }
