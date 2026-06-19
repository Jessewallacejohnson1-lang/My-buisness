import Link from 'next/link'
import { createClient } from '@/lib/supabase/server'
import ScoreRing, { scoreTone } from './components/ScoreRing'
import Reveal from './components/Reveal'
import { IconBarcode, IconCheck, IconFlame, IconLeaf } from './components/Icons'

const TICKER: [string, number][] = [
  ['Blueberries', 97],
  ['Wild salmon', 94],
  ['Lentils', 95],
  ['Greek yogurt', 92],
  ['Steel-cut oats', 91],
  ['Almonds', 89],
  ['Olive oil', 88],
  ['Sourdough', 72],
  ['Dark chocolate', 64],
  ['Granola bar', 41],
  ['Instant noodles', 22],
  ['Diet cola', 14],
]

function TickerChip({ name, score }: { name: string; score: number }) {
  const tone = scoreTone(score)
  return (
    <span className="flex items-center gap-2.5 bg-paper border border-black/[0.10] rounded-full pl-4 pr-3 py-2 shrink-0">
      <span className="text-sm text-ink whitespace-nowrap">{name}</span>
      <span
        className={`font-mono text-xs tabular-nums px-2 py-0.5 rounded-full ${tone.text}`}
        style={{ background: 'color-mix(in srgb, currentColor 12%, transparent)' }}
      >
        {score}
      </span>
    </span>
  )
}

function HyggeFlame({ size = 20 }: { size?: number }) {
  return (
    <svg viewBox="0 0 24 24" width={size} height={size} fill="none" stroke="currentColor"
      strokeWidth={1.5} strokeLinecap="round" strokeLinejoin="round" aria-hidden>
      <path d="M12 21c-4 0-6.5-2.6-6.5-6 0-2.5 1.4-4.4 2.7-6C9.4 7.6 10.5 6 10.5 3.5c3 1.5 4 4.5 3.5 6.5 1-.5 1.8-1.3 2-2.5 1.6 1.7 2.5 3.9 2.5 6 0 3.4-2.5 7.5-6.5 7.5Z" />
    </svg>
  )
}

/* Static tri-ring for the hero preview — CSS animates the fill on load. */
function PreviewRings() {
  const rings = [
    { r: 84, pct: 0.71, color: 'var(--color-honey-600)' },
    { r: 67, pct: 0.64, color: 'var(--color-moss-700)' },
    { r: 50, pct: 0.88, color: 'var(--color-ink)' },
  ]
  return (
    <div className="relative w-[180px] h-[180px] shrink-0">
      <svg viewBox="0 0 200 200" width={180} height={180} className="-rotate-90">
        {rings.map((ring, i) => {
          const circ = 2 * Math.PI * ring.r
          const target = circ * (1 - ring.pct)
          return (
            <g key={i}>
              <circle cx="100" cy="100" r={ring.r} fill="none" stroke="rgba(60,60,60,0.08)" strokeWidth="10" />
              <circle
                cx="100" cy="100" r={ring.r} fill="none"
                stroke={ring.color} strokeWidth="10" strokeLinecap="round"
                strokeDasharray={circ} className="ring-fill"
                style={{ '--circ': circ, '--target': target, animationDelay: `${0.3 + i * 0.15}s` } as React.CSSProperties}
              />
            </g>
          )
        })}
      </svg>
      <div className="absolute inset-0 flex flex-col items-center justify-center">
        <span className="font-mono text-3xl text-ink tabular-nums">612</span>
        <span className="text-[10px] uppercase tracking-[0.18em] text-ink-2 mt-0.5">kcal left</span>
      </div>
    </div>
  )
}

const PILLARS = [
  { icon: 'bowl', title: 'Diet', body: 'A clean food score from 1 to 100, nutrition tracking, and a barcode scanner that logs in seconds.' },
  { icon: 'dumbbell', title: 'Fitness', body: 'Guided sessions and progress rings. Strength, HIIT, yoga, cardio — or log your own.' },
  { icon: 'book', title: 'Health Info', body: 'Daily, actionable tips. Small, honest changes that add up — never a wall of dashboards.' },
  { icon: 'users', title: 'Community', body: 'A hyper-local events board. Run clubs, meetups, RSVPs — the people on your actual street.' },
]

