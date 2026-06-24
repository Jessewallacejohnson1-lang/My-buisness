'use client'

import { useCallback, useEffect, useRef, useState } from 'react'
import {
  getTodayEvents,
  getEventsByDate,
  getMonthEventDates,
  addEvent,
  rsvpEvent,
  unRsvpEvent,
  getCurrentUser,
  isAdminEmail,
  getTodayQuest,
  getQuestCompletionCount,
  hasUserCompletedQuest,
  completeQuest,
  setQuest,
  type TimelineEvent,
  type NewEventInput,
  type DailyQuest,
} from '@/lib/community'
import { haptic } from '@/lib/haptics'

type Tab = 'timeline' | 'calendar' | 'add' | 'quest'

const HAIRLINE = '1px solid rgba(0,0,0,0.07)'

// Shared form styles (Add Event + admin quest setter)
const fieldStyle: React.CSSProperties = {
  width: '100%',
  padding: '11px 13px',
  borderRadius: 8,
  border: HAIRLINE,
  background: 'var(--color-paper)',
  fontSize: 15,
  color: 'var(--color-ink)',
  fontFamily: 'var(--font-sans)',
  outline: 'none',
  boxSizing: 'border-box',
}
const labelStyle: React.CSSProperties = {
  fontSize: 11,
  color: 'var(--color-ink-3)',
  textTransform: 'uppercase',
  letterSpacing: '0.08em',
  marginBottom: 6,
  display: 'block',
  fontFamily: 'var(--font-sans)',
}

// ── Icons ────────────────────────────────────────────────────────────────────

function TabIcon({ id, active }: { id: Tab; active: boolean }) {
  const c = active ? 'var(--color-moss-700)' : 'var(--color-ink-3)'
  const sp = {
    fill: 'none' as const,
    stroke: c,
    strokeWidth: id === 'add' ? '2.1' : '1.7',
    strokeLinecap: 'round' as const,
    strokeLinejoin: 'round' as const,
  }
  if (id === 'timeline')
    return (
      <svg width="22" height="22" viewBox="0 0 24 24" {...sp} aria-hidden>
        <line x1="8" y1="6" x2="21" y2="6" />
        <line x1="8" y1="12" x2="21" y2="12" />
        <line x1="8" y1="18" x2="21" y2="18" />
        <line x1="3" y1="6" x2="3.01" y2="6" strokeWidth="2.5" strokeLinecap="round" />
        <line x1="3" y1="12" x2="3.01" y2="12" strokeWidth="2.5" strokeLinecap="round" />
        <line x1="3" y1="18" x2="3.01" y2="18" strokeWidth="2.5" strokeLinecap="round" />
      </svg>
    )
  if (id === 'calendar')
    return (
      <svg width="22" height="22" viewBox="0 0 24 24" {...sp} aria-hidden>
        <rect x="3" y="4" width="18" height="18" rx="2" />
        <line x1="16" y1="2" x2="16" y2="6" />
        <line x1="8" y1="2" x2="8" y2="6" />
        <line x1="3" y1="10" x2="21" y2="10" />
      </svg>
    )
  if (id === 'add')
    return (
      <svg width="22" height="22" viewBox="0 0 24 24" {...sp} aria-hidden>
        <circle cx="12" cy="12" r="9" />
        <line x1="12" y1="8" x2="12" y2="16" />
        <line x1="8" y1="12" x2="16" y2="12" />
      </svg>
    )
  // quest
  return (
    <svg width="22" height="22" viewBox="0 0 24 24" {...sp} aria-hidden>
      <polygon points="12 2 15.09 8.26 22 9.27 17 14.14 18.18 21.02 12 17.77 5.82 21.02 7 14.14 2 9.27 8.91 8.26 12 2" />
    </svg>
  )
}

function CheckIcon({ size = 14 }: { size?: number }) {
  return (
    <svg
      width={size}
      height={size}
      viewBox="0 0 14 14"
      fill="none"
      stroke="currentColor"
      strokeWidth="2"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden
      style={{ display: 'inline-block', verticalAlign: 'middle', marginLeft: 5 }}
    >
      <polyline points="2 7 5.5 10.5 12 3.5" />
    </svg>
  )
}

// ── Time parsing (only used to place the "now" divider) ───────────────────────

