'use client'

import { useCallback, useEffect, useState } from 'react'
import {
  getTodayEvents,
  getEventsByDate,
  getMonthEventDates,
  addEvent,
  rsvpEvent,
  unRsvpEvent,
  getCurrentUser,
  isAdminEmail,
  type TimelineEvent,
  type NewEventInput,
} from '@/lib/community'
import { haptic } from '@/lib/haptics'

type Tab = 'timeline' | 'calendar' | 'add' | 'quest'

// ── Icons ────────────────────────────────────────────────────────────────────

function TabIcon({ id, active }: { id: Tab; active: boolean }) {
  const c = active ? '#1a1a1a' : '#9ca3af'
  const sp = {
    fill: 'none' as const,
    stroke: c,
    strokeWidth: '1.8',
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

// ── Inline SVG checkmark ──────────────────────────────────────────────────────

function CheckIcon() {
  return (
    <svg
      width="14"
      height="14"
      viewBox="0 0 14 14"
      fill="none"
      stroke="currentColor"
      strokeWidth="2"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden
      style={{ display: 'inline-block', verticalAlign: 'middle', marginLeft: 4 }}
    >
      <polyline points="2 7 5.5 10.5 12 3.5" />
    </svg>
  )
}

// ── Event card ────────────────────────────────────────────────────────────────

function EventCard({
  event,
  onRsvp,
}: {
  event: TimelineEvent & { location?: string | null }
  onRsvp: (id: string, rsvpd: boolean) => void
}) {
  return (
    <div
      className="rise"
      style={{
        background: 'var(--color-paper)',
        border: '1px solid rgba(0,0,0,0.07)',
        borderRadius: 12,
        padding: '14px 16px',
        display: 'flex',
        flexDirection: 'column',
        gap: 6,
      }}
    >
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', gap: 8 }}>
        <div style={{ flex: 1 }}>
          {event.start_time && (
            <p className="font-mono" style={{ fontSize: 11, color: 'var(--color-ink-3)', marginBottom: 2, letterSpacing: '0.04em' }}>
              {event.start_time.toUpperCase()}
            </p>
          )}
          <p className="font-sans" style={{ fontSize: 15, fontWeight: 600, color: 'var(--color-ink)', lineHeight: 1.3 }}>
            {event.title}
          </p>
          {event.location && (
            <p className="font-sans" style={{ fontSize: 13, color: 'var(--color-ink-2)', marginTop: 2 }}>
              {event.location}
            </p>
          )}
        </div>
        <button
          onClick={() => { haptic('tap'); onRsvp(event.id, event.rsvpd) }}
          className="press"
          style={{
            flexShrink: 0,
            padding: '6px 14px',
            borderRadius: 20,
            border: event.rsvpd ? 'none' : '1.5px solid rgba(0,0,0,0.15)',
            background: event.rsvpd ? 'var(--color-moss-700)' : 'transparent',
            color: event.rsvpd ? '#fff' : 'var(--color-ink-2)',
            fontSize: 13,
            fontWeight: 500,
            cursor: 'pointer',
            fontFamily: 'var(--font-sans)',
            display: 'flex',
            alignItems: 'center',
          }}
        >
          {event.rsvpd ? (
            <>Going<CheckIcon /></>
          ) : (
            'RSVP'
          )}
        </button>
      </div>
      <p
        className="font-mono"
        style={{ fontSize: 11, color: 'var(--color-ink-3)' }}
      >
        <span style={{ fontVariantNumeric: 'tabular-nums' }}>{event.going_count}</span> going
      </p>
    </div>
  )
}

// ── Timeline tab ─────────────────────────────────────────────────────────────

function TimelineTab() {
  const [events, setEvents] = useState<TimelineEvent[]>([])
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    getTodayEvents().then(setEvents).finally(() => setLoading(false))
  }, [])

  const handleRsvp = useCallback(async (id: string, rsvpd: boolean) => {
    setEvents((prev) =>
      prev.map((e) =>
        e.id === id
          ? { ...e, rsvpd: !rsvpd, going_count: e.going_count + (rsvpd ? -1 : 1) }
          : e
      )
    )
    try {
      if (rsvpd) await unRsvpEvent(id)
      else await rsvpEvent(id)
    } catch {
      // revert on error
      setEvents((prev) =>
        prev.map((e) =>
          e.id === id
            ? { ...e, rsvpd, going_count: e.going_count + (rsvpd ? 1 : -1) }
            : e
        )
      )
    }
  }, [])

  if (loading) {
    return (
      <div style={{ padding: '48px 0', textAlign: 'center', color: 'var(--color-ink-3)', fontFamily: 'var(--font-sans)', fontSize: 14 }}>
        Loading…
      </div>
    )
  }

  const today = new Date().toLocaleDateString('en-US', { weekday: 'long', month: 'long', day: 'numeric' })

  return (
    <div style={{ padding: '16px 16px 0' }}>
      <p className="font-sans" style={{ fontSize: 12, color: 'var(--color-ink-3)', marginBottom: 14, textTransform: 'uppercase', letterSpacing: '0.06em' }}>
        {today}
      </p>
      {events.length === 0 ? (
        <div style={{ padding: '48px 0', textAlign: 'center' }}>
          <p className="font-sans" style={{ fontSize: 15, color: 'var(--color-ink-3)' }}>Nothing on the calendar today</p>
          <p className="font-sans" style={{ fontSize: 13, color: 'var(--color-ink-3)', marginTop: 6 }}>Add something for the community</p>
        </div>
      ) : (
        <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
          {events.map((e) => (
            <EventCard key={e.id} event={e} onRsvp={handleRsvp} />
          ))}
        </div>
      )}
    </div>
  )
}

