# Calendar "Plan & Commit" Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the Calendar tab from a read-only month viewer into a plan-ahead-and-commit surface: real event density, fast "this weekend"/"today" orientation, and per-event actions (Add to calendar · Directions · Tell a neighbor) plus an "add on this day" path from empty days.

**Architecture:** Keep the existing grid-first scroll. Add a pure ICS/time module and a thin cross-platform `eventActions` lib (web vs. native branches), surface them through a small `EventActions` row rendered in the day sheet, and extend core with a per-day count query to drive density. Reuse the existing `openInMaps` for Directions and RN's built-in `Share` for sharing.

**Tech Stack:** Expo SDK 54, React Native 0.81, Expo Router 6, TypeScript, `@hygge/core` (Supabase), `react-native-svg`. New deps: `expo-file-system`, `expo-sharing`.

## Global Constraints

- Verify every task from `apps/mobile/`: `npx tsc --noEmit -p tsconfig.json` **and** `npx expo export --platform web` must both pass. There is **no test runner** in this repo — pure helpers are checked with `node --experimental-strip-types` (Node ≥22; if older, run the check file through `npx tsx`).
- Install Expo packages with `npx expo install <pkg>` (SDK-correct versions); any npm install uses `--legacy-peer-deps`.
- Numbers (dates, times, counts) render in `F.mono` (Geist Mono). `moss` (`C.moss700`/`C.moss500`) only for positive/committed state — never decorative.
- No emoji — inline `react-native-svg` only, added to `src/components/icons.tsx`.
- Dates derived with `localDate()` from `@hygge/core`, never `toISOString()`.
- **Real counts only** — never seed or inflate. **No reminders/notifications.**
- Reuse, don't duplicate: `openInMaps` (`src/lib/maps.ts`), `EventRow`, theme tokens `C`/`F`/`HAIRLINE`, `expo-clipboard`, `expo-linking`.
- `git add` only the files a task touches (the working tree has unrelated rebuild WIP — never `git add -A`).

---

### Task 1: Install native calendar/share dependencies

**Files:**
- Modify: `apps/mobile/package.json` (via installer)

**Interfaces:**
- Produces: `expo-file-system` and `expo-sharing` available to later tasks (used dynamically in Task 4).

- [ ] **Step 1: Install**

Run from `apps/mobile/`:
```bash
npx expo install expo-file-system expo-sharing
```

- [ ] **Step 2: Verify the app still bundles**

Run from `apps/mobile/`:
```bash
npx expo export --platform web
```
Expected: build completes without "Unable to resolve" errors.

- [ ] **Step 3: Commit**

```bash
git add apps/mobile/package.json package-lock.json
git commit -m "build(mobile): add expo-file-system + expo-sharing for add-to-calendar"
```

---

### Task 2: Add per-day event counts to core

**Files:**
- Modify: `packages/core/src/community.ts` (next to `getMonthEventDates`, ~line 214)
- Modify: `apps/mobile/src/lib/api.ts` (re-export is automatic via `createCommunityApi`; no change unless it lists methods explicitly — verify)

**Interfaces:**
- Produces: `getMonthEventCounts(year: number, month: number): Promise<Record<string, number>>` on the api — keys are `YYYY-MM-DD`, values are the count of approved events on that day.

- [ ] **Step 1: Implement the query**

In `packages/core/src/community.ts`, directly after `getMonthEventDates`, add:
```ts
  async function getMonthEventCounts(year: number, month: number): Promise<Record<string, number>> {
    const from = `${year}-${String(month).padStart(2, '0')}-01`
    const lastDay = new Date(year, month, 0).getDate()
    const to = `${year}-${String(month).padStart(2, '0')}-${String(lastDay).padStart(2, '0')}`
    const { data, error } = await supabase
      .from('club_events').select('event_date').eq('status', 'approved').eq('kind', 'event').gte('event_date', from).lte('event_date', to)
    if (error) throw error
    const counts: Record<string, number> = {}
    for (const e of data ?? []) counts[e.event_date] = (counts[e.event_date] ?? 0) + 1
    return counts
  }
```

