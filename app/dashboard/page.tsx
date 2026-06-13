'use client'

import Link from 'next/link'
import { useRouter } from 'next/navigation'
import { useState, useEffect, useCallback } from 'react'
import {
  getFoodLogs,
  getWorkouts,
  getStreak,
  getWeeklyCalories,
  getProfile,
  toggleWorkoutComplete,
  localDate,
  type FoodLog,
  type Workout,
} from '@/lib/db'
import type { Profile } from '@/lib/profile'
import AppShell from '../components/AppShell'
import { GrowthRings, useCountUp } from '../components/GrowthRings'
import { IconAlert, IconBarcode, IconBowl, IconCheck, IconFlame, IconPlus } from '../components/Icons'

function ChecklistRow({
  done,
  label,
  href,
}: {
  done: boolean
  label: string
  href?: string
}) {
  const inner = (
    <>
      <span
        className={`w-6 h-6 rounded-full border flex items-center justify-center shrink-0 transition-colors ${
          done ? 'bg-moss-700 border-moss-700 text-white' : 'border-black/[0.15]'
        }`}
      >
        {done && <IconCheck className="w-3.5 h-3.5" strokeWidth={2.5} />}
      </span>
      <span className={`text-sm ${done ? 'text-ink-3 line-through' : 'text-ink'}`}>{label}</span>
      {!done && href && <span className="ml-auto text-moss-700 text-xs">Do it →</span>}
    </>
  )
  if (href && !done)
    return (
      <Link href={href} className="flex items-center gap-3 py-2 group">
        {inner}
      </Link>
    )
  return <div className="flex items-center gap-3 py-2">{inner}</div>
}

const DEFAULT_CAL = 2100
const DEFAULT_PROTEIN = 140
const DEFAULT_CARBS = 210
const DEFAULT_FAT = 70
const DEFAULT_FIBRE = 30

function scoreColor(score: number) {
  if (score >= 70) return 'var(--color-moss-700)'
  if (score >= 40) return 'var(--color-honey-600)'
  return 'var(--color-clay-700)'
}

