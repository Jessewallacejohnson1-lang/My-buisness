'use client'

/*
  Community tier — standalone 4-tab app (Today / Clubs / Letter / Hello).
  Ported from the design handoff (community-app.jsx). Clubs (join/leave) and the
  Today timeline (RSVP) are wired to Supabase; Letter, Hello, quest, advice and
  weather come from lib/community-content for now. Its own header + bottom nav —
  it does NOT use the fitness AppShell.
*/

import { useCallback, useEffect, useState } from 'react'
import Link from 'next/link'
import { haptic } from '@/lib/haptics'
import {
  getApprovedClubs,
  getPendingClubs,
  getTodayEvents,
  getWeekEvents,
  joinClub,
  leaveClub,
  rsvpEvent,
  unRsvpEvent,
  submitClub,
  setClubStatus,
  getCurrentUser,
  isAdminEmail,
  firstNameFromEmail,
  type ClubView,
  type ClubRow,
  type TimelineEvent,
  type WeekEvent,
} from '@/lib/community'
import { WEATHER, MORNING, EVENING, SUNDAY_LETTER, DAILY_HELLO } from '@/lib/community-content'

type Tab = 'today' | 'clubs' | 'letter' | 'hello'
type Mode = 'morning' | 'evening'

const EASE = 'var(--ease-out)'

/* ── tiny inline icons (no emoji per brand rule) ─────────────────────────── */

function SunIcon() {
  return (
    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" aria-hidden>
      <circle cx="12" cy="12" r="4" /><path d="M12 2v2M12 20v2M2 12h2M20 12h2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M19.1 4.9l-1.4 1.4M6.3 17.7l-1.4 1.4" />
    </svg>
  )
}
function MoonGlyph({ size = 14, opacity = 1 }: { size?: number; opacity?: number }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none" style={{ opacity }} aria-hidden>
      <path d="M21 12.79A9 9 0 1 1 11.21 3 7 7 0 0 0 21 12.79z" fill="currentColor" />
    </svg>
  )
}
function WaveIcon() {
  return (
    <svg width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round" aria-hidden>
      <path d="M18 11V6a2 2 0 0 0-2-2 2 2 0 0 0-2 2" /><path d="M14 10V4a2 2 0 0 0-2-2 2 2 0 0 0-2 2v2" />
      <path d="M10 10.5V6a2 2 0 0 0-2-2 2 2 0 0 0-2 2v8" />
      <path d="M18 8a2 2 0 0 1 4 0v6a8 8 0 0 1-8 8h-2c-2.8 0-4.5-.86-5.99-2.34l-3.6-3.6a2 2 0 0 1 2.83-2.82L7 15" />
    </svg>
  )
}
function TabIcon({ id, active }: { id: Tab; active: boolean }) {
  const c = active ? 'var(--slate-600)' : 'var(--text-faint)'
  const sp = { fill: 'none', stroke: c, strokeWidth: '1.8', strokeLinecap: 'round' as const, strokeLinejoin: 'round' as const }
  if (id === 'today') return <svg width="22" height="22" viewBox="0 0 24 24" {...sp}><path d="M3 9l9-7 9 7v11a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z" /><polyline points="9 22 9 12 15 12 15 22" /></svg>
  if (id === 'clubs') return <svg width="22" height="22" viewBox="0 0 24 24" {...sp}><path d="M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2" /><circle cx="9" cy="7" r="4" /><path d="M23 21v-2a4 4 0 0 0-3-3.87" /><path d="M16 3.13a4 4 0 0 1 0 7.75" /></svg>
  if (id === 'letter') return <svg width="22" height="22" viewBox="0 0 24 24" {...sp}><rect x="2" y="4" width="20" height="16" rx="2" /><polyline points="22,6 12,13 2,6" /></svg>
  return <svg width="22" height="22" viewBox="0 0 24 24" {...sp}><path d="M18 11V6a2 2 0 0 0-2-2 2 2 0 0 0-2 2" /><path d="M14 10V4a2 2 0 0 0-2-2 2 2 0 0 0-2 2v2" /><path d="M10 10.5V6a2 2 0 0 0-2-2 2 2 0 0 0-2 2v8" /><path d="M18 8a2 2 0 0 1 4 0v6a8 8 0 0 1-8 8h-2c-2.8 0-4.5-.86-5.99-2.34l-3.6-3.6a2 2 0 0 1 2.83-2.82L7 15" /></svg>
}

/* ── ambient pieces ──────────────────────────────────────────────────────── */