- [ ] **Step 2: Export it from the api object**

In the `return { ... }` of `createCommunityApi` (same file), add `getMonthEventCounts,` alongside `getMonthEventDates`.

- [ ] **Step 3: Verify typecheck**

Run from `apps/mobile/`:
```bash
npx tsc --noEmit -p tsconfig.json
```
Expected: no errors (the new method is typed and exported).

- [ ] **Step 4: Commit**

```bash
git add packages/core/src/community.ts
git commit -m "feat(core): getMonthEventCounts for calendar density"
```

---

### Task 3: Pure ICS + time-parse helpers

**Files:**
- Create: `apps/mobile/src/lib/ics.ts`
- Create: `apps/mobile/src/lib/ics.check.ts` (assertion script, not bundled)

**Interfaces:**
- Produces:
  - `type CalendarEventInput = { title: string; event_date: string; start_time?: string | null; location?: string | null; description?: string | null; url?: string | null }`
  - `parseStartTime(input?: string | null): { h: number; m: number } | null`
  - `buildIcs(ev: CalendarEventInput): string`

- [ ] **Step 1: Write `ics.ts`**

```ts
// Pure, dependency-free helpers for turning a community event into a calendar
// entry. `start_time` is a human display string ('7pm', '7:00p', '19:00'), so we
// best-effort parse it and fall back to an all-day event when we can't.

export type CalendarEventInput = {
  title: string
  event_date: string // 'YYYY-MM-DD'
  start_time?: string | null
  location?: string | null
  description?: string | null
  url?: string | null
}

/** Best-effort parse of a display time into 24h {h, m}. null when unparseable. */
export function parseStartTime(input?: string | null): { h: number; m: number } | null {
  if (!input) return null
  const m = input.trim().toLowerCase().match(/^(\d{1,2})(?::(\d{2}))?\s*(am|pm|a|p)?/)
  if (!m) return null
  let h = parseInt(m[1], 10)
  const min = m[2] ? parseInt(m[2], 10) : 0
  const mer = m[3]?.[0] // 'a' | 'p' | undefined
  if (h > 23 || min > 59) return null
  if (mer === 'p' && h < 12) h += 12
  if (mer === 'a' && h === 12) h = 0
  return { h, m: min }
}

const pad = (n: number) => String(n).padStart(2, '0')
const esc = (v: string) =>
  v.replace(/\\/g, '\\\\').replace(/;/g, '\\;').replace(/,/g, '\\,').replace(/\n/g, '\\n')

/** Build a single-event VCALENDAR string. Timed when start_time parses (2h
 *  default duration), else an all-day event on event_date. Floating local time. */
export function buildIcs(ev: CalendarEventInput): string {
  const [y, mo, d] = ev.event_date.split('-').map((x) => parseInt(x, 10))
  const t = parseStartTime(ev.start_time)
  const uid =
    `${ev.event_date}-${ev.title}`.replace(/[^a-z0-9]+/gi, '-').toLowerCase() + '@hygge.stjoe'
  const lines = [
    'BEGIN:VCALENDAR',
    'VERSION:2.0',
    'PRODID:-//Hygge//St. Joe//EN',
    'BEGIN:VEVENT',
    `UID:${uid}`,
    `SUMMARY:${esc(ev.title)}`,
  ]
  if (t) {
    const start = new Date(y, mo - 1, d, t.h, t.m)
    const end = new Date(start.getTime() + 2 * 60 * 60 * 1000)
    const fmt = (x: Date) =>
      `${x.getFullYear()}${pad(x.getMonth() + 1)}${pad(x.getDate())}T${pad(x.getHours())}${pad(x.getMinutes())}00`
    lines.push(`DTSTART:${fmt(start)}`, `DTEND:${fmt(end)}`)
  } else {
    lines.push(`DTSTART;VALUE=DATE:${y}${pad(mo)}${pad(d)}`)
  }
  if (ev.location) lines.push(`LOCATION:${esc(ev.location)}`)
  const desc = [ev.description, ev.url].filter(Boolean).join('\n')
  if (desc) lines.push(`DESCRIPTION:${esc(desc)}`)
  lines.push('END:VEVENT', 'END:VCALENDAR')
  return lines.join('\r\n')
}
```