function greeting() {
  const h = new Date().getHours()
  if (h < 12) return 'Good morning.'
  if (h < 18) return 'Good afternoon.'
  return 'Good evening.'
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

function Eyebrow({ children }: { children: React.ReactNode }) {
  return (
    <p className="text-[11px] uppercase tracking-[0.18em] text-ink-2 mb-4">{children}</p>
  )
}

function Skeleton() {
  return (
    <div className="max-w-5xl mx-auto px-5 md:px-8 pt-6 md:pt-10">
      <div className="h-9 w-56 bg-paper-100 rounded-lg animate-pulse mb-8" />
      <div className="grid grid-cols-2 lg:grid-cols-12 gap-3 md:gap-4">
        <div className="col-span-2 lg:col-span-7 lg:row-span-2 h-80 bg-paper-50 border border-black/[0.07] rounded-2xl animate-pulse" />
        <div className="col-span-1 lg:col-span-5 h-36 bg-paper-50 border border-black/[0.07] rounded-2xl animate-pulse" />
        <div className="col-span-1 lg:col-span-5 h-36 bg-paper-50 border border-black/[0.07] rounded-2xl animate-pulse" />
        <div className="col-span-2 lg:col-span-7 h-48 bg-paper-50 border border-black/[0.07] rounded-2xl animate-pulse" />
        <div className="col-span-2 lg:col-span-5 h-48 bg-paper-50 border border-black/[0.07] rounded-2xl animate-pulse" />
      </div>
    </div>
  )
}

export default function DashboardPage() {
  const router = useRouter()
  const [logs, setLogs] = useState<FoodLog[]>([])
  const [workouts, setWorkouts] = useState<Workout[]>([])
  const [streak, setStreak] = useState(0)
  const [weekCals, setWeekCals] = useState<{ date: string; total: number }[]>([])
  const [profile, setProfile] = useState<Profile | null>(null)
  const [loading, setLoading] = useState(true)

  const today = localDate()

  const GOAL_CAL = profile?.goal_calories ?? DEFAULT_CAL
  const GOAL_PROTEIN = profile?.goal_protein ?? DEFAULT_PROTEIN
  const GOAL_CARBS = profile?.goal_carbs ?? DEFAULT_CARBS
  const GOAL_FAT = profile?.goal_fat ?? DEFAULT_FAT
  const GOAL_FIBRE = profile?.goal_fibre ?? DEFAULT_FIBRE

  const [needsOnboarding, setNeedsOnboarding] = useState(false)
  const [setupError, setSetupError] = useState<string | null>(null)

  const load = useCallback(async () => {
    // Fetch the profile on its own so we can tell "no profile yet" (→ onboarding)
    // apart from a real DB/setup error (→ show it, don't loop).
    let prof: Profile | null
    try {
      prof = await getProfile()
    } catch (err) {
      const e = err as { code?: string; message?: string }
      setSetupError(
        e.code === '42703' || e.code === '42P01'
          ? 'Your database is missing the latest changes. Re-run supabase/migration-profiles.sql in the Supabase SQL editor, then reload.'
          : e.message || 'Couldn’t reach the database. Check your connection and reload.'
      )
      setLoading(false)
      return
    }
    if (!prof) {
      setNeedsOnboarding(true)
      setLoading(false)
      return
    }
    try {
      const [foodLogs, todayWorkouts, streakCount, weekly] = await Promise.all([
        getFoodLogs(localDate()),
        getWorkouts(localDate()),
        getStreak(),
        getWeeklyCalories(),
      ])
      setProfile(prof)
      setLogs(foodLogs)
      setWorkouts(todayWorkouts)
      setStreak(streakCount)
      setWeekCals(weekly)
    } catch (err) {
      const e = err as { message?: string }
      setSetupError(e.message || 'Couldn’t load your data. Reload to try again.')
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => {
    // All state updates inside load() happen after awaits — nothing synchronous.
    // eslint-disable-next-line react-hooks/set-state-in-effect
    load()
  }, [load])

  useEffect(() => {
    if (needsOnboarding) router.push('/onboarding')
  }, [needsOnboarding, router])

  const handleToggleWorkout = async (id: string, completed: boolean) => {
    const snapshot = workouts
    setWorkouts((ws) => ws.map((w) => (w.id === id ? { ...w, completed: !completed } : w)))
    try {
      await toggleWorkoutComplete(id, !completed)
      load()
    } catch {
      setWorkouts(snapshot)
    }
  }

  const totalCal = logs.reduce((s, f) => s + f.calories, 0)
  const totalProtein = logs.reduce((s, f) => s + f.protein, 0)
  const totalCarbs = logs.reduce((s, f) => s + f.carbs, 0)
  const totalFat = logs.reduce((s, f) => s + f.fat, 0)
  const totalFibre = logs.reduce((s, f) => s + f.fibre, 0)
  const avgScore = logs.length
    ? Math.round(logs.reduce((s, f) => s + f.score, 0) / logs.length)
    : 0

  const calLeft = Math.max(0, GOAL_CAL - totalCal)
  const calLeftAnimated = useCountUp(loading ? 0 : calLeft)

  const maxWeekCal = Math.max(...weekCals.map((d) => d.total), GOAL_CAL)
  const weekLabels = weekCals.map((d) =>
    new Date(d.date + 'T12:00:00').toLocaleDateString('en-US', { weekday: 'narrow' })
  )
  const loggedDays = weekCals.filter((d) => d.total > 0).length
  const avgWeekCal =
    weekCals.filter((d) => d.total > 0).reduce((s, d) => s + d.total, 0) / (loggedDays || 1)

  const dateLabel = new Date().toLocaleDateString('en-US', {
    weekday: 'long',
    month: 'long',
    day: 'numeric',
  })

  if (loading) {
    return (
      <AppShell>
        <Skeleton />
      </AppShell>
    )
  }

  if (setupError) {
    return (
      <AppShell>
        <div className="max-w-md mx-auto px-5 pt-16 text-center">
          <div className="mx-auto mb-5 w-12 h-12 rounded-full bg-clay-700/10 border border-clay-700/20 flex items-center justify-center">
            <IconAlert className="w-5 h-5 text-clay-700" />
          </div>
          <h1 className="font-display text-2xl text-ink mb-2">Something needs setup</h1>
          <p className="text-sm text-ink-2 leading-relaxed mb-6">{setupError}</p>
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
        <header className="rise mb-6 md:mb-8 flex items-end justify-between">
          <div>
            <h1 className="font-display text-3xl md:text-4xl text-ink">{greeting()}</h1>
            <p className="font-mono text-[11px] uppercase tracking-wider text-ink-2 mt-2">
              {dateLabel}
              <Link href="/onboarding" className="ml-3 normal-case tracking-normal font-sans text-ink-3 hover:text-moss-700 transition-colors">
                Edit goals
              </Link>
            </p>
          </div>
          <p className="hidden md:block text-sm text-ink-2">
            {logs.length === 0
              ? 'Nothing logged yet'
              : `${logs.length} food${logs.length !== 1 ? 's' : ''} logged`}
          </p>
        </header>

        {/* Getting started — only while the account is brand new */}
        {loggedDays <= 1 && streak <= 1 && (
          <section className="rise bg-moss-700/[0.05] border border-moss-700/20 rounded-2xl p-5 mb-3 md:mb-4">
            <p className="text-[11px] uppercase tracking-[0.18em] text-moss-700 mb-2">
              Getting started
            </p>
            <ChecklistRow done label="Set your daily plan" />
            <ChecklistRow
              done={logs.length > 0 || loggedDays > 0}
              label="Log your first food — scan, photo, or search"
              href="/scan"
            />
            <ChecklistRow done={workouts.length > 0} label="Log a workout" href="/workouts" />
            <ChecklistRow done={streak >= 2} label="Come back tomorrow to start a streak" />
          </section>
        )}

        <div className="grid grid-cols-2 lg:grid-cols-12 gap-3 md:gap-4">
          {/* Daily rings */}
          <Card className="col-span-2 lg:col-span-7 lg:row-span-2" delay={40}>
            <Eyebrow>Today&apos;s rings</Eyebrow>
            <div className="flex flex-col sm:flex-row items-center gap-6 sm:gap-10 py-2">
              <GrowthRings
                size={210}
                rings={[
                  { pct: totalCal / GOAL_CAL, color: 'var(--color-honey-600)' },
                  { pct: totalProtein / GOAL_PROTEIN, color: 'var(--color-moss-700)' },
                  { pct: avgScore / 100, color: scoreColor(avgScore || 100) },
                ]}
              >
                <span className="font-mono text-4xl text-ink tabular-nums">
                  {calLeftAnimated.toLocaleString()}
                </span>
                <span className="text-[11px] uppercase tracking-[0.18em] text-ink-2 mt-1">
                  kcal left
                </span>
              </GrowthRings>

              <div className="w-full sm:flex-1 space-y-4">
                {[
                  {
                    label: 'Calories',
                    value: `${totalCal.toLocaleString()} / ${GOAL_CAL.toLocaleString()}`,
                    color: 'bg-honey-600',
                  },
                  {
                    label: 'Protein',
                    value: `${Math.round(totalProtein)}g / ${GOAL_PROTEIN}g`,
                    color: 'bg-moss-700',
                  },
                  {
                    label: 'Clean score',
                    value: logs.length ? `${avgScore} / 100` : '—',
                    color: avgScore >= 70 || !logs.length ? 'bg-moss-700' : avgScore >= 40 ? 'bg-honey-600' : 'bg-clay-700',
                  },
                ].map((row) => (
                  <div key={row.label} className="flex items-center justify-between gap-4">
                    <span className="flex items-center gap-2.5 text-sm text-ink-2">
                      <span className={`w-2 h-2 rounded-full ${row.color}`} />
                      {row.label}
                    </span>
                    <span className="font-mono text-sm text-ink tabular-nums">{row.value}</span>
                  </div>
                ))}
                {logs.length === 0 && (
                  <p className="text-sm text-ink-3 leading-relaxed pt-2">
                    Log your first food and the rings start to grow.
                  </p>
                )}
              </div>
            </div>
          </Card>

          {/* Streak */}
          <Card className="col-span-1 lg:col-span-5" delay={100}>
            <div className="flex items-start justify-between">
              <Eyebrow>Streak</Eyebrow>
              <IconFlame
                className={`w-5 h-5 ${streak > 0 ? 'text-honey-600' : 'text-ink-3'}`}
              />
            </div>
            <p className="font-mono text-4xl text-ink tabular-nums">{streak}</p>
            <p className="text-sm text-ink-2 mt-1">{streak === 1 ? 'day' : 'days'} in a row</p>
            <div className="flex gap-1.5 mt-4">
              {weekCals.map((d) => (
                <span
                  key={d.date}
                  className={`h-1.5 flex-1 rounded-full ${
                    d.total > 0 ? 'bg-moss-700' : 'bg-paper-200'
                  } ${d.date === today ? 'ring-1 ring-moss-700/40' : ''}`}
                  title={d.date}
                />
              ))}
            </div>
          </Card>

          {/* Macros */}
          <Card className="col-span-1 lg:col-span-5" delay={160}>
            <Eyebrow>Macros</Eyebrow>
            <div className="space-y-3">
              {[
                { label: 'Protein', value: totalProtein, goal: GOAL_PROTEIN, color: 'bg-moss-700' },
                { label: 'Carbs', value: totalCarbs, goal: GOAL_CARBS, color: 'bg-honey-600' },
                { label: 'Fat', value: totalFat, goal: GOAL_FAT, color: 'bg-clay-700' },
                { label: 'Fibre', value: totalFibre, goal: GOAL_FIBRE, color: 'bg-moss-400' },
              ].map((m) => (
                <div key={m.label}>
                  <div className="flex justify-between items-baseline mb-1">
                    <span className="text-xs text-ink-2">{m.label}</span>
                    <span className="font-mono text-[11px] text-ink-2 tabular-nums">
                      <span className="text-ink">{Math.round(m.value)}</span>/{m.goal}g
                    </span>
                  </div>
                  <div className="h-1 bg-paper-200 rounded-full overflow-hidden">
                    <div
                      className={`h-full rounded-full ${m.color} transition-all duration-700`}
                      style={{ width: `${Math.min(100, (m.value / m.goal) * 100)}%` }}
                    />
                  </div>
                </div>
              ))}
            </div>
          </Card>

          {/* This week */}
          <Card className="col-span-2 lg:col-span-7" delay={220}>
            <Eyebrow>This week</Eyebrow>
            <div className="flex items-end gap-2 h-28">
              {weekCals.map((d, i) => {
                const isToday = d.date === today
                const pct = d.total ? Math.max(8, (d.total / maxWeekCal) * 100) : 0
                return (
                  <div key={d.date} className="flex-1 flex flex-col items-center gap-2 h-full justify-end">
                    {d.total > 0 && (
                      <span className="font-mono text-[9px] text-ink-3 tabular-nums">
                        {d.total.toLocaleString()}
                      </span>
                    )}
                    <div
                      className={`w-full rounded-md transition-all duration-700 ${
                        d.total === 0
                          ? 'bg-paper-100 border border-black/[0.05]'
                          : isToday
                            ? 'bg-honey-600'
                            : 'bg-moss-500'
                      }`}
                      style={{ height: d.total === 0 ? 4 : `${pct}%` }}
                    />
                    <span
                      className={`text-[10px] ${isToday ? 'text-ink' : 'text-ink-3'}`}
                    >
                      {weekLabels[i]}
                    </span>
                  </div>
                )
              })}
            </div>
            <div className="flex justify-between mt-4 pt-3 border-t border-black/[0.07]">
              <span className="font-mono text-[11px] text-ink-2 tabular-nums">
                avg {Math.round(avgWeekCal).toLocaleString()} kcal
              </span>
              <span className="font-mono text-[11px] text-ink-3 tabular-nums">
                goal {GOAL_CAL.toLocaleString()} kcal
              </span>
            </div>
          </Card>

          {/* Today's training */}
          <Card className="col-span-2 lg:col-span-5" delay={280}>
            <div className="flex items-center justify-between mb-4">
              <p className="text-[11px] uppercase tracking-[0.18em] text-ink-2">Training</p>
              <Link
                href="/workouts"
                className="flex items-center gap-1 text-xs text-moss-700 hover:text-moss-400 transition-colors"
              >
                <IconPlus className="w-3.5 h-3.5" /> Add
              </Link>
            </div>
            {workouts.length === 0 ? (
              <div className="py-4">
                <p className="text-sm text-ink-3 mb-4">No session logged today.</p>
                <Link
                  href="/workouts"
                  className="inline-block bg-paper-100 hover:bg-paper-200 border border-black/[0.08] text-ink text-sm px-4 py-2.5 rounded-xl transition-colors"
                >
                  Start a workout
                </Link>
              </div>
            ) : (
              <ul className="space-y-2.5">
                {workouts.map((w) => (
                  <li key={w.id} className="flex items-center gap-3">
                    <button
                      onClick={() => handleToggleWorkout(w.id, w.completed)}
                      aria-label={w.completed ? `Mark ${w.name} incomplete` : `Mark ${w.name} complete`}
                      className={`w-6 h-6 rounded-full border flex items-center justify-center shrink-0 transition-colors ${
                        w.completed
                          ? 'bg-moss-700 border-moss-700 text-white'
                          : 'border-paper-300 hover:border-moss-600'
                      }`}
                    >
                      {w.completed && <IconCheck className="w-3.5 h-3.5" strokeWidth={2.5} />}
                    </button>
                    <div className="flex-1 min-w-0">
                      <p
                        className={`text-sm truncate ${
                          w.completed ? 'line-through text-ink-3' : 'text-ink'
                        }`}
                      >
                        {w.name}
                      </p>
                      <p className="font-mono text-[11px] text-ink-3 tabular-nums">
                        {w.exercises.length > 0 ? `${w.exercises.length} exercises · ` : ''}
                        {w.duration_min} min
                      </p>
                    </div>
                  </li>
                ))}
              </ul>
            )}
          </Card>

          {/* Quick actions — mobile only; desktop has the rail */}
          <Link
            href="/meal-log"
            className="rise md:hidden col-span-1 bg-paper-50 border border-black/[0.07] rounded-2xl p-5 hover:border-moss-700/30 transition-colors"
            style={{ animationDelay: '340ms' }}
          >
            <IconBowl className="w-5 h-5 text-moss-700 mb-3" />
            <p className="text-sm text-ink">Log a meal</p>
            <p className="font-mono text-[11px] text-ink-3 mt-0.5 tabular-nums">
              {logs.length} today
            </p>
          </Link>
          <Link
            href="/scan"
            className="rise md:hidden col-span-1 bg-paper-50 border border-black/[0.07] rounded-2xl p-5 hover:border-moss-700/30 transition-colors"
            style={{ animationDelay: '380ms' }}
          >
            <IconBarcode className="w-5 h-5 text-moss-700 mb-3" />
            <p className="text-sm text-ink">Scan a barcode</p>
            <p className="text-[11px] text-ink-3 mt-0.5">instant log</p>
          </Link>
        </div>
      </div>
    </AppShell>
  )
}