// ── Placeholder tabs (filled in later tasks) ──────────────────────────────────

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

  useEffect(() => {
    setLoadingDays(true)
    getMonthEventDates(year, month)
      .then((dates) => setEventDates(new Set(dates)))
      .finally(() => setLoadingDays(false))
  }, [year, month])

  const selectDate = async (ymd: string) => {
    setSelectedDate(ymd)
    setSheetOpen(true)
    setLoadingEvents(true)
    const evs = await getEventsByDate(ymd).finally(() => setLoadingEvents(false))
    setDayEvents(evs)
  }

  const handleRsvp = useCallback(async (id: string, rsvpd: boolean) => {
    setDayEvents((prev) =>
      prev.map((e) =>
        e.id === id ? { ...e, rsvpd: !rsvpd, going_count: e.going_count + (rsvpd ? -1 : 1) } : e
      )
    )
    try {
      if (rsvpd) await unRsvpEvent(id)
      else await rsvpEvent(id)
    } catch {
      setDayEvents((prev) =>
        prev.map((e) =>
          e.id === id ? { ...e, rsvpd, going_count: e.going_count + (rsvpd ? 1 : -1) } : e
        )
      )
    }
  }, [])

  // Build month grid
  const firstDay = new Date(year, month - 1, 1).getDay() // 0=Sun
  const daysInMonth = new Date(year, month, 0).getDate()
  const cells: (number | null)[] = [
    ...Array(firstDay).fill(null),
    ...Array.from({ length: daysInMonth }, (_, i) => i + 1),
  ]
  // pad to complete weeks
  while (cells.length % 7 !== 0) cells.push(null)

  const monthLabel = new Date(year, month - 1, 1).toLocaleDateString('en-US', { month: 'long', year: 'numeric' })
  const todayYmd = `${today.getFullYear()}-${String(today.getMonth() + 1).padStart(2, '0')}-${String(today.getDate()).padStart(2, '0')}`

  return (
    <div style={{ padding: '16px' }}>
      {/* Month navigation */}
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 16 }}>
        <button
          onClick={() => {
            if (month === 1) { setYear(y => y - 1); setMonth(12) } else setMonth(m => m - 1)
          }}
          style={{ background: 'none', border: 'none', cursor: 'pointer', padding: 8, color: 'var(--color-ink-2)' }}
          aria-label="Previous month"
        >
          <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round"><polyline points="15 18 9 12 15 6" /></svg>
        </button>
        <span className="font-sans" style={{ fontSize: 15, fontWeight: 600, color: 'var(--color-ink)' }}>{monthLabel}</span>
        <button
          onClick={() => {
            if (month === 12) { setYear(y => y + 1); setMonth(1) } else setMonth(m => m + 1)
          }}
          style={{ background: 'none', border: 'none', cursor: 'pointer', padding: 8, color: 'var(--color-ink-2)' }}
          aria-label="Next month"
        >
          <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round"><polyline points="9 18 15 12 9 6" /></svg>
        </button>
      </div>

      {/* Day-of-week headers */}
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(7, 1fr)', marginBottom: 4 }}>
        {['S','M','T','W','T','F','S'].map((d, i) => (
          <div key={i} className="font-sans" style={{ textAlign: 'center', fontSize: 11, color: 'var(--color-ink-3)', padding: '4px 0', letterSpacing: '0.04em' }}>{d}</div>
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
              style={{
                display: 'flex',
                flexDirection: 'column',
                alignItems: 'center',
                justifyContent: 'center',
                gap: 3,
                padding: '8px 0',
                borderRadius: 8,
                border: 'none',
                background: isSelected ? 'var(--color-moss-700)' : isToday ? 'var(--color-paper-100)' : 'transparent',
                cursor: 'pointer',
              }}
            >
              <span
                className="font-sans"
                style={{
                  fontSize: 14,
                  fontWeight: isToday ? 700 : 400,
                  color: isSelected ? '#fff' : isToday ? 'var(--color-moss-700)' : 'var(--color-ink)',
                }}
              >
                {day}
              </span>
              {hasEvent && (
                <span style={{
                  width: 4, height: 4, borderRadius: '50%',
                  background: isSelected ? 'rgba(255,255,255,0.7)' : 'var(--color-moss-600)',
                }} />
              )}
            </button>
          )
        })}
      </div>

      {/* Event sheet */}
      {sheetOpen && selectedDate && (
        <div
          className="sheet-up"
          style={{
            position: 'fixed',
            bottom: 0,
            left: '50%',
            transform: 'translateX(-50%)',
            width: '100%',
            maxWidth: 480,
            background: 'var(--color-paper)',
            borderTop: '1px solid rgba(0,0,0,0.1)',
            borderRadius: '16px 16px 0 0',
            padding: '16px 16px max(16px, env(safe-area-inset-bottom))',
            maxHeight: '60dvh',
            overflowY: 'auto',
            zIndex: 10,
          }}
        >
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 14 }}>
            <span className="font-sans" style={{ fontSize: 14, fontWeight: 600, color: 'var(--color-ink)' }}>
              {new Date(selectedDate + 'T00:00:00').toLocaleDateString('en-US', { weekday: 'long', month: 'long', day: 'numeric' })}
            </span>
            <button
              onClick={() => setSheetOpen(false)}
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
            <p className="font-sans" style={{ color: 'var(--color-ink-3)', fontSize: 14 }}>Loading…</p>
          ) : dayEvents.length === 0 ? (
            <p className="font-sans" style={{ color: 'var(--color-ink-3)', fontSize: 14 }}>No events this day.</p>
          ) : (
            <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
              {dayEvents.map((e) => <EventCard key={e.id} event={e} onRsvp={handleRsvp} />)}
            </div>
          )}
        </div>
      )}
      {/* Sheet backdrop */}
      {sheetOpen && (
        <div
          onClick={() => setSheetOpen(false)}
          style={{ position: 'fixed', inset: 0, background: 'rgba(0,0,0,0.3)', zIndex: 9 }}
        />
      )}
    </div>
  )
}
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
      setError('Title, date, time, and location are required.')
      return
    }
    setError(null)
    setSubmitting(true)
    try {
      await addEvent({ ...form, title: form.title.trim(), location: form.location.trim() })
      haptic('success')
      onSuccess()
    } catch {
      setError('Failed to add event. Try again.')
    } finally {
      setSubmitting(false)
    }
  }

  const fieldStyle: React.CSSProperties = {
    width: '100%',
    padding: '11px 13px',
    borderRadius: 10,
    border: '1.5px solid rgba(0,0,0,0.12)',
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
    letterSpacing: '0.06em',
    marginBottom: 5,
    display: 'block',
    fontFamily: 'var(--font-sans)',
  }

  return (
    <div style={{ padding: '20px 16px' }}>
      <h2 className="font-sans" style={{ fontSize: 18, fontWeight: 700, color: 'var(--color-ink)', marginBottom: 20 }}>
        Add an Event
      </h2>
      <form onSubmit={handleSubmit} style={{ display: 'flex', flexDirection: 'column', gap: 16 }}>
        <div>
          <label style={labelStyle}>Title *</label>
          <input style={fieldStyle} placeholder="Saturday Farmers Market" value={form.title} onChange={set('title')} />
        </div>
        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 12 }}>
          <div>
            <label style={labelStyle}>Date *</label>
            <input type="date" style={fieldStyle} value={form.event_date} onChange={set('event_date')} />
          </div>
          <div>
            <label style={labelStyle}>Time *</label>
            <input style={fieldStyle} placeholder="7am" value={form.start_time} onChange={set('start_time')} />
          </div>
        </div>
        <div>
          <label style={labelStyle}>Location *</label>
          <input style={fieldStyle} placeholder="Riverside Park" value={form.location} onChange={set('location')} />
        </div>
        <div>
          <label style={labelStyle}>Description</label>
          <textarea
            style={{ ...fieldStyle, minHeight: 80, resize: 'vertical' }}
            placeholder="Tell people what to expect…"
            value={form.description}
            onChange={set('description')}
          />
        </div>
        {error && (
          <p className="font-sans" style={{ fontSize: 13, color: 'var(--color-clay-700)' }}>{error}</p>
        )}
        <button
          type="submit"
          disabled={submitting}
          className="press"
          style={{
            padding: '13px',
            borderRadius: 12,
            border: 'none',
            background: submitting ? 'var(--color-paper-200)' : 'var(--color-moss-700)',
            color: submitting ? 'var(--color-ink-3)' : '#fff',
            fontSize: 15,
            fontWeight: 600,
            cursor: submitting ? 'not-allowed' : 'pointer',
            fontFamily: 'var(--font-sans)',
          }}
        >
          {submitting ? 'Adding…' : 'Add Event'}
        </button>
      </form>
    </div>
  )
}
function QuestTab({ isAdmin }: { isAdmin: boolean }) {
  void isAdmin
  return <div style={{ padding: 24, fontFamily: 'var(--font-sans)', color: 'var(--color-ink-3)' }}>Quest — coming in Task 7</div>
}

