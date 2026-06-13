import Link from 'next/link'
import { createClient } from '@/lib/supabase/server'
import ScoreRing, { scoreTone } from './components/ScoreRing'
import Reveal from './components/Reveal'
import { IconBarcode, IconCheck, IconFlame, IconLeaf } from './components/Icons'

/* Korina is a tonewood — the hero wears its grain. Deterministic SVG, no randomness. */
function WoodGrain({ className = '' }: { className?: string }) {
  const lines = Array.from({ length: 14 }, (_, i) => {
    const x = 40 + i * 44
    const sway = (i % 3) * 10 - 10
    return `M ${x} -20 C ${x + 18 + sway} 220, ${x - 20 - sway} 480, ${x + 12} 840`
  })
  return (
    <svg
      aria-hidden
      viewBox="0 0 640 820"
      preserveAspectRatio="xMidYMid slice"
      className={`pointer-events-none ${className}`}
      fill="none"
      stroke="var(--color-moss-600)"
      strokeWidth="1.2"
    >
      <g opacity="0.13">
        {lines.map((d, i) => (
          <path key={i} d={d} />
        ))}
        {/* the knot */}
        {[14, 34, 58, 86, 118].map((rx, i) => (
          <ellipse key={rx} cx="356" cy="330" rx={rx} ry={rx * 1.55} opacity={1 - i * 0.15} />
        ))}
      </g>
    </svg>
  )
}

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
    <span className="flex items-center gap-2.5 bg-paper border border-black/[0.08] rounded-full pl-4 pr-3 py-2 shrink-0">
      <span className="text-sm text-ink whitespace-nowrap">{name}</span>
      <span
        className={`font-mono text-xs tabular-nums px-2 py-0.5 rounded-full ${tone.text}`}
        style={{ background: 'color-mix(in srgb, currentColor 10%, transparent)' }}
      >
        {score}
      </span>
    </span>
  )
}

