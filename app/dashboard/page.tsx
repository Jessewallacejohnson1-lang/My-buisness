'use client'

import Link from 'next/link'
import { useState, useEffect, useCallback } from 'react'
import {
  getFoodLogs,
  getWorkouts,
  getStreak,
  getWeeklyCalories,
  toggleWorkoutComplete,
  localDate,
  type FoodLog,
  type Workout,
} from '@/lib/db'
import AppShell from '../components/AppShell'
import { GrowthRings, useCountUp } from '../components/GrowthRings'
import { IconBarcode, IconBowl, IconCheck, IconFlame, IconPlus } from '../components/Icons'

const GOAL_CAL = 2100
const GOAL_PROTEIN = 140
const GOAL_CARBS = 210
const GOAL_FAT = 70
const GOAL_FIBRE = 30

function scoreColor(score: number) {
  if (score >= 70) return 'var(--color-moss-400)'
  if (score >= 40) return 'var(--color-honey-400)'
  return 'var(--color-clay-400)'
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
      className={`rise bg-bark-900 border border-white/[0.06] rounded-2xl p-5 ${className}`}
      style={{ animationDelay: `${delay}ms` }}
    >
      {children}
    </section>
  )
}

function Eyebrow({ children }: { children: React.ReactNode }) {
  return (
    <p className="text-[11px] uppercase tracking-[0.18em] text-fog mb-4">{children}</p>
  )
}

function Skeleton() {
  return (
    <div className="max-w-5xl mx-auto px-5 md:px-8 pt-6 md:pt-10">
      <div className="h-9 w-56 bg-bark-800 rounded-lg animate-pulse mb-8" />
      <div className="grid grid-cols-2 lg:grid-cols-12 gap-3 md:gap-4">
        <div className="col-span-2 lg:col-span-7 lg:row-span-2 h-80 bg-bark-900 border border-white/[0.06] rounded-2xl animate-pulse" />
        <div className="col-span-1 lg:col-span-5 h-36 bg-bark-900 border border-white/[0.06] rounded-2xl animate-pulse" />
        <div className="col-span-1 lg:col-span-5 h-36 bg-bark-900 border border-white/[0.06] rounded-2xl animate-pulse" />
        <div className="col-span-2 lg:col-span-7 h-48 bg-bark-900 border border-white/[0.06] rounded-2xl animate-pulse" />
        <div className="col-span-2 lg:col-span-5 h-48 bg-bark-900 border border-white/[0.06] rounded-2xl animate-pulse" />
      </div>
    </div>
  )
}