// ── Page shell ────────────────────────────────────────────────────────────────

export default function CommunityPage() {
  const [tab, setTab] = useState<Tab>('timeline')
  const [isAdmin, setIsAdmin] = useState(false)

  useEffect(() => {
    getCurrentUser().then((u) => setIsAdmin(isAdminEmail(u?.email)))
  }, [])

  const switchTab = (t: Tab) => { haptic('tap'); setTab(t) }

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
      {/* Header */}
      <header
        style={{
          padding: '18px 16px 12px',
          borderBottom: '1px solid rgba(0,0,0,0.07)',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'space-between',
        }}
      >
        <span className="font-display" style={{ fontSize: 22, color: 'var(--color-ink)', letterSpacing: '-0.02em' }}>
          Hygge
        </span>
        <span className="font-sans" style={{ fontSize: 12, color: 'var(--color-ink-3)', letterSpacing: '0.05em', textTransform: 'uppercase' }}>
          St. Joseph
        </span>
      </header>

      {/* Tab content */}
      <main style={{ flex: 1, overflowY: 'auto', paddingBottom: 80 }}>
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
          background: 'rgba(255,255,255,0.92)',
          backdropFilter: 'blur(12px)',
          borderTop: '1px solid rgba(0,0,0,0.07)',
          display: 'grid',
          gridTemplateColumns: 'repeat(4, 1fr)',
          padding: '8px 0 max(8px, env(safe-area-inset-bottom))',
        }}
      >
        {TABS.map((t) => (
          <button
            key={t.id}
            onClick={() => switchTab(t.id)}
            style={{
              display: 'flex',
              flexDirection: 'column',
              alignItems: 'center',
              gap: 3,
              background: 'none',
              border: 'none',
              cursor: 'pointer',
              padding: '4px 0',
            }}
          >
            <TabIcon id={t.id} active={tab === t.id} />
            <span
              className="font-sans"
              style={{
                fontSize: 10,
                color: tab === t.id ? 'var(--color-ink)' : '#9ca3af',
                letterSpacing: '0.04em',
                fontWeight: tab === t.id ? 600 : 400,
              }}
            >
              {t.label}
            </span>
          </button>
        ))}
      </nav>
    </div>
  )
}