function StepArt({ n }: { n: string }) {
  const common = {
    viewBox: '0 0 56 56',
    fill: 'none',
    stroke: 'currentColor',
    strokeWidth: 1.5,
    strokeLinecap: 'round' as const,
    strokeLinejoin: 'round' as const,
  }
  if (n === '01')
    return (
      <svg {...common} className="w-12 h-12 text-ink">
        <path d="M10 30h36a18 18 0 0 1-36 0Z" />
        <path d="M21 30c0-8 3-14 11-17" opacity="0.45" />
        <circle cx="40" cy="14" r="8" stroke="var(--color-moss-600)" strokeDasharray="38 13" transform="rotate(-90 40 14)" />
      </svg>
    )
  if (n === '02')
    return (
      <svg {...common} className="w-12 h-12 text-ink">
        <path d="M16 16v24M40 16v24M9 21v14M47 21v14M16 28h24" />
        <path d="M22 9c4 2 8 2 12 0" stroke="var(--color-moss-600)" />
      </svg>
    )
  return (
    <svg {...common} className="w-12 h-12 text-ink">
      <circle cx="28" cy="28" r="7" stroke="var(--color-moss-600)" />
      <circle cx="28" cy="28" r="14" strokeDasharray="66 22" transform="rotate(-90 28 28)" opacity="0.7" />
      <circle cx="28" cy="28" r="21" strokeDasharray="106 26" transform="rotate(-90 28 28)" opacity="0.4" />
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
              <circle cx="100" cy="100" r={ring.r} fill="none" stroke="rgba(0,0,0,0.07)" strokeWidth="10" />
              <circle
                cx="100"
                cy="100"
                r={ring.r}
                fill="none"
                stroke={ring.color}
                strokeWidth="10"
                strokeLinecap="round"
                strokeDasharray={circ}
                className="ring-fill"
                style={
                  {
                    '--circ': circ,
                    '--target': target,
                    animationDelay: `${0.3 + i * 0.15}s`,
                  } as React.CSSProperties
                }
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

const STEPS = [
  {
    n: '01',
    title: 'Log what you eat',
    desc: 'Scan a barcode or search 700,000+ foods. Every item is scored 1–100 the moment it hits your log.',
  },
  {
    n: '02',
    title: 'Train',
    desc: 'Quick-start strength, HIIT, yoga, or cardio sessions — or log your own. One tap to mark it done.',
  },
  {
    n: '03',
    title: 'Watch it compound',
    desc: 'Rings close. Streaks grow. The weekly chart fills in. Progress you can actually see.',
  },
]

const TRUST = [
  {
    title: 'Built on open data',
    desc: 'Every score starts from Open Food Facts — the world’s open, community-run food database. 700,000+ real products, not numbers we made up.',
  },
  {
    title: 'Transparent scoring',
    desc: 'Tap any food to see exactly why it scored what it did — the points it earned and the points it lost. No black box.',
  },
  {
    title: 'Free, and yours',
    desc: 'No card to start. Your log is private to your account, and you can delete anything you’ve logged, anytime.',
  },
]

export default async function Home() {
  const supabase = await createClient()
  const {
    data: { user },
  } = await supabase.auth.getUser()

  const appHref = user ? '/dashboard' : '/login'

  return (
    <div className="min-h-screen overflow-x-clip grain">
      {/* nav */}
      <nav className="sticky top-0 z-50 bg-paper/80 backdrop-blur-md border-b border-black/[0.07]">
        <div className="max-w-6xl mx-auto px-5 md:px-8 h-16 flex items-center justify-between">
          <span className="font-display text-sky-600 tracking-[0.25em] uppercase text-lg">Korina</span>
          <div className="flex items-center gap-6">
            <a href="#score" className="hidden md:block text-sm text-ink-2 hover:text-ink transition-colors">
              The score
            </a>
            <a href="#scanner" className="hidden md:block text-sm text-ink-2 hover:text-ink transition-colors">
              Scanner
            </a>
            {user ? (
              <Link
                href="/dashboard"
                className="bg-sky-700 hover:bg-sky-800 text-white font-semibold px-5 py-3 rounded-xl text-sm transition-colors"
              >
                Open Korina
              </Link>
            ) : (
              <>
                <Link href="/login" className="hidden sm:block text-sm text-ink-2 hover:text-ink transition-colors">
                  Sign in
                </Link>
                <Link
                  href="/login"
                  className="bg-sky-700 hover:bg-sky-800 text-white font-semibold px-5 py-3 rounded-xl text-sm transition-colors"
                >
                  Start free
                </Link>
              </>
            )}
          </div>
        </div>
      </nav>

      {/* hero */}
      <section className="relative">
        {/* korina wood-grain ornament */}
        <WoodGrain className="absolute right-0 top-0 h-full w-[55%] hidden md:block" />
        <div
          aria-hidden
          className="absolute right-[-10%] top-[10%] w-[480px] h-[480px] rounded-full bg-sky-500/10 blur-[120px] pointer-events-none"
        />

        <div className="relative max-w-6xl mx-auto px-5 md:px-8 pt-16 md:pt-24 pb-20 grid grid-cols-1 lg:grid-cols-2 gap-14 items-center">
          <div className="rise">
            <p className="text-[11px] uppercase tracking-[0.22em] text-moss-700 mb-6">
              Nutrition-first fitness tracking
            </p>
            <h1 className="font-display text-5xl md:text-6xl text-ink leading-[1.04] mb-7">
              Eat clean.
              <br />
              Train hard.
              <br />
              <em className="text-moss-700">Watch it compound.</em>
            </h1>
            <p className="text-ink-2 text-lg leading-relaxed max-w-md mb-10">
              Every food you log gets a clean score from 1 to 100. Every workout counts.
              Korina turns daily habits into rings you can watch grow.
            </p>
            <div className="flex gap-3 flex-wrap">
              <Link
                href={appHref}
                className="bg-sky-700 hover:bg-sky-800 text-white font-semibold px-7 py-3.5 rounded-xl text-sm transition-colors"
              >
                {user ? 'Open Korina' : 'Start free'}
              </Link>
              <a
                href="#score"
                className="border border-black/[0.12] text-ink px-7 py-3.5 rounded-xl text-sm hover:bg-paper-100 transition-colors"
              >
                How foods score
              </a>
            </div>
          </div>

          {/* app preview — phone frame */}
          <div className="rise relative max-w-[330px] w-full mx-auto lg:ml-auto" style={{ animationDelay: '150ms' }}>
            <div className="rounded-[2.8rem] border-[9px] border-ink bg-paper-50 shadow-[0_44px_90px_-32px_rgba(29,31,28,0.4)] overflow-hidden">
              <div className="h-8 flex items-center justify-center">
                <span className="w-16 h-1.5 rounded-full bg-paper-300" />
              </div>
              <div className="px-5 pb-7">
              <div className="flex items-center justify-between mb-4">
                <span className="text-[11px] uppercase tracking-[0.18em] text-ink-2">Today</span>
                <span className="flex items-center gap-1.5 font-mono text-[11px] text-honey-600 tabular-nums">
                  <IconFlame className="w-3.5 h-3.5" /> 12 days
                </span>
              </div>

              <div className="flex justify-center py-2">
                <PreviewRings />
              </div>

              <div className="space-y-1.5 mt-4 mb-4">
                {[
                  { label: 'Calories', value: '1,488 / 2,100', color: 'bg-honey-600' },
                  { label: 'Protein', value: '90g / 140g', color: 'bg-moss-700' },
                  { label: 'Clean score', value: '88 / 100', color: 'bg-ink' },
                ].map((row) => (
                  <div key={row.label} className="flex items-center justify-between">
                    <span className="flex items-center gap-2 text-xs text-ink-2">
                      <span className={`w-1.5 h-1.5 rounded-full ${row.color}`} />
                      {row.label}
                    </span>
                    <span className="font-mono text-xs text-ink tabular-nums">{row.value}</span>
                  </div>
                ))}
              </div>

              <div className="border-t border-black/[0.07] pt-3 space-y-2.5">
                <div className="flex items-center gap-3">
                  <ScoreRing score={92} size={34} />
                  <div className="flex-1 min-w-0">
                    <p className="text-xs text-ink truncate">Greek yogurt, plain</p>
                    <p className="font-mono text-[10px] text-ink-3 tabular-nums">146 kcal · 20P</p>
                  </div>
                  <span className="text-[10px] text-moss-700">Clean</span>
                </div>
                <div className="flex items-center gap-3">
                  <span className="w-[34px] h-[34px] rounded-full bg-moss-700 text-white flex items-center justify-center shrink-0">
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
        <div className="marquee relative overflow-hidden py-5 border-t border-black/[0.07]">
          <div className="marquee-track flex gap-3 w-max pr-3">
            {TICKER.map(([name, score]) => (
              <TickerChip key={name} name={name} score={score} />
            ))}
            <span aria-hidden className="flex gap-3">
              {TICKER.map(([name, score]) => (
                <TickerChip key={`dup-${name}`} name={name} score={score} />
              ))}
            </span>
          </div>
          <div className="absolute inset-y-0 left-0 w-24 bg-gradient-to-r from-paper to-transparent pointer-events-none" />
          <div className="absolute inset-y-0 right-0 w-24 bg-gradient-to-l from-paper to-transparent pointer-events-none" />
        </div>

        {/* data strip */}
        <div className="relative border-y border-black/[0.07]">
          <div className="max-w-6xl mx-auto px-5 md:px-8 grid grid-cols-1 sm:grid-cols-3 divide-y sm:divide-y-0 sm:divide-x divide-black/[0.07]">
            {[
              ['700,000+', 'foods in the database'],
              ['1–100', 'clean score on every log'],
              ['~2 sec', 'from barcode to logged'],
            ].map(([num, label]) => (
              <div key={label} className="py-6 sm:px-8 first:pl-0 flex items-baseline gap-3">
                <span className="font-mono text-xl text-ink tabular-nums">{num}</span>
                <span className="text-sm text-ink-2">{label}</span>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* clean score */}
      <section id="score" className="max-w-6xl mx-auto px-5 md:px-8 py-24 md:py-32 grid grid-cols-1 lg:grid-cols-2 gap-14 items-center">
        <Reveal className="order-2 lg:order-1">
          <div className="lift bg-paper-50 border border-black/[0.09] rounded-3xl p-6 max-w-sm mx-auto lg:mx-0">
            <p className="text-[11px] uppercase tracking-[0.18em] text-ink-2 mb-5">Clean score</p>
            <div className="flex items-center gap-5 mb-6">
              <ScoreRing score={92} size={72} />
              <div>
                <p className="text-ink">Greek yogurt, plain</p>
                <p className="text-[11px] uppercase tracking-[0.18em] text-moss-700 mt-1">Clean</p>
                <div className="flex gap-1.5 mt-2.5 flex-wrap">
                  {['Whole food', 'High protein'].map((b) => (
                    <span
                      key={b}
                      className="inline-flex items-center gap-1 text-[10px] text-moss-700 bg-moss-700/10 border border-moss-700/20 px-2 py-0.5 rounded-full"
                    >
                      <IconLeaf className="w-2.5 h-2.5" />
                      {b}
                    </span>
                  ))}
                </div>
              </div>
            </div>
            <div className="flex items-center gap-5 pt-5 border-t border-black/[0.07]">
              <ScoreRing score={14} size={72} />
              <div>
                <p className="text-ink">Diet cola</p>
                <p className="text-[11px] uppercase tracking-[0.18em] text-clay-700 mt-1">Avoid</p>
                <p className="text-[11px] text-ink-2 mt-2 leading-relaxed">
                  Ultra-processed · artificial sweeteners
                </p>
              </div>
            </div>
          </div>
        </Reveal>

        <Reveal className="order-1 lg:order-2">
          <p className="text-[11px] uppercase tracking-[0.22em] text-moss-700 mb-5">The clean score</p>
          <h2 className="font-display text-4xl md:text-5xl text-ink leading-tight mb-6">
            We read the label
            <br />
            so you don&apos;t have to.
          </h2>
          <p className="text-ink-2 leading-relaxed mb-10 max-w-md">
            Calories never told the whole story. Korina scores every food on how processed it
            really is — the same rules, applied to everything you log.
          </p>
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-x-10 gap-y-1">
            <div>
              <p className="text-[11px] uppercase tracking-[0.18em] text-ink-2 mb-3">Earns points</p>
              {EARNS.map((f) => (
                <div
                  key={f.label}
                  className="flex items-center justify-between gap-4 py-2.5 border-t border-black/[0.07]"
                >
                  <span className="text-sm text-ink">{f.label}</span>
                  <span className="font-mono text-sm text-moss-700 tabular-nums">{f.delta}</span>
                </div>
              ))}
            </div>
            <div className="mt-6 sm:mt-0">
              <p className="text-[11px] uppercase tracking-[0.18em] text-ink-2 mb-3">Loses points</p>
              {LOSES.map((f) => (
                <div
                  key={f.label}
                  className="flex items-center justify-between gap-4 py-2.5 border-t border-black/[0.07]"
                >
                  <span className="text-sm text-ink">{f.label}</span>
                  <span className="font-mono text-sm text-clay-700 tabular-nums">{f.delta}</span>
                </div>
              ))}
            </div>
          </div>
        </Reveal>
      </section>

      {/* scanner */}
      <section id="scanner" className="border-y border-black/[0.07] bg-paper-50/40">
        <div className="max-w-6xl mx-auto px-5 md:px-8 py-24 md:py-32 grid grid-cols-1 lg:grid-cols-2 gap-14 items-center">
          <Reveal>
            <p className="text-[11px] uppercase tracking-[0.22em] text-moss-700 mb-5">Instant logging</p>
            <h2 className="font-display text-4xl md:text-5xl text-ink leading-tight mb-6">
              Scan it. Logged.
            </h2>
            <p className="text-ink-2 leading-relaxed mb-8 max-w-md">
              Point your camera at any barcode and the full breakdown lands in your log —
              calories, macros, and the clean score. No typing, no searching.
            </p>
            <Link
              href={user ? '/scan' : '/login'}
              className="inline-flex items-center gap-2.5 bg-sky-700 hover:bg-sky-800 text-white font-semibold px-7 py-3.5 rounded-xl text-sm transition-colors"
            >
              <IconBarcode className="w-4 h-4" />
              Try the scanner
            </Link>
          </Reveal>

          <Reveal className="relative max-w-sm w-full mx-auto lg:ml-auto">
            <div className="lift bg-paper-50 border border-black/[0.09] rounded-3xl p-5">
              <div className="flex items-center justify-between mb-4">
                <span className="text-[11px] uppercase tracking-[0.18em] text-ink-2">Scan</span>
                <span className="w-1.5 h-1.5 rounded-full bg-moss-700 animate-pulse" />
              </div>
              <div className="relative bg-paper-100 border border-black/[0.06] rounded-2xl aspect-video overflow-hidden">
                <div className="absolute inset-5">
                  <span className="absolute top-0 left-0 w-6 h-6 border-t-2 border-l-2 border-moss-700 rounded-tl-lg" />
                  <span className="absolute top-0 right-0 w-6 h-6 border-t-2 border-r-2 border-moss-700 rounded-tr-lg" />
                  <span className="absolute bottom-0 left-0 w-6 h-6 border-b-2 border-l-2 border-moss-700 rounded-bl-lg" />
                  <span className="absolute bottom-0 right-0 w-6 h-6 border-b-2 border-r-2 border-moss-700 rounded-br-lg" />
                  <span
                    className="absolute left-2 right-2 h-px bg-moss-700/80"
                    style={{ animation: 'beam 2.4s ease-in-out infinite', boxShadow: '0 0 12px rgba(26,111,168,0.5)' }}
                  />
                </div>
                <IconBarcode className="absolute inset-0 m-auto w-12 h-12 text-ink-3" />
              </div>
              <div className="mt-4 bg-paper-100 border border-black/[0.06] rounded-2xl p-3.5 flex items-center gap-3">
                <ScoreRing score={78} size={38} />
                <div className="flex-1 min-w-0">
                  <p className="text-xs text-ink truncate">Dark chocolate almonds</p>
                  <p className="font-mono text-[10px] text-ink-3 tabular-nums">200 kcal · 6P · 13C</p>
                </div>
                <span className="bg-moss-700 text-white text-[11px] font-semibold px-3 py-1.5 rounded-lg shrink-0">
                  Add
                </span>
              </div>
            </div>
          </Reveal>
        </div>
      </section>

      {/* daily loop */}
      <section className="max-w-6xl mx-auto px-5 md:px-8 py-24 md:py-32">
        <Reveal className="max-w-xl mb-14">
          <p className="text-[11px] uppercase tracking-[0.22em] text-moss-700 mb-5">The daily loop</p>
          <h2 className="font-display text-4xl md:text-5xl text-ink leading-tight">
            Two minutes a day.
            <br />
            That&apos;s the whole system.
          </h2>
        </Reveal>
        <div className="grid grid-cols-1 md:grid-cols-3 gap-10 md:gap-8">
          {STEPS.map((s) => (
            <Reveal key={s.n} className="border-t border-black/[0.12] pt-6">
              <div className="flex items-start justify-between mb-5">
                <StepArt n={s.n} />
                <p className="font-mono text-xs text-ink-3 tabular-nums">{s.n}</p>
              </div>
              <h3 className="text-lg text-ink mb-3">{s.title}</h3>
              <p className="text-sm text-ink-2 leading-relaxed">{s.desc}</p>
            </Reveal>
          ))}
        </div>
      </section>

      {/* why trust it — real substance instead of invented reviews */}
      <section className="border-t border-black/[0.07]">
        <div className="max-w-6xl mx-auto px-5 md:px-8 py-24 md:py-32">
          <Reveal className="max-w-xl mb-12 md:mb-14">
            <p className="text-[11px] uppercase tracking-[0.22em] text-moss-700 mb-5">
              Built to be trusted
            </p>
            <h2 className="font-display text-4xl md:text-5xl text-ink leading-tight">
              No hype — just how it works.
            </h2>
          </Reveal>
          <div className="grid grid-cols-1 md:grid-cols-3 gap-5">
            {TRUST.map((c) => (
              <Reveal
                key={c.title}
                className="lift bg-paper-50 border border-black/[0.07] rounded-3xl p-7"
              >
                <h3 className="text-ink mb-2.5">{c.title}</h3>
                <p className="text-sm text-ink-2 leading-relaxed">{c.desc}</p>
              </Reveal>
            ))}
          </div>
          {/* Once you have real signups, add an honest count here, e.g.:
              <p className="text-center text-sm text-ink-2 mt-12">
                <span className="text-ink font-medium">312</span> people have started. Be next.
              </p> */}
        </div>
      </section>

      {/* CTA */}
      <section className="relative border-t border-black/[0.07] overflow-hidden">
        {/* half-buried growth rings */}
        <svg
          aria-hidden
          viewBox="0 0 800 400"
          className="absolute left-1/2 -translate-x-1/2 bottom-[-200px] w-[800px] pointer-events-none"
          fill="none"
          strokeWidth="16"
          strokeLinecap="round"
        >
          <circle cx="400" cy="400" r="180" stroke="var(--color-ink)" opacity="0.06" />
          <circle cx="400" cy="400" r="260" stroke="var(--color-moss-600)" opacity="0.14" strokeDasharray="1230 400" transform="rotate(140 400 400)" />
          <circle cx="400" cy="400" r="340" stroke="var(--color-honey-600)" opacity="0.12" strokeDasharray="1600 535" transform="rotate(155 400 400)" />
        </svg>
        <Reveal className="relative max-w-2xl mx-auto px-5 md:px-8 py-24 md:py-32 text-center">
          <h2 className="font-display text-4xl md:text-5xl text-ink leading-tight mb-5">
            Start your first ring today.
          </h2>
          <p className="text-ink-2 mb-10">
            Free to use. Your first meal is logged in under a minute.
          </p>
          <Link
            href={appHref}
            className="inline-block bg-sky-700 hover:bg-sky-800 text-white font-semibold px-9 py-4 rounded-xl transition-colors"
          >
            {user ? 'Open Korina' : 'Start free'}
          </Link>
        </Reveal>
      </section>

      {/* footer */}
      <footer className="border-t border-black/[0.07]">
        <div className="max-w-6xl mx-auto px-5 md:px-8 py-12 flex flex-col sm:flex-row items-center justify-between gap-4">
          <div>
            <p className="font-display text-sky-600 tracking-[0.25em] uppercase">Korina</p>
            <p className="text-sm text-ink-3 mt-1.5">Feel good, inside and out.</p>
          </div>
          <p className="font-mono text-[11px] text-ink-3">© 2026 Korina</p>
        </div>
      </footer>
    </div>
  )
}
