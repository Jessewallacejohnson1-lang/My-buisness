import { useEffect, useRef } from 'react'
import { Pressable, Text, View, type TextStyle } from 'react-native'
import Animated, {
  Easing, useAnimatedStyle, useReducedMotion, useSharedValue, withRepeat, withSequence, withSpring, withTiming,
} from 'react-native-reanimated'
import { CheckIcon, PinIcon, PlusIcon, SunArcIcon } from './icons'
import { openInMaps, copyAddress } from '../lib/maps'
import { minutesOf, nowMinutes, clockLabel } from '../lib/time'
import { C, F, HAIRLINE, CARD_SHADOW, GRAPH, RADIUS } from '../theme'

const TAB: TextStyle['fontVariant'] = ['tabular-nums']

// Rail geometry — the gutter is the almanac's left margin (mono times), the lane
// carries the spine + node, the body carries the entry.
const GUTTER = 52
const LANE = 22
const NODE_TOP = 25 // node center, aligned to the first line of the time/title

/** A timeline entry. Today's rows carry rsvp/club fields; other days are lighter. */
export type TimelineRow = {
  id: string
  title: string
  start_time: string | null
  location: string | null
  going_count: number
  rsvpd?: boolean
  club_name?: string | null
  from_joined_club?: boolean
  event_date?: string
}

type Item =
  | { kind: 'daypart'; label: string; key: string }
  | { kind: 'now'; label: string; key: string }
  | { kind: 'event'; row: TimelineRow; past: boolean; key: string }

const daypartOf = (mins: number) => (mins >= 24 * 60 ? 'ALL DAY' : mins < 12 * 60 ? 'MORNING' : mins < 17 * 60 ? 'AFTERNOON' : 'EVENING')

/** The day's schedule — a printed-agenda rail. One lifted paper card holding a
 *  time gutter, a hairline spine with punched nodes, and the day's entries. */
