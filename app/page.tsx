import Link from 'next/link'
import { createClient } from '@/lib/supabase/server'
import ScoreRing from './components/ScoreRing'
import Reveal from './components/Reveal'
import { IconBarcode, IconCheck, IconFlame, IconLeaf } from './components/Icons'

/* Static tri-ring for the hero preview — CSS animates the fill on load. */
function PreviewRings() {
  const rings = [
    { r: 84, pct: 0.71, color: 'var(--color-honey-400)' },
    { r: 67, pct: 0.64, color: 'var(--color-moss-400)' },
    { r: 50, pct: 0.88, color: 'var(--color-cream)' },
  ]
  return (
    <div className="relative w-[180px] h-[180px] shrink-0">
      <svg viewBox="0 0 200 200" width={180} height={180} className="-rotate-90">
        {rings.map((ring, i) => {
          const circ = 2 * Math.PI * ring.r
          const target = circ * (1 - ring.pct)
          return (
            <g key={i}>
              <circle cx="100" cy="100" r={ring.r} fill="none" stroke="rgba(255,255,255,0.06)" strokeWidth="10" />
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
        <span className="font-mono text-3xl text-cream tabular-nums">612</span>
        <span className="text-[10px] uppercase tracking-[0.18em] text-fog mt-0.5">kcal left</span>
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

const TESTIMONIALS = [
  {
    quote:
      'Grove is the only tracker I’ve kept open past a week. The scanner alone saves me ten minutes a day.',
    name: 'Maya R.',
    detail: 'Lost 14 lbs in 3 months',
  },
  {
    quote:
      'Watching the rings close is more motivating than any badge an app has ever given me.',
    name: 'Jordan T.',
    detail: '62-day streak',
  },
  {
    quote:
      'I finally understand what I’m actually eating. The clean score changed how I cook, not just how I log.',
    name: 'Priya S.',
    detail: 'Hit protein goal 47 days straight',
  },
]

export default async function Home() {
  const supabase = await createClient()
  const {
    data: { user },
  } = await supabase.auth.getUser()

  const appHref = user ? '/dashboard' : '/login'

  return (
    <div className="min-h-screen overflow-x-clip">
      {/* nav */}
      <nav className="sticky top-0 z-50 bg-bark-950/80 backdrop-blur-md border-b border-white/[0.06]">
        <div className="max-w-6xl mx-auto px-5 md:px-8 h-16 flex items-center justify-between">
          <span className="font-display text-cream tracking-[0.25em] uppercase text-lg">Grove</span>
          <div className="flex items-center gap-6">
            <a href="#score" className="hidden md:block text-sm text-fog hover:text-cream transition-colors">
              The score
            </a>
            <a href="#scanner" className="hidden md:block text-sm text-fog hover:text-cream transition-colors">
              Scanner
            </a>
            {user ? (
              <Link
                href="/dashboard"
                className="bg-moss-400 hover:bg-moss-300 text-bark-950 font-semibold px-5 py-2.5 rounded-xl text-sm transition-colors"
              >
                Open Grove
              </Link>
            ) : (
              <>
                <Link href="/login" className="hidden sm:block text-sm text-fog hover:text-cream transition-colors">
                  Sign in
                </Link>
                <Link
                  href="/login"
                  className="bg-moss-400 hover:bg-moss-300 text-bark-950 font-semibold px-5 py-2.5 rounded-xl text-sm transition-colors"
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
        {/* growth-rings ornament */}
        <div
          aria-hidden
          className="absolute inset-0 pointer-events-none"
          style={{
            background:
              'repeating-radial-gradient(circle at 78% 38%, transparent 0px, transparent 89px, rgba(164,193,143,0.06) 90px, transparent 91px)',
          }}
        />
        <div
          aria-hidden
          className="absolute right-[-10%] top-[10%] w-[480px] h-[480px] rounded-full bg-moss-600/10 blur-[120px] pointer-events-none"
        />

        <div className="relative max-w-6xl mx-auto px-5 md:px-8 pt-16 md:pt-24 pb-20 grid grid-cols-1 lg:grid-cols-2 gap-14 items-center">
          <div className="rise">
            <p className="text-[11px] uppercase tracking-[0.22em] text-moss-300 mb-6">
              Nutrition-first fitness tracking
            </p>
            <h1 className="font-display text-5xl md:text-6xl text-cream leading-[1.04] mb-7">
              Eat clean.
              <br />
              Train hard.
              <br />
              <em className="text-moss-300">Watch it compound.</em>
            </h1>
            <p className="text-fog text-lg leading-relaxed max-w-md mb-10">
              Every food you log gets a clean score from 1 to 100. Every workout counts.
              Grove turns daily habits into rings you can watch grow.
            </p>
            <div className="flex gap-3 flex-wrap">
              <Link
                href={appHref}
                className="bg-moss-400 hover:bg-moss-300 text-bark-950 font-semibold px-7 py-3.5 rounded-xl text-sm transition-colors"
              >
                {user ? 'Open Grove' : 'Start free'}
              </Link>
              <a
                href="#score"
                className="border border-white/[0.1] text-cream px-7 py-3.5 rounded-xl text-sm hover:bg-bark-800 transition-colors"
              >
                How foods score
              </a>
            </div>
          </div>

          {/* app preview */}
          <div className="rise relative max-w-sm w-full mx-auto lg:ml-auto" style={{ animationDelay: '150ms' }}>
            <div className="bg-bark-900 border border-white/[0.08] rounded-3xl p-5 shadow-[0_24px_80px_-24px_rgba(0,0,0,0.8)]">
              <div className="flex items-center justify-between mb-4">
                <span className="text-[11px] uppercase tracking-[0.18em] text-fog">Today</span>
                <span className="flex items-center gap-1.5 font-mono text-[11px] text-honey-300 tabular-nums">
                  <IconFlame className="w-3.5 h-3.5" /> 12 days
                </span>
              </div>

              <div className="flex justify-center py-2">
                <PreviewRings />
              </div>

              <div className="space-y-1.5 mt-4 mb-4">
                {[
                  { label: 'Calories', value: '1,488 / 2,100', color: 'bg-honey-400' },
                  { label: 'Protein', value: '90g / 140g', color: 'bg-moss-400' },
                  { label: 'Clean score', value: '88 / 100', color: 'bg-cream' },
                ].map((row) => (
                  <div key={row.label} className="flex items-center justify-between">
                    <span className="flex items-center gap-2 text-xs text-fog">
                      <span className={`w-1.5 h-1.5 rounded-full ${row.color}`} />
                      {row.label}
                    </span>
                    <span className="font-mono text-xs text-cream tabular-nums">{row.value}</span>
                  </div>
                ))}
              </div>

              <div className="border-t border-white/[0.06] pt-3 space-y-2.5">
                <div className="flex items-center gap-3">
                  <ScoreRing score={92} size={34} />
                  <div className="flex-1 min-w-0">
                    <p className="text-xs text-cream truncate">Greek yogurt, plain</p>
                    <p className="font-mono text-[10px] text-fog-dim tabular-nums">146 kcal · 20P</p>
                  </div>
                  <span className="text-[10px] text-moss-300">Clean</span>
                </div>
                <div className="flex items-center gap-3">
                  <span className="w-[34px] h-[34px] rounded-full bg-moss-400 text-bark-950 flex items-center justify-center shrink-0">
                    <IconCheck className="w-4 h-4" strokeWidth={2.5} />
                  </span>
                  <div className="flex-1 min-w-0">
                    <p className="text-xs text-cream truncate">Upper Body Strength</p>
                    <p className="font-mono text-[10px] text-fog-dim tabular-nums">4 exercises · 45 min</p>
                  </div>
                  <span className="text-[10px] text-fog">Done</span>
                </div>
              </div>
            </div>
          </div>
        </div>

        {/* data strip */}
        <div className="relative border-y border-white/[0.06]">
          <div className="max-w-6xl mx-auto px-5 md:px-8 grid grid-cols-1 sm:grid-cols-3 divide-y sm:divide-y-0 sm:divide-x divide-white/[0.06]">
            {[
              ['700,000+', 'foods in the database'],
              ['1–100', 'clean score on every log'],
              ['~2 sec', 'from barcode to logged'],
            ].map(([num, label]) => (
              <div key={label} className="py-6 sm:px-8 first:pl-0 flex items-baseline gap-3">
                <span className="font-mono text-xl text-cream tabular-nums">{num}</span>
                <span className="text-sm text-fog">{label}</span>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* clean score */}
      <section id="score" className="max-w-6xl mx-auto px-5 md:px-8 py-24 md:py-32 grid grid-cols-1 lg:grid-cols-2 gap-14 items-center">
        <Reveal className="order-2 lg:order-1">
          <div className="bg-bark-900 border border-white/[0.08] rounded-3xl p-6 max-w-sm mx-auto lg:mx-0">
            <p className="text-[11px] uppercase tracking-[0.18em] text-fog mb-5">Clean score</p>
            <div className="flex items-center gap-5 mb-6">
              <ScoreRing score={92} size={72} />
              <div>
                <p className="text-cream">Greek yogurt, plain</p>
                <p className="text-[11px] uppercase tracking-[0.18em] text-moss-300 mt-1">Clean</p>
                <div className="flex gap-1.5 mt-2.5 flex-wrap">
                  {['Whole food', 'High protein'].map((b) => (
                    <span
                      key={b}
                      className="inline-flex items-center gap-1 text-[10px] text-moss-300 bg-moss-500/10 border border-moss-500/20 px-2 py-0.5 rounded-full"
                    >
                      <IconLeaf className="w-2.5 h-2.5" />
                      {b}
                    </span>
                  ))}
                </div>
              </div>
            </div>
            <div className="flex items-center gap-5 pt-5 border-t border-white/[0.06]">
              <ScoreRing score={14} size={72} />
              <div>
                <p className="text-cream">Diet cola</p>
                <p className="text-[11px] uppercase tracking-[0.18em] text-clay-300 mt-1">Avoid</p>
                <p className="text-[11px] text-fog mt-2 leading-relaxed">
                  Ultra-processed · artificial sweeteners
                </p>
              </div>
            </div>
          </div>
        </Reveal>

        <Reveal className="order-1 lg:order-2">
          <p className="text-[11px] uppercase tracking-[0.22em] text-moss-300 mb-5">The clean score</p>
          <h2 className="font-display text-4xl md:text-5xl text-cream leading-tight mb-6">
            We read the label
            <br />
            so you don&apos;t have to.
          </h2>
          <p className="text-fog leading-relaxed mb-10 max-w-md">
            Calories never told the whole story. Grove scores every food on how processed it
            really is — the same rules, applied to everything you log.
          </p>
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-x-10 gap-y-1">
            <div>
              <p className="text-[11px] uppercase tracking-[0.18em] text-fog mb-3">Earns points</p>
              {EARNS.map((f) => (
                <div
                  key={f.label}
                  className="flex items-center justify-between gap-4 py-2.5 border-t border-white/[0.06]"
                >
                  <span className="text-sm text-cream">{f.label}</span>
                  <span className="font-mono text-sm text-moss-300 tabular-nums">{f.delta}</span>
                </div>
              ))}
            </div>
            <div className="mt-6 sm:mt-0">
              <p className="text-[11px] uppercase tracking-[0.18em] text-fog mb-3">Loses points</p>
              {LOSES.map((f) => (
                <div
                  key={f.label}
                  className="flex items-center justify-between gap-4 py-2.5 border-t border-white/[0.06]"
                >
                  <span className="text-sm text-cream">{f.label}</span>
                  <span className="font-mono text-sm text-clay-300 tabular-nums">{f.delta}</span>
                </div>
              ))}
            </div>
          </div>
        </Reveal>
      </section>

      {/* scanner */}
      <section id="scanner" className="border-y border-white/[0.06] bg-bark-900/40">
        <div className="max-w-6xl mx-auto px-5 md:px-8 py-24 md:py-32 grid grid-cols-1 lg:grid-cols-2 gap-14 items-center">
          <Reveal>
            <p className="text-[11px] uppercase tracking-[0.22em] text-moss-300 mb-5">Instant logging</p>
            <h2 className="font-display text-4xl md:text-5xl text-cream leading-tight mb-6">
              Scan it. Logged.
            </h2>
            <p className="text-fog leading-relaxed mb-8 max-w-md">
              Point your camera at any barcode and the full breakdown lands in your log —
              calories, macros, and the clean score. No typing, no searching.
            </p>
            <Link
              href={user ? '/scan' : '/login'}
              className="inline-flex items-center gap-2.5 bg-moss-400 hover:bg-moss-300 text-bark-950 font-semibold px-7 py-3.5 rounded-xl text-sm transition-colors"
            >
              <IconBarcode className="w-4 h-4" />
              Try the scanner
            </Link>
          </Reveal>

          <Reveal className="relative max-w-sm w-full mx-auto lg:ml-auto">
            <div className="bg-bark-900 border border-white/[0.08] rounded-3xl p-5">
              <div className="flex items-center justify-between mb-4">
                <span className="text-[11px] uppercase tracking-[0.18em] text-fog">Scan</span>
                <span className="w-1.5 h-1.5 rounded-full bg-moss-400 animate-pulse" />
              </div>
              <div className="relative bg-bark-950 rounded-2xl aspect-video overflow-hidden">
                <div className="absolute inset-5">
                  <span className="absolute top-0 left-0 w-6 h-6 border-t-2 border-l-2 border-moss-300 rounded-tl-lg" />
                  <span className="absolute top-0 right-0 w-6 h-6 border-t-2 border-r-2 border-moss-300 rounded-tr-lg" />
                  <span className="absolute bottom-0 left-0 w-6 h-6 border-b-2 border-l-2 border-moss-300 rounded-bl-lg" />
                  <span className="absolute bottom-0 right-0 w-6 h-6 border-b-2 border-r-2 border-moss-300 rounded-br-lg" />
                  <span
                    className="absolute left-2 right-2 h-px bg-moss-300/80"
                    style={{ animation: 'beam 2.4s ease-in-out infinite', boxShadow: '0 0 12px rgba(191,211,175,0.5)' }}
                  />
                </div>
                <IconBarcode className="absolute inset-0 m-auto w-12 h-12 text-fog-dim" />
              </div>
              <div className="mt-4 bg-bark-800 border border-white/[0.05] rounded-2xl p-3.5 flex items-center gap-3">
                <ScoreRing score={78} size={38} />
                <div className="flex-1 min-w-0">
                  <p className="text-xs text-cream truncate">Dark chocolate almonds</p>
                  <p className="font-mono text-[10px] text-fog-dim tabular-nums">200 kcal · 6P · 13C</p>
                </div>
                <span className="bg-moss-400 text-bark-950 text-[11px] font-semibold px-3 py-1.5 rounded-lg shrink-0">
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
          <p className="text-[11px] uppercase tracking-[0.22em] text-moss-300 mb-5">The daily loop</p>
          <h2 className="font-display text-4xl md:text-5xl text-cream leading-tight">
            Two minutes a day.
            <br />
            That&apos;s the whole system.
          </h2>
        </Reveal>
        <div className="grid grid-cols-1 md:grid-cols-3 gap-10 md:gap-8">
          {STEPS.map((s) => (
            <Reveal key={s.n} className="border-t border-white/[0.1] pt-6">
              <p className="font-mono text-xs text-moss-300 mb-4 tabular-nums">{s.n}</p>
              <h3 className="text-lg text-cream mb-3">{s.title}</h3>
              <p className="text-sm text-fog leading-relaxed">{s.desc}</p>
            </Reveal>
          ))}
        </div>
      </section>

      {/* testimonials */}
      <section className="border-t border-white/[0.06]">
        <div className="max-w-6xl mx-auto px-5 md:px-8 py-24 md:py-32">
          <Reveal>
            <p className="text-[11px] uppercase tracking-[0.22em] text-moss-300 mb-12 text-center">
              From the grove
            </p>
          </Reveal>
          <div className="grid grid-cols-1 md:grid-cols-3 gap-5">
            {TESTIMONIALS.map((t) => (
              <Reveal
                key={t.name}
                className="bg-bark-900 border border-white/[0.06] rounded-3xl p-7"
              >
                <figure className="flex flex-col h-full">
                <blockquote className="text-cream/90 leading-relaxed flex-1 mb-7">
                  “{t.quote}”
                </blockquote>
                <figcaption className="flex items-center gap-3.5 pt-5 border-t border-white/[0.06]">
                  <span className="w-9 h-9 rounded-full bg-moss-500/15 border border-moss-500/25 text-moss-300 text-sm flex items-center justify-center">
                    {t.name[0]}
                  </span>
                  <div>
                    <p className="text-sm text-cream">{t.name}</p>
                    <p className="font-mono text-[11px] text-fog-dim mt-0.5 tabular-nums">{t.detail}</p>
                  </div>
                </figcaption>
                </figure>
              </Reveal>
            ))}
          </div>
        </div>
      </section>

      {/* CTA */}
      <section className="relative border-t border-white/[0.06] overflow-hidden">
        <div
          aria-hidden
          className="absolute inset-0 pointer-events-none"
          style={{
            background:
              'repeating-radial-gradient(circle at 50% 130%, transparent 0px, transparent 79px, rgba(164,193,143,0.07) 80px, transparent 81px)',
          }}
        />
        <Reveal className="relative max-w-2xl mx-auto px-5 md:px-8 py-24 md:py-32 text-center">
          <h2 className="font-display text-4xl md:text-5xl text-cream leading-tight mb-5">
            Start your first ring today.
          </h2>
          <p className="text-fog mb-10">
            Free to use. Your first meal is logged in under a minute.
          </p>
          <Link
            href={appHref}
            className="inline-block bg-moss-400 hover:bg-moss-300 text-bark-950 font-semibold px-9 py-4 rounded-xl transition-colors"
          >
            {user ? 'Open Grove' : 'Start free'}
          </Link>
        </Reveal>
      </section>

      {/* footer */}
      <footer className="border-t border-white/[0.06]">
        <div className="max-w-6xl mx-auto px-5 md:px-8 py-12 flex flex-col sm:flex-row items-center justify-between gap-4">
          <div>
            <p className="font-display text-cream tracking-[0.25em] uppercase">Grove</p>
            <p className="text-sm text-fog-dim mt-1.5">Feel good, inside and out.</p>
          </div>
          <p className="font-mono text-[11px] text-fog-dim">© 2026 Grove</p>
        </div>
      </footer>
    </div>
  )
}