function Bird() {
  return (
    <div style={{ position: 'relative', height: 52, overflow: 'hidden', pointerEvents: 'none', marginBottom: 2 }}>
      <svg viewBox="0 0 72 44" width="56" height="34" style={{ position: 'absolute', top: 8, left: 0, animation: 'birdFly 5.8s var(--ease-out) 0.5s forwards' }}>
        <ellipse cx="32" cy="26" rx="12" ry="6" fill="#6b7b84" />
        <ellipse cx="43" cy="23" rx="5" ry="4.5" fill="#6b7b84" />
        <circle cx="44.5" cy="21.5" r="1.2" fill="#e1dbc9" />
        <path d="M47.5 22.5 L53 22" stroke="#55636b" strokeWidth="1.6" strokeLinecap="round" />
        <path d="M21 26 L13 20 M21 27.5 L12 31" stroke="#6b7b84" strokeWidth="2.4" strokeLinecap="round" />
        <path d="M29 23 Q17 12 9 21" stroke="#6b7b84" strokeWidth="3.8" fill="none" strokeLinecap="round" style={{ transformOrigin: '29px 23px', animation: 'wingFlap 0.44s ease-in-out infinite' }} />
        <path d="M36 23 Q45 14 53 21" stroke="#6b7b84" strokeWidth="2.2" fill="none" strokeLinecap="round" opacity="0.4" style={{ transformOrigin: '36px 23px', animation: 'wingFlap 0.44s ease-in-out infinite 0.22s' }} />
      </svg>
    </div>
  )
}

function Candle() {
  return (
    <div style={{ display: 'flex', justifyContent: 'center', height: 88, alignItems: 'flex-end', paddingBottom: 4, pointerEvents: 'none' }}>
      <svg viewBox="0 0 50 92" width="50" height="92">
        <ellipse cx="25" cy="27" rx="22" ry="24" fill="oklch(80% 0.13 65)" className="flicker" style={{ transformOrigin: '25px 40px', opacity: 0.13, animationDuration: '2.4s' }} />
        <ellipse cx="25" cy="22" rx="9.5" ry="15" fill="oklch(68% 0.20 50)" className="flicker" style={{ transformOrigin: '25px 36px', animationDuration: '1.7s' }} />
        <ellipse cx="25" cy="25" rx="6" ry="10" fill="oklch(80% 0.18 68)" className="flicker" style={{ transformOrigin: '25px 36px', animationDuration: '2.0s', animationDelay: '-0.5s' }} />
        <ellipse cx="25" cy="28" rx="2.8" ry="5.5" fill="oklch(94% 0.07 88)" />
        <line x1="25" y1="35" x2="25" y2="40" stroke="#5e5d56" strokeWidth="1.5" strokeLinecap="round" />
        <rect x="17" y="40" width="16" height="42" rx="3" fill="var(--sand-300)" stroke="var(--sand-400)" strokeWidth="1" />
        <path d="M17 48 Q14 56 16 64 L17 64Z" fill="var(--sand-300)" />
        <rect x="13" y="80" width="24" height="6" rx="3" fill="var(--sand-400)" />
      </svg>
    </div>
  )
}

/* ── collapsible folder ──────────────────────────────────────────────────── */

function Folder({ label, children, open: defaultOpen = true }: { label: string; children: React.ReactNode; open?: boolean }) {
  const [open, setOpen] = useState(defaultOpen)
  return (
    <section style={{ marginBottom: 24 }}>
      <button onClick={() => { haptic('select'); setOpen((o) => !o) }} className="press" style={{ display: 'flex', alignItems: 'center', gap: 8, background: 'none', border: 'none', padding: '0 0 10px', cursor: 'pointer', width: '100%', textAlign: 'left' }}>
        <span style={{ fontSize: 11, letterSpacing: '.18em', textTransform: 'uppercase', color: 'var(--slate-600)', fontWeight: 500, flexShrink: 0 }}>{label}</span>
        <svg width="10" height="10" viewBox="0 0 10 10" style={{ color: 'var(--slate-400)', transform: open ? 'rotate(0deg)' : 'rotate(-90deg)', transition: `transform 0.2s ${EASE}`, flexShrink: 0 }}>
          <path d="M1 3l4 4 4-4" stroke="currentColor" strokeWidth="1.7" fill="none" strokeLinecap="round" strokeLinejoin="round" />
        </svg>
        <span style={{ flex: 1, height: 1, background: 'var(--border-hairline)' }} />
      </button>
      {open && <div className="section-in">{children}</div>}
    </section>
  )
}

/* ── timeline row ────────────────────────────────────────────────────────── */

