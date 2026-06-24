import Link from 'next/link'
import { createClient } from '@/lib/supabase/server'
import Reveal from './components/Reveal'

// ─── inline SVG icons ────────────────────────────────────────────────────────

function IconMapPin({ size = 16 }: { size?: number }) {
  return (
    <svg viewBox="0 0 24 24" width={size} height={size} fill="none" stroke="currentColor"
      strokeWidth={1.5} strokeLinecap="round" strokeLinejoin="round" aria-hidden>
      <path d="M12 21c4-4.5 7-7.6 7-11a7 7 0 1 0-14 0c0 3.4 3 6.5 7 11Z" />
      <circle cx="12" cy="10" r="2.4" opacity="0.6" />
    </svg>
  )
}

function IconCalendar({ size = 20 }: { size?: number }) {
  return (
    <svg viewBox="0 0 24 24" width={size} height={size} fill="none" stroke="currentColor"
      strokeWidth={1.5} strokeLinecap="round" strokeLinejoin="round" aria-hidden>
      <rect x="3" y="5" width="18" height="16" rx="2.5" />
      <path d="M3 10h18M8 3v4M16 3v4" />
    </svg>
  )
}

function IconSun({ size = 20 }: { size?: number }) {
  return (
    <svg viewBox="0 0 24 24" width={size} height={size} fill="none" stroke="currentColor"
      strokeWidth={1.5} strokeLinecap="round" strokeLinejoin="round" aria-hidden>
      <circle cx="12" cy="12" r="4" />
      <path d="M12 2v2M12 20v2M4.22 4.22l1.42 1.42M18.36 18.36l1.42 1.42M2 12h2M20 12h2M4.22 19.78l1.42-1.42M18.36 5.64l1.42-1.42" />
    </svg>
  )
}

function IconPeople({ size = 20 }: { size?: number }) {
  return (
    <svg viewBox="0 0 24 24" width={size} height={size} fill="none" stroke="currentColor"
      strokeWidth={1.5} strokeLinecap="round" strokeLinejoin="round" aria-hidden>
      <circle cx="9" cy="8" r="3.2" />
      <path d="M3.5 19c0-3 2.5-5 5.5-5s5.5 2 5.5 5" />
      <path d="M16 5.2a3.2 3.2 0 0 1 0 5.6M17 14.4c2.3.5 3.8 2.3 3.8 4.6" opacity="0.6" />
    </svg>
  )
}

function IconWalk({ size = 20 }: { size?: number }) {
  return (
    <svg viewBox="0 0 24 24" width={size} height={size} fill="none" stroke="currentColor"
      strokeWidth={1.5} strokeLinecap="round" strokeLinejoin="round" aria-hidden>
      <circle cx="13" cy="4.5" r="1.5" />
      <path d="M10 8.5l3-2 2.5 4-3.5 1.5-1 4.5M13 10.5l2.5 3M8.5 13l1.5-1.5" />
      <path d="M9 18l1-3.5M15.5 18l-1-3" />
    </svg>
  )
}

// ─── event data (realistic St. Joe events — no RSVP counts) ──────────────────

const EVENTS = [
  {
    weekday: 'Sat',
    date: '28',
    month: 'Jun',
    title: 'Saturday Run Club',
    where: 'Millstream Park · 8:00 AM',
  },
  {
    weekday: 'Sun',
    date: '29',
    month: 'Jun',
    title: 'Sunrise Yoga',
    where: 'Lake Wobegon Trail · 6:30 AM',
  },
  {
    weekday: 'Wed',
    date: '2',
    month: 'Jul',
    title: 'Farmers Market',
    where: 'Veterans Park · 9:00 AM',
  },
]

// ─── pillars ─────────────────────────────────────────────────────────────────

const PILLARS = [
  {
    icon: 'calendar',
    label: 'Get out',
    body: 'A daily, chronological list of what\'s happening in town — run clubs, markets, yoga in the park. RSVP in one tap.',
  },
  {
    icon: 'sun',
    label: 'Show up',
    body: 'A small daily quest — a gentle nudge to get outside and connect. Mark it done when you get back.',
  },
  {
    icon: 'people',
    label: 'Find your people',
    body: 'A full calendar of everything in St. Joe. Add your own event. Find the club that fits your pace.',
  },
]

// ─── page ─────────────────────────────────────────────────────────────────────