- [ ] **Step 2: Write `ics.check.ts` (assertions)**

```ts
import { parseStartTime, buildIcs } from './ics'

const eq = (a: unknown, b: unknown, msg: string) => {
  if (JSON.stringify(a) !== JSON.stringify(b)) throw new Error(`FAIL ${msg}: ${JSON.stringify(a)} !== ${JSON.stringify(b)}`)
  console.log('ok', msg)
}
const has = (s: string, sub: string, msg: string) => {
  if (!s.includes(sub)) throw new Error(`FAIL ${msg}: missing ${sub}`)
  console.log('ok', msg)
}

eq(parseStartTime('7pm'), { h: 19, m: 0 }, '7pm')
eq(parseStartTime('7:00p'), { h: 19, m: 0 }, '7:00p')
eq(parseStartTime('12am'), { h: 0, m: 0 }, '12am')
eq(parseStartTime('12pm'), { h: 12, m: 0 }, '12pm')
eq(parseStartTime('19:30'), { h: 19, m: 30 }, '24h')
eq(parseStartTime('noon'), null, 'unparseable')
eq(parseStartTime(''), null, 'empty')

has(buildIcs({ title: 'Trivia, Pints', event_date: '2026-07-01', start_time: '7pm', location: 'Bad Habit' }), 'DTSTART:20260701T190000', 'timed start')
has(buildIcs({ title: 'Trivia, Pints', event_date: '2026-07-01', start_time: '7pm' }), 'SUMMARY:Trivia\\, Pints', 'comma escaped')
has(buildIcs({ title: 'Market', event_date: '2026-07-04', start_time: null }), 'DTSTART;VALUE=DATE:20260704', 'all-day')
console.log('all ics checks passed')
```

- [ ] **Step 3: Run the assertions**

Run from `apps/mobile/`:
```bash
node --experimental-strip-types src/lib/ics.check.ts
```
Expected: lines of `ok ...` then `all ics checks passed`. (If Node < 22: `npx tsx src/lib/ics.check.ts`.)

- [ ] **Step 4: Typecheck**

```bash
npx tsc --noEmit -p tsconfig.json
```
Expected: no errors.

- [ ] **Step 5: Commit**

```bash
git add apps/mobile/src/lib/ics.ts apps/mobile/src/lib/ics.check.ts
git commit -m "feat(mobile): pure ICS + start_time parser for calendar export"
```

---

### Task 4: Cross-platform event-actions lib

**Files:**
- Create: `apps/mobile/src/lib/eventActions.ts`

**Interfaces:**
- Consumes: `buildIcs`, `CalendarEventInput` (Task 3); `openInMaps` (`src/lib/maps.ts`); `expo-file-system`, `expo-sharing` (Task 1).
- Produces:
  - `addEventToCalendar(ev: CalendarEventInput): Promise<void>`
  - `shareEvent(ev: CalendarEventInput): Promise<void>`
  - `openDirections(location: string): Promise<void>` (re-export of `openInMaps`)

- [ ] **Step 1: Write `eventActions.ts`**

```ts
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
```

- [ ] **Step 2: Typecheck + bundle**

Run from `apps/mobile/`:
```bash
npx tsc --noEmit -p tsconfig.json && npx expo export --platform web
```
Expected: both pass. (`expo-file-system/legacy` and `expo-sharing` resolve; the web path returns before importing them.)

- [ ] **Step 3: Commit**

```bash
git add apps/mobile/src/lib/eventActions.ts
git commit -m "feat(mobile): cross-platform add-to-calendar + share helpers"
```

---

### Task 5: Add `CalendarPlusIcon` and `ShareIcon`

**Files:**
- Modify: `apps/mobile/src/components/icons.tsx`

**Interfaces:**
- Consumes: existing icon pattern (`{ size?: number; color?: string }`, `react-native-svg`). `PinIcon` already exists and is reused for Directions.
- Produces: `CalendarPlusIcon`, `ShareIcon`, each `({ size, color }) => JSX`.