export default function DashboardPage() {
  const [logs, setLogs] = useState<FoodLog[]>([])
  const [workouts, setWorkouts] = useState<Workout[]>([])
  const [streak, setStreak] = useState(0)
  const [weekCals, setWeekCals] = useState<{ date: string; total: number }[]>([])
  const [loading, setLoading] = useState(true)

  const today = localDate()

  const load = useCallback(async () => {
    try {
      const [foodLogs, todayWorkouts, streakCount, weekly] = await Promise.all([
        getFoodLogs(localDate()),
        getWorkouts(localDate()),
        getStreak(),
        getWeeklyCalories(),
      ])
      setLogs(foodLogs)
      setWorkouts(todayWorkouts)
      setStreak(streakCount)
      setWeekCals(weekly)
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => {
    load()
  }, [load])

  const handleToggleWorkout = async (id: string, completed: boolean) => {
    setWorkouts((ws) => ws.map((w) => (w.id === id ? { ...w, completed: !completed } : w)))
    await toggleWorkoutComplete(id, !completed)
    load()
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

  return (
    <AppShell>
      <div className="max-w-5xl mx-auto px-5 md:px-8 pt-6 md:pt-10">
        <header className="rise mb-6 md:mb-8 flex items-end justify-between">
          <div>
            <h1 className="font-display text-3xl md:text-4xl text-cream">{greeting()}</h1>
            <p className="font-mono text-[11px] uppercase tracking-wider text-fog mt-2">
              {dateLabel}
            </p>
          </div>
          <p className="hidden md:block text-sm text-fog">
            {logs.length === 0
              ? 'Nothing logged yet'
              : `${logs.length} food${logs.length !== 1 ? 's' : ''} logged`}
          </p>
        </header>

        <div className="grid grid-cols-2 lg:grid-cols-12 gap-3 md:gap-4">
          {/* Daily rings */}
          <Card className="col-span-2 lg:col-span-7 lg:row-span-2" delay={40}>
            <Eyebrow>Today&apos;s rings</Eyebrow>
            <div className="flex flex-col sm:flex-row items-center gap-6 sm:gap-10 py-2">
              <GrowthRings
                size={210}
                rings={[
                  { pct: totalCal / GOAL_CAL, color: 'var(--color-honey-400)' },
                  { pct: totalProtein / GOAL_PROTEIN, color: 'var(--color-moss-400)' },
                  { pct: avgScore / 100, color: scoreColor(avgScore || 100) },
                ]}
              >
                <span className="font-mono text-4xl text-cream tabular-nums">
                  {calLeftAnimated.toLocaleString()}
                </span>
                <span className="text-[11px] uppercase tracking-[0.18em] text-fog mt-1">
                  kcal left
                </span>
              </GrowthRings>

              <div className="w-full sm:flex-1 space-y-4">
                {[
                  {
                    label: 'Calories',
                    value: `${totalCal.toLocaleString()} / ${GOAL_CAL.toLocaleString()}`,
                    color: 'bg-honey-400',
                  },
                  {
                    label: 'Protein',
                    value: `${Math.round(totalProtein)}g / ${GOAL_PROTEIN}g`,
                    color: 'bg-moss-400',
                  },
                  {
                    label: 'Clean score',
                    value: logs.length ? `${avgScore} / 100` : '—',
                    color: avgScore >= 70 || !logs.length ? 'bg-moss-400' : avgScore >= 40 ? 'bg-honey-400' : 'bg-clay-400',
                  },
                ].map((row) => (
                  <div key={row.label} className="flex items-center justify-between gap-4">
                    <span className="flex items-center gap-2.5 text-sm text-fog">
                      <span className={`w-2 h-2 rounded-full ${row.color}`} />
                      {row.label}
                    </span>
                    <span className="font-mono text-sm text-cream tabular-nums">{row.value}</span>
                  </div>
                ))}
                {logs.length === 0 && (
                  <p className="text-sm text-fog-dim leading-relaxed pt-2">
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
                className={`w-5 h-5 ${streak > 0 ? 'text-honey-400' : 'text-fog-dim'}`}
              />
            </div>
            <p className="font-mono text-4xl text-cream tabular-nums">{streak}</p>
            <p className="text-sm text-fog mt-1">{streak === 1 ? 'day' : 'days'} in a row</p>
            <div className="flex gap-1.5 mt-4">
              {weekCals.map((d) => (
                <span
                  key={d.date}
                  className={`h-1.5 flex-1 rounded-full ${
                    d.total > 0 ? 'bg-moss-400' : 'bg-bark-700'
                  } ${d.date === today ? 'ring-1 ring-moss-300/40' : ''}`}
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
                { label: 'Protein', value: totalProtein, goal: GOAL_PROTEIN, color: 'bg-moss-400' },
                { label: 'Carbs', value: totalCarbs, goal: GOAL_CARBS, color: 'bg-honey-400' },
                { label: 'Fat', value: totalFat, goal: GOAL_FAT, color: 'bg-clay-300' },
                { label: 'Fibre', value: totalFibre, goal: GOAL_FIBRE, color: 'bg-moss-200' },
              ].map((m) => (
                <div key={m.label}>
                  <div className="flex justify-between items-baseline mb-1">
                    <span className="text-xs text-fog">{m.label}</span>
                    <span className="font-mono text-[11px] text-fog tabular-nums">
                      <span className="text-cream">{Math.round(m.value)}</span>/{m.goal}g
                    </span>
                  </div>
                  <div className="h-1 bg-bark-700 rounded-full overflow-hidden">
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
                      <span className="font-mono text-[9px] text-fog-dim tabular-nums">
                        {d.total.toLocaleString()}
                      </span>
                    )}
                    <div
                      className={`w-full rounded-md transition-all duration-700 ${
                        d.total === 0
                          ? 'bg-bark-800 border border-white/[0.04]'
                          : isToday
                            ? 'bg-honey-400'
                            : 'bg-moss-600'
                      }`}
                      style={{ height: d.total === 0 ? 4 : `${pct}%` }}
                    />
                    <span
                      className={`text-[10px] ${isToday ? 'text-cream' : 'text-fog-dim'}`}
                    >
                      {weekLabels[i]}
                    </span>
                  </div>
                )
              })}
            </div>
            <div className="flex justify-between mt-4 pt-3 border-t border-white/[0.06]">
              <span className="font-mono text-[11px] text-fog tabular-nums">
                avg {Math.round(avgWeekCal).toLocaleString()} kcal
              </span>
              <span className="font-mono text-[11px] text-fog-dim tabular-nums">
                goal {GOAL_CAL.toLocaleString()} kcal
              </span>
            </div>
          </Card>

          {/* Today's training */}
          <Card className="col-span-2 lg:col-span-5" delay={280}>
            <div className="flex items-center justify-between mb-4">
              <p className="text-[11px] uppercase tracking-[0.18em] text-fog">Training</p>
              <Link
                href="/workouts"
                className="flex items-center gap-1 text-xs text-moss-300 hover:text-moss-200 transition-colors"
              >
                <IconPlus className="w-3.5 h-3.5" /> Add
              </Link>
            </div>
            {workouts.length === 0 ? (
              <div className="py-4">
                <p className="text-sm text-fog-dim mb-4">No session logged today.</p>
                <Link
                  href="/workouts"
                  className="inline-block bg-bark-800 hover:bg-bark-700 border border-white/[0.07] text-cream text-sm px-4 py-2.5 rounded-xl transition-colors"
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
                          ? 'bg-moss-400 border-moss-400 text-bark-950'
                          : 'border-bark-600 hover:border-moss-500'
                      }`}
                    >
                      {w.completed && <IconCheck className="w-3.5 h-3.5" strokeWidth={2.5} />}
                    </button>
                    <div className="flex-1 min-w-0">
                      <p
                        className={`text-sm truncate ${
                          w.completed ? 'line-through text-fog-dim' : 'text-cream'
                        }`}
                      >
                        {w.name}
                      </p>
                      <p className="font-mono text-[11px] text-fog-dim tabular-nums">
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
            className="rise md:hidden col-span-1 bg-bark-900 border border-white/[0.06] rounded-2xl p-5 hover:border-moss-500/30 transition-colors"
            style={{ animationDelay: '340ms' }}
          >
            <IconBowl className="w-5 h-5 text-moss-400 mb-3" />
            <p className="text-sm text-cream">Log a meal</p>
            <p className="font-mono text-[11px] text-fog-dim mt-0.5 tabular-nums">
              {logs.length} today
            </p>
          </Link>
          <Link
            href="/scan"
            className="rise md:hidden col-span-1 bg-bark-900 border border-white/[0.06] rounded-2xl p-5 hover:border-moss-500/30 transition-colors"
            style={{ animationDelay: '380ms' }}
          >
            <IconBarcode className="w-5 h-5 text-moss-400 mb-3" />
            <p className="text-sm text-cream">Scan a barcode</p>
            <p className="text-[11px] text-fog-dim mt-0.5">instant log</p>
          </Link>
        </div>
      </div>
    </AppShell>
  )
}