function TimelineRow({ item, onToggle }: { item: TimelineEvent; onToggle: (e: TimelineEvent) => void }) {
  return (
    <div onClick={() => onToggle(item)} className="press" style={{ display: 'flex', alignItems: 'center', gap: 14, padding: '11px 0', borderBottom: '1px solid var(--border-hairline)', cursor: 'pointer' }}>
      <span style={{ fontFamily: 'var(--font-mono)', fontSize: 11, color: 'var(--text-faint)', minWidth: 34, flexShrink: 0 }}>{item.start_time}</span>
      <span style={{ flex: 1, fontSize: 14, color: 'var(--text-body)', lineHeight: 1.3 }}>{item.title}</span>
      {item.rsvpd ? (
        <span style={{ fontSize: 13, color: 'var(--slate-600)', flexShrink: 0, fontWeight: 500 }}>✓</span>
      ) : item.going_count > 0 ? (
        <span style={{ fontFamily: 'var(--font-mono)', fontSize: 11, color: 'var(--text-faint)', flexShrink: 0, fontVariantNumeric: 'tabular-nums' }}>{item.going_count} going</span>
      ) : (
        <span style={{ fontSize: 11, color: 'var(--slate-500)', background: 'var(--slate-100)', borderRadius: 'var(--radius-pill)', padding: '2px 8px', flexShrink: 0 }}>for you</span>
      )}
    </div>
  )
}

/* ── quest card (personal daily prompt; no fake social counter) ──────────── */

function QuestCard({ prompt, cta, doneLabel }: { prompt: string; cta: string; doneLabel: string }) {
  const [done, setDone] = useState(false)
  const [burst, setBurst] = useState(false)
  function tap() {
    if (done) return
    setDone(true)
    haptic('success')
    setBurst(true)
    setTimeout(() => setBurst(false), 900)
  }
  return (
    <div style={{ background: 'var(--sand-400)', borderRadius: 'var(--radius-xl)', padding: 20, position: 'relative', overflow: 'hidden' }}>
      {burst && <div className="burst-fade" style={{ position: 'absolute', inset: 0, background: 'radial-gradient(circle at 50% 90%, oklch(76% 0.15 55 / 0.55) 0%, transparent 70%)', pointerEvents: 'none' }} />}
      <p style={{ fontSize: 19, fontFamily: 'var(--font-display)', fontWeight: 500, color: 'var(--char-900)', margin: '0 0 16px', lineHeight: 1.35 }}>{done ? doneLabel : prompt}</p>
      <button onClick={tap} disabled={done} className="press" style={{ width: '100%', padding: 13, borderRadius: 'var(--radius-sm)', background: done ? 'var(--slate-600)' : 'var(--char-700)', color: 'var(--linen-50)', border: 'none', fontSize: 14, cursor: done ? 'default' : 'pointer', transition: `background 0.35s ${EASE}` }}>
        {done ? 'Done for today  ✦' : cta}
      </button>
    </div>
  )
}

/* ── this-week horizontal scroll ─────────────────────────────────────────── */

function WeekScroll({ events }: { events: WeekEvent[] }) {
  if (events.length === 0) return <p style={{ fontSize: 13, color: 'var(--text-faint)', margin: 0 }}>Nothing on the calendar yet this week.</p>
  return (
    <div style={{ display: 'flex', gap: 10, overflowX: 'auto', paddingBottom: 6, scrollbarWidth: 'none' }}>
      {events.map((ev) => (
        <div key={ev.id} className="press" style={{ flexShrink: 0, width: 134, background: 'var(--surface-card)', border: '1px solid var(--border-hairline)', borderTop: '3px solid var(--slate-600)', borderRadius: 'var(--radius-md)', padding: '13px 14px 12px', cursor: 'pointer', boxShadow: 'var(--shadow-card)' }}>
          <p style={{ fontSize: 13, color: 'var(--text-body)', margin: '0 0 4px', fontWeight: 500, lineHeight: 1.3 }}>{ev.title}</p>
          <p style={{ fontFamily: 'var(--font-mono)', fontSize: 11, color: 'var(--text-faint)', margin: 0, fontVariantNumeric: 'tabular-nums' }}>{ev.date_label}{ev.going_count > 0 ? ` · ${ev.going_count} going` : ''}</p>
        </div>
      ))}
    </div>
  )
}

/* ── club card ───────────────────────────────────────────────────────────── */

