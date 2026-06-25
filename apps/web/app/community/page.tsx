'use client'

import { useCallback, useEffect, useRef, useState } from 'react'
import { useRouter } from 'next/navigation'
import {
  getTodayEvents,
  getWeekEvents,
  getEventsByDate,
  getMonthEventDates,
  addEvent,
  rsvpEvent,
  unRsvpEvent,
  getCurrentUser,
  firstNameFromEmail,
  isAdminEmail,
  getTodayQuest,
  getQuestCompletionCount,
  hasUserCompletedQuest,
  completeQuest,
  setQuest,
  type TimelineEvent,
  type WeekEvent,
  type NewEventInput,
  type DailyQuest,
} from '@/lib/community'
import { createClient } from '@/lib/supabase/client'
import { haptic } from '@/lib/haptics'

type Tab = 'home' | 'calendar' | 'add' | 'quest'

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
  if (id === 'home')
    return (
      <svg width="22" height="22" viewBox="0 0 24 24" {...sp} aria-hidden>
        <path d="M3 11.4 12 4l9 7.4" />
        <path d="M5.6 9.8v9.7c0 .3.2.5.5.5h11.8c.3 0 .5-.2.5-.5V9.8" />
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

// ── Home tab (the hub) ───────────────────────────────────────────────────────

type Scope = 'today' | 'week' | 'going'

const SCOPES: { id: Scope; label: string }[] = [
  { id: 'today', label: 'Today' },
  { id: 'week', label: 'This week' },
  { id: 'going', label: 'Going' },
]

// Real St. Joseph–area places. Photos are freely-licensed (Wikimedia Commons);
// see public/around-town/CREDITS.md for per-image attribution. Tapping a place
// filters the day's list to events at or near it (matched on title + location).
type Collection = { name: string; blurb: string; image: string; kw: string[] | null }
const COLLECTIONS: Collection[] = [
  { name: 'Downtown', blurb: 'Shops & cafés on Minnesota St', image: '/around-town/downtown.jpg', kw: ['downtown', 'minnesota st', 'local blend', 'krewe', 'bo diddley', 'middy', 'college ave'] },
  { name: "Saint Ben's", blurb: 'College of Saint Benedict', image: '/around-town/saint-bens.jpg', kw: ['saint ben', 'st. ben', 'st ben', 'csb', 'benedict', 'gorecki', 'campus'] },
  { name: 'Sacred Heart Chapel', blurb: 'The monastery & its dome', image: '/around-town/sacred-heart-chapel.jpg', kw: ['chapel', 'sacred heart', 'monastery', 'mass', 'sisters'] },
  { name: "Saint John's", blurb: 'The Abbey in Collegeville', image: '/around-town/saint-johns-abbey.jpg', kw: ['saint john', 'st. john', 'st john', 'sju', 'abbey', 'collegeville'] },
  { name: 'Wobegon Trail', blurb: 'Bike, walk & run the trail', image: '/around-town/wobegon-trail.jpg', kw: ['wobegon', 'trail', 'bike', 'walk', 'run', 'ride', 'river', 'watab'] },
]

function matchesKw(text: string, kw: string[] | null): boolean {
  if (!kw) return true
  const t = text.toLowerCase()
  return kw.some((k) => t.includes(k))
}

/** Free-text display time ("7am", "5:30pm", "noon") → minutes from midnight; undated sorts last. */
function minutesOf(s: string | null): number {
  if (!s) return 24 * 60
  const t = s.trim().toLowerCase()
  if (t.includes('noon')) return 12 * 60
  if (t.includes('midnight')) return 0
  const m = t.match(/(\d{1,2})(?::(\d{2}))?\s*(a|p)/)
  if (!m) return 24 * 60
  let h = parseInt(m[1], 10)
  const min = m[2] ? parseInt(m[2], 10) : 0
  if (m[3] === 'p' && h < 12) h += 12
  if (m[3] === 'a' && h === 12) h = 0
  return h * 60 + min
}

function SectionHead({ children }: { children: React.ReactNode }) {
  return (
    <h2 className="font-sans" style={{ fontSize: 20, fontWeight: 700, letterSpacing: '-0.015em', color: 'var(--color-ink)', lineHeight: 1.1 }}>
      {children}
    </h2>
  )
}

function HyggeMark() {
  return (
    <span style={{ width: 32, height: 32, borderRadius: 9, background: 'var(--color-moss-700)', display: 'inline-flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0 }}>
      <span className="font-display" style={{ fontSize: 19, fontWeight: 600, color: 'var(--color-paper)', lineHeight: 1 }}>H</span>
    </span>
  )
}

function GlassCircle({ children, onClick, label, active }: { children: React.ReactNode; onClick: () => void; label: string; active?: boolean }) {
  return (
    <button
      onClick={onClick}
      aria-label={label}
      className="press hygge-tap"
      style={{
        width: 44, height: 44, borderRadius: '50%',
        display: 'flex', alignItems: 'center', justifyContent: 'center', cursor: 'pointer',
        background: active ? 'rgba(45,69,48,0.16)' : 'rgba(255,255,255,0.42)',
        backdropFilter: 'blur(18px) saturate(1.9)',
        WebkitBackdropFilter: 'blur(18px) saturate(1.9)',
        border: '1px solid rgba(255,255,255,0.55)',
        boxShadow: 'inset 0 1px 0 rgba(255,255,255,0.85), 0 2px 10px rgba(31,48,34,0.10)',
      }}
    >
      {children}
    </button>
  )
}

function SearchIcon() {
  return (
    <svg width="19" height="19" viewBox="0 0 24 24" fill="none" stroke="var(--color-ink)" strokeWidth="1.9" strokeLinecap="round" strokeLinejoin="round" aria-hidden>
      <circle cx="11" cy="11" r="7" /><line x1="16.5" y1="16.5" x2="21" y2="21" />
    </svg>
  )
}

function AccountIcon() {
  return (
    <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="var(--color-ink)" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" aria-hidden>
      <circle cx="12" cy="9" r="3.4" /><path d="M5.5 20c0-3.6 2.9-6 6.5-6s6.5 2.4 6.5 6" />
    </svg>
  )
}

function ScopeIcon({ id, active }: { id: Scope; active: boolean }) {
  const c = active ? 'var(--color-paper)' : 'var(--color-ink-3)'
  const sp = { fill: 'none' as const, stroke: c, strokeWidth: '1.7', strokeLinecap: 'round' as const, strokeLinejoin: 'round' as const }
  if (id === 'today')
    return (
      <svg width="14" height="14" viewBox="0 0 24 24" {...sp} aria-hidden>
        <circle cx="12" cy="12" r="4.2" />
        <line x1="12" y1="2.5" x2="12" y2="5" /><line x1="12" y1="19" x2="12" y2="21.5" />
        <line x1="2.5" y1="12" x2="5" y2="12" /><line x1="19" y1="12" x2="21.5" y2="12" />
        <line x1="5.4" y1="5.4" x2="7.1" y2="7.1" /><line x1="16.9" y1="16.9" x2="18.6" y2="18.6" />
        <line x1="16.9" y1="7.1" x2="18.6" y2="5.4" /><line x1="5.4" y1="18.6" x2="7.1" y2="16.9" />
      </svg>
    )
  if (id === 'week')
    return (
      <svg width="14" height="14" viewBox="0 0 24 24" {...sp} aria-hidden>
        <rect x="3" y="4.5" width="18" height="16.5" rx="2.5" /><line x1="3" y1="9" x2="21" y2="9" />
        <line x1="8" y1="2.5" x2="8" y2="6" /><line x1="16" y1="2.5" x2="16" y2="6" />
      </svg>
    )
  return (
    <svg width="14" height="14" viewBox="0 0 24 24" {...sp} aria-hidden>
      <circle cx="12" cy="12" r="9" /><polyline points="8.4 12 11 14.6 15.6 9.4" />
    </svg>
  )
}

function ActiveBadge() {
  return (
    <span style={{ position: 'absolute', top: 12, right: 12, width: 22, height: 22, borderRadius: '50%', background: 'rgba(255,255,255,0.92)', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
      <svg width="12" height="12" viewBox="0 0 14 14" fill="none" stroke="#2a2a28" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round" aria-hidden>
        <polyline points="2 7 5.5 10.5 12 3.5" />
      </svg>
    </span>
  )
}

// ── Weather (live, open-meteo · St. Joseph, MN) ───────────────────────────────

type Weather = { temp: number; code: number; hi: number; lo: number; day: boolean }

function wmoText(code: number): string {
  if (code === 0) return 'Clear'
  if (code <= 2) return 'Partly cloudy'
  if (code === 3) return 'Cloudy'
  if (code <= 48) return 'Fog'
  if (code <= 57) return 'Drizzle'
  if (code <= 67) return 'Rain'
  if (code <= 77) return 'Snow'
  if (code <= 82) return 'Showers'
  if (code <= 86) return 'Snow showers'
  return 'Storms'
}

function WeatherGlyph({ code, day = true, color = 'var(--color-ink-2)' }: { code: number; day?: boolean; color?: string }) {
  const sp = { fill: 'none' as const, stroke: color, strokeWidth: '1.7', strokeLinecap: 'round' as const, strokeLinejoin: 'round' as const }
  let kind: 'sun' | 'moon' | 'cloud' | 'rain' | 'snow' = 'sun'
  if (code === 3 || (code >= 45 && code <= 48)) kind = 'cloud'
  else if ((code >= 51 && code <= 67) || (code >= 80 && code <= 82) || code >= 95) kind = 'rain'
  else if (code >= 71 && code <= 86) kind = 'snow'
  else if (!day) kind = 'moon'
  return (
    <svg width="20" height="20" viewBox="0 0 24 24" {...sp} aria-hidden>
      {kind === 'moon' && <path d="M20 14.5A8 8 0 0 1 9.5 4a8 8 0 1 0 10.5 10.5z" />}
      {kind === 'sun' && (
        <>
          <circle cx="12" cy="12" r="4" />
          <line x1="12" y1="3" x2="12" y2="5.4" /><line x1="12" y1="18.6" x2="12" y2="21" />
          <line x1="3" y1="12" x2="5.4" y2="12" /><line x1="18.6" y1="12" x2="21" y2="12" />
          <line x1="5.6" y1="5.6" x2="7.3" y2="7.3" /><line x1="16.7" y1="16.7" x2="18.4" y2="18.4" />
          <line x1="16.7" y1="7.3" x2="18.4" y2="5.6" /><line x1="5.6" y1="18.4" x2="7.3" y2="16.7" />
        </>
      )}
      {kind === 'cloud' && <path d="M7 17.5h9.5a3.3 3.3 0 0 0 .3-6.6 4.7 4.7 0 0 0-9.1-1.2A3.6 3.6 0 0 0 7 17.5z" />}
      {kind === 'rain' && (
        <>
          <path d="M7 14.5h9.5a3.3 3.3 0 0 0 .3-6.6 4.7 4.7 0 0 0-9.1-1.2A3.6 3.6 0 0 0 7 14.5z" />
          <line x1="9" y1="17.5" x2="8.4" y2="20.5" /><line x1="12.5" y1="17.5" x2="11.9" y2="20.5" /><line x1="16" y1="17.5" x2="15.4" y2="20.5" />
        </>
      )}
      {kind === 'snow' && (
        <>
          <path d="M7 14.5h9.5a3.3 3.3 0 0 0 .3-6.6 4.7 4.7 0 0 0-9.1-1.2A3.6 3.6 0 0 0 7 14.5z" />
          <circle cx="9" cy="18.6" r="0.7" /><circle cx="12.5" cy="19.4" r="0.7" /><circle cx="16" cy="18.6" r="0.7" />
        </>
      )}
    </svg>
  )
}

// ── Ambient weather backdrop — calm CSS scene behind the weather bar ──────────

type WxKind = 'clear' | 'clouds' | 'fog' | 'rain' | 'snow' | 'storm'
function wxKind(code: number): WxKind {
  if (code >= 95) return 'storm'
  if ((code >= 71 && code <= 77) || (code >= 85 && code <= 86)) return 'snow'
  if ((code >= 51 && code <= 67) || (code >= 80 && code <= 82)) return 'rain'
  if (code >= 45 && code <= 48) return 'fog'
  if (code === 2 || code === 3) return 'clouds'
  return 'clear' // 0 = clear, 1 = mainly clear
}

// Soft shadow that keeps the bar's white text legible over a vivid photo.
const WX_TEXT_SHADOW = '0 1px 3px rgba(0,0,0,0.55)'

// Real-photo backdrop per condition (freely licensed — public/weather/CREDITS.md).
const WX_IMAGE: Record<string, string> = {
  clearDay: '/weather/clear-day.jpg',
  clearNight: '/weather/clear-night.jpg',
  clouds: '/weather/clouds.jpg',
  overcast: '/weather/overcast.jpg',
  rain: '/weather/rain.png',
  snow: '/weather/snow.jpg',
  fog: '/weather/fog.jpg',
  storm: '/weather/storm.jpg',
}

/** A real weather photo behind the bar, with a slow Ken-Burns drift and a linen
 *  veil so the ink text stays readable. The photo is chosen from the live WMO
 *  code + day/night. */
function WeatherBackdrop({ code, day }: { code: number; day: boolean }) {
  const kind = wxKind(code)
  const key =
    kind === 'clear' ? (day ? 'clearDay' : 'clearNight')
    : kind === 'clouds' ? (code === 3 ? 'overcast' : 'clouds')
    : kind // 'rain' | 'snow' | 'fog' | 'storm'
  // Favour the starry upper band of the night shot; centre the rest.
  const objPos = key === 'clearNight' ? '50% 28%' : '50% 50%'

  return (
    <div aria-hidden style={{ position: 'absolute', inset: 0, overflow: 'hidden', pointerEvents: 'none' }}>
      <div
        className="wx-ken"
        style={{
          position: 'absolute', inset: '-8%',
          backgroundImage: `url(${WX_IMAGE[key]})`,
          backgroundSize: 'cover', backgroundPosition: objPos, backgroundRepeat: 'no-repeat',
          filter: 'brightness(1.06) saturate(1.12) contrast(1.03)',
        }}
      />
      {/* Edge scrim — only the two ends darken, where the temp/label (left) and
          H/L (right) sit, so white text stays legible while the photo stays vivid
          and bright through the middle. */}
      <div style={{ position: 'absolute', inset: 0, background: 'linear-gradient(90deg, rgba(0,0,0,0.52) 0%, rgba(0,0,0,0.30) 36%, rgba(0,0,0,0.10) 50%, rgba(0,0,0,0.10) 60%, rgba(0,0,0,0.30) 80%, rgba(0,0,0,0.48) 100%)' }} />
    </div>
  )
}

// ── A single block in the horizontal "your day" schedule strip ────────────────

function ScheduleItem({ time, title, location, meta, accent }: { time: string; title: string; location?: string | null; meta?: string; accent?: boolean }) {
  return (
    <div
      className="rise"
      style={{
        flexShrink: 0, width: 170, scrollSnapAlign: 'start',
        padding: '14px 15px', borderRadius: 16,
        background: 'var(--color-paper-100)', border: HAIRLINE,
        display: 'flex', flexDirection: 'column', gap: 7,
      }}
    >
      <span className="font-mono" style={{ fontSize: 12, fontWeight: 500, color: accent ? 'var(--color-moss-700)' : 'var(--color-ink-2)', fontVariantNumeric: 'tabular-nums', letterSpacing: '0.02em' }}>
        {time}
      </span>
      <span className="font-sans" style={{ fontSize: 14, fontWeight: 600, color: 'var(--color-ink)', lineHeight: 1.25, display: '-webkit-box', WebkitLineClamp: 2, WebkitBoxOrient: 'vertical', overflow: 'hidden' }}>
        {title}
      </span>
      {location && (
        <span className="font-sans" style={{ fontSize: 12, color: 'var(--color-ink-2)', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>
          {location}
        </span>
      )}
      {meta && <span className="font-mono" style={{ fontSize: 11, color: 'var(--color-ink-3)', marginTop: 'auto', fontVariantNumeric: 'tabular-nums' }}>{meta}</span>}
    </div>
  )
}

function AccountPopover({ name, onSignOut }: { name: string | null; onSignOut: () => void }) {
  return (
    <div
      className="section-in"
      style={{
        position: 'absolute', top: 52, right: 0, zIndex: 6, width: 200,
        background: 'rgba(251,250,245,0.96)',
        backdropFilter: 'blur(20px) saturate(1.4)', WebkitBackdropFilter: 'blur(20px) saturate(1.4)',
        border: '1px solid rgba(0,0,0,0.07)', borderRadius: 16,
        boxShadow: '0 8px 28px rgba(0,0,0,0.14)', padding: 12,
      }}
    >
      <p className="font-sans" style={{ fontSize: 11, color: 'var(--color-ink-3)', textTransform: 'uppercase', letterSpacing: '0.12em', marginBottom: 4 }}>Signed in</p>
      <p className="font-sans" style={{ fontSize: 15, fontWeight: 600, color: 'var(--color-ink)', marginBottom: 10 }}>{name ?? 'Neighbor'}</p>
      <button
        onClick={onSignOut}
        className="press hygge-tap"
        style={{ width: '100%', padding: 9, borderRadius: 10, border: HAIRLINE, background: 'transparent', cursor: 'pointer', fontFamily: 'var(--font-sans)', fontSize: 14, fontWeight: 500, color: 'var(--color-ink)' }}
      >
        Sign out
      </button>
    </div>
  )
}

function HomeTab({ onNav }: { onNav: (t: Tab) => void }) {
  const router = useRouter()
  const [today, setToday] = useState<TimelineEvent[]>([])
  const [week, setWeek] = useState<WeekEvent[]>([])
  const [loading, setLoading] = useState(true)
  const [scope, setScope] = useState<Scope>('today')
  const [collection, setCollection] = useState<number | null>(null)
  const [query, setQuery] = useState('')
  const [searchOpen, setSearchOpen] = useState(false)
  const [accountOpen, setAccountOpen] = useState(false)
  const [name, setName] = useState<string | null>(null)
  const [weather, setWeather] = useState<Weather | null>(null)

  useEffect(() => {
    Promise.all([getTodayEvents(), getWeekEvents()])
      .then(([t, w]) => { setToday(t); setWeek(w) })
      .finally(() => setLoading(false))
    getCurrentUser().then((u) => setName(firstNameFromEmail(u?.email)))
    // live weather for St. Joseph, MN — no key required
    fetch('https://api.open-meteo.com/v1/forecast?latitude=45.5647&longitude=-94.3208&current=temperature_2m,weather_code,is_day&daily=temperature_2m_max,temperature_2m_min&temperature_unit=fahrenheit&timezone=auto&forecast_days=1')
      .then((r) => r.json())
      .then((d) => { if (d?.current) setWeather({ temp: d.current.temperature_2m, code: d.current.weather_code, hi: d.daily.temperature_2m_max[0], lo: d.daily.temperature_2m_min[0], day: d.current.is_day === 1 }) })
      .catch(() => {})
  }, [])

  const dateLine = new Date().toLocaleDateString('en-US', { weekday: 'long', month: 'long', day: 'numeric' })
  const activeKw = collection !== null ? COLLECTIONS[collection].kw : null
  const q = query.trim().toLowerCase()
  const keep = (text: string) => matchesKw(text, activeKw) && (!q || text.toLowerCase().includes(q))

  const todayList = today
    .filter((e) => keep(`${e.title} ${e.location ?? ''}`))
    .sort((a, b) => minutesOf(a.start_time) - minutesOf(b.start_time))
  const goingList = todayList.filter((e) => e.rsvpd)
  const weekList = week.filter((e) => keep(e.title))

  const selectCollection = (i: number) => {
    haptic('tap')
    if (collection === i) { setCollection(null); return }
    setCollection(i)
  }

  const signOut = async () => {
    await createClient().auth.signOut()
    router.replace('/login')
  }

  // Build the horizontal "your day" schedule blocks for the active scope.
  const scheduleNodes =
    scope === 'week'
      ? weekList.map((e) => <ScheduleItem key={e.id} time={e.date_label} title={e.title} meta={`${e.going_count} going`} />)
      : (scope === 'going' ? goingList : todayList).map((e) => (
          <ScheduleItem key={e.id} time={e.start_time || 'All day'} title={e.title} location={e.location} meta={`${e.going_count} going`} accent />
        ))
  const scheduleEmpty =
    scope === 'week' ? 'Nothing on the calendar this week.' : scope === 'going' ? "You haven't joined anything yet." : 'Nothing scheduled — a clear day.'

  return (
    <div>
      {/* Masthead — logo + Joetown */}
      <div style={{ padding: '24px 20px 6px', display: 'flex', alignItems: 'flex-start', justifyContent: 'space-between' }}>
        <div>
          <div style={{ display: 'flex', alignItems: 'center', gap: 11 }}>
            <HyggeMark />
            <h1 className="font-sans" style={{ fontSize: 30, fontWeight: 700, letterSpacing: '-0.025em', color: 'var(--color-ink)', lineHeight: 1 }}>Joetown</h1>
          </div>
          <p className="font-sans" style={{ fontSize: 13, color: 'var(--color-ink-3)', marginTop: 8, marginLeft: 1 }}>{dateLine}</p>
        </div>
        <div style={{ display: 'flex', gap: 10 }}>
          <GlassCircle label="Search" active={searchOpen} onClick={() => { haptic('tap'); setAccountOpen(false); setSearchOpen((o) => !o) }}>
            <SearchIcon />
          </GlassCircle>
          <div style={{ position: 'relative' }}>
            <GlassCircle label="Account" active={accountOpen} onClick={() => { haptic('tap'); setSearchOpen(false); setAccountOpen((o) => !o) }}>
              {name ? <span className="font-sans" style={{ fontSize: 15, fontWeight: 600, color: 'var(--color-ink)' }}>{name[0]}</span> : <AccountIcon />}
            </GlassCircle>
            {accountOpen && <AccountPopover name={name} onSignOut={signOut} />}
          </div>
        </div>
      </div>

      {/* Weather — horizontal bar across the full width, with an ambient backdrop */}
      <div style={{ position: 'relative', overflow: 'hidden', marginTop: 12, borderTop: HAIRLINE, borderBottom: HAIRLINE, background: 'var(--color-paper-100)' }}>
        {weather && <WeatherBackdrop code={weather.code} day={weather.day} />}
        <div style={{ position: 'relative', zIndex: 1, padding: '11px 20px', display: 'flex', alignItems: 'center', gap: 10 }}>
        {weather ? (
          <>
            <WeatherGlyph code={weather.code} day={weather.day} color="rgba(255,255,255,0.96)" />
            <span className="font-mono" style={{ fontSize: 16, fontWeight: 600, color: '#fff', fontVariantNumeric: 'tabular-nums', textShadow: WX_TEXT_SHADOW }}>{Math.round(weather.temp)}°</span>
            <span className="font-sans" style={{ fontSize: 13.5, color: 'rgba(255,255,255,0.92)', textShadow: WX_TEXT_SHADOW }}>{wmoText(weather.code)} in St. Joseph</span>
            <span style={{ flex: 1 }} />
            <span className="font-mono" style={{ fontSize: 12.5, color: 'rgba(255,255,255,0.85)', fontVariantNumeric: 'tabular-nums', textShadow: WX_TEXT_SHADOW }}>
              H {Math.round(weather.hi)}°
            </span>
            <span className="font-mono" style={{ fontSize: 12.5, color: 'rgba(255,255,255,0.85)', fontVariantNumeric: 'tabular-nums', textShadow: WX_TEXT_SHADOW }}>
              L {Math.round(weather.lo)}°
            </span>
          </>
        ) : (
          <span className="font-sans" style={{ fontSize: 13, color: 'var(--color-ink-3)' }}>Loading today&rsquo;s weather…</span>
        )}
        </div>
      </div>

      {/* Search field */}
      {searchOpen && (
        <div className="section-in" style={{ padding: '12px 20px 0' }}>
          <input autoFocus className="hygge-field" style={fieldStyle} placeholder="Search events…" value={query} onChange={(e) => setQuery(e.target.value)} />
        </div>
      )}

      {/* Segmented scope pills */}
      <div style={{ padding: '14px 20px 2px', display: 'flex', gap: 8 }}>
        {SCOPES.map((s) => {
          const active = s.id === scope
          return (
            <button
              key={s.id}
              onClick={() => { haptic('tap'); setScope(s.id) }}
              className="press hygge-tap"
              style={{
                display: 'flex', alignItems: 'center', gap: 6,
                padding: '8px 15px', borderRadius: 20,
                border: active ? 'none' : HAIRLINE,
                background: active ? 'var(--color-ink)' : 'transparent',
                color: active ? 'var(--color-paper)' : 'var(--color-ink-2)',
                fontSize: 13.5, fontWeight: active ? 600 : 500,
                fontFamily: 'var(--font-sans)', cursor: 'pointer',
                transition: 'background 0.15s ease, color 0.15s ease',
              }}
            >
              <ScopeIcon id={s.id} active={active} />
              {s.label}
            </button>
          )
        })}
      </div>

      {/* Your day — horizontal schedule strip (replaces the old quick-actions grid) */}
      <div style={{ padding: '18px 0 4px' }}>
        <div style={{ display: 'flex', alignItems: 'baseline', gap: 8, padding: '0 20px' }}>
          <SectionHead>{scope === 'today' ? 'Your day' : scope === 'week' ? 'This week' : "You're going"}</SectionHead>
          {collection !== null && (
            <button
              onClick={() => { haptic('tap'); setCollection(null) }}
              className="hygge-tap"
              style={{ display: 'inline-flex', alignItems: 'center', gap: 5, padding: '3px 10px', borderRadius: 20, border: HAIRLINE, background: 'var(--color-paper-100)', cursor: 'pointer', fontFamily: 'var(--font-sans)', fontSize: 12, color: 'var(--color-ink-2)' }}
            >
              {COLLECTIONS[collection].name}
              <svg width="11" height="11" viewBox="0 0 12 12" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" aria-hidden>
                <line x1="3" y1="3" x2="9" y2="9" /><line x1="9" y1="3" x2="3" y2="9" />
              </svg>
            </button>
          )}
        </div>
        <div style={{ display: 'flex', gap: 10, overflowX: 'auto', scrollbarWidth: 'none', padding: '12px 20px 8px', scrollSnapType: 'x mandatory', alignItems: 'stretch' }}>
          {loading ? (
            <div style={{ padding: '18px 0', color: 'var(--color-ink-3)', fontFamily: 'var(--font-sans)', fontSize: 14 }}>Loading…</div>
          ) : (
            <>
              {scheduleNodes.length === 0 ? (
                <div style={{ flexShrink: 0, display: 'flex', alignItems: 'center', padding: '16px 18px', borderRadius: 16, border: '1.5px dashed rgba(0,0,0,0.13)' }}>
                  <span className="font-sans" style={{ fontSize: 13, color: 'var(--color-ink-2)' }}>{scheduleEmpty}</span>
                </div>
              ) : (
                scheduleNodes
              )}
              <button
                onClick={() => onNav('add')}
                className="press hygge-tap"
                style={{
                  flexShrink: 0, width: 116, scrollSnapAlign: 'start',
                  display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', gap: 8,
                  borderRadius: 16, border: '1.5px dashed rgba(0,0,0,0.13)', background: 'transparent', cursor: 'pointer',
                }}
              >
                <span style={{ width: 30, height: 30, borderRadius: 9, background: 'var(--color-paper-100)', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
                  <svg width="14" height="14" viewBox="0 0 15 15" fill="none" stroke="var(--color-ink-2)" strokeWidth="2" strokeLinecap="round" aria-hidden>
                    <line x1="7.5" y1="2" x2="7.5" y2="13" /><line x1="2" y1="7.5" x2="13" y2="7.5" />
                  </svg>
                </span>
                <span className="font-sans" style={{ fontSize: 12, color: 'var(--color-ink-2)', fontWeight: 500 }}>Add event</span>
              </button>
            </>
          )}
        </div>
      </div>

      {/* Around town — collections carousel */}
      <div style={{ padding: '14px 0 4px' }}>
        <div style={{ padding: '0 20px' }}><SectionHead>Around town</SectionHead></div>
        <div style={{ display: 'flex', gap: 12, overflowX: 'auto', scrollbarWidth: 'none', padding: '12px 20px 6px', scrollSnapType: 'x mandatory' }}>
          {COLLECTIONS.map((c, i) => {
            const active = collection === i
            return (
              <button
                key={c.name}
                onClick={() => selectCollection(i)}
                className="press hygge-tap"
                style={{
                  scrollSnapAlign: 'start', flexShrink: 0, width: 268, height: 168,
                  borderRadius: 22, border: 'none', cursor: 'pointer',
                  padding: '18px 20px', display: 'flex', flexDirection: 'column', justifyContent: 'flex-end', textAlign: 'left',
                  background: `linear-gradient(to top, rgba(20,18,14,0.74) 4%, rgba(20,18,14,0.28) 42%, rgba(20,18,14,0.08) 100%), url(${c.image}) center/cover no-repeat`,
                  color: '#fbfaf5',
                  position: 'relative', overflow: 'hidden',
                  boxShadow: active ? '0 0 0 2.5px var(--color-ink), 0 8px 22px rgba(0,0,0,0.16)' : '0 6px 18px rgba(0,0,0,0.10)',
                }}
              >
                {active && <ActiveBadge />}
                <span className="font-sans" style={{ fontSize: 23, fontWeight: 700, letterSpacing: '-0.02em', lineHeight: 1.08, textShadow: '0 1px 8px rgba(0,0,0,0.45)' }}>{c.name}</span>
                <span className="font-sans" style={{ fontSize: 13, opacity: 0.92, marginTop: 5, textShadow: '0 1px 6px rgba(0,0,0,0.45)' }}>{c.blurb}</span>
              </button>
            )
          })}
        </div>
      </div>

      <div style={{ height: 8 }} />

      {/* tap-away catcher for the account popover */}
      {accountOpen && <div onClick={() => setAccountOpen(false)} style={{ position: 'fixed', inset: 0, zIndex: 5 }} />}
    </div>
  )
}

// ── Calendar tab ─────────────────────────────────────────────────────────────

const WEEKDAYS = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat']

function MonthBlock({
  year,
  month,
  eventDates,
  selectedDate,
  todayYmd,
  onSelect,
}: {
  year: number
  month: number
  eventDates: Set<string>
  selectedDate: string | null
  todayYmd: string
  onSelect: (d: string) => void
}) {
  const label = new Date(year, month - 1, 1).toLocaleDateString('en-US', { month: 'long' })
  const firstDay = new Date(year, month - 1, 1).getDay()
  const daysInMonth = new Date(year, month, 0).getDate()
  const cells: (number | null)[] = [
    ...Array(firstDay).fill(null),
    ...Array.from({ length: daysInMonth }, (_, i) => i + 1),
  ]
  while (cells.length % 7 !== 0) cells.push(null)

  return (
    <div style={{ marginBottom: 4 }}>
      <h2 className="font-sans" style={{ fontSize: 28, fontWeight: 700, color: 'var(--color-ink)', letterSpacing: '-0.015em', margin: '24px 0 6px' }}>
        {label}
      </h2>
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(7, 1fr)' }}>
        {cells.map((day, i) => {
          if (!day) return <div key={i} />
          const date = `${year}-${String(month).padStart(2, '0')}-${String(day).padStart(2, '0')}`
          const hasEvent = eventDates.has(date)
          const isSelected = date === selectedDate
          const isToday = date === todayYmd
          const isPast = date < todayYmd
          return (
            <button
              key={i}
              onClick={() => onSelect(date)}
              className="hygge-tap"
              aria-label={`${label} ${day}${hasEvent ? ', has events' : ''}`}
              style={{
                position: 'relative',
                height: 60,
                display: 'flex',
                flexDirection: 'column',
                alignItems: 'center',
                justifyContent: 'center',
                background: 'none',
                border: 'none',
                cursor: 'pointer',
                padding: 0,
              }}
            >
              <span
                style={{
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'center',
                  width: 46,
                  height: 46,
                  borderRadius: '50%',
                  background: isSelected ? 'var(--color-moss-700)' : 'transparent',
                  border: isToday && !isSelected ? '1.5px solid var(--color-moss-700)' : '1.5px solid transparent',
                }}
              >
                <span
                  className="font-sans"
                  style={{
                    fontSize: 19,
                    fontWeight: 600,
                    fontVariantNumeric: 'tabular-nums',
                    color: isSelected ? 'var(--color-paper)' : isPast ? 'var(--color-ink-3)' : 'var(--color-ink)',
                  }}
                >
                  {day}
                </span>
              </span>
              <span
                style={{
                  position: 'absolute',
                  bottom: 7,
                  width: 5,
                  height: 5,
                  borderRadius: '50%',
                  background: hasEvent && !isSelected ? 'var(--color-moss-600)' : 'transparent',
                }}
              />
            </button>
          )
        })}
      </div>
    </div>
  )
}

function CalendarTab() {
  const today = new Date()
  const todayYmd = `${today.getFullYear()}-${String(today.getMonth() + 1).padStart(2, '0')}-${String(today.getDate()).padStart(2, '0')}`
  const [selectedDate, setSelectedDate] = useState<string | null>(null)
  const [eventDates, setEventDates] = useState<Set<string>>(new Set())
  const [dayEvents, setDayEvents] = useState<TimelineEvent[]>([])
  const [sheetOpen, setSheetOpen] = useState(false)
  const [loadingEvents, setLoadingEvents] = useState(false)
  const requestedDateRef = useRef<string | null>(null)
  const handleRsvp = useRsvpHandler(setDayEvents)

  // 12 months starting from the current one.
  const months = Array.from({ length: 12 }, (_, k) => {
    const idx = today.getMonth() + k
    return { year: today.getFullYear() + Math.floor(idx / 12), month: (idx % 12) + 1 }
  })

  useEffect(() => {
    let alive = true
    Promise.all(
      Array.from({ length: 12 }, (_, k) => {
        const idx = today.getMonth() + k
        const y = today.getFullYear() + Math.floor(idx / 12)
        const m = (idx % 12) + 1
        return getMonthEventDates(y, m).catch(() => [] as string[])
      })
    ).then((res) => { if (alive) setEventDates(new Set(res.flat())) })
    return () => { alive = false }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

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

  return (
    <div style={{ padding: '4px 20px 0' }}>
      <h1 className="font-sans" style={{ fontSize: 28, fontWeight: 700, color: 'var(--color-ink)', letterSpacing: '-0.02em', margin: '16px 0 18px', lineHeight: 1.1 }}>
        What&rsquo;s coming up?
      </h1>

      {/* Pinned weekday header */}
      <div
        style={{
          position: 'sticky',
          top: 0,
          zIndex: 2,
          background: 'var(--color-paper)',
          display: 'grid',
          gridTemplateColumns: 'repeat(7, 1fr)',
          paddingTop: 6,
          paddingBottom: 6,
        }}
      >
        {WEEKDAYS.map((d) => (
          <div key={d} className="font-sans" style={{ textAlign: 'center', fontSize: 13, fontWeight: 600, color: 'var(--color-ink)' }}>
            {d}
          </div>
        ))}
      </div>

      {months.map((m) => (
        <MonthBlock
          key={`${m.year}-${m.month}`}
          year={m.year}
          month={m.month}
          eventDates={eventDates}
          selectedDate={selectedDate}
          todayYmd={todayYmd}
          onSelect={selectDate}
        />
      ))}
      <div style={{ height: 24 }} />

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
  const [tab, setTab] = useState<Tab>('home')
  const [isAdmin, setIsAdmin] = useState(false)

  useEffect(() => {
    getCurrentUser().then((u) => setIsAdmin(isAdminEmail(u?.email)))
  }, [])

  const switchTab = (t: Tab) => { if (t !== tab) haptic('tap'); setTab(t) }

  const TABS: { id: Tab; label: string }[] = [
    { id: 'home', label: 'Home' },
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
        @keyframes tab-enter {
          from { opacity: 0; transform: translateY(7px); }
          to   { opacity: 1; transform: translateY(0); }
        }
        .tab-enter { animation: tab-enter 0.22s cubic-bezier(0.22,1,0.36,1) both; }
        @media (prefers-reduced-motion: reduce) { .tab-enter { animation-duration: 0.01ms !important; } }
        .nav-pill {
          display: flex; flex-direction: column; align-items: center; gap: 3px;
          padding: 6px 13px; border-radius: 14px;
          transition: background 0.18s ease;
        }
        .nav-pill.nav-pill--active { background: rgba(45,69,48,0.10); }
      `}</style>

      {/* Tab content — no shared masthead; each tab owns its header */}
      <main style={{ flex: 1, overflowY: 'auto', paddingBottom: 108 }}>
        <div key={tab} className="tab-enter">
          {tab === 'home' && <HomeTab onNav={switchTab} />}
          {tab === 'calendar' && <CalendarTab />}
          {tab === 'add' && <AddEventTab onSuccess={() => setTab('timeline')} />}
          {tab === 'quest' && <QuestTab isAdmin={isAdmin} />}
        </div>
      </main>

      {/* Bottom nav — floating frosted-glass pill */}
      <nav
        style={{
          position: 'fixed',
          bottom: 'max(16px, env(safe-area-inset-bottom))',
          left: '50%',
          transform: 'translateX(-50%)',
          width: 'calc(100% - 32px)',
          maxWidth: 448,
          background: 'rgba(251,250,245,0.55)',
          backdropFilter: 'blur(30px) saturate(1.9)',
          WebkitBackdropFilter: 'blur(30px) saturate(1.9)',
          boxShadow: '0 10px 34px rgba(31,48,34,0.18), inset 0 1px 0 rgba(255,255,255,0.9), inset 0 0 0 1px rgba(255,255,255,0.18)',
          borderRadius: 28,
          border: '1px solid rgba(0,0,0,0.06)',
          display: 'grid',
          gridTemplateColumns: 'repeat(4, 1fr)',
          padding: '6px 4px 8px',
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
                background: 'none',
                border: 'none',
                cursor: 'pointer',
                padding: '2px 0',
              }}
            >
              <span className={`nav-pill${active ? ' nav-pill--active' : ''}`}>
                <TabIcon id={t.id} active={active} />
                <span
                  className="font-sans"
                  style={{
                    fontSize: 10,
                    color: active ? 'var(--color-moss-700)' : 'var(--color-ink-3)',
                    letterSpacing: '0.04em',
                    fontWeight: active ? 600 : 400,
                    transition: 'color 0.15s ease',
                  }}
                >
                  {t.label}
                </span>
              </span>
            </button>
          )
        })}
      </nav>
    </div>
  )
}