/** Parse a free-text display time like "7am", "5:30pm", "noon" to minutes-from-midnight, or null. */
function parseTime(s: string | null): number | null {
  if (!s) return null
  const t = s.trim().toLowerCase()
  if (t.includes('noon')) return 12 * 60
  if (t.includes('midnight')) return 0
  const m = t.match(/(\d{1,2})(?::(\d{2}))?\s*(a\.?m\.?|p\.?m\.?)?/)
  if (!m) return null
  let h = parseInt(m[1], 10)
  const min = m[2] ? parseInt(m[2], 10) : 0
  const ap = m[3] ? m[3].replace(/\./g, '') : ''
  if (ap === 'pm' && h < 12) h += 12
  if (ap === 'am' && h === 12) h = 0
  return h * 60 + min
}

// ── Event row (printed-paper agenda row; reused by Timeline + Calendar sheet) ──

function EventRow({
  event,
  onRsvp,
  last,
}: {
  event: TimelineEvent
  onRsvp: (id: string, rsvpd: boolean) => void
  last?: boolean
}) {
  return (
    <div
      className="rise"
      style={{
        display: 'flex',
        gap: 14,
        alignItems: 'flex-start',
        padding: '15px 0',
        borderBottom: last ? 'none' : HAIRLINE,
      }}
    >
      <div style={{ width: 50, flexShrink: 0, paddingTop: 2 }}>
        {event.start_time && (
          <span
            className="font-mono"
            style={{ fontSize: 12, color: 'var(--color-ink-3)', fontVariantNumeric: 'tabular-nums', letterSpacing: '0.01em' }}
          >
            {event.start_time}
          </span>
        )}
      </div>

      <div style={{ flex: 1, minWidth: 0 }}>
        <p className="font-sans" style={{ fontSize: 15, fontWeight: 600, color: 'var(--color-ink)', lineHeight: 1.3 }}>
          {event.title}
        </p>
        {event.location && (
          <p className="font-sans" style={{ fontSize: 13, color: 'var(--color-ink-2)', marginTop: 2 }}>
            {event.location}
          </p>
        )}
        <p className="font-mono" style={{ fontSize: 11, color: 'var(--color-ink-3)', marginTop: 7 }}>
          <span style={{ fontVariantNumeric: 'tabular-nums' }}>{event.going_count}</span> going
        </p>
      </div>

      <button
        onClick={() => { haptic('tap'); onRsvp(event.id, event.rsvpd) }}
        className="press hygge-tap"
        aria-pressed={event.rsvpd}
        style={{
          flexShrink: 0,
          marginTop: 1,
          padding: '6px 15px',
          borderRadius: 20,
          border: event.rsvpd ? '1.5px solid transparent' : '1.5px solid rgba(0,0,0,0.14)',
          background: event.rsvpd ? 'var(--color-moss-700)' : 'transparent',
          color: event.rsvpd ? 'var(--color-paper)' : 'var(--color-ink-2)',
          fontSize: 13,
          fontWeight: 500,
          cursor: 'pointer',
          fontFamily: 'var(--font-sans)',
          display: 'flex',
          alignItems: 'center',
        }}
      >
        {event.rsvpd ? <>Going<CheckIcon /></> : 'Join'}
      </button>
    </div>
  )
}

/** Shared optimistic RSVP toggler over a setEvents state updater. */
function useRsvpHandler(setList: React.Dispatch<React.SetStateAction<TimelineEvent[]>>) {
  return useCallback(
    async (id: string, rsvpd: boolean) => {
      setList((prev) =>
        prev.map((e) => (e.id === id ? { ...e, rsvpd: !rsvpd, going_count: e.going_count + (rsvpd ? -1 : 1) } : e))
      )
      try {
        if (rsvpd) await unRsvpEvent(id)
        else await rsvpEvent(id)
      } catch {
        setList((prev) =>
          prev.map((e) => (e.id === id ? { ...e, rsvpd, going_count: e.going_count + (rsvpd ? 1 : -1) } : e))
        )
      }
    },
    [setList]
  )
}

// ── Timeline tab ─────────────────────────────────────────────────────────────