function ClubCard({ club, onToggle }: { club: ClubView; onToggle: (c: ClubView) => void }) {
  return (
    <div style={{ background: 'var(--surface-card)', borderRadius: 'var(--radius-md)', padding: '15px 16px 13px', border: '1px solid var(--border-hairline)', borderLeft: `3px solid ${club.joined ? 'var(--slate-600)' : 'var(--border-hairline)'}`, boxShadow: 'var(--shadow-card)', transition: `border-color 0.2s ${EASE}` }}>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', gap: 12, marginBottom: 6 }}>
        <div style={{ flex: 1, minWidth: 0 }}>
          <p style={{ fontSize: 14, fontWeight: 500, color: 'var(--text-strong)', margin: '0 0 2px' }}>{club.name}</p>
          {club.host && <p style={{ fontSize: 12, color: 'var(--text-faint)', margin: 0 }}>with {club.host}</p>}
        </div>
        <button onClick={() => onToggle(club)} className="press" style={{ flexShrink: 0, padding: '5px 14px', borderRadius: 'var(--radius-pill)', border: club.joined ? 'none' : '1px solid var(--slate-400)', background: club.joined ? 'var(--slate-600)' : 'transparent', color: club.joined ? 'var(--linen-50)' : 'var(--slate-600)', fontSize: 13, cursor: 'pointer', transition: `all 0.2s ${EASE}` }}>
          {club.joined ? '✓ Joined' : 'Join'}
        </button>
      </div>
      {club.vibe && <p style={{ fontSize: 13, color: 'var(--text-muted)', margin: '0 0 8px', fontStyle: 'italic', lineHeight: 1.4 }}>{club.vibe}</p>}
      <div style={{ display: 'flex', gap: 14 }}>
        {club.schedule && <span style={{ fontFamily: 'var(--font-mono)', fontSize: 11, color: 'var(--text-faint)' }}>{club.schedule}</span>}
        {club.member_count > 0 && <span style={{ fontFamily: 'var(--font-mono)', fontSize: 11, color: 'var(--text-faint)', fontVariantNumeric: 'tabular-nums' }}>{club.member_count} {club.member_count === 1 ? 'Hygger' : 'Hyggers'}</span>}
      </div>
    </div>
  )
}

/* ── page ────────────────────────────────────────────────────────────────── */