- [ ] **Step 1: Add the two icons**

Append to `src/components/icons.tsx` (use the same `Svg`/`Path` imports already at the top of the file):
```tsx
export function CalendarPlusIcon({ size = 16, color = '#2a2a28' }: { size?: number; color?: string }) {
  return (
    <Svg width={size} height={size} viewBox="0 0 24 24" fill="none">
      <Path d="M7 3v3M17 3v3M4 8.5h16M5 6.5h14a1 1 0 0 1 1 1V19a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1V7.5a1 1 0 0 1 1-1Z" stroke={color} strokeWidth={1.6} strokeLinecap="round" strokeLinejoin="round" />
      <Path d="M12 12.5v4M10 14.5h4" stroke={color} strokeWidth={1.6} strokeLinecap="round" />
    </Svg>
  )
}

export function ShareIcon({ size = 16, color = '#2a2a28' }: { size?: number; color?: string }) {
  return (
    <Svg width={size} height={size} viewBox="0 0 24 24" fill="none">
      <Path d="M12 14V4M12 4 8.5 7.5M12 4l3.5 3.5" stroke={color} strokeWidth={1.6} strokeLinecap="round" strokeLinejoin="round" />
      <Path d="M6 11v7a1 1 0 0 0 1 1h10a1 1 0 0 0 1-1v-7" stroke={color} strokeWidth={1.6} strokeLinecap="round" strokeLinejoin="round" />
    </Svg>
  )
}
```

- [ ] **Step 2: Typecheck**

```bash
npx tsc --noEmit -p tsconfig.json
```
Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add apps/mobile/src/components/icons.tsx
git commit -m "feat(mobile): calendar-plus + share icons"
```

---

### Task 6: `EventActions` row component

**Files:**
- Create: `apps/mobile/src/components/EventActions.tsx`

**Interfaces:**
- Consumes: `addEventToCalendar`, `shareEvent`, `openDirections` (Task 4); `CalendarPlusIcon`, `ShareIcon`, `PinIcon`; `TimelineEvent` from `@hygge/core`.
- Produces: `EventActions({ event, date }: { event: TimelineEvent; date: string }) => JSX` — the calm action row. (`date` is the day's `YYYY-MM-DD`, since `TimelineEvent` carries no `event_date`.)

- [ ] **Step 1: Write the component**

```tsx
import { useState } from 'react'
import { Pressable, Text, View } from 'react-native'
import type { TimelineEvent } from '@hygge/core'
import { C, F } from '../theme'
import { CalendarPlusIcon, ShareIcon, PinIcon } from './icons'
import { addEventToCalendar, shareEvent, openDirections } from '../lib/eventActions'

function ActionBtn({ label, icon, active, onPress }: {
  label: string; icon: React.ReactNode; active?: boolean; onPress: () => void
}) {
  return (
    <Pressable onPress={onPress} hitSlop={6} style={({ pressed }) => ({ flexDirection: 'row', alignItems: 'center', gap: 5, opacity: pressed ? 0.6 : 1 })}>
      {icon}
      <Text style={{ fontFamily: F.sansMed, fontSize: 12.5, color: active ? C.moss700 : C.ink2 }}>{label}</Text>
    </Pressable>
  )
}