function TimelineTab() {
  const [events, setEvents] = useState<TimelineEvent[]>([])
  const [loading, setLoading] = useState(true)
  const handleRsvp = useRsvpHandler(setEvents)

  useEffect(() => {
    getTodayEvents().then(setEvents).finally(() => setLoading(false))
  }, [])

  if (loading) {
    return (
      <div style={{ padding: '48px 0', textAlign: 'center', color: 'var(--color-ink-3)', fontFamily: 'var(--font-sans)', fontSize: 14 }}>
        Loading…
      </div>
    )
  }

  const now = new Date()
  const dateLine = now.toLocaleDateString('en-US', { weekday: 'long', month: 'long', day: 'numeric' })

  // Find where "now" falls between ordered events (only split when there's a before AND after).
  const nowMin = now.getHours() * 60 + now.getMinutes()
  let nowIndex = -1
  for (let i = 0; i < events.length; i++) {
    const t = parseTime(events[i].start_time)
    if (t !== null && t >= nowMin) { nowIndex = i; break }
  }
  const showNow = nowIndex > 0 && nowIndex < events.length

  return (
    <div style={{ padding: '20px 18px 0' }}>
      {/* Dateline — the editorial anchor */}
      <p className="font-sans" style={{ fontSize: 11, color: 'var(--color-ink-3)', textTransform: 'uppercase', letterSpacing: '0.16em', marginBottom: 3 }}>
        Today
      </p>
      <h1 className="font-display" style={{ fontSize: 24, color: 'var(--color-ink)', lineHeight: 1.1, marginBottom: 12 }}>
        {dateLine}
      </h1>

      {events.length === 0 ? (
        <div style={{ padding: '52px 0 64px', textAlign: 'center' }}>
          <p className="font-sans" style={{ fontSize: 15, color: 'var(--color-ink-2)' }}>Nothing on the calendar today.</p>
          <p className="font-sans" style={{ fontSize: 14, color: 'var(--color-ink-3)', marginTop: 6 }}>Add something for the neighborhood.</p>
        </div>
      ) : (
        <div style={{ borderTop: HAIRLINE }}>
          {events.map((e, i) => (
            <div key={e.id}>
              {showNow && i === nowIndex && (
                <div style={{ display: 'flex', alignItems: 'center', gap: 8, padding: '11px 0 9px' }}>
                  <span className="font-sans" style={{ fontSize: 9, fontWeight: 600, letterSpacing: '0.14em', color: 'var(--color-moss-700)' }}>NOW</span>
                  <span style={{ flex: 1, height: 1, background: 'var(--color-moss-600)', opacity: 0.45 }} />
                </div>
              )}
              <EventRow event={e} onRsvp={handleRsvp} last={i === events.length - 1} />
            </div>
          ))}
        </div>
      )}
    </div>
  )
}

// ── Calendar tab ─────────────────────────────────────────────────────────────