export default function CommunityPage() {
  const [tab, setTab] = useState<Tab>('today')
  const [mode, setMode] = useState<Mode>(() => {
    const h = new Date().getHours()
    return h >= 18 || h < 5 ? 'evening' : 'morning'
  })

  const [name, setName] = useState<string | null>(null)
  const [isAdmin, setIsAdmin] = useState(false)
  const [clubs, setClubs] = useState<ClubView[]>([])
  const [timeline, setTimeline] = useState<TimelineEvent[]>([])
  const [week, setWeek] = useState<WeekEvent[]>([])
  const [pending, setPending] = useState<ClubRow[]>([])
  const [loading, setLoading] = useState(true)
  const [err, setErr] = useState<string | null>(null)

  const load = useCallback(async () => {
    try {
      const user = await getCurrentUser()
      const admin = isAdminEmail(user?.email)
      const [clubsD, todayD, weekD] = await Promise.all([getApprovedClubs(), getTodayEvents(), getWeekEvents()])
      const pendingD = admin ? await getPendingClubs() : []
      setName(firstNameFromEmail(user?.email))
      setIsAdmin(admin)
      setClubs(clubsD)
      setTimeline(todayD)
      setWeek(weekD)
      setPending(pendingD)
      setErr(null)
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => {
    // Async rejection (e.g. migration not yet run) surfaces a hint, off the sync path.
    load().catch(() => setErr("Couldn't load the community. Run the community migration in Supabase, then refresh."))
  }, [load])

  const toggleRsvp = async (ev: TimelineEvent) => {
    const snapshot = timeline
    const joining = !ev.rsvpd
    setErr(null)
    setTimeline((t) => t.map((x) => (x.id === ev.id ? { ...x, rsvpd: joining, going_count: Math.max(0, x.going_count + (joining ? 1 : -1)) } : x)))
    haptic(joining ? 'select' : 'tap')
    try {
      if (joining) await rsvpEvent(ev.id)
      else await unRsvpEvent(ev.id)
    } catch {
      setTimeline(snapshot)
      setErr("Couldn't update your RSVP. Check your connection.")
      haptic('error')
    }
  }

  const toggleJoin = async (club: ClubView) => {
    const snapshot = clubs
    const joining = !club.joined
    setErr(null)
    setClubs((cs) => cs.map((c) => (c.id === club.id ? { ...c, joined: joining, member_count: Math.max(0, c.member_count + (joining ? 1 : -1)) } : c)))
    haptic(joining ? 'select' : 'tap')
    try {
      if (joining) await joinClub(club.id)
      else await leaveClub(club.id)
    } catch {
      setClubs(snapshot)
      setErr("Couldn't update the club. Check your connection.")
      haptic('error')
    }
  }

  const moderate = async (id: string, status: 'approved' | 'rejected') => {
    setErr(null)
    setPending((p) => p.filter((c) => c.id !== id))
    haptic(status === 'approved' ? 'success' : 'tap')
    try {
      await setClubStatus(id, status)
      await load()
    } catch {
      setErr("Couldn't update that submission.")
      haptic('error')
      await load()
    }
  }

  const greeting = mode === 'morning' ? 'Good morning' : 'Good evening'
  const TABS: { id: Tab; label: string }[] = [
    { id: 'today', label: 'Today' },
    { id: 'clubs', label: 'Clubs' },
    { id: 'letter', label: 'Letter' },
    { id: 'hello', label: 'Hello' },
  ]

  return (
    <div style={{ minHeight: '100dvh', background: 'var(--surface-app)', display: 'flex', justifyContent: 'center' }}>
      <div style={{ width: '100%', maxWidth: 460, display: 'flex', flexDirection: 'column', minHeight: '100dvh' }}>

        {/* header */}
        <div style={{ position: 'sticky', top: 0, zIndex: 20, display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '15px 22px 11px', background: 'color-mix(in srgb, var(--surface-app) 88%, transparent)', backdropFilter: 'blur(12px)', borderBottom: '1px solid var(--border-hairline)' }}>
          <Link href="/dashboard" aria-label="Back to app" style={{ fontSize: 13, letterSpacing: '.24em', textTransform: 'uppercase', color: 'var(--text-body)', fontWeight: 600 }}>HYGGE</Link>
          {tab === 'today' && (
            <button onClick={() => { haptic('select'); setMode((m) => (m === 'morning' ? 'evening' : 'morning')) }} className="press" style={{ display: 'flex', alignItems: 'center', gap: 6, padding: '5px 12px', borderRadius: 'var(--radius-pill)', background: 'var(--surface-raised)', border: '1px solid var(--border-hairline)', cursor: 'pointer', color: 'var(--text-muted)', fontSize: 12 }}>
              <span style={{ display: 'flex', color: 'var(--slate-600)' }}>{mode === 'morning' ? <SunIcon /> : <MoonGlyph />}</span>
              <span>{mode === 'morning' ? 'Morning' : 'Evening'}</span>
            </button>
          )}
        </div>

        {/* body */}
        <div key={tab + mode} className="section-in" style={{ flex: 1, overflowY: 'auto', padding: '20px 22px 30px' }}>
          {err && (
            <div className="rise" style={{ fontSize: 13, color: 'var(--avoid-600)', background: 'color-mix(in srgb, var(--avoid-600) 9%, transparent)', border: '1px solid color-mix(in srgb, var(--avoid-600) 22%, transparent)', borderRadius: 'var(--radius-md)', padding: '12px 14px', marginBottom: 16, lineHeight: 1.5 }}>{err}</div>
          )}

          {loading ? (
            <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
              {[0, 1, 2].map((i) => <div key={i} style={{ height: 60, background: 'var(--surface-raised)', borderRadius: 'var(--radius-md)' }} className="animate-pulse" />)}
            </div>
          ) : (
            <>
              {/* ── TODAY ── */}
              {tab === 'today' && (
                <div>
                  <p style={{ textAlign: 'center', fontSize: 11, letterSpacing: '.28em', textTransform: 'uppercase', color: 'var(--text-faint)', margin: '0 0 2px' }}>ST. JOE</p>
                  {mode === 'morning' ? <Bird /> : <Candle />}
                  <div style={{ marginBottom: 26 }}>
                    <h1 style={{ fontFamily: 'var(--font-display)', fontSize: 24, fontWeight: 500, color: 'var(--text-strong)', margin: '0 0 4px', letterSpacing: '-0.01em' }}>{greeting}{name ? `, ${name}` : ''}.</h1>
                    <p style={{ fontSize: 14, color: 'var(--text-muted)', margin: 0 }}>{mode === 'morning' ? WEATHER.morning : WEATHER.evening}</p>
                  </div>

                  {mode === 'morning' ? (
                    <>
                      <Folder label="Today">
                        {timeline.length === 0
                          ? <p style={{ fontSize: 13, color: 'var(--text-faint)', margin: 0 }}>Nothing scheduled today. Join a club to fill your timeline.</p>
                          : timeline.map((item) => <TimelineRow key={item.id} item={item} onToggle={toggleRsvp} />)}
                      </Folder>
                      <Folder label="Quest"><QuestCard prompt={MORNING.quest} cta={MORNING.questCta} doneLabel={MORNING.questDone} /></Folder>
                      <Folder label="This Week"><WeekScroll events={week} /></Folder>
                      <Folder label="Advice" open={false}>
                        <p style={{ fontSize: 14, color: 'var(--text-body)', lineHeight: 1.65, margin: '0 0 8px', textWrap: 'pretty' }}>{MORNING.advice}</p>
                        <span style={{ fontSize: 13, color: 'var(--slate-600)' }}>Read more →</span>
                      </Folder>
                    </>
                  ) : (
                    <>
                      <Folder label="Tomorrow's Quest">
                        <p style={{ fontSize: 15, fontFamily: 'var(--font-display)', fontStyle: 'italic', color: 'var(--text-body)', lineHeight: 1.6, margin: 0 }}>&ldquo;{EVENING.quest}&rdquo;</p>
                      </Folder>
                      <Folder label="Tomorrow">
                        {timeline.length > 0
                          ? <p style={{ fontSize: 14, color: 'var(--text-body)', margin: 0, lineHeight: 1.6 }}>Next up: <strong style={{ fontWeight: 500, color: 'var(--text-strong)' }}>{timeline[0].title}</strong>{timeline[0].start_time ? `, ${timeline[0].start_time}` : ''}.</p>
                          : <p style={{ fontSize: 14, color: 'var(--text-faint)', margin: 0 }}>Nothing on the calendar yet.</p>}
                      </Folder>
                      <Folder label="Wind Down">
                        <div style={{ background: 'var(--sand-400)', borderRadius: 'var(--radius-lg)', padding: '18px 20px' }}>
                          <p style={{ fontSize: 15, fontStyle: 'italic', fontFamily: 'var(--font-display)', color: 'var(--char-700)', lineHeight: 1.65, margin: 0 }}>{EVENING.windDown}</p>
                        </div>
                      </Folder>
                      <div style={{ textAlign: 'center', padding: '12px 0 4px', color: 'var(--char-700)' }}><MoonGlyph size={20} opacity={0.38} /></div>
                    </>
                  )}
                </div>
              )}

              {/* ── CLUBS ── */}
              {tab === 'clubs' && (
                <div>
                  <h1 style={{ fontFamily: 'var(--font-display)', fontSize: 24, fontWeight: 500, color: 'var(--text-strong)', margin: '0 0 4px', letterSpacing: '-0.01em' }}>Clubs</h1>
                  <p style={{ fontSize: 14, color: 'var(--text-muted)', margin: '0 0 22px', lineHeight: 1.5 }}>Join one and its events show up in your timeline.</p>

                  {isAdmin && pending.length > 0 && (
                    <section style={{ marginBottom: 22 }}>
                      <p style={{ fontSize: 11, letterSpacing: '.18em', textTransform: 'uppercase', color: 'var(--slate-600)', fontWeight: 500, margin: '0 0 10px' }}>Pending review</p>
                      <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
                        {pending.map((c) => (
                          <div key={c.id} style={{ background: 'var(--surface-card)', border: '1px solid var(--border-hairline)', borderRadius: 'var(--radius-md)', padding: '13px 14px', boxShadow: 'var(--shadow-card)' }}>
                            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', gap: 10 }}>
                              <div style={{ minWidth: 0 }}>
                                <p style={{ fontSize: 14, fontWeight: 500, color: 'var(--text-strong)', margin: '0 0 2px' }}>{c.name}</p>
                                {c.schedule && <p style={{ fontFamily: 'var(--font-mono)', fontSize: 11, color: 'var(--text-faint)', margin: 0 }}>{c.schedule}</p>}
                              </div>
                              <div style={{ display: 'flex', gap: 8, flexShrink: 0 }}>
                                <button onClick={() => moderate(c.id, 'rejected')} className="press" style={{ padding: '6px 12px', borderRadius: 'var(--radius-pill)', border: '1px solid var(--border-strong)', background: 'transparent', color: 'var(--avoid-600)', fontSize: 12, cursor: 'pointer' }}>Reject</button>
                                <button onClick={() => moderate(c.id, 'approved')} className="press" style={{ padding: '6px 12px', borderRadius: 'var(--radius-pill)', border: 'none', background: 'var(--moss-700)', color: 'var(--linen-50)', fontSize: 12, cursor: 'pointer' }}>Approve</button>
                              </div>
                            </div>
                          </div>
                        ))}
                      </div>
                    </section>
                  )}

                  <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
                    {clubs.length === 0
                      ? <p style={{ fontSize: 13, color: 'var(--text-faint)', margin: 0 }}>No clubs yet — suggest the first one below.</p>
                      : clubs.map((club) => <ClubCard key={club.id} club={club} onToggle={toggleJoin} />)}
                  </div>

                  <SuggestClub onDone={load} />
                </div>
              )}

              {/* ── LETTER ── */}
              {tab === 'letter' && (
                <div>
                  <p style={{ fontSize: 11, letterSpacing: '.18em', textTransform: 'uppercase', color: 'var(--text-muted)', margin: '0 0 14px' }}>{SUNDAY_LETTER.eyebrow}</p>
                  <h1 style={{ fontFamily: 'var(--font-display)', fontSize: 22, fontWeight: 500, color: 'var(--text-strong)', margin: '0 0 6px', lineHeight: 1.3 }}>{SUNDAY_LETTER.headline}</h1>
                  <p style={{ fontFamily: 'var(--font-mono)', fontSize: 11, color: 'var(--text-faint)', margin: '0 0 24px', letterSpacing: '.04em' }}>{SUNDAY_LETTER.byline}</p>
                  {SUNDAY_LETTER.paragraphs.map((p, i) => (
                    <p key={i} style={{ fontSize: 15, color: 'var(--text-body)', lineHeight: 1.72, margin: i === 0 ? '0 0 18px' : 0, textWrap: 'pretty' }}>{p}</p>
                  ))}
                  <div style={{ marginTop: 24, paddingTop: 18, borderTop: '1px solid var(--border-hairline)' }}>
                    <p style={{ fontSize: 13, color: 'var(--text-faint)', margin: 0 }}>{SUNDAY_LETTER.signoff}</p>
                  </div>
                </div>
              )}

              {/* ── HELLO ── */}
              {tab === 'hello' && <Hello />}
            </>
          )}
        </div>

        {/* FAB: Today → Clubs */}
        {tab === 'today' && !loading && (
          <button onClick={() => { haptic('tap'); setTab('clubs') }} className="press" aria-label="Browse clubs" style={{ position: 'fixed', bottom: 84, right: 'max(20px, calc(50vw - 230px + 20px))', width: 48, height: 48, borderRadius: '50%', background: 'var(--slate-600)', border: 'none', cursor: 'pointer', display: 'flex', alignItems: 'center', justifyContent: 'center', boxShadow: '0 4px 18px rgba(107,123,132,0.5)', zIndex: 30 }}>
            <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="var(--linen-50)" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2" /><circle cx="9" cy="7" r="4" /><path d="M23 21v-2a4 4 0 0 0-3-3.87" /><path d="M16 3.13a4 4 0 0 1 0 7.75" /></svg>
          </button>
        )}

        {/* tab bar */}
        <nav style={{ position: 'sticky', bottom: 0, zIndex: 20, display: 'grid', gridTemplateColumns: 'repeat(4,1fr)', background: 'color-mix(in srgb, var(--linen-100) 96%, transparent)', backdropFilter: 'blur(12px)', borderTop: '1px solid var(--border-hairline)', paddingBottom: 'max(12px, env(safe-area-inset-bottom))' }}>
          {TABS.map((t) => {
            const active = tab === t.id
            return (
              <button key={t.id} onClick={() => { if (!active) haptic('select'); setTab(t.id) }} className="press" style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 4, padding: '10px 0 2px', background: 'none', border: 'none', cursor: 'pointer' }}>
                <TabIcon id={t.id} active={active} />
                <span style={{ fontSize: 10, color: active ? 'var(--slate-600)' : 'var(--text-faint)' }}>{t.label}</span>
              </button>
            )
          })}
        </nav>
      </div>
    </div>
  )
}