export default async function Home() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  const ctaHref = user ? '/community' : '/login'
  const ctaLabel = user ? 'Open the app' : 'Get the app'

  return (
    <div className="min-h-screen overflow-x-clip grain" style={{ background: 'var(--sand-300)' }}>

      {/* ── nav ─────────────────────────────────────────────────────────── */}
      <nav
        className="sticky top-0 z-50"
        style={{
          background: 'color-mix(in srgb, var(--sand-300) 85%, transparent)',
          backdropFilter: 'blur(12px)',
          borderBottom: '1px solid var(--border-onSand)',
        }}
      >
        <div className="max-w-5xl mx-auto px-5 md:px-8 h-[60px] flex items-center justify-between">
          {/* wordmark */}
          <div className="flex items-center gap-2 text-ink">
            <IconMapPin size={15} />
            <span className="font-display text-base tracking-wide" style={{ letterSpacing: '0.04em', fontWeight: 500 }}>
              Hygge
            </span>
            <span className="hidden sm:block text-ink-3 text-xs font-sans ml-1">· St. Joseph, MN</span>
          </div>
          {/* cta */}
          <Link
            href={ctaHref}
            className="press font-sans text-sm font-semibold px-5 py-2 rounded-[8px] transition-colors"
            style={{ background: 'var(--pine-700)', color: 'var(--linen-50)' }}
          >
            {ctaLabel}
          </Link>
        </div>
      </nav>

      {/* ── hero ─────────────────────────────────────────────────────────── */}
      <section className="max-w-5xl mx-auto px-5 md:px-8 pt-16 pb-10 md:pt-24 md:pb-16">
        <div className="grid grid-cols-1 lg:grid-cols-[1fr_auto] gap-12 lg:gap-16 items-start">

          {/* left: headline + cta */}
          <div className="rise">
            {/* eyebrow */}
            <p className="flex items-center gap-1.5 font-sans text-[11px] uppercase tracking-[0.2em] text-ink-2 mb-5">
              <IconMapPin size={12} />
              Saint Joseph, Minnesota
            </p>

            {/* headline — the big serif thesis */}
            <h1
              className="font-display leading-[1.0] mb-6"
              style={{
                fontSize: 'clamp(2.75rem, 8vw, 5rem)',
                color: 'var(--char-900)',
                fontWeight: 500,
                letterSpacing: '-0.02em',
              }}
            >
              Your town,<br />
              every day.
            </h1>

            <p className="font-sans text-lg leading-relaxed text-ink-2 max-w-[36ch] mb-8">
              Hygge is a quiet place to see what's happening in St. Joe, join a neighbor for a walk,
              and make the place you live feel a little smaller.
            </p>

            <div className="flex items-center gap-4 flex-wrap">
              <Link
                href={ctaHref}
                className="press font-sans font-semibold text-sm px-7 py-3.5 rounded-[9px] transition-colors"
                style={{ background: 'var(--pine-700)', color: 'var(--linen-50)' }}
              >
                {ctaLabel}
              </Link>
              {!user && (
                <Link
                  href="/login"
                  className="font-sans text-sm text-ink-2 hover:text-ink transition-colors"
                >
                  Sign in
                </Link>
              )}
            </div>

            {/* price — quiet, honest */}
            <p className="font-sans text-[13px] text-ink-3 mt-5">
              <span className="font-mono tabular-nums">$2</span>
              {' '}/ month — less than a cup of coffee at Covenant Cup.
            </p>
          </div>

          {/* right: event card stack — the bulletin board */}
          <div
            className="rise flex flex-col gap-3 w-full lg:w-[280px] shrink-0"
            style={{ animationDelay: '120ms' }}
            aria-label="Upcoming events in St. Joseph"
          >
            <p className="font-sans text-[11px] uppercase tracking-[0.18em] text-ink-3 mb-1">
              Coming up in St. Joe
            </p>
            {EVENTS.map((e) => (
              <div
                key={e.title}
                className="lift flex items-start gap-4 rounded-[14px] px-4 py-3.5"
                style={{
                  background: 'var(--linen-50)',
                  border: '1px solid var(--border-hairline)',
                  boxShadow: 'var(--shadow-card)',
                }}
              >
                {/* date block */}
                <div className="shrink-0 text-center w-10 pt-0.5">
                  <div className="font-sans text-[10px] uppercase tracking-wider text-ink-3">{e.weekday}</div>
                  <div
                    className="font-mono tabular-nums text-xl leading-tight"
                    style={{ color: 'var(--char-900)' }}
                  >
                    {e.date}
                  </div>
                  <div className="font-sans text-[10px] text-ink-3">{e.month}</div>
                </div>
                {/* divider */}
                <div className="self-stretch w-px mt-0.5" style={{ background: 'var(--border-hairline)' }} />
                {/* text */}
                <div className="min-w-0">
                  <p className="font-sans text-[14px] text-ink leading-snug">{e.title}</p>
                  <p className="font-sans text-[12px] text-ink-2 mt-0.5">{e.where}</p>
                </div>
              </div>
            ))}
            <Link
              href={ctaHref}
              className="font-sans text-[12px] text-ink-2 hover:text-ink transition-colors text-right mt-1 pr-1"
            >
              See all events →
            </Link>
          </div>
        </div>
      </section>

      {/* ── divider ──────────────────────────────────────────────────────── */}
      <div className="max-w-5xl mx-auto px-5 md:px-8">
        <hr style={{ borderColor: 'var(--border-onSand)' }} />
      </div>

      {/* ── three pillars ─────────────────────────────────────────────────── */}
      <section className="max-w-5xl mx-auto px-5 md:px-8 py-16 md:py-24">
        <Reveal>
          <p className="font-sans text-[11px] uppercase tracking-[0.2em] text-ink-3 mb-10">
            What Hygge does
          </p>
        </Reveal>
        <div className="grid grid-cols-1 md:grid-cols-3 gap-0">
          {PILLARS.map((p, i) => (
            <Reveal key={p.label}>
              <div
                className="py-8 md:px-8"
                style={{
                  borderTop: '1px solid var(--border-onSand)',
                  borderLeft: i > 0 ? '1px solid var(--border-onSand)' : undefined,
                }}
              >
                {/* icon */}
                <span className="block mb-4 text-ink-2">
                  {p.icon === 'calendar' && <IconCalendar size={22} />}
                  {p.icon === 'sun' && <IconSun size={22} />}
                  {p.icon === 'people' && <IconPeople size={22} />}
                </span>
                <h3
                  className="font-display text-2xl mb-3"
                  style={{ color: 'var(--char-900)', fontWeight: 500, letterSpacing: '-0.01em' }}
                >
                  {p.label}
                </h3>
                <p className="font-sans text-sm leading-relaxed text-ink-2 max-w-[28ch]">
                  {p.body}
                </p>
              </div>
            </Reveal>
          ))}
        </div>
      </section>

      {/* ── divider ──────────────────────────────────────────────────────── */}
      <div className="max-w-5xl mx-auto px-5 md:px-8">
        <hr style={{ borderColor: 'var(--border-onSand)' }} />
      </div>

      {/* ── daily quest ───────────────────────────────────────────────────── */}
      <section className="max-w-5xl mx-auto px-5 md:px-8 py-16 md:py-24">
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-12 items-center">
          <Reveal>
            <p className="font-sans text-[11px] uppercase tracking-[0.2em] text-ink-3 mb-5">
              The daily quest
            </p>
            <h2
              className="font-display text-3xl md:text-4xl leading-snug mb-5"
              style={{ color: 'var(--char-900)', fontWeight: 500, letterSpacing: '-0.015em' }}
            >
              A small reason<br />to step outside.
            </h2>
            <p className="font-sans text-sm leading-relaxed text-ink-2 max-w-[38ch]">
              Each morning, Hygge offers a single, quiet prompt — a short walk, a wave to someone
              at the trail, a stop at the market. You mark it done when you're back. That's the whole thing.
            </p>
          </Reveal>

          {/* quest card — styled like a note, not a game widget */}
          <Reveal>
            <div
              className="lift rounded-[18px] p-7 max-w-[340px] mx-auto lg:mx-0"
              style={{
                background: 'var(--linen-50)',
                border: '1px solid var(--border-hairline)',
                boxShadow: 'var(--shadow-card)',
              }}
            >
              <div className="flex items-center justify-between mb-6">
                <span className="font-sans text-[11px] uppercase tracking-[0.18em] text-ink-3">
                  Today's quest
                </span>
                <span className="font-sans text-[11px] text-ink-3">Tuesday</span>
              </div>

              {/* the quest itself — italic display, the signature visual risk */}
              <p
                className="font-display text-2xl leading-snug mb-8"
                style={{
                  color: 'var(--char-900)',
                  fontWeight: 400,
                  fontStyle: 'italic',
                  letterSpacing: '-0.01em',
                }}
              >
                Walk to the trailhead<br />before 9 in the morning.
              </p>

              {/* done button — quiet, honest */}
              <button
                type="button"
                disabled
                className="font-sans text-sm font-semibold w-full py-3 rounded-[9px] flex items-center justify-center gap-2"
                style={{ background: 'var(--linen-100)', color: 'var(--char-500)', cursor: 'default' }}
                aria-label="Mark quest done (demo)"
              >
                <span
                  className="inline-flex items-center justify-center w-4 h-4 rounded-full"
                  style={{ border: '1.5px solid var(--sand-400)' }}
                  aria-hidden
                />
                Mark as done
              </button>
            </div>
          </Reveal>
        </div>
      </section>

      {/* ── divider ──────────────────────────────────────────────────────── */}
      <div className="max-w-5xl mx-auto px-5 md:px-8">
        <hr style={{ borderColor: 'var(--border-onSand)' }} />
      </div>

      {/* ── founder voice ─────────────────────────────────────────────────── */}
      <section style={{ background: 'var(--char-900)' }}>
        <Reveal className="max-w-5xl mx-auto px-5 md:px-8 py-16 md:py-24">
          <div className="max-w-[46ch]">
            {/* wordmark on dark */}
            <div className="flex items-center gap-2 mb-8" style={{ color: 'var(--linen-50)', opacity: 0.6 }}>
              <IconMapPin size={14} />
              <span className="font-display text-sm tracking-wide" style={{ letterSpacing: '0.04em', fontWeight: 500 }}>
                Hygge
              </span>
            </div>

            <blockquote
              className="font-display leading-snug mb-7"
              style={{
                fontSize: 'clamp(1.5rem, 3.5vw, 2.25rem)',
                color: 'var(--linen-50)',
                fontWeight: 400,
                fontStyle: 'italic',
                letterSpacing: '-0.01em',
              }}
            >
              "I built Hygge because none of the apps I tried felt like they were made
              for anyone on my actual street."
            </blockquote>

            <p
              className="font-sans text-sm"
              style={{ color: 'rgba(251,250,245,0.5)' }}
            >
              — Jesse, Saint Joseph, Minnesota
            </p>
          </div>
        </Reveal>
      </section>

      {/* ── final cta ─────────────────────────────────────────────────────── */}
      <section>
        <Reveal className="max-w-5xl mx-auto px-5 md:px-8 py-16 md:py-24 text-center flex flex-col items-center">
          <p className="font-sans text-[11px] uppercase tracking-[0.2em] text-ink-3 mb-6">
            Join St. Joe
          </p>
          <h2
            className="font-display text-3xl md:text-4xl leading-tight mb-4 max-w-[20ch]"
            style={{ color: 'var(--char-900)', fontWeight: 500, letterSpacing: '-0.015em' }}
          >
            See what's happening<br />in your town.
          </h2>
          <p className="font-sans text-sm text-ink-2 mb-8 max-w-[32ch]">
            Hygge is built for the people on your street — no global leaderboard, no feed to scroll.
            Just your town.
          </p>
          <Link
            href={ctaHref}
            className="press font-sans font-semibold text-base px-9 py-4 rounded-[9px] transition-colors"
            style={{ background: 'var(--pine-700)', color: 'var(--linen-50)' }}
          >
            {ctaLabel}
          </Link>
          <p className="font-sans text-[12px] text-ink-3 mt-4">
            <span className="font-mono tabular-nums">$2</span> / month. Cancel any time.
          </p>
        </Reveal>
      </section>

      {/* ── footer ───────────────────────────────────────────────────────── */}
      <footer style={{ borderTop: '1px solid var(--border-onSand)' }}>
        <div className="max-w-5xl mx-auto px-5 md:px-8 py-8 flex flex-col sm:flex-row items-center justify-between gap-4">
          <div className="flex items-center gap-2 text-ink">
            <IconMapPin size={14} />
            <span className="font-display text-sm tracking-wide" style={{ letterSpacing: '0.04em', fontWeight: 500 }}>
              Hygge
            </span>
          </div>
          <p className="font-mono text-[11px] text-ink-3 tabular-nums">© 2026 Hygge · Saint Joseph, MN</p>
        </div>
      </footer>

    </div>
  )
}