function CalendarTab() {
  const today = new Date()
  const [year, setYear] = useState(today.getFullYear())
  const [month, setMonth] = useState(today.getMonth() + 1) // 1-indexed
  const [selectedDate, setSelectedDate] = useState<string | null>(null)
  const [eventDates, setEventDates] = useState<Set<string>>(new Set())
  const [dayEvents, setDayEvents] = useState<TimelineEvent[]>([])
  const [sheetOpen, setSheetOpen] = useState(false)
  const [loadingDays, setLoadingDays] = useState(true)
  const [loadingEvents, setLoadingEvents] = useState(false)
  const requestedDateRef = useRef<string | null>(null)
  const handleRsvp = useRsvpHandler(setDayEvents)

  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect
    setLoadingDays(true)
    getMonthEventDates(year, month)
      .then((dates) => setEventDates(new Set(dates)))
      .finally(() => setLoadingDays(false))
  }, [year, month])

  const selectDate = async (ymd: string) => {
    setSelectedDate(ymd)
    setSheetOpen(true)
    setLoadingEvents(true)
    requestedDateRef.current = ymd
    const evs = await getEventsByDate(ymd)
    if (requestedDateRef.current === ymd) {
      setDayEvents(evs)
      setLoadingEvents(false)
    }
  }

  // Build month grid
  const firstDay = new Date(year, month - 1, 1).getDay() // 0=Sun
  const daysInMonth = new Date(year, month, 0).getDate()
  const cells: (number | null)[] = [
    ...Array(firstDay).fill(null),
    ...Array.from({ length: daysInMonth }, (_, i) => i + 1),
  ]
  while (cells.length % 7 !== 0) cells.push(null)

  const monthLabel = new Date(year, month - 1, 1).toLocaleDateString('en-US', { month: 'long', year: 'numeric' })
  const todayYmd = `${today.getFullYear()}-${String(today.getMonth() + 1).padStart(2, '0')}-${String(today.getDate()).padStart(2, '0')}`

  const chevron = (dir: 'prev' | 'next') => (
    <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" aria-hidden>
      <polyline points={dir === 'prev' ? '15 18 9 12 15 6' : '9 18 15 12 9 6'} />
    </svg>
  )

  return (
    <div style={{ padding: '20px 18px' }}>
      {/* Month navigation */}
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 14 }}>
        <h1 className="font-display" style={{ fontSize: 22, color: 'var(--color-ink)' }}>{monthLabel}</h1>
        <div style={{ display: 'flex', gap: 2 }}>
          <button
            onClick={() => { if (month === 1) { setYear((y) => y - 1); setMonth(12) } else setMonth((m) => m - 1) }}
            className="press hygge-tap"
            style={{ background: 'none', border: 'none', cursor: 'pointer', padding: 8, color: 'var(--color-ink-2)' }}
            aria-label="Previous month"
          >
            {chevron('prev')}
          </button>
          <button
            onClick={() => { if (month === 12) { setYear((y) => y + 1); setMonth(1) } else setMonth((m) => m + 1) }}
            className="press hygge-tap"
            style={{ background: 'none', border: 'none', cursor: 'pointer', padding: 8, color: 'var(--color-ink-2)' }}
            aria-label="Next month"
          >
            {chevron('next')}
          </button>
        </div>
      </div>

      {/* Day-of-week headers */}
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(7, 1fr)', marginBottom: 6 }}>
        {['S', 'M', 'T', 'W', 'T', 'F', 'S'].map((d, i) => (
          <div key={i} className="font-sans" style={{ textAlign: 'center', fontSize: 11, color: 'var(--color-ink-3)', padding: '2px 0', letterSpacing: '0.04em' }}>{d}</div>
        ))}
      </div>

      {/* Calendar grid */}
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(7, 1fr)', gap: 2, opacity: loadingDays ? 0.5 : 1, transition: 'opacity 0.2s' }}>
        {cells.map((day, i) => {
          if (!day) return <div key={i} />
          const ymd = `${year}-${String(month).padStart(2, '0')}-${String(day).padStart(2, '0')}`
          const hasEvent = eventDates.has(ymd)
          const isToday = ymd === todayYmd
          const isSelected = ymd === selectedDate
          return (
            <button
              key={i}
              onClick={() => selectDate(ymd)}
              className="hygge-tap"
              aria-label={`${monthLabel} ${day}${hasEvent ? ', has events' : ''}`}
              style={{
                position: 'relative',
                display: 'flex',
                flexDirection: 'column',
                alignItems: 'center',
                justifyContent: 'center',
                gap: 4,
                padding: '9px 0 7px',
                borderRadius: 10,
                border: isToday && !isSelected ? '1px solid rgba(0,0,0,0.18)' : '1px solid transparent',
                background: isSelected ? 'var(--color-ink)' : 'transparent',
                cursor: 'pointer',
              }}
            >
              <span
                className="font-mono"
                style={{
                  fontSize: 14,
                  fontVariantNumeric: 'tabular-nums',
                  fontWeight: isToday || isSelected ? 600 : 400,
                  color: isSelected ? 'var(--color-paper)' : 'var(--color-ink)',
                }}
              >
                {day}
              </span>
              <span
                style={{
                  width: 4,
                  height: 4,
                  borderRadius: '50%',
                  background: hasEvent ? (isSelected ? 'var(--color-paper)' : 'var(--color-moss-600)') : 'transparent',
                }}
              />
            </button>
          )
        })}
      </div>

      {/* Event sheet */}
      {sheetOpen && selectedDate && (
        <div
          className="sheet-up"
          role="dialog"
          aria-modal="true"
          style={{
            position: 'fixed',
            bottom: 0,
            left: '50%',
            transform: 'translateX(-50%)',
            width: '100%',
            maxWidth: 480,
            background: 'var(--color-paper)',
            borderTop: HAIRLINE,
            borderRadius: '18px 18px 0 0',
            boxShadow: '0 -8px 30px rgba(0,0,0,0.08)',
            padding: '10px 18px max(18px, env(safe-area-inset-bottom))',
            maxHeight: '62dvh',
            overflowY: 'auto',
            zIndex: 10,
          }}
        >
          {/* drag handle */}
          <div style={{ display: 'flex', justifyContent: 'center', paddingBottom: 8 }}>
            <span style={{ width: 36, height: 4, borderRadius: 2, background: 'rgba(0,0,0,0.14)' }} />
          </div>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 4 }}>
            <h2 className="font-display" style={{ fontSize: 18, color: 'var(--color-ink)' }}>
              {new Date(selectedDate + 'T00:00:00').toLocaleDateString('en-US', { weekday: 'long', month: 'long', day: 'numeric' })}
            </h2>
            <button
              onClick={() => setSheetOpen(false)}
              className="hygge-tap"
              style={{ background: 'none', border: 'none', cursor: 'pointer', color: 'var(--color-ink-3)', padding: 4, display: 'flex', alignItems: 'center', justifyContent: 'center' }}
              aria-label="Close"
            >
              <svg width="18" height="18" viewBox="0 0 18 18" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" aria-hidden>
                <line x1="3" y1="3" x2="15" y2="15" />
                <line x1="15" y1="3" x2="3" y2="15" />
              </svg>
            </button>
          </div>
          {loadingEvents ? (
            <p className="font-sans" style={{ color: 'var(--color-ink-3)', fontSize: 14, padding: '12px 0' }}>Loading…</p>
          ) : dayEvents.length === 0 ? (
            <p className="font-sans" style={{ color: 'var(--color-ink-3)', fontSize: 14, padding: '12px 0' }}>No events this day.</p>
          ) : (
            <div>
              {dayEvents.map((e, i) => (
                <EventRow key={e.id} event={e} onRsvp={handleRsvp} last={i === dayEvents.length - 1} />
              ))}
            </div>
          )}
        </div>
      )}
      {sheetOpen && (
        <div
          onClick={() => setSheetOpen(false)}
          style={{ position: 'fixed', inset: 0, background: 'rgba(0,0,0,0.28)', zIndex: 9 }}
        />
      )}
    </div>
  )
}