/* ── suggest-a-club form (members submit → owner reviews) ─────────────────── */

function SuggestClub({ onDone }: { onDone: () => void }) {
  const [open, setOpen] = useState(false)
  const [busy, setBusy] = useState(false)
  const [sent, setSent] = useState(false)
  const [name, setName] = useState('')
  const [host, setHost] = useState('')
  const [schedule, setSchedule] = useState('')
  const [vibe, setVibe] = useState('')

  const input: React.CSSProperties = { width: '100%', background: 'var(--surface-raised)', border: '1px solid var(--border-hairline)', borderRadius: 'var(--radius-sm)', padding: '11px 13px', fontSize: 14, color: 'var(--text-body)', outline: 'none' }

  const submit = async () => {
    if (!name.trim()) return
    setBusy(true)
    haptic('tap')
    try {
      await submitClub({ name: name.trim(), host: host.trim() || undefined, schedule: schedule.trim() || undefined, vibe: vibe.trim() || undefined })
      setName(''); setHost(''); setSchedule(''); setVibe('')
      setOpen(false); setSent(true)
      haptic('success')
      onDone()
    } catch {
      haptic('error')
    } finally {
      setBusy(false)
    }
  }

  if (sent) return <p style={{ fontSize: 13, color: 'var(--slate-600)', textAlign: 'center', margin: '18px 0 0' }}>Sent for review — we&rsquo;ll post it once it&rsquo;s approved.</p>

  return (
    <div style={{ marginTop: 16 }}>
      {!open ? (
        <button onClick={() => { haptic('tap'); setOpen(true) }} className="press" style={{ width: '100%', display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 8, padding: 13, borderRadius: 'var(--radius-md)', border: '1px dashed var(--slate-400)', background: 'transparent', color: 'var(--text-muted)', fontSize: 14, cursor: 'pointer' }}>
          <span style={{ fontSize: 16, lineHeight: 1 }}>＋</span> Suggest a club
        </button>
      ) : (
        <div style={{ background: 'var(--surface-card)', border: '1px solid var(--border-hairline)', borderRadius: 'var(--radius-md)', padding: 16, display: 'flex', flexDirection: 'column', gap: 10, boxShadow: 'var(--shadow-card)' }}>
          <input autoFocus value={name} onChange={(e) => setName(e.target.value)} placeholder="Club name" style={input} />
          <input value={host} onChange={(e) => setHost(e.target.value)} placeholder="Host (optional)" style={input} />
          <input value={schedule} onChange={(e) => setSchedule(e.target.value)} placeholder="Schedule — e.g. Every Saturday, 7am" style={input} />
          <input value={vibe} onChange={(e) => setVibe(e.target.value)} placeholder="One-line vibe (optional)" style={input} />
          <div style={{ display: 'flex', gap: 8 }}>
            <button onClick={() => setOpen(false)} className="press" style={{ flex: 1, padding: 12, borderRadius: 'var(--radius-sm)', border: '1px solid var(--border-hairline)', background: 'transparent', color: 'var(--text-muted)', fontSize: 14, cursor: 'pointer' }}>Cancel</button>
            <button onClick={submit} disabled={!name.trim() || busy} className="press" style={{ flex: 1, padding: 12, borderRadius: 'var(--radius-sm)', border: 'none', background: 'var(--char-700)', color: 'var(--linen-50)', fontSize: 14, cursor: 'pointer', opacity: !name.trim() || busy ? 0.5 : 1 }}>{busy ? 'Sending…' : 'Send'}</button>
          </div>
        </div>
      )}
    </div>
  )
}

