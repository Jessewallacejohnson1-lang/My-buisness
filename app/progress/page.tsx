'use client'

import { useState, useEffect, useCallback } from 'react'
import {
  getDailyStats,
  getWeightLogs,
  getLatestWeight,
  addWeightLog,
  getWorkoutHistory,
  getProfile,
  type DayStat,
  type WeightLog,
  type Workout,
} from '@/lib/db'
import type { Profile } from '@/lib/profile'
import { haptic } from '@/lib/haptics'
import AppShell from '../components/AppShell'
import { useCountUp } from '../components/GrowthRings'
import { IconAlert, IconScale, IconCheck } from '../components/Icons'

const RANGES = [
  { days: 7, label: '7d' },
  { days: 30, label: '30d' },
  { days: 90, label: '90d' },
] as const

function scoreColor(score: number) {
  if (score >= 70) return 'var(--color-moss-700)'
  if (score >= 40) return 'var(--color-honey-600)'
  return 'var(--color-clay-700)'
}

function Card({
  children,
  className = '',
  delay = 0,
}: {
  children: React.ReactNode
  className?: string
  delay?: number
}) {
  return (
    <section
      className={`rise bg-paper-50 border border-black/[0.07] rounded-2xl p-5 ${className}`}
      style={{ animationDelay: `${delay}ms` }}
    >
      {children}
    </section>
  )
}

function Eyebrow({ children, right }: { children: React.ReactNode; right?: React.ReactNode }) {
  return (
    <div className="flex items-center justify-between mb-4">
      <p className="text-[11px] uppercase tracking-[0.18em] text-ink-2">{children}</p>
      {right}
    </div>
  )
}

/** Smooth area + line chart over a series of values; nulls leave gaps. */
function Sparkline({
  values,
  color,
  goal,
  height = 96,
  unit = '',
}: {
  values: (number | null)[]
  color: string
  goal?: number
  height?: number
  unit?: string
}) {
  const present = values.filter((v): v is number => v != null)
  if (present.length < 2) {
    return (
      <div
        className="flex items-center justify-center text-xs text-ink-3"
        style={{ height }}
      >
        Not enough data yet — keep logging.
      </div>
    )
  }
  const W = 300
  const H = height
  const pad = 6
  const max = Math.max(...present, goal ?? 0) * 1.08 || 1
  const min = Math.min(...present, goal ?? Infinity) * 0.96
  const span = max - min || 1
  const x = (i: number) => pad + (i / (values.length - 1)) * (W - pad * 2)
  const y = (v: number) => H - pad - ((v - min) / span) * (H - pad * 2)

  const pts = values
    .map((v, i) => (v == null ? null : `${x(i)},${y(v)}`))
    .filter(Boolean)
    .join(' ')
  const first = values.findIndex((v) => v != null)
  const last = values.length - 1 - [...values].reverse().findIndex((v) => v != null)
  const area = `M ${x(first)},${H - pad} L ${pts.replaceAll(' ', ' L ')} L ${x(last)},${H - pad} Z`
  const gid = `g-${color.replace(/[^a-z]/gi, '')}`

  return (
    <svg viewBox={`0 0 ${W} ${H}`} width="100%" height={H} preserveAspectRatio="none" aria-hidden>
      <defs>
        <linearGradient id={gid} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0%" stopColor={color} stopOpacity="0.18" />
          <stop offset="100%" stopColor={color} stopOpacity="0" />
        </linearGradient>
      </defs>
      {goal != null && (
        <line
          x1={pad}
          x2={W - pad}
          y1={y(goal)}
          y2={y(goal)}
          stroke="var(--color-ink-3)"
          strokeWidth="1"
          strokeDasharray="3 4"
          opacity="0.6"
        />
      )}
      <path d={area} fill={`url(#${gid})`} />
      <polyline
        points={pts}
        fill="none"
        stroke={color}
        strokeWidth="2"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
      {values.map((v, i) =>
        v == null ? null : i === last ? (
          <circle key={i} cx={x(i)} cy={y(v)} r="3" fill={color} />
        ) : null
      )}
      {unit && null}
    </svg>
  )
}

function Skeleton() {
  return (
    <div className="max-w-5xl mx-auto px-5 md:px-8 pt-6 md:pt-10">
      <div className="h-9 w-48 bg-paper-100 rounded-lg animate-pulse mb-8" />
      <div className="grid grid-cols-2 lg:grid-cols-12 gap-3 md:gap-4">
        <div className="col-span-2 lg:col-span-7 h-64 bg-paper-50 border border-black/[0.07] rounded-2xl animate-pulse" />
        <div className="col-span-2 lg:col-span-5 h-64 bg-paper-50 border border-black/[0.07] rounded-2xl animate-pulse" />
        <div className="col-span-2 lg:col-span-6 h-48 bg-paper-50 border border-black/[0.07] rounded-2xl animate-pulse" />
        <div className="col-span-2 lg:col-span-6 h-48 bg-paper-50 border border-black/[0.07] rounded-2xl animate-pulse" />
      </div>
    </div>
  )
}