// ── Add Event tab ────────────────────────────────────────────────────────────

function AddEventTab({ onSuccess }: { onSuccess: () => void }) {
  const todayYmd = (() => {
    const d = new Date()
    return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`
  })()
  const [form, setForm] = useState<NewEventInput>({
    title: '',
    event_date: todayYmd,
    start_time: '',
    location: '',
    description: '',
  })
  const [submitting, setSubmitting] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const set = (field: keyof NewEventInput) => (e: React.ChangeEvent<HTMLInputElement | HTMLTextAreaElement>) =>
    setForm((f) => ({ ...f, [field]: e.target.value }))

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    if (!form.title.trim() || !form.event_date || !form.start_time.trim() || !form.location.trim()) {
      setError('Add a title, date, time, and location.')
      return
    }
    setError(null)
    setSubmitting(true)
    try {
      await addEvent({ ...form, title: form.title.trim(), location: form.location.trim() })
      haptic('success')
      onSuccess()
    } catch {
      setError('Could not add the event — try again.')
    } finally {
      setSubmitting(false)
    }
  }

  return (
    <div style={{ padding: '24px 18px' }}>
      <p className="font-sans" style={{ fontSize: 11, color: 'var(--color-ink-3)', textTransform: 'uppercase', letterSpacing: '0.16em', marginBottom: 3 }}>
        New
      </p>
      <h1 className="font-display" style={{ fontSize: 24, color: 'var(--color-ink)', marginBottom: 22 }}>
        Add an event
      </h1>
      <form onSubmit={handleSubmit} style={{ display: 'flex', flexDirection: 'column', gap: 16 }}>
        <div>
          <label style={labelStyle}>Title</label>
          <input className="hygge-field" style={fieldStyle} placeholder="Saturday Farmers Market" value={form.title} onChange={set('title')} />
        </div>
        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 12 }}>
          <div>
            <label style={labelStyle}>Date</label>
            <input type="date" className="hygge-field" style={fieldStyle} value={form.event_date} onChange={set('event_date')} />
          </div>
          <div>
            <label style={labelStyle}>Time</label>
            <input className="hygge-field" style={fieldStyle} placeholder="7am" value={form.start_time} onChange={set('start_time')} />
          </div>
        </div>
        <div>
          <label style={labelStyle}>Location</label>
          <input className="hygge-field" style={fieldStyle} placeholder="Millstream Park" value={form.location} onChange={set('location')} />
        </div>
        <div>
          <label style={labelStyle}>Description <span style={{ textTransform: 'none', letterSpacing: 0, color: 'var(--color-ink-3)' }}>· optional</span></label>
          <textarea
            className="hygge-field"
            style={{ ...fieldStyle, minHeight: 84, resize: 'vertical' }}
            placeholder="Tell people what to expect…"
            value={form.description}
            onChange={set('description')}
          />
        </div>
        {error && <p className="font-sans" style={{ fontSize: 13, color: 'var(--color-clay-700)' }}>{error}</p>}
        <button
          type="submit"
          disabled={submitting}
          className="press hygge-tap"
          style={{
            marginTop: 4,
            padding: '14px',
            borderRadius: 12,
            border: 'none',
            background: submitting ? 'var(--color-paper-200)' : 'var(--color-moss-700)',
            color: submitting ? 'var(--color-ink-3)' : 'var(--color-paper)',
            fontSize: 15,
            fontWeight: 600,
            cursor: submitting ? 'not-allowed' : 'pointer',
            fontFamily: 'var(--font-sans)',
          }}
        >
          {submitting ? 'Adding…' : 'Add event'}
        </button>
      </form>
    </div>
  )
}

// ── Quest tab ────────────────────────────────────────────────────────────────

function QuestTab({ isAdmin }: { isAdmin: boolean }) {
  const [quest, setQuest_] = useState<DailyQuest | null>(null)
  const [count, setCount] = useState(0)
  const [done, setDone] = useState(false)
  const [loading, setLoading] = useState(true)
  const [completing, setCompleting] = useState(false)
  const [completeError, setCompleteError] = useState<string | null>(null)
  // Admin form state
  const [adminTitle, setAdminTitle] = useState('')
  const [adminDesc, setAdminDesc] = useState('')
  const [adminDate, setAdminDate] = useState('')
  const [adminSaving, setAdminSaving] = useState(false)
  const [adminMsg, setAdminMsg] = useState<string | null>(null)

  useEffect(() => {
    async function load() {
      const q = await getTodayQuest()
      setQuest_(q)
      if (q) {
        const [c, user] = await Promise.all([getQuestCompletionCount(q.id), getCurrentUser()])
        setCount(c)
        if (user) setDone(await hasUserCompletedQuest(q.id, user.id))
      }
      setLoading(false)
    }
    load()
  }, [])

  const handleComplete = async () => {
    if (!quest || done || completing) return
    setCompleting(true)
    setCompleteError(null)
    try {
      await completeQuest(quest.id)
      haptic('success')
      setDone(true)
      setCount((c) => c + 1)
    } catch {
      setCompleteError('Could not mark done — try again.')
    } finally {
      setCompleting(false)
    }
  }

  const handleSetQuest = async (e: React.FormEvent) => {
    e.preventDefault()
    if (!adminTitle.trim() || !adminDate) return
    setAdminSaving(true)
    setAdminMsg(null)
    try {
      await setQuest(adminTitle.trim(), adminDesc.trim(), adminDate)
      setAdminMsg('Quest saved.')
      setAdminTitle('')
      setAdminDesc('')
      setAdminDate('')
    } catch {
      setAdminMsg('Could not save — try again.')
    } finally {
      setAdminSaving(false)
    }
  }

  if (loading) {
    return <div style={{ padding: 48, textAlign: 'center', fontFamily: 'var(--font-sans)', fontSize: 14, color: 'var(--color-ink-3)' }}>Loading…</div>
  }

  return (
    <div style={{ padding: '24px 18px', display: 'flex', flexDirection: 'column', gap: 28 }}>
      {/* Today's quest — the card owns the screen */}
      {quest ? (
        <div className="rise" style={{ paddingTop: 8 }}>
          <p className="font-sans" style={{ fontSize: 11, color: 'var(--color-ink-3)', textTransform: 'uppercase', letterSpacing: '0.16em', marginBottom: 14 }}>
            Today&apos;s quest
          </p>
          <h1 className="font-display" style={{ fontSize: 33, color: 'var(--color-ink)', lineHeight: 1.12, marginBottom: 14 }}>
            {quest.title}
          </h1>
          {quest.description && (
            <p className="font-sans" style={{ fontSize: 16, color: 'var(--color-ink-2)', lineHeight: 1.55, marginBottom: 20 }}>
              {quest.description}
            </p>
          )}
          <p className="font-mono" style={{ fontSize: 13, color: 'var(--color-ink-3)', marginBottom: 22 }}>
            <span style={{ fontVariantNumeric: 'tabular-nums' }}>{count}</span>
            <span className="font-sans"> {count === 1 ? 'neighbor' : 'neighbors'} did this today</span>
          </p>

          {completeError && (
            <p className="font-sans" style={{ fontSize: 13, color: 'var(--color-clay-700)', marginBottom: 12 }}>{completeError}</p>
          )}

          {done ? (
            <div
              className="fade-in"
              style={{
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                gap: 4,
                width: '100%',
                padding: '15px',
                borderRadius: 12,
                border: '1.5px solid var(--color-moss-700)',
                color: 'var(--color-moss-700)',
                fontSize: 15,
                fontWeight: 600,
                fontFamily: 'var(--font-sans)',
              }}
            >
              Done for today<CheckIcon size={16} />
            </div>
          ) : (
            <button
              onClick={handleComplete}
              disabled={completing}
              className="press hygge-tap"
              style={{
                width: '100%',
                padding: '15px',
                borderRadius: 12,
                border: 'none',
                background: 'var(--color-moss-700)',
                color: 'var(--color-paper)',
                fontSize: 15,
                fontWeight: 600,
                cursor: completing ? 'default' : 'pointer',
                fontFamily: 'var(--font-sans)',
              }}
            >
              {completing ? '…' : 'Mark done'}
            </button>
          )}
        </div>
      ) : (
        <div style={{ padding: '64px 0', textAlign: 'center' }}>
          <p className="font-sans" style={{ fontSize: 16, color: 'var(--color-ink-2)' }}>No quest today.</p>
          <p className="font-sans" style={{ fontSize: 14, color: 'var(--color-ink-3)', marginTop: 6 }}>Check back tomorrow.</p>
        </div>
      )}

      {/* Admin: set a quest */}
      {isAdmin && (
        <div style={{ borderTop: HAIRLINE, paddingTop: 22 }}>
          <p className="font-sans" style={{ fontSize: 11, color: 'var(--color-ink-3)', textTransform: 'uppercase', letterSpacing: '0.1em', marginBottom: 14 }}>
            Set a quest · admin
          </p>
          <form onSubmit={handleSetQuest} style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
            <div>
              <label style={labelStyle}>Date</label>
              <input type="date" className="hygge-field" style={fieldStyle} value={adminDate} onChange={(e) => setAdminDate(e.target.value)} />
            </div>
            <div>
              <label style={labelStyle}>Title</label>
              <input className="hygge-field" style={fieldStyle} placeholder="Walk to the park" value={adminTitle} onChange={(e) => setAdminTitle(e.target.value)} />
            </div>
            <div>
              <label style={labelStyle}>Description</label>
              <textarea className="hygge-field" style={{ ...fieldStyle, minHeight: 72, resize: 'vertical' }} placeholder="Optional details…" value={adminDesc} onChange={(e) => setAdminDesc(e.target.value)} />
            </div>
            {adminMsg && (
              <p className="font-sans" style={{ fontSize: 13, color: adminMsg.startsWith('Quest saved') ? 'var(--color-moss-700)' : 'var(--color-clay-700)' }}>{adminMsg}</p>
            )}
            <button
              type="submit"
              disabled={adminSaving}
              className="press hygge-tap"
              style={{
                padding: '12px',
                borderRadius: 10,
                border: 'none',
                background: adminSaving ? 'var(--color-paper-200)' : 'var(--color-ink)',
                color: adminSaving ? 'var(--color-ink-3)' : 'var(--color-paper)',
                fontSize: 14,
                fontWeight: 600,
                cursor: adminSaving ? 'not-allowed' : 'pointer',
                fontFamily: 'var(--font-sans)',
              }}
            >
              {adminSaving ? 'Saving…' : 'Save quest'}
            </button>
          </form>
        </div>
      )}
    </div>
  )
}

// ── Page shell ────────────────────────────────────────────────────────────────

export default function CommunityPage() {
  const [tab, setTab] = useState<Tab>('timeline')
  const [isAdmin, setIsAdmin] = useState(false)

  useEffect(() => {
    getCurrentUser().then((u) => setIsAdmin(isAdminEmail(u?.email)))
  }, [])

  const switchTab = (t: Tab) => { if (t !== tab) haptic('tap'); setTab(t) }

  const TABS: { id: Tab; label: string }[] = [
    { id: 'timeline', label: 'Today' },
    { id: 'calendar', label: 'Calendar' },
    { id: 'add', label: 'Add' },
    { id: 'quest', label: 'Quest' },
  ]

  return (
    <div
      style={{
        minHeight: '100dvh',
        background: 'var(--color-paper)',
        display: 'flex',
        flexDirection: 'column',
        maxWidth: 480,
        margin: '0 auto',
      }}
    >
      <style>{`
        .hygge-field:focus { border-color: var(--color-sky-600); }
        .hygge-field:focus-visible { outline: 2px solid var(--color-sky-600); outline-offset: 1px; }
        .hygge-tap:focus-visible { outline: 2px solid var(--color-sky-600); outline-offset: 2px; border-radius: 8px; }
      `}</style>

      {/* Masthead */}
      <header
        style={{
          padding: '16px 18px 12px',
          borderBottom: HAIRLINE,
          display: 'flex',
          flexDirection: 'column',
          alignItems: 'flex-start',
        }}
      >
        <span className="font-display" style={{ fontSize: 23, color: 'var(--color-ink)', lineHeight: 1, letterSpacing: '-0.01em' }}>
          Hygge
        </span>
        <span className="font-sans" style={{ fontSize: 10.5, color: 'var(--color-ink-3)', letterSpacing: '0.2em', textTransform: 'uppercase', marginTop: 4 }}>
          St. Joseph, MN
        </span>
      </header>

      {/* Tab content */}
      <main style={{ flex: 1, overflowY: 'auto', paddingBottom: 84 }}>
        {tab === 'timeline' && <TimelineTab />}
        {tab === 'calendar' && <CalendarTab />}
        {tab === 'add' && <AddEventTab onSuccess={() => setTab('timeline')} />}
        {tab === 'quest' && <QuestTab isAdmin={isAdmin} />}
      </main>

      {/* Bottom nav */}
      <nav
        style={{
          position: 'fixed',
          bottom: 0,
          left: '50%',
          transform: 'translateX(-50%)',
          width: '100%',
          maxWidth: 480,
          background: 'var(--color-paper)',
          borderTop: HAIRLINE,
          display: 'grid',
          gridTemplateColumns: 'repeat(4, 1fr)',
          padding: '9px 0 max(9px, env(safe-area-inset-bottom))',
        }}
      >
        {TABS.map((t) => {
          const active = tab === t.id
          return (
            <button
              key={t.id}
              onClick={() => switchTab(t.id)}
              className="hygge-tap"
              aria-current={active ? 'page' : undefined}
              aria-label={t.label}
              style={{
                display: 'flex',
                flexDirection: 'column',
                alignItems: 'center',
                gap: 4,
                background: 'none',
                border: 'none',
                cursor: 'pointer',
                padding: '4px 0',
              }}
            >
              <TabIcon id={t.id} active={active} />
              <span
                className="font-sans"
                style={{
                  fontSize: 10,
                  color: active ? 'var(--color-ink)' : 'var(--color-ink-3)',
                  letterSpacing: '0.04em',
                  fontWeight: active ? 600 : 400,
                }}
              >
                {t.label}
              </span>
            </button>
          )
        })}
      </nav>
    </div>
  )
}