/* ── daily hello ─────────────────────────────────────────────────────────── */

function Hello() {
  const [state, setState] = useState<'idle' | 'waved' | 'skipped'>('idle')

  if (state === 'skipped') return (
    <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', paddingTop: 72, gap: 14 }}>
      <svg viewBox="0 0 24 24" width="30" height="30" fill="none" stroke="var(--text-faint)" strokeWidth="1.5" strokeLinecap="round">
        <circle cx="12" cy="12" r="10" /><path d="M8 15s1.5 2 4 2 4-2 4-2" /><circle cx="9" cy="9" r="0.8" fill="var(--text-faint)" /><circle cx="15" cy="9" r="0.8" fill="var(--text-faint)" />
      </svg>
      <p style={{ fontSize: 14, color: 'var(--text-faint)', textAlign: 'center', lineHeight: 1.55, maxWidth: 200 }}>Come back tomorrow for someone new.</p>
    </div>
  )

  return (
    <div>
      <p style={{ fontSize: 11, letterSpacing: '.18em', textTransform: 'uppercase', color: 'var(--text-muted)', margin: '0 0 20px' }}>Daily Hello</p>
      <div style={{ background: 'var(--surface-card)', border: '1px solid var(--border-hairline)', borderRadius: 'var(--radius-xl)', padding: '28px 22px 24px', textAlign: 'center', marginBottom: 14, boxShadow: 'var(--shadow-card)' }}>
        <div style={{ width: 64, height: 64, borderRadius: '50%', background: 'var(--sand-400)', margin: '0 auto 16px', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
          <span style={{ fontFamily: 'var(--font-display)', fontSize: 26, color: 'var(--char-500)', fontWeight: 500 }}>{DAILY_HELLO.initial}</span>
        </div>
        <p style={{ fontSize: 18, fontFamily: 'var(--font-display)', fontWeight: 500, color: 'var(--text-strong)', margin: '0 0 6px' }}>{DAILY_HELLO.name}</p>
        <p style={{ fontSize: 13, color: 'var(--text-muted)', margin: '0 0 14px', lineHeight: 1.5 }}>{DAILY_HELLO.bio}</p>
        <p style={{ fontSize: 13, color: 'var(--text-faint)', margin: 0, fontStyle: 'italic', fontFamily: 'var(--font-display)' }}>&ldquo;{DAILY_HELLO.quote}&rdquo;</p>
      </div>
      {state === 'waved' ? (
        <div className="bounce-in" style={{ textAlign: 'center', padding: '14px 0' }}>
          <p style={{ fontSize: 15, color: 'var(--slate-600)', margin: 0, display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 6 }}><WaveIcon /> Wave sent to {DAILY_HELLO.name.split(' ')[0]}</p>
          <p style={{ fontSize: 13, color: 'var(--text-faint)', margin: '5px 0 0' }}>They&rsquo;ll get a notification.</p>
        </div>
      ) : (
        <div style={{ display: 'flex', gap: 10 }}>
          <button onClick={() => { haptic('success'); setState('waved') }} className="press" style={{ flex: 1, display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 7, padding: 13, borderRadius: 'var(--radius-sm)', background: 'var(--char-700)', color: 'var(--linen-50)', border: 'none', fontSize: 14, cursor: 'pointer' }}><WaveIcon /> Wave</button>
          <button onClick={() => { haptic('tap'); setState('skipped') }} className="press" style={{ flex: 1, padding: 13, borderRadius: 'var(--radius-sm)', background: 'none', color: 'var(--text-muted)', border: '1px solid var(--border-strong)', fontSize: 14, cursor: 'pointer' }}>Skip</button>
        </div>
      )}
    </div>
  )
}