/** Quiet commitment actions beneath an event in the day sheet. */
export function EventActions({ event, date }: { event: TimelineEvent; date: string }) {
  const [added, setAdded] = useState(false)
  const input = { title: event.title, event_date: date, start_time: event.start_time, location: event.location }
  return (
    <View style={{ flexDirection: 'row', alignItems: 'center', flexWrap: 'wrap', gap: 18, paddingLeft: 64, paddingBottom: 15 }}>
      <ActionBtn
        label={added ? 'Added' : 'Add to calendar'}
        active={added}
        icon={<CalendarPlusIcon size={14} color={added ? C.moss700 : C.ink2} />}
        onPress={async () => { await addEventToCalendar(input); setAdded(true) }}
      />
      {!!event.location && (
        <ActionBtn label="Directions" icon={<PinIcon size={13} color={C.ink2} />} onPress={() => openDirections(event.location!)} />
      )}
      <ActionBtn label="Tell a neighbor" icon={<ShareIcon size={14} color={C.ink2} />} onPress={() => shareEvent(input)} />
    </View>
  )
}
```

- [ ] **Step 2: Typecheck + bundle**

```bash
npx tsc --noEmit -p tsconfig.json && npx expo export --platform web
```
Expected: both pass.

- [ ] **Step 3: Commit**

```bash
git add apps/mobile/src/components/EventActions.tsx
git commit -m "feat(mobile): EventActions row (add-to-calendar/directions/share)"
```

---

### Task 7: Prefill the Add screen from a `date` param

**Files:**
- Modify: `apps/mobile/src/app/(tabs)/add.tsx` (imports near line 7; effects near line 59-72)

**Interfaces:**
- Consumes: Expo Router `useLocalSearchParams`.
- Produces: opening `/(tabs)/add?date=YYYY-MM-DD` prefills `form.event_date` with that date (used by Task 8's empty-day link).

- [ ] **Step 1: Read the param and apply it**

In `add.tsx`, change the router import (line 7) to also pull params:
```ts
import { useLocalSearchParams, useRouter } from 'expo-router'
```
Inside the component, after `const router = useRouter()` (line 59), add:
```ts
  const { date } = useLocalSearchParams<{ date?: string }>()
  useEffect(() => {
    if (date) setForm((f) => ({ ...f, event_date: date }))
  }, [date])
```
(`useEffect` is already imported if used elsewhere; if not, add it to the `react` import.)

- [ ] **Step 2: Typecheck + bundle**

```bash
npx tsc --noEmit -p tsconfig.json && npx expo export --platform web
```
Expected: both pass.

- [ ] **Step 3: Verify in preview**

Start the web app, navigate to `/(tabs)/add?date=2026-07-04`, confirm the date field shows Jul 4 2026. (Toolkit: `preview_start` → `preview_eval` to navigate → `preview_screenshot`.)

- [ ] **Step 4: Commit**

```bash
git add "apps/mobile/src/app/(tabs)/add.tsx"
git commit -m "feat(mobile): Add screen prefills event_date from ?date param"
```

---

### Task 8: Wire EventActions + empty-day "Add" into the day sheet

**Files:**
- Modify: `apps/mobile/src/app/(tabs)/calendar.tsx` (imports; `Calendar` component; the sheet `ScrollView`, lines ~205-213)

**Interfaces:**
- Consumes: `EventActions` (Task 6); `useRouter` from `expo-router`.
- Produces: each event in the sheet shows its action row; empty days show a tappable "+ Add something on this day" that deep-links to Add with the date prefilled and closes the sheet.

- [ ] **Step 1: Add imports**

In `calendar.tsx`, add:
```ts
import { useRouter } from 'expo-router'
import { EventActions } from '../../components/EventActions'
```
Inside `Calendar`, after the other hooks: `const router = useRouter()`.

- [ ] **Step 2: Render actions + empty-day add**

Replace the sheet body (the block from `{loadingEvents ? (` through its closing `)}` around lines 206-212) with:
```tsx
            {loadingEvents ? (
              <Text style={{ fontFamily: F.sans, fontSize: 14, color: C.ink3, paddingVertical: 12 }}>Loading…</Text>
            ) : dayEvents.length === 0 ? (
              <Pressable
                onPress={() => { setSheetOpen(false); router.push({ pathname: '/(tabs)/add', params: { date: selectedDate! } }) }}
                style={({ pressed }) => ({ flexDirection: 'row', alignItems: 'center', gap: 8, paddingVertical: 16, opacity: pressed ? 0.6 : 1 })}
              >
                <PlusIcon size={16} color={C.moss700} />
                <Text style={{ fontFamily: F.sansMed, fontSize: 14, color: C.moss700 }}>Add something on this day</Text>
              </Pressable>
            ) : (
              dayEvents.map((e, i) => (
                <View key={e.id}>
                  <EventRow event={e} onRsvp={handleRsvp} last />
                  <EventActions event={e} date={selectedDate!} />
                </View>
              ))
            )}