const PILLAR_ICONS: Record<string, React.ReactNode> = {
  bowl: (
    <svg viewBox="0 0 24 24" width={26} height={26} fill="none" stroke="currentColor" strokeWidth={1.5} strokeLinecap="round" strokeLinejoin="round" aria-hidden>
      <path d="M4 12h16a8 8 0 0 1-16 0Z" /><path d="M9 12c0-4 1.5-7 5.5-8.5" opacity="0.55" />
    </svg>
  ),
  dumbbell: (
    <svg viewBox="0 0 24 24" width={26} height={26} fill="none" stroke="currentColor" strokeWidth={1.5} strokeLinecap="round" strokeLinejoin="round" aria-hidden>
      <path d="M6.5 6.5v11M17.5 6.5v11M3.5 9v6M20.5 9v6M6.5 12h11" />
    </svg>
  ),
  book: (
    <svg viewBox="0 0 24 24" width={26} height={26} fill="none" stroke="currentColor" strokeWidth={1.5} strokeLinecap="round" strokeLinejoin="round" aria-hidden>
      <path d="M5 5.5A2 2 0 0 1 7 4h11v15H7a2 2 0 0 0-2 2V5.5Z" /><path d="M5 19a2 2 0 0 1 2-2h11" opacity="0.55" />
    </svg>
  ),
  users: (
    <svg viewBox="0 0 24 24" width={26} height={26} fill="none" stroke="currentColor" strokeWidth={1.5} strokeLinecap="round" strokeLinejoin="round" aria-hidden>
      <circle cx="9" cy="8" r="3.2" /><path d="M3.5 19c0-3 2.5-5 5.5-5s5.5 2 5.5 5" />
      <path d="M16 5.2a3.2 3.2 0 0 1 0 5.6M17 14.4c2.3.5 3.8 2.3 3.8 4.6" opacity="0.6" />
    </svg>
  ),
}

const EARNS = [
  { label: 'Whole, unprocessed food', delta: '+20' },
  { label: 'Nutri-Score A', delta: '+15' },
  { label: 'Zero additives', delta: '+10' },
  { label: 'Certified organic', delta: '+8' },
]

const LOSES = [
  { label: 'Ultra-processed (NOVA 4)', delta: '−25' },
  { label: 'Artificial sweeteners', delta: '−15' },
  { label: 'Artificial dyes', delta: '−10' },
  { label: 'High-fructose corn syrup', delta: '−10' },
]

const EVENTS = [
  { day: 'SAT', date: '21', title: 'Saturday Run Club', where: 'Millstream Park · 8:00 AM', rsvps: 14 },
  { day: 'SUN', date: '22', title: 'Sunrise Yoga', where: 'Lake Wobegon dock · 6:30 AM', rsvps: 9 },
  { day: 'SUN', date: '22', title: 'Meal-prep Sunday', where: "Jesse's kitchen · 4:00 PM", rsvps: 6 },
]

const TRUST = [
  {
    title: 'Built on open data',
    desc: "Every score starts from Open Food Facts — the world's open, community-run food database. 700,000+ real products, not numbers we made up.",
  },
  {
    title: 'Transparent scoring',
    desc: 'Tap any food to see exactly why it scored what it did — the points it earned and the points it lost. No black box.',
  },
  {
    title: 'Free, and yours',
    desc: "No card to start. Your log is private to your account, and you can delete anything you've logged, anytime.",
  },
]