export function DayTimeline({
  title,
  rows,
  interactive,
  loading,
  comingUp,
  onToggleRsvp,
  onSelectDate,
  onAdd,
}: {
  title: string
  rows: TimelineRow[]
  interactive: boolean
  loading: boolean
  comingUp: TimelineRow[]
  onToggleRsvp: (row: TimelineRow) => void
  onSelectDate: (date: string) => void
  onAdd: () => void
}) {
  const reduce = useReducedMotion()
  const nowM = nowMinutes()

  // Live "now" marker sits before the first upcoming timed event — but only when
  // there is BOTH a past and an upcoming event, so it never pins to an edge.
  let markerBeforeId: string | null = null
  if (interactive && rows.length > 0) {
    const firstUpcoming = rows.find((r) => r.start_time && minutesOf(r.start_time) > nowM)
    const hasPast = rows.some((r) => r.start_time && minutesOf(r.start_time) <= nowM)
    if (firstUpcoming && hasPast) markerBeforeId = firstUpcoming.id
  }

  // Dayparts only earn their labels on a full day (≥4 timed entries) — sparse days,
  // and all-day-only days, stay quiet.
  const showDayparts = rows.filter((r) => r.start_time).length >= 4
  const items: Item[] = []
  let lastPart = ''
  for (const r of rows) {
    if (markerBeforeId && r.id === markerBeforeId) {
      items.push({ kind: 'now', label: `NOW · ${clockLabel(nowM)}`, key: 'now' })
    }
    if (showDayparts) {
      const part = daypartOf(minutesOf(r.start_time))
      if (part !== lastPart) {
        items.push({ kind: 'daypart', label: part, key: `dp-${part}` })
        lastPart = part
      }
    }
    const past = interactive && !!r.start_time && minutesOf(r.start_time) <= nowM
    items.push({ kind: 'event', row: r, past, key: r.id })
  }

  const eventPositions = items.map((it, i) => (it.kind === 'event' ? i : -1)).filter((i) => i >= 0)
  const firstNode = eventPositions[0] ?? -1
  const lastNode = eventPositions[eventPositions.length - 1] ?? -1

  return (
    <View style={{ marginHorizontal: 20, borderRadius: RADIUS.lg, backgroundColor: C.paper, borderWidth: 1, borderColor: HAIRLINE, paddingVertical: 6, ...CARD_SHADOW }}>
      {/* section header */}
      <View style={{ flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', paddingHorizontal: 18, paddingTop: 14, paddingBottom: 6 }}>
        <Text style={{ fontWeight: F.mono, fontSize: 10.5, color: C.ink3, letterSpacing: 1.6 }}>{title}</Text>
        {rows.length > 0 && (
          <Text style={{ fontWeight: F.mono, fontSize: 9, color: C.ink3, letterSpacing: 0.8 }}>
            NO. <Text style={{ fontWeight: F.monoMed, fontSize: 13, color: C.ink, fontVariant: TAB }}>{rows.length}</Text>
          </Text>
        )}
      </View>

      {loading ? (
        <View style={{ paddingHorizontal: 16, paddingBottom: 6 }}>
          {[0, 1, 2].map((i) => (
            <SkeletonRow key={i} last={i === 2} />
          ))}
        </View>
      ) : rows.length === 0 ? (
        <ClearDay interactive={interactive} comingUp={comingUp} onAdd={onAdd} onSelectDate={onSelectDate} />
      ) : (
        <View style={{ paddingHorizontal: 16 }}>
          {items.map((it, p) => {
            const showTop = p > firstNode && p <= lastNode
            const showBottom = p >= firstNode && p < lastNode
            if (it.kind === 'daypart') return <DaypartRow key={it.key} label={it.label} showTop={showTop} showBottom={showBottom} />
            if (it.kind === 'now') return <NowRow key={it.key} label={it.label} reduce={reduce} />
            const nextIsEvent = items[p + 1]?.kind === 'event'
            return (
              <EventRailRow
                key={it.key}
                row={it.row}
                past={it.past}
                interactive={interactive}
                divider={nextIsEvent}
                showTop={showTop}
                showBottom={showBottom}
                reduce={reduce}
                onToggleRsvp={onToggleRsvp}
              />
            )
          })}
        </View>
      )}
    </View>
  )
}

// — Spine segments in the node lane (hairline; masked at the node by a paper halo) —
function Spine({ showTop, showBottom }: { showTop: boolean; showBottom: boolean }) {
  return (
    <>
      {showTop && <View style={{ position: 'absolute', left: (LANE - 1) / 2, top: 0, height: NODE_TOP, width: 1, backgroundColor: HAIRLINE }} />}
      {showBottom && <View style={{ position: 'absolute', left: (LANE - 1) / 2, top: NODE_TOP, bottom: 0, width: 1, backgroundColor: HAIRLINE }} />}
    </>
  )
}

function Node({ variant, reduce }: { variant: 'going' | 'ring' | 'past' | 'future'; reduce: boolean }) {
  const scale = useSharedValue(1)
  const first = useRef(true)
  useEffect(() => {
    if (first.current) {
      first.current = false
      return
    }
    if (reduce) return
    scale.value = withSequence(withTiming(1.18, { duration: 140, easing: Easing.out(Easing.quad) }), withSpring(1, { damping: 14, stiffness: 200 }))
  }, [variant, reduce, scale])
  const aStyle = useAnimatedStyle(() => ({ transform: [{ scale: scale.value }] }))

  const inner =
    variant === 'going' ? (
      { width: 11, height: 11, borderRadius: 5.5, backgroundColor: C.moss700 }
    ) : variant === 'past' ? (
      { width: 11, height: 11, borderRadius: 5.5, backgroundColor: 'rgba(0,0,0,0.14)' }
    ) : (
      { width: 11, height: 11, borderRadius: 5.5, backgroundColor: C.paper, borderWidth: 1.5, borderColor: variant === 'ring' ? 'rgba(42,42,40,0.22)' : 'rgba(130,128,119,0.55)' }
    )

  return (
    // paper halo masks the spine passing behind the dot ("punched" schedule)
    <Animated.View style={[{ position: 'absolute', top: NODE_TOP - 8, left: (LANE - 16) / 2, width: 16, height: 16, borderRadius: 8, backgroundColor: C.paper, alignItems: 'center', justifyContent: 'center' }, aStyle]}>
      <View style={inner} />
    </Animated.View>
  )
}

function EventRailRow({
  row, past, interactive, divider, showTop, showBottom, reduce, onToggleRsvp,
}: {
  row: TimelineRow
  past: boolean
  interactive: boolean
  divider: boolean
  showTop: boolean
  showBottom: boolean
  reduce: boolean
  onToggleRsvp: (row: TimelineRow) => void
}) {
  const variant = past ? 'past' : interactive ? (row.rsvpd ? 'going' : 'ring') : 'future'
  return (
    <View style={{ flexDirection: 'row', opacity: past ? 0.45 : 1 }}>
      {/* gutter — mono time, right-aligned */}
      <View style={{ width: GUTTER, paddingTop: NODE_TOP - 8, alignItems: 'flex-end', paddingRight: 4 }}>
        {row.start_time ? (
          <Text style={{ fontWeight: F.mono, fontSize: 12, color: C.ink2, fontVariant: TAB }}>{row.start_time}</Text>
        ) : (
          <Text style={{ fontWeight: F.mono, fontSize: 11, color: C.ink3 }}>all day</Text>
        )}
      </View>

      {/* lane — spine + node */}
      <View style={{ width: LANE }}>
        <Spine showTop={showTop} showBottom={showBottom} />
        <Node variant={variant} reduce={reduce} />
      </View>

      {/* body — entry + RSVP affordance */}
      <View style={{ flex: 1, flexDirection: 'row', alignItems: 'flex-start', paddingVertical: 15, paddingLeft: 4, borderBottomWidth: divider ? 1 : 0, borderBottomColor: HAIRLINE }}>
        <View style={{ flex: 1, minWidth: 0 }}>
          <Text style={{ fontWeight: F.sansSemi, fontSize: 15, color: C.ink, lineHeight: 20 }}>{row.title}</Text>
          {!!row.location && (
            <Pressable
              onPress={() => openInMaps(row.location!)}
              onLongPress={() => copyAddress(row.location!)}
              style={{ flexDirection: 'row', alignItems: 'center', gap: 4, marginTop: 3, alignSelf: 'flex-start' }}
            >
              <PinIcon size={12} color={C.sky600} />
              <Text style={{ fontWeight: F.sans, fontSize: 13, color: C.sky600, textDecorationLine: 'underline' }}>{row.location}</Text>
            </Pressable>
          )}
          <View style={{ flexDirection: 'row', alignItems: 'center', flexWrap: 'wrap', gap: 8, marginTop: 7 }}>
            {!!row.club_name && (
              <View style={{ flexDirection: 'row', alignItems: 'center', gap: 5, paddingVertical: 2, paddingHorizontal: 8, borderRadius: 11, backgroundColor: row.from_joined_club ? 'rgba(0,0,0,0.06)' : C.paper100 }}>
                {row.from_joined_club && <View style={{ width: 5, height: 5, borderRadius: 2.5, backgroundColor: C.moss700 }} />}
                <Text style={{ fontWeight: F.sansMed, fontSize: 11, color: row.from_joined_club ? C.moss700 : C.ink2 }}>{row.club_name}</Text>
              </View>
            )}
            <Text style={{ fontWeight: F.mono, fontSize: 11, color: C.ink2, fontVariant: TAB }}>{row.going_count} going</Text>
          </View>
        </View>

        {interactive ? (
          <Pressable
            onPress={() => onToggleRsvp(row)}
            style={({ pressed }) => ({
              marginTop: 1, marginLeft: 8, paddingHorizontal: 15, paddingVertical: 6, borderRadius: 20,
              borderWidth: 1.5, borderColor: row.rsvpd ? 'transparent' : 'rgba(0,0,0,0.14)',
              backgroundColor: row.rsvpd ? C.moss700 : 'transparent',
              flexDirection: 'row', alignItems: 'center', gap: 5, opacity: pressed ? 0.85 : 1,
            })}
          >
            <Text style={{ fontWeight: F.sansMed, fontSize: 13, color: row.rsvpd ? C.paper : C.ink2 }}>{row.rsvpd ? 'Going' : 'Join'}</Text>
            {row.rsvpd && <CheckIcon size={13} color={C.paper} />}
          </Pressable>
        ) : (
          <Text style={{ fontWeight: F.mono, fontSize: 11, color: C.ink3, marginTop: 4, marginLeft: 8 }}>upcoming</Text>
        )}
      </View>
    </View>
  )
}

function DaypartRow({ label, showTop, showBottom }: { label: string; showTop: boolean; showBottom: boolean }) {
  return (
    <View style={{ flexDirection: 'row', minHeight: 30 }}>
      <View style={{ width: GUTTER }} />
      <View style={{ width: LANE }}>
        {(showTop || showBottom) && <View style={{ position: 'absolute', left: (LANE - 1) / 2, top: 0, bottom: 0, width: 1, backgroundColor: HAIRLINE }} />}
      </View>
      <View style={{ flex: 1, justifyContent: 'flex-end', paddingLeft: 4, paddingTop: 12, paddingBottom: 4 }}>
        <Text style={{ fontWeight: F.mono, fontSize: 9.5, color: C.ink3, letterSpacing: 1.6 }}>{label}</Text>
      </View>
    </View>
  )
}

function NowRow({ label, reduce }: { label: string; reduce: boolean }) {
  const pulse = useSharedValue(1)
  useEffect(() => {
    if (reduce) return
    pulse.value = withRepeat(withTiming(0.55, { duration: 1100, easing: Easing.inOut(Easing.ease) }), -1, true)
  }, [reduce, pulse])
  const dotStyle = useAnimatedStyle(() => ({ opacity: pulse.value }))
  return (
    <View style={{ flexDirection: 'row', alignItems: 'center', height: 26 }}>
      <View style={{ width: GUTTER, alignItems: 'flex-end', paddingRight: 4 }}>
        <Text style={{ fontWeight: F.mono, fontSize: 9.5, color: GRAPH.amber, letterSpacing: 0.4, fontVariant: TAB }}>{label}</Text>
      </View>
      <View style={{ width: LANE, alignItems: 'center', justifyContent: 'center' }}>
        <View style={{ position: 'absolute', left: (LANE - 1) / 2, top: 0, bottom: 0, width: 1, backgroundColor: HAIRLINE }} />
        <Animated.View style={[{ width: 5, height: 5, borderRadius: 2.5, backgroundColor: GRAPH.amber }, dotStyle]} />
      </View>
      <View style={{ flex: 1, marginLeft: 4, height: 1, backgroundColor: GRAPH.amber, opacity: 0.5 }} />
    </View>
  )
}

function SkeletonRow({ last }: { last?: boolean }) {
  return (
    <View style={{ flexDirection: 'row' }}>
      <View style={{ width: GUTTER, paddingTop: NODE_TOP - 6, alignItems: 'flex-end', paddingRight: 4 }}>
        <View style={{ width: 30, height: 12, borderRadius: 4, backgroundColor: C.paper200 }} />
      </View>
      <View style={{ width: LANE }}>
        <View style={{ position: 'absolute', left: (LANE - 16) / 2, top: NODE_TOP - 8, width: 16, height: 16, borderRadius: 8, backgroundColor: C.paper, alignItems: 'center', justifyContent: 'center' }}>
          <View style={{ width: 11, height: 11, borderRadius: 5.5, backgroundColor: C.paper, borderWidth: 1.5, borderColor: 'rgba(42,42,40,0.10)' }} />
        </View>
      </View>
      <View style={{ flex: 1, paddingVertical: 15, paddingLeft: 4, borderBottomWidth: last ? 0 : 1, borderBottomColor: HAIRLINE, gap: 9 }}>
        <View style={{ width: '72%', height: 15, borderRadius: 4, backgroundColor: C.paper200 }} />
        <View style={{ width: '42%', height: 11, borderRadius: 4, backgroundColor: C.paper200 }} />
      </View>
    </View>
  )
}

function ClearDay({
  interactive, comingUp, onAdd, onSelectDate,
}: {
  interactive: boolean
  comingUp: TimelineRow[]
  onAdd: () => void
  onSelectDate: (date: string) => void
}) {
  const upcoming = interactive ? comingUp.slice(0, 3) : []
  return (
    <View style={{ paddingHorizontal: 20, paddingTop: 6, paddingBottom: 20 }}>
      <View style={{ alignItems: 'center', paddingVertical: 10, gap: 10 }}>
        <SunArcIcon size={34} color={C.ink3} />
        <Text style={{ fontWeight: F.display, fontSize: 20, color: C.ink, letterSpacing: -0.3 }}>
          {interactive ? 'A clear day in St. Joe' : 'Nothing on this day'}
        </Text>
        <Text style={{ fontWeight: F.sans, fontSize: 13, color: C.ink2, lineHeight: 20, textAlign: 'center' }}>
          {interactive
            ? 'Nothing on the schedule yet. Start something — a walk, a coffee, a hello.'
            : 'No gatherings here yet.'}
        </Text>
        {interactive && (
          <Pressable
            onPress={onAdd}
            style={({ pressed }) => ({ flexDirection: 'row', alignItems: 'center', gap: 7, paddingVertical: 11, paddingHorizontal: 18, borderRadius: 20, backgroundColor: C.moss700, opacity: pressed ? 0.85 : 1, marginTop: 2 })}
          >
            <Text style={{ fontWeight: F.sansSemi, fontSize: 13.5, color: C.paper }}>Add an event</Text>
            <PlusIcon size={14} color={C.paper} />
          </Pressable>
        )}
      </View>

      {upcoming.length > 0 && (
        <>
          <View style={{ height: 1, backgroundColor: HAIRLINE, marginTop: 14 }} />
          <Text style={{ fontWeight: F.mono, fontSize: 10.5, color: C.ink3, letterSpacing: 1.6, marginTop: 14, marginBottom: 4 }}>COMING UP</Text>
          {upcoming.map((r) => (
            <Pressable
              key={r.id}
              onPress={() => r.event_date && onSelectDate(r.event_date)}
              style={({ pressed }) => ({ flexDirection: 'row', alignItems: 'center', gap: 12, paddingVertical: 10, opacity: pressed ? 0.6 : 1 })}
            >
              <Text style={{ width: 58, fontWeight: F.mono, fontSize: 11, color: C.ink3, fontVariant: TAB }}>{comingUpLabel(r)}</Text>
              <Text numberOfLines={1} style={{ flex: 1, fontWeight: F.sansSemi, fontSize: 14, color: C.ink }}>{r.title}</Text>
              <Text style={{ fontWeight: F.mono, fontSize: 11, color: C.ink2, fontVariant: TAB }}>{r.going_count} going</Text>
            </Pressable>
          ))}
        </>
      )}
    </View>
  )
}

function comingUpLabel(r: TimelineRow): string {
  if (!r.event_date) return r.start_time || ''
  const [y, m, d] = r.event_date.split('-').map(Number)
  const wd = new Date(y, m - 1, d).toLocaleDateString('en-US', { weekday: 'short' })
  return `${wd} ${r.start_time || ''}`.trim()
}