```
Add `PlusIcon` to the existing `icons` import line in `calendar.tsx` (`import { CloseIcon, PlusIcon } from '../../components/icons'`).

- [ ] **Step 3: Typecheck + bundle**

```bash
npx tsc --noEmit -p tsconfig.json && npx expo export --platform web
```
Expected: both pass.

- [ ] **Step 4: Verify in preview**

Open a day **with** events → each event shows "Add to calendar · Directions · Tell a neighbor"; clicking Add to calendar downloads an `.ics`. Open a day **with no** events → "+ Add something on this day" appears and navigates to the Add screen with that date prefilled.

- [ ] **Step 5: Commit**

```bash
git add "apps/mobile/src/app/(tabs)/calendar.tsx"
git commit -m "feat(mobile): event actions + empty-day add in calendar day sheet"
```

---

### Task 9: Event density dots from real counts

**Files:**
- Modify: `apps/mobile/src/app/(tabs)/calendar.tsx` (`DayCell`, `WeekRow`, `MonthBlock`, `Calendar` — replace the `eventDates: Set<string>` plumbing with `counts: Record<string, number>`)

**Interfaces:**
- Consumes: `api.getMonthEventCounts` (Task 2).
- Produces: each day cell shows up to 3 moss dots, then a `+` for 4+; counts are real.

- [ ] **Step 1: Fetch counts instead of a date Set**

In `Calendar`, replace the `eventDates` state and its effect:
```ts
  const [counts, setCounts] = useState<Record<string, number>>({})
```
```ts
  useEffect(() => {
    let alive = true
    Promise.all(months.map((m) => api.getMonthEventCounts(m.year, m.month).catch(() => ({} as Record<string, number>))))
      .then((res) => { if (alive) setCounts(Object.assign({}, ...res)) })
    return () => { alive = false }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])
```

- [ ] **Step 2: Thread `counts` through the prop chain**

In `MonthBlock`, `WeekRow`, and `DayCell` prop types and JSX, replace every `eventDates: Set<string>` with `counts: Record<string, number>` and pass `counts` where `eventDates` was passed (in `Calendar`'s `<MonthBlock ... counts={counts} />`, `MonthBlock`'s `<WeekRow ... counts={counts} />`, and `WeekRow`'s `<DayCell ... counts={counts} />`).

- [ ] **Step 3: Render density in `DayCell`**

In `DayCell`, replace `const hasEvent = eventDates.has(date)` with `const count = counts[date] ?? 0`, and replace the single reserved-dot `View` (the `width: 5, height: 5 …` block) with:
```tsx
      <View style={{ flexDirection: 'row', alignItems: 'center', gap: 2, height: 5, marginTop: 4 }}>
        {!isSelected && Array.from({ length: Math.min(count, 3) }).map((_, i) => (
          <View key={i} style={{ width: 5, height: 5, borderRadius: 2.5, backgroundColor: C.moss500 }} />
        ))}
        {!isSelected && count > 3 && (
          <Text style={{ fontFamily: F.mono, fontSize: 9, lineHeight: 9, color: C.moss500 }}>+</Text>
        )}
      </View>
```

- [ ] **Step 4: Typecheck + bundle**

```bash
npx tsc --noEmit -p tsconfig.json && npx expo export --platform web
```
Expected: both pass.

- [ ] **Step 5: Verify in preview**

A day with multiple events shows multiple dots (4+ shows `+`); a one-event day shows one dot; empty days show none. Counts match real data — cross-check one day against its sheet.

- [ ] **Step 6: Commit**

```bash
git add "apps/mobile/src/app/(tabs)/calendar.tsx"
git commit -m "feat(mobile): real event-density dots on calendar days"
```

---

### Task 10: "This weekend" chip + "Today" jump

**Files:**
- Modify: `apps/mobile/src/app/(tabs)/calendar.tsx` (`Calendar` — header + `ScrollView`)

**Interfaces:**
- Consumes: existing `selectDate`, `months`, `todayYmd`.
- Produces: a header with two pills; "This weekend" scrolls to today's month and opens Saturday's sheet; "Today" appears after scrolling past today and snaps back.

- [ ] **Step 1: Add scroll ref + offset tracking**

In `Calendar`, add:
```ts
  const scrollRef = useRef<ScrollView>(null)
  const offsets = useRef<Record<string, number>>({})
  const [showToday, setShowToday] = useState(false)
  const todayKey = `${today.getFullYear()}-${today.getMonth() + 1}`

  const upcomingSaturday = (() => {
    const d = new Date(today)
    d.setDate(d.getDate() + ((6 - d.getDay() + 7) % 7)) // today if already Sat
    return localDate(d)
  })()

  const jumpToToday = () => scrollRef.current?.scrollTo({ y: Math.max(0, (offsets.current[todayKey] ?? 0) - 8), animated: true })
  const goThisWeekend = () => { jumpToToday(); selectDate(upcomingSaturday) }