export default function ProgressPage() {
  const [range, setRange] = useState<number>(30)
  const [stats, setStats] = useState<DayStat[]>([])
  const [weights, setWeights] = useState<WeightLog[]>([])
  const [latest, setLatest] = useState<WeightLog | null>(null)
  const [workouts, setWorkouts] = useState<Workout[]>([])
  const [profile, setProfile] = useState<Profile | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  const [weightInput, setWeightInput] = useState('')
  const [savingWeight, setSavingWeight] = useState(false)
  const [weightSaved, setWeightSaved] = useState(false)

  const load = useCallback(async (days: number) => {
    try {
      const [s, w, lw, wh, prof] = await Promise.all([
        getDailyStats(days),
        getWeightLogs(days),
        getLatestWeight(),
        getWorkoutHistory(days),
        getProfile(),
      ])
      setStats(s)
      setWeights(w)
      setLatest(lw)
      setWorkouts(wh)
      setProfile(prof)
    } catch (err) {
      const e = err as { code?: string; message?: string }
      setError(
        e.code === '42P01'
          ? 'The progress tables aren’t set up yet. Run supabase/migration-progress.sql in the Supabase SQL editor, then reload.'
          : e.message || 'Couldn’t load your progress. Reload to try again.'
      )
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect
    load(range)
  }, [load, range])

  const saveWeight = async (e: React.FormEvent) => {
    e.preventDefault()
    const kg = parseFloat(weightInput)
    if (!kg || kg <= 0) return
    setSavingWeight(true)
    haptic('tap')
    try {
      await addWeightLog(kg)
      setWeightInput('')
      setWeightSaved(true)
      haptic('success')
      setTimeout(() => setWeightSaved(false), 1800)
      await load(range)
    } catch {
      haptic('error')
    } finally {
      setSavingWeight(false)
    }
  }

  // ---- derived series ---------------------------------------------------
  const calSeries = stats.map((d) => (d.count > 0 ? d.calories : null))
  const scoreSeries = stats.map((d) => (d.count > 0 ? d.score : null))
  const proteinSeries = stats.map((d) => (d.count > 0 ? Math.round(d.protein) : null))

  const goalCal = profile?.goal_calories ?? 2100
  const goalProtein = profile?.goal_protein ?? 140

  const loggedDays = stats.filter((d) => d.count > 0)
  const avgCal = loggedDays.length
    ? Math.round(loggedDays.reduce((s, d) => s + d.calories, 0) / loggedDays.length)
    : 0
  const avgScore = loggedDays.length
    ? Math.round(loggedDays.reduce((s, d) => s + d.score, 0) / loggedDays.length)
    : 0
  const proteinHitRate = loggedDays.length
    ? Math.round(
        (loggedDays.filter((d) => d.protein >= goalProtein * 0.9).length / loggedDays.length) * 100
      )
    : 0

  // weight: aligned to the date axis so gaps show honestly
  const weightByDate = new Map(weights.map((w) => [w.date, w.weight_kg]))
  const weightSeries = stats.map((d) => weightByDate.get(d.date) ?? null)
  const firstWeight = weights[0]?.weight_kg
  const lastWeight = weights[weights.length - 1]?.weight_kg ?? latest?.weight_kg
  const weightDelta =
    firstWeight != null && lastWeight != null ? +(lastWeight - firstWeight).toFixed(1) : null
  const latestWeightAnimated = useCountUp(loading ? 0 : Math.round(lastWeight ?? 0))

  // training: sessions completed per day
  const completedByDate = new Map<string, number>()
  workouts.forEach((w) => {
    if (w.completed) completedByDate.set(w.date, (completedByDate.get(w.date) ?? 0) + 1)
  })
  const totalSessions = [...completedByDate.values()].reduce((s, n) => s + n, 0)
  const weeksInRange = Math.max(1, Math.round(range / 7))
  const perWeek = (totalSessions / weeksInRange).toFixed(1)

  // personal records: heaviest weight ever recorded per exercise (completed sessions)
  const prs = new Map<string, number>()
  workouts.forEach((w) => {
    if (!w.completed) return
    w.exercises.forEach((ex) => {
      if (ex.weight && ex.weight > (prs.get(ex.name) ?? 0)) prs.set(ex.name, ex.weight)
    })
  })
  const prList = [...prs.entries()].sort((a, b) => b[1] - a[1]).slice(0, 6)

  if (loading) {
    return (
      <AppShell>
        <Skeleton />
      </AppShell>
    )
  }

  if (error) {
    return (
      <AppShell>
        <div className="max-w-md mx-auto px-5 pt-16 text-center">
          <div className="mx-auto mb-5 w-12 h-12 rounded-full bg-clay-700/10 border border-clay-700/20 flex items-center justify-center">
            <IconAlert className="w-5 h-5 text-clay-700" />
          </div>
          <h1 className="font-display text-2xl text-ink mb-2">Progress needs setup</h1>
          <p className="text-sm text-ink-2 leading-relaxed mb-6">{error}</p>
          <button
            onClick={() => window.location.reload()}
            className="bg-moss-700 hover:bg-moss-800 text-white font-semibold px-6 py-3 rounded-xl text-sm transition-colors"
          >
            Reload
          </button>
        </div>
      </AppShell>
    )
  }

  return (
    <AppShell>
      <div className="max-w-5xl mx-auto px-5 md:px-8 pt-6 md:pt-10">
        <header className="rise mb-6 md:mb-8 flex items-end justify-between gap-4">
          <div>
            <h1 className="font-display text-3xl md:text-4xl text-ink">Progress</h1>
            <p className="text-sm text-ink-2 mt-2">
              The long view — is it actually working?
            </p>
          </div>
          <div className="flex gap-1 p-1 bg-paper-100 rounded-xl shrink-0">
            {RANGES.map((r) => (
              <button
                key={r.days}
                onClick={() => { if (range !== r.days) haptic('select'); setRange(r.days) }}
                className={`press px-3 py-1.5 rounded-lg text-xs font-mono tabular-nums transition-colors ${
                  range === r.days ? 'bg-paper text-ink shadow-sm' : 'text-ink-2 hover:text-ink'
                }`}
              >
                {r.label}
              </button>
            ))}
          </div>
        </header>

        <div className="grid grid-cols-2 lg:grid-cols-12 gap-3 md:gap-4">
          {/* Body weight */}
          <Card className="col-span-2 lg:col-span-7" delay={40}>
            <Eyebrow
              right={
                weightDelta != null ? (
                  <span
                    className={`font-mono text-xs tabular-nums ${
                      weightDelta < 0 ? 'text-moss-700' : weightDelta > 0 ? 'text-clay-700' : 'text-ink-2'
                    }`}
                  >
                    {weightDelta > 0 ? '+' : ''}
                    {weightDelta} kg
                  </span>
                ) : undefined
              }
            >
              Body weight
            </Eyebrow>
            <div className="flex items-baseline gap-2 mb-3">
              <span className="font-mono text-4xl text-ink tabular-nums">
                {lastWeight != null ? latestWeightAnimated : '—'}
              </span>
              {lastWeight != null && <span className="text-sm text-ink-2">kg</span>}
            </div>
            <Sparkline values={weightSeries} color="var(--color-sky-600)" />
            <form onSubmit={saveWeight} className="flex gap-2 mt-4 pt-4 border-t border-black/[0.07]">
              <div className="relative flex-1">
                <IconScale className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-ink-3" />
                <input
                  type="number"
                  step="0.1"
                  min="0"
                  inputMode="decimal"
                  value={weightInput}
                  onChange={(e) => setWeightInput(e.target.value)}
                  placeholder="Log today’s weight (kg)"
                  className="w-full bg-paper-100 border border-black/[0.08] rounded-xl pl-9 pr-4 py-2.5 text-sm text-ink placeholder:text-ink-3 focus:border-sky-600/50 focus:outline-none transition-colors"
                />
              </div>
              <button
                type="submit"
                disabled={savingWeight || !weightInput}
                className={`press px-4 py-2.5 rounded-xl text-sm font-semibold transition-colors disabled:opacity-50 ${
                  weightSaved
                    ? 'bg-moss-700 text-white'
                    : 'bg-moss-700 hover:bg-moss-800 text-white'
                }`}
              >
                {weightSaved ? <IconCheck className="pop w-4 h-4" strokeWidth={2.5} /> : savingWeight ? '…' : 'Log'}
              </button>
            </form>
          </Card>

          {/* Consistency stats */}
          <Card className="col-span-2 lg:col-span-5" delay={100}>
            <Eyebrow>Consistency</Eyebrow>
            <div className="grid grid-cols-2 gap-x-4 gap-y-5">
              {[
                { label: 'Days logged', value: `${loggedDays.length}`, sub: `of ${range}` },
                { label: 'Avg calories', value: avgCal ? avgCal.toLocaleString() : '—', sub: `goal ${goalCal.toLocaleString()}` },
                { label: 'Avg clean score', value: loggedDays.length ? `${avgScore}` : '—', sub: 'out of 100', color: loggedDays.length ? scoreColor(avgScore) : undefined },
                { label: 'Protein goal hit', value: loggedDays.length ? `${proteinHitRate}%` : '—', sub: 'of logged days' },
              ].map((s) => (
                <div key={s.label}>
                  <p
                    className="font-mono text-2xl tabular-nums leading-none"
                    style={{ color: s.color ?? 'var(--color-ink)' }}
                  >
                    {s.value}
                  </p>
                  <p className="text-xs text-ink-2 mt-1.5">{s.label}</p>
                  <p className="font-mono text-[10px] text-ink-3 tabular-nums">{s.sub}</p>
                </div>
              ))}
            </div>
          </Card>

          {/* Calories trend */}
          <Card className="col-span-2 lg:col-span-6" delay={160}>
            <Eyebrow
              right={<span className="font-mono text-[11px] text-ink-3 tabular-nums">goal {goalCal.toLocaleString()}</span>}
            >
              Calories
            </Eyebrow>
            <Sparkline values={calSeries} color="var(--color-honey-600)" goal={goalCal} />
          </Card>

          {/* Clean score trend */}
          <Card className="col-span-2 lg:col-span-6" delay={220}>
            <Eyebrow
              right={
                loggedDays.length ? (
                  <span className="font-mono text-[11px] tabular-nums" style={{ color: scoreColor(avgScore) }}>
                    avg {avgScore}
                  </span>
                ) : undefined
              }
            >
              Clean score
            </Eyebrow>
            <Sparkline values={scoreSeries} color={loggedDays.length ? scoreColor(avgScore) : 'var(--color-moss-700)'} goal={70} />
          </Card>

          {/* Protein trend */}
          <Card className="col-span-2 lg:col-span-6" delay={280}>
            <Eyebrow
              right={<span className="font-mono text-[11px] text-ink-3 tabular-nums">goal {goalProtein}g</span>}
            >
              Protein
            </Eyebrow>
            <Sparkline values={proteinSeries} color="var(--color-moss-700)" goal={goalProtein} />
          </Card>

          {/* Training frequency */}
          <Card className="col-span-2 lg:col-span-6" delay={340}>
            <Eyebrow
              right={<span className="font-mono text-[11px] text-ink-3 tabular-nums">{perWeek}/week</span>}
            >
              Training
            </Eyebrow>
            <div className="flex items-baseline gap-2 mb-4">
              <span className="font-mono text-4xl text-ink tabular-nums">{totalSessions}</span>
              <span className="text-sm text-ink-2">
                session{totalSessions !== 1 ? 's' : ''} in {range} days
              </span>
            </div>
            <div className="flex flex-wrap gap-1">
              {stats.map((d) => {
                const n = completedByDate.get(d.date) ?? 0
                return (
                  <span
                    key={d.date}
                    title={`${d.date}: ${n} session${n !== 1 ? 's' : ''}`}
                    className="h-3 flex-1 min-w-[6px] rounded-sm"
                    style={{
                      background:
                        n === 0
                          ? 'var(--color-paper-200)'
                          : `color-mix(in srgb, var(--color-moss-700) ${Math.min(100, 45 + n * 30)}%, transparent)`,
                    }}
                  />
                )
              })}
            </div>
          </Card>

          {/* Personal records */}
          {prList.length > 0 && (
            <Card className="col-span-2 lg:col-span-12" delay={400}>
              <Eyebrow>Personal records</Eyebrow>
              <div className="grid sm:grid-cols-2 lg:grid-cols-3 gap-x-6 gap-y-2.5">
                {prList.map(([name, weight]) => (
                  <div key={name} className="flex items-center justify-between gap-3 py-1">
                    <span className="text-sm text-ink truncate">{name}</span>
                    <span className="font-mono text-sm text-moss-700 tabular-nums shrink-0">
                      {weight} kg
                    </span>
                  </div>
                ))}
              </div>
              <p className="text-xs text-ink-3 mt-4 pt-3 border-t border-black/[0.07] leading-relaxed">
                Add weights to your exercises on the Train tab and they’ll show up here.
              </p>
            </Card>
          )}
        </div>
      </div>
    </AppShell>
  )
}