export default async function Home() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  const appHref = user ? '/dashboard' : '/login'

  return (
    <div className="min-h-screen overflow-x-clip grain" style={{ background: 'var(--sand-300)' }}>

      {/* nav */}
      <nav
        className="sticky top-0 z-50 border-b"
        style={{
          background: 'color-mix(in srgb, var(--sand-300) 82%, transparent)',
          backdropFilter: 'blur(10px)',
          borderColor: 'var(--border-onSand)',
        }}
      >
        <div className="max-w-6xl mx-auto px-5 md:px-8 h-[68px] flex items-center justify-between">
          <div className="flex items-center gap-2.5 text-ink">
            <HyggeFlame size={20} />
            <span className="font-display tracking-[0.28em] uppercase text-base font-medium">HYGGE</span>
          </div>
          <div className="flex items-center gap-6">
            <a href="#pillars" className="hidden md:block text-sm text-ink-2 hover:text-ink transition-colors">What it is</a>
            <a href="#score" className="hidden md:block text-sm text-ink-2 hover:text-ink transition-colors">The score</a>
            <a href="#community" className="hidden md:block text-sm text-ink-2 hover:text-ink transition-colors">Community</a>
            {user ? (
              <Link href="/dashboard"
                className="font-semibold px-5 py-2.5 rounded-[10px] text-sm transition-colors"
                style={{ background: 'var(--char-700)', color: 'var(--linen-50)' }}
              >
                Open app
              </Link>
            ) : (
              <>
                <Link href="/login" className="hidden sm:block text-sm text-ink-2 hover:text-ink transition-colors">Sign in</Link>
                <Link href="/login"
                  className="font-semibold px-5 py-2.5 rounded-[10px] text-sm transition-colors"
                  style={{ background: 'var(--char-700)', color: 'var(--linen-50)' }}
                >
                  Join the waitlist
                </Link>
              </>
            )}
          </div>
        </div>
      </nav>

      {/* hero */}
      <section>
        <div className="max-w-6xl mx-auto px-5 md:px-8 pt-16 md:pt-20 pb-20 grid grid-cols-1 lg:grid-cols-2 gap-14 items-center">
          <div className="rise">
            <span className="inline-flex items-center gap-1.5 text-[12px] uppercase tracking-[0.16em] mb-6"
              style={{ color: 'var(--pine-700)' }}>
              <svg viewBox="0 0 24 24" width={14} height={14} fill="none" stroke="currentColor" strokeWidth={1.5} strokeLinecap="round" strokeLinejoin="round" aria-hidden>
                <path d="M12 21c4-4.5 7-7.6 7-11a7 7 0 1 0-14 0c0 3.4 3 6.5 7 11Z" />
                <circle cx="12" cy="10" r="2.4" opacity="0.6" />
              </svg>
              Saint Joseph, MN
            </span>
            <h1 className="font-display text-5xl md:text-6xl leading-[1.04] mb-6" style={{ color: 'var(--char-900)', letterSpacing: '-0.015em', fontWeight: 500 }}>
              Eat clean.<br />
              Train hard.<br />
              <em style={{ fontStyle: 'italic', color: 'var(--pine-700)' }}>Watch it compound.</em>
            </h1>
            <p className="font-display text-xl leading-relaxed mb-9 max-w-md" style={{ color: 'var(--char-500)', fontWeight: 300 }}>
              The health app built for your town — not another global dashboard you open twice and forget.
            </p>
            <div className="flex gap-3 flex-wrap">
              <Link href={appHref}
                className="press font-semibold px-7 py-3.5 rounded-[10px] text-sm transition-colors"
                style={{ background: 'var(--char-700)', color: 'var(--linen-50)' }}
              >
                {user ? 'Open the app' : 'Join the waitlist'}
              </Link>
              <a href="#score"
                className="press px-7 py-3.5 rounded-[10px] text-sm transition-colors"
                style={{ background: 'transparent', border: '1px solid var(--border-strong)', color: 'var(--char-700)' }}
              >
                How foods score
              </a>
            </div>
            <p className="text-[13px] mt-4" style={{ color: 'var(--char-400)' }}>
              Free at launch · No card · Join 47 others from St. Joe.
            </p>
          </div>

          {/* phone preview */}
          <div className="rise relative max-w-[300px] w-full mx-auto lg:ml-auto" style={{ animationDelay: '150ms' }}>
            <div className="rounded-[2.8rem] overflow-hidden"
              style={{ border: '9px solid var(--char-900)', background: 'var(--linen-50)', boxShadow: 'var(--shadow-lift)' }}>
              <div className="h-8 flex items-center justify-center">
                <span className="w-16 h-1.5 rounded-full" style={{ background: 'var(--sand-400)' }} />
              </div>
              <div className="px-5 pb-7">
                <div className="flex items-center justify-between mb-4">
                  <span className="text-[11px] uppercase tracking-[0.18em] text-ink-2">Today</span>
                  <span className="flex items-center gap-1.5 font-mono text-[11px] tabular-nums flicker" style={{ color: 'var(--moderate-600)' }}>
                    <IconFlame className="w-3.5 h-3.5" /> 12 days
                  </span>
                </div>
                <div className="flex justify-center py-2">
                  <PreviewRings />
                </div>
                <div className="space-y-1.5 mt-4 mb-4">
                  {[
                    { label: 'Calories', value: '1,488 / 2,100', color: 'var(--moderate-600)' },
                    { label: 'Protein', value: '90g / 140g', color: 'var(--clean-600)' },
                    { label: 'Clean score', value: '88 / 100', color: 'var(--char-700)' },
                  ].map((row) => (
                    <div key={row.label} className="flex items-center justify-between">
                      <span className="flex items-center gap-2 text-xs text-ink-2">
                        <span className="w-1.5 h-1.5 rounded-full" style={{ background: row.color }} />
                        {row.label}
                      </span>
                      <span className="font-mono text-xs text-ink tabular-nums">{row.value}</span>
                    </div>
                  ))}
                </div>
                <div className="pt-3 space-y-2.5" style={{ borderTop: '1px solid var(--border-hairline)' }}>
                  <div className="flex items-center gap-3">
                    <ScoreRing score={92} size={34} />
                    <div className="flex-1 min-w-0">
                      <p className="text-xs text-ink truncate">Greek yogurt, plain</p>
                      <p className="font-mono text-[10px] text-ink-3 tabular-nums">146 kcal · 20P</p>
                    </div>
                    <span className="text-[10px] text-moss-700">Clean</span>
                  </div>
                  <div className="flex items-center gap-3">
                    <span className="w-[34px] h-[34px] rounded-full flex items-center justify-center shrink-0"
                      style={{ background: 'var(--pine-700)', color: 'var(--linen-50)' }}>
                      <IconCheck className="w-4 h-4" strokeWidth={2.5} />
                    </span>
                    <div className="flex-1 min-w-0">
                      <p className="text-xs text-ink truncate">Upper Body Strength</p>
                      <p className="font-mono text-[10px] text-ink-3 tabular-nums">4 exercises · 45 min</p>
                    </div>
                    <span className="text-[10px] text-ink-2">Done</span>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>

        {/* food ticker */}
        <div className="marquee relative overflow-hidden py-5" style={{ borderTop: '1px solid var(--border-onSand)' }}>
          <div className="marquee-track flex gap-3 w-max pr-3">
            {TICKER.map(([name, score]) => <TickerChip key={name} name={name} score={score} />)}
            <span aria-hidden className="flex gap-3">
              {TICKER.map(([name, score]) => <TickerChip key={`dup-${name}`} name={name} score={score} />)}
            </span>
          </div>
          <div className="absolute inset-y-0 left-0 w-20 pointer-events-none"
            style={{ background: 'linear-gradient(to right, var(--sand-300), transparent)' }} />
          <div className="absolute inset-y-0 right-0 w-20 pointer-events-none"
            style={{ background: 'linear-gradient(to left, var(--sand-300), transparent)' }} />
        </div>

        {/* data strip */}
        <div style={{ borderTop: '1px solid var(--border-onSand)', borderBottom: '1px solid var(--border-onSand)' }}>
          <div className="max-w-6xl mx-auto px-5 md:px-8 grid grid-cols-1 sm:grid-cols-3">
            {[
              ['700,000+', 'foods in the database'],
              ['1–100', 'clean score on every log'],
              ['~2 sec', 'from barcode to logged'],
            ].map(([num, label]) => (
              <div key={label} className="py-6 sm:px-8 first:pl-0 flex items-baseline gap-3"
                style={{ borderRight: '1px solid var(--border-onSand)' }}>
                <span className="font-mono text-xl text-ink tabular-nums">{num}</span>
                <span className="text-sm text-ink-2">{label}</span>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* four pillars */}
      <section id="pillars" style={{ borderTop: '1px solid var(--border-onSand)' }}>
        <div className="max-w-6xl mx-auto px-5 md:px-8 py-20 md:py-28">
          <Reveal>
            <p className="text-[12px] uppercase tracking-[0.18em] mb-4" style={{ color: 'var(--pine-700)' }}>What it is</p>
            <h2 className="font-display text-4xl md:text-5xl mb-14 max-w-xs" style={{ color: 'var(--char-900)', fontWeight: 500, letterSpacing: '-0.01em' }}>
              Four quiet pillars. One steady routine.
            </h2>
          </Reveal>
          <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-5">
            {PILLARS.map((p, i) => (
              <Reveal key={p.title}>
                <div className="lift rounded-[18px] p-6 h-full"
                  style={{ background: 'var(--linen-50)', border: '1px solid var(--border-hairline)', boxShadow: 'var(--shadow-card)' }}>
                  <span style={{ color: 'var(--pine-700)' }}>{PILLAR_ICONS[p.icon]}</span>
                  <h3 className="font-display text-xl mt-4 mb-2" style={{ color: 'var(--char-900)', fontWeight: 500 }}>{p.title}</h3>
                  <p className="text-sm leading-relaxed text-ink-2">{p.body}</p>
                </div>
              </Reveal>
            ))}
          </div>
        </div>
      </section>

      {/* clean score */}
      <section id="score" style={{ borderTop: '1px solid var(--border-onSand)' }}>
        <div className="max-w-6xl mx-auto px-5 md:px-8 py-20 md:py-28 grid grid-cols-1 lg:grid-cols-2 gap-14 items-center">
          <Reveal className="order-2 lg:order-1">
            <div className="lift rounded-[24px] p-6 max-w-sm mx-auto lg:mx-0"
              style={{ background: 'var(--linen-50)', border: '1px solid var(--border-hairline)', boxShadow: 'var(--shadow-card)' }}>
              <p className="text-[11px] uppercase tracking-[0.18em] text-ink-2 mb-5">Clean score</p>
              <div className="flex items-center gap-5 mb-6">
                <ScoreRing score={92} size={72} />
                <div>
                  <p className="text-ink">Greek yogurt, plain</p>
                  <p className="text-[11px] uppercase tracking-[0.18em] mt-1" style={{ color: 'var(--clean-600)' }}>Clean</p>
                  <div className="flex gap-1.5 mt-2.5 flex-wrap">
                    {['Whole food', 'High protein'].map((b) => (
                      <span key={b} className="inline-flex items-center gap-1 text-[10px] px-2 py-0.5 rounded-full"
                        style={{ color: 'var(--clean-600)', background: 'color-mix(in srgb, var(--clean-600) 12%, transparent)', border: '1px solid color-mix(in srgb, var(--clean-600) 20%, transparent)' }}>
                        <IconLeaf className="w-2.5 h-2.5" />
                        {b}
                      </span>
                    ))}
                  </div>
                </div>
              </div>
              <div className="flex items-center gap-5 pt-5" style={{ borderTop: '1px solid var(--border-hairline)' }}>
                <ScoreRing score={14} size={72} />
                <div>
                  <p className="text-ink">Diet cola</p>
                  <p className="text-[11px] uppercase tracking-[0.18em] mt-1" style={{ color: 'var(--avoid-600)' }}>Avoid</p>
                  <p className="text-[11px] text-ink-2 mt-2 leading-relaxed">Ultra-processed · artificial sweeteners</p>
                </div>
              </div>
            </div>
          </Reveal>

          <Reveal className="order-1 lg:order-2">
            <p className="text-[12px] uppercase tracking-[0.18em] mb-5" style={{ color: 'var(--pine-700)' }}>The clean score</p>
            <h2 className="font-display text-4xl md:text-5xl leading-tight mb-6" style={{ color: 'var(--char-900)', fontWeight: 500 }}>
              We read the label<br />so you don't have to.
            </h2>
            <p className="text-ink-2 leading-relaxed mb-10 max-w-md">
              Calories never told the whole story. Hygge scores every food on how processed it really is — the same rules, applied to everything you log.
            </p>
            <div className="grid grid-cols-1 sm:grid-cols-2 gap-x-10 gap-y-1">
              <div>
                <p className="text-[11px] uppercase tracking-[0.18em] text-ink-2 mb-3">Earns points</p>
                {EARNS.map((f) => (
                  <div key={f.label} className="flex items-center justify-between gap-4 py-2.5"
                    style={{ borderTop: '1px solid var(--border-hairline)' }}>
                    <span className="text-sm text-ink">{f.label}</span>
                    <span className="font-mono text-sm tabular-nums" style={{ color: 'var(--clean-600)' }}>{f.delta}</span>
                  </div>
                ))}
              </div>
              <div className="mt-6 sm:mt-0">
                <p className="text-[11px] uppercase tracking-[0.18em] text-ink-2 mb-3">Loses points</p>
                {LOSES.map((f) => (
                  <div key={f.label} className="flex items-center justify-between gap-4 py-2.5"
                    style={{ borderTop: '1px solid var(--border-hairline)' }}>
                    <span className="text-sm text-ink">{f.label}</span>
                    <span className="font-mono text-sm tabular-nums" style={{ color: 'var(--avoid-600)' }}>{f.delta}</span>
                  </div>
                ))}
              </div>
            </div>
          </Reveal>
        </div>
      </section>

      {/* scanner */}
      <section id="scanner" style={{ borderTop: '1px solid var(--border-onSand)', background: 'color-mix(in srgb, var(--linen-50) 40%, var(--sand-300))' }}>
        <div className="max-w-6xl mx-auto px-5 md:px-8 py-20 md:py-28 grid grid-cols-1 lg:grid-cols-2 gap-14 items-center">
          <Reveal>
            <p className="text-[12px] uppercase tracking-[0.18em] mb-5" style={{ color: 'var(--pine-700)' }}>Instant logging</p>
            <h2 className="font-display text-4xl md:text-5xl leading-tight mb-6" style={{ color: 'var(--char-900)', fontWeight: 500 }}>
              Scan it. Logged.
            </h2>
            <p className="text-ink-2 leading-relaxed mb-8 max-w-md">
              Point your camera at any barcode and the full breakdown lands in your log — calories, macros, and the clean score. No typing, no searching.
            </p>
            <Link href={user ? '/scan' : '/login'}
              className="press inline-flex items-center gap-2.5 font-semibold px-7 py-3.5 rounded-[10px] text-sm transition-colors"
              style={{ background: 'var(--char-700)', color: 'var(--linen-50)' }}>
              <IconBarcode className="w-4 h-4" />
              Try the scanner
            </Link>
          </Reveal>

          <Reveal className="relative max-w-sm w-full mx-auto lg:ml-auto">
            <div className="lift rounded-[24px] p-5"
              style={{ background: 'var(--linen-50)', border: '1px solid var(--border-hairline)', boxShadow: 'var(--shadow-card)' }}>
              <div className="flex items-center justify-between mb-4">
                <span className="text-[11px] uppercase tracking-[0.18em] text-ink-2">Scan</span>
                <span className="w-1.5 h-1.5 rounded-full animate-pulse" style={{ background: 'var(--pine-700)' }} />
              </div>
              <div className="relative rounded-[18px] aspect-video overflow-hidden"
                style={{ background: 'var(--linen-100)', border: '1px solid var(--border-hairline)' }}>
                <div className="absolute inset-5">
                  {[['top', 'left'], ['top', 'right'], ['bottom', 'left'], ['bottom', 'right']].map(([v, h]) => (
                    <span key={v + h} className="absolute w-6 h-6"
                      style={{
                        [v]: 0, [h]: 0,
                        [`border${v[0].toUpperCase() + v.slice(1)}`]: `2px solid var(--pine-700)`,
                        [`border${h[0].toUpperCase() + h.slice(1)}`]: `2px solid var(--pine-700)`,
                        borderRadius: 6,
                      } as React.CSSProperties} />
                  ))}
                  <span className="absolute left-2 right-2 h-px"
                    style={{ background: 'var(--pine-700)', opacity: 0.8, animation: 'beam 2.4s ease-in-out infinite' }} />
                </div>
                <IconBarcode className="absolute inset-0 m-auto w-12 h-12 text-ink-3" />
              </div>
              <div className="mt-4 rounded-[14px] p-3.5 flex items-center gap-3"
                style={{ background: 'var(--linen-100)', border: '1px solid var(--border-hairline)' }}>
                <ScoreRing score={78} size={38} />
                <div className="flex-1 min-w-0">
                  <p className="text-xs text-ink truncate">Dark chocolate almonds</p>
                  <p className="font-mono text-[10px] text-ink-3 tabular-nums">200 kcal · 6P · 13C</p>
                </div>
                <span className="text-[11px] font-semibold px-3 py-1.5 rounded-lg shrink-0"
                  style={{ background: 'var(--pine-700)', color: 'var(--linen-50)' }}>
                  Add
                </span>
              </div>
            </div>
          </Reveal>
        </div>
      </section>

      {/* community */}
      <section id="community" style={{ borderTop: '1px solid var(--border-onSand)' }}>
        <div className="max-w-6xl mx-auto px-5 md:px-8 py-20 md:py-28 grid grid-cols-1 lg:grid-cols-2 gap-14 items-center">
          <Reveal>
            <p className="text-[12px] uppercase tracking-[0.18em] mb-4" style={{ color: 'var(--pine-700)' }}>The difference</p>
            <h2 className="font-display text-4xl md:text-5xl leading-tight mb-5" style={{ color: 'var(--char-900)', fontWeight: 500, letterSpacing: '-0.01em' }}>
              Not for everyone.<br />Built for Saint Joseph.
            </h2>
            <p className="text-ink-2 leading-relaxed max-w-prose">
              Noom, MyFitnessPal and Whoop are built for everyone, everywhere. Hygge is built for the people on your street — a board of real meetups, run clubs and RSVPs in your town.
            </p>
          </Reveal>
          <Reveal className="flex flex-col gap-3">
            {EVENTS.map((e) => (
              <div key={e.title} className="lift flex items-center gap-4 rounded-[18px] p-4"
                style={{ background: 'var(--linen-50)', border: '1px solid var(--border-hairline)', boxShadow: 'var(--shadow-card)' }}>
                <div className="w-12 text-center shrink-0">
                  <div className="text-[10px] uppercase tracking-wider text-ink-2">{e.day}</div>
                  <div className="font-mono text-2xl leading-tight" style={{ color: 'var(--char-900)' }}>{e.date}</div>
                </div>
                <div className="w-px self-stretch" style={{ background: 'var(--border-hairline)' }} />
                <div className="flex-1 min-w-0">
                  <p className="text-[15px] text-ink">{e.title}</p>
                  <p className="text-sm text-ink-2 mt-0.5">{e.where}</p>
                </div>
                <div className="flex items-center gap-1.5 shrink-0" style={{ color: 'var(--slate-700)' }}>
                  <svg viewBox="0 0 24 24" width={15} height={15} fill="none" stroke="currentColor" strokeWidth={1.5} strokeLinecap="round" strokeLinejoin="round" aria-hidden>
                    <circle cx="9" cy="8" r="3.2" /><path d="M3.5 19c0-3 2.5-5 5.5-5s5.5 2 5.5 5" />
                    <path d="M16 5.2a3.2 3.2 0 0 1 0 5.6M17 14.4c2.3.5 3.8 2.3 3.8 4.6" opacity="0.6" />
                  </svg>
                  <span className="font-mono text-sm">{e.rsvps}</span>
                </div>
              </div>
            ))}
          </Reveal>
        </div>
      </section>

      {/* founder — dark section */}
      <section style={{ borderTop: '1px solid var(--border-onSand)', background: 'var(--char-900)' }}>
        <div className="max-w-6xl mx-auto px-5 md:px-8 py-20 md:py-28 grid grid-cols-1 lg:grid-cols-2 gap-12 items-center">
          <Reveal>
            <div className="rounded-[24px] aspect-[4/5] max-w-[280px] flex items-end p-5 relative overflow-hidden"
              style={{ background: 'linear-gradient(160deg, var(--slate-600), var(--pine-700))' }}>
              <span className="absolute top-4 right-5 text-[10px] uppercase tracking-[0.14em]" style={{ color: 'rgba(251,250,245,0.6)' }}>
                Photo · Jesse
              </span>
              <span className="font-display text-2xl italic" style={{ color: 'var(--linen-50)', fontWeight: 300 }}>
                St. Joe, born & raised
              </span>
            </div>
          </Reveal>
          <Reveal>
            <div className="flex items-center gap-2 mb-6" style={{ color: 'var(--linen-50)' }}>
              <HyggeFlame size={22} />
              <span className="font-display tracking-[0.28em] uppercase text-sm font-medium">HYGGE</span>
            </div>
            <h2 className="font-display text-3xl md:text-4xl leading-snug" style={{ color: 'var(--linen-50)', fontWeight: 400, maxWidth: '26ch' }}>
              "I'm Jesse. I built Hygge Health for my town because the apps I tried never felt like they were made for anyone I actually know."
            </h2>
            <p className="text-sm mt-6" style={{ color: 'rgba(251,250,245,0.6)' }}>Founder · Saint Joseph, Minnesota</p>
          </Reveal>
        </div>
      </section>

      {/* trust */}
      <section style={{ borderTop: '1px solid var(--border-onSand)' }}>
        <div className="max-w-6xl mx-auto px-5 md:px-8 py-20 md:py-28">
          <Reveal className="max-w-xl mb-14">
            <p className="text-[12px] uppercase tracking-[0.18em] mb-4" style={{ color: 'var(--pine-700)' }}>Built to be trusted</p>
            <h2 className="font-display text-4xl md:text-5xl leading-tight" style={{ color: 'var(--char-900)', fontWeight: 500 }}>
              No hype — just how it works.
            </h2>
          </Reveal>
          <div className="grid grid-cols-1 md:grid-cols-3 gap-5">
            {TRUST.map((c) => (
              <Reveal key={c.title}>
                <div className="lift rounded-[18px] p-7 h-full"
                  style={{ background: 'var(--linen-50)', border: '1px solid var(--border-hairline)', boxShadow: 'var(--shadow-card)' }}>
                  <h3 className="text-ink mb-2.5">{c.title}</h3>
                  <p className="text-sm text-ink-2 leading-relaxed">{c.desc}</p>
                </div>
              </Reveal>
            ))}
          </div>
        </div>
      </section>

      {/* CTA */}
      <section style={{ borderTop: '1px solid var(--border-onSand)' }}>
        <Reveal className="max-w-2xl mx-auto px-5 md:px-8 py-24 md:py-32 text-center flex flex-col items-center">
          <div className="flex items-center gap-2 mb-7" style={{ color: 'var(--char-900)' }}>
            <HyggeFlame size={26} />
            <span className="font-display tracking-[0.28em] uppercase text-lg font-medium">HYGGE</span>
          </div>
          <h2 className="font-display text-4xl md:text-5xl leading-tight mb-4" style={{ color: 'var(--char-900)', fontWeight: 500, letterSpacing: '-0.01em' }}>
            Be one of the first in St. Joe.
          </h2>
          <p className="text-ink-2 mb-9 text-lg">Free at launch. Your first meal is logged in under a minute.</p>
          <Link href={appHref}
            className="press font-semibold px-9 py-4 rounded-[10px] text-base transition-colors"
            style={{ background: 'var(--char-700)', color: 'var(--linen-50)' }}>
            {user ? 'Open the app' : 'Join the waitlist'}
          </Link>
        </Reveal>
      </section>

      {/* footer */}
      <footer style={{ borderTop: '1px solid var(--border-onSand)' }}>
        <div className="max-w-6xl mx-auto px-5 md:px-8 py-10 flex flex-col sm:flex-row items-center justify-between gap-4">
          <div>
            <div className="flex items-center gap-2 text-ink">
              <HyggeFlame size={16} />
              <span className="font-display tracking-[0.28em] uppercase text-sm font-medium">HYGGE</span>
            </div>
            <p className="text-sm text-ink-3 mt-1.5">Warmth and intention, not grind culture.</p>
          </div>
          <p className="font-mono text-[11px] text-ink-3">© 2026 Hygge Health · Saint Joseph, MN</p>
        </div>
      </footer>
    </div>
  )
}