```
(`localDate` is already imported.)

- [ ] **Step 2: Wire the ScrollView**

Give the `ScrollView` the ref + scroll handler:
```tsx
        <ScrollView
          ref={scrollRef}
          scrollEventThrottle={16}
          onScroll={(e) => setShowToday(e.nativeEvent.contentOffset.y > (offsets.current[todayKey] ?? 0) + 120)}
          contentContainerStyle={{ paddingHorizontal: 20, paddingBottom: 120 }}
        >
```
And capture each month's offset by wrapping each `<MonthBlock>` with an `onLayout` View — change the `months.map` to:
```tsx
          {months.map((m) => (
            <View key={`${m.year}-${m.month}`} onLayout={(e) => { offsets.current[`${m.year}-${m.month}`] = e.nativeEvent.layout.y }}>
              <MonthBlock
                year={m.year} month={m.month} counts={counts} selectedDate={selectedDate} todayYmd={todayYmd}
                onSelect={selectDate} progress={progress} onExpandStart={onExpandStart} onAbort={onAbort} onCommit={onCommit}
              />
            </View>
          ))}
```

- [ ] **Step 3: Add the header pills**

Directly under the `"What's coming up?"` title `Text`, add:
```tsx
        <View style={{ flexDirection: 'row', gap: 8, paddingHorizontal: 20, marginBottom: 12 }}>
          <Pressable onPress={goThisWeekend} style={({ pressed }) => ({ paddingVertical: 7, paddingHorizontal: 14, borderRadius: 18, backgroundColor: C.moss700, opacity: pressed ? 0.85 : 1 })}>
            <Text style={{ fontFamily: F.sansMed, fontSize: 13, color: C.paper }}>This weekend</Text>
          </Pressable>
          {showToday && (
            <Pressable onPress={jumpToToday} style={({ pressed }) => ({ paddingVertical: 7, paddingHorizontal: 14, borderRadius: 18, borderWidth: 1, borderColor: HAIRLINE, opacity: pressed ? 0.6 : 1 })}>
              <Text style={{ fontFamily: F.sansMed, fontSize: 13, color: C.ink2 }}>Today</Text>
            </Pressable>
          )}
        </View>
```

- [ ] **Step 4: Typecheck + bundle**

```bash
npx tsc --noEmit -p tsconfig.json && npx expo export --platform web
```
Expected: both pass.

- [ ] **Step 5: Verify in preview**

"This weekend" scrolls to the current month and opens Saturday's sheet. Scroll down a few months → "Today" pill appears; tapping it snaps back to today's month and the pill disappears.

- [ ] **Step 6: Commit**

```bash
git add "apps/mobile/src/app/(tabs)/calendar.tsx"
git commit -m "feat(mobile): this-weekend chip + today jump on calendar"
```

---

## Final verification

From `apps/mobile/`:
```bash
npx tsc --noEmit -p tsconfig.json
npx expo export --platform web
node --experimental-strip-types src/lib/ics.check.ts
```
All three pass, and a preview pass confirms: density dots match real counts; This-weekend + Today work; the day sheet's three actions fire (add-to-calendar produces an .ics, Directions opens maps, Tell-a-neighbor opens the share sheet); empty-day add deep-links with the date prefilled. Clears the on-brand bar (calm, real counts, no notifications).
