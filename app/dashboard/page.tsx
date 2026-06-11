'use client'

import Link from 'next/link'
import { useState, useEffect, useCallback } from 'react'
import { getFoodLogs, getWorkouts, getStreak, getWeeklyCalories, toggleWorkoutComplete, type FoodLog, type Workout } from '@/lib/db'

const TODAY = new Date().toISOString().split('T')[0]
const GOAL_CAL = 2100
const GOAL_PROTEIN = 140
const GOAL_CARBS = 210
const GOAL_FAT = 70

function scoreColor(score: number) {
  if (score >= 70) return { stroke: '#166534', text: 'text-green-800' }
  if (score >= 40) return { stroke: '#b45309', text: 'text-amber-700' }
  return { stroke: '#b91c1c', text: 'text-red-700' }
}

function ScoreArc({ score }: { score: number }) {
  const r = 54
  const circ = 2 * Math.PI * r
  const filled = (score / 100) * circ * 0.75
  const { stroke } = scoreColor(score)
  return (
    <svg viewBox="0 0 130 100" className="w-full max-w-[160px]">
      <circle cx="65" cy="72" r={r} fill="none" stroke="#e7e5e4" strokeWidth="10"
        strokeDasharray={`${circ * 0.75} ${circ * 0.25}`}
        strokeDashoffset={circ * 0.125} strokeLinecap="round" />
      <circle cx="65" cy="72" r={r} fill="none" stroke={stroke} strokeWidth="10"
        strokeDasharray={`${filled} ${circ - filled + circ * 0.25}`}
        strokeDashoffset={circ * 0.125} strokeLinecap="round" />
      <text x="65" y="68" textAnchor="middle" fontSize="26" fontWeight="700" fill="#1c1917">{score}</text>
      <text x="65" y="84" textAnchor="middle" fontSize="9" fill="#a8a29e" letterSpacing="1">OUT OF 100</text>
    </svg>
  )
}

function MiniBar({ value, goal, color }: { value: number; goal: number; color: string }) {
  return (
    <div className="h-1.5 bg-stone-100 rounded-full overflow-hidden">
      <div className={`h-full rounded-full ${color}`} style={{ width: `${Math.min(100, (value / goal) * 100)}%` }} />
    </div>
  )
}

export default function DashboardPage() {
  const [logs, setLogs] = useState<FoodLog[]>([])
  const [workouts, setWorkouts] = useState<Workout[]>([])
  const [streak, setStreak] = useState(0)
  const [weekCals, setWeekCals] = useState<{ date: string; total: number }[]>([])
  const [loading, setLoading] = useState(true)

  const load = useCallback(async () => {
    setLoading(true)
    try {
      const [foodLogs, todayWorkouts, streakCount, weekly] = await Promise.all([
        getFoodLogs(TODAY),
        getWorkouts(TODAY),
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

  useEffect(() => { load() }, [load])

  const handleToggleWorkout = async (id: string, completed: boolean) => {
    await toggleWorkoutComplete(id, !completed)
    await load()
  }

  const totalCal = logs.reduce((s, f) => s + f.calories, 0)
  const totalProtein = logs.reduce((s, f) => s + f.protein, 0)
  const totalCarbs = logs.reduce((s, f) => s + f.carbs, 0)
  const totalFat = logs.reduce((s, f) => s + f.fat, 0)
  const totalFibre = logs.reduce((s, f) => s + f.fibre, 0)
  const avgScore = logs.length ? Math.round(logs.reduce((s, f) => s + f.score, 0) / logs.length) : 0

  const cleanCount = logs.filter(f => f.score >= 70).length
  const moderateCount = logs.filter(f => f.score >= 40 && f.score < 70).length
  const avoidCount = logs.filter(f => f.score < 40).length
  const avoidItems = logs.filter(f => f.score < 40).map(f => f.food_name)

  const maxWeekCal = Math.max(...weekCals.map(d => d.total), GOAL_CAL)
  const weekLabels = weekCals.map(d => new Date(d.date + 'T12:00:00').toLocaleDateString('en-US', { weekday: 'narrow' }))
  const avgWeekCal = weekCals.filter(d => d.total > 0).reduce((s, d) => s + d.total, 0) / (weekCals.filter(d => d.total > 0).length || 1)

  const dateLabel = new Date().toLocaleDateString('en-US', { weekday: 'long', month: 'short', day: 'numeric' })

  if (loading) {
    return (
      <div className="min-h-screen bg-stone-100 flex items-center justify-center" style={{ fontFamily: 'var(--font-nunito), sans-serif' }}>
        <p className="text-stone-400 text-sm">Loading your stats...</p>
      </div>
    )
  }

  return (
    <div className="min-h-screen bg-stone-100" style={{ fontFamily: 'var(--font-nunito), sans-serif' }}>
      <nav className="flex items-center justify-between px-5 py-4 max-w-2xl mx-auto">
        <Link href="/" className="font-bold text-green-800 tracking-[0.2em] uppercase text-lg">Grove</Link>
        <p className="text-stone-400 text-sm">{dateLabel}</p>
      </nav>

      <div className="max-w-2xl mx-auto px-4 pb-16">
        <div className="mb-5">
          <h1 className="text-2xl text-stone-900" style={{ fontFamily: 'var(--font-dm-serif), serif' }}>Your stats</h1>
          <p className="text-stone-400 text-sm">{logs.length === 0 ? 'Nothing logged yet today — add some food!' : `${logs.length} food${logs.length !== 1 ? 's' : ''} logged today`}</p>
        </div>

        <div className="grid grid-cols-2 gap-3">

          {/* Clean score */}
          <div className="col-span-2 bg-white rounded-3xl p-5 shadow-sm border border-stone-100 flex items-center gap-6">
            <div className="shrink-0">
              <ScoreArc score={avgScore || 0} />
            </div>
            <div className="flex-1">
              <p className="text-xs text-stone-400 uppercase tracking-widest mb-1">Today&apos;s clean score</p>
              {logs.length === 0 ? (
                <p className="text-stone-500 text-sm">Log your first meal to get a score</p>
              ) : (
                <>
                  <p className="text-stone-800 font-semibold text-sm mb-3">
                    {avgScore >= 80 ? 'Great — very clean day' : avgScore >= 60 ? 'Good — mostly clean' : avgScore >= 40 ? 'OK — a few things to watch' : 'Needs work — several flags'}
                  </p>
                  <div className="space-y-2">
                    {cleanCount > 0 && <div className="flex items-center gap-2 text-xs"><span className="w-2 h-2 rounded-full bg-green-700 shrink-0" /><span className="text-stone-500">{cleanCount} clean food{cleanCount !== 1 ? 's' : ''}</span></div>}
                    {moderateCount > 0 && <div className="flex items-center gap-2 text-xs"><span className="w-2 h-2 rounded-full bg-amber-500 shrink-0" /><span className="text-stone-500">{moderateCount} moderate item{moderateCount !== 1 ? 's' : ''}</span></div>}
                    {avoidCount > 0 && <div className="flex items-center gap-2 text-xs"><span className="w-2 h-2 rounded-full bg-red-500 shrink-0" /><span className="text-stone-500">{avoidCount} to avoid ({avoidItems.join(', ')})</span></div>}
                  </div>
                </>
              )}
            </div>
          </div>

          {/* Calories */}
          <div className="bg-green-800 text-white rounded-3xl p-5 shadow-sm flex flex-col justify-between min-h-[160px]">
            <p className="text-green-300 text-xs uppercase tracking-widest">Calories</p>
            <div>
              <p className="text-3xl font-bold">{totalCal.toLocaleString()}</p>
              <p className="text-green-300 text-xs mt-0.5">of {GOAL_CAL.toLocaleString()}</p>
              <div className="mt-3 h-1.5 bg-green-900 rounded-full overflow-hidden">
                <div className="h-full bg-green-400 rounded-full transition-all" style={{ width: `${Math.min(100, (totalCal / GOAL_CAL) * 100)}%` }} />
              </div>
              <p className="text-green-300 text-xs mt-1.5">{Math.max(0, GOAL_CAL - totalCal).toLocaleString()} remaining</p>
            </div>
          </div>

          {/* Streak */}
          <div className="bg-amber-50 rounded-3xl p-5 shadow-sm border border-amber-100 flex flex-col justify-between min-h-[160px]">
            <p className="text-amber-700 text-xs uppercase tracking-widest">Streak</p>
            <div>
              <p className="text-5xl font-bold text-amber-600">{streak}</p>
              <p className="text-amber-700 text-xs mt-1">{streak === 1 ? 'day' : 'days'} in a row {streak >= 7 ? '🔥' : '⭐'}</p>
              {streak === 0 && <p className="text-amber-500 text-xs mt-2">Log food today to start!</p>}
            </div>
          </div>

          {/* Macros */}
          <div className="col-span-2 bg-white rounded-3xl p-5 shadow-sm border border-stone-100">
            <p className="text-xs text-stone-400 uppercase tracking-widest mb-4">Macros today</p>
            <div className="space-y-3.5">
              {[
                { label: 'Protein', value: totalProtein, goal: GOAL_PROTEIN, unit: 'g', color: 'bg-amber-400' },
                { label: 'Carbs', value: totalCarbs, goal: GOAL_CARBS, unit: 'g', color: 'bg-orange-400' },
                { label: 'Fat', value: totalFat, goal: GOAL_FAT, unit: 'g', color: 'bg-green-500' },
                { label: 'Fibre', value: totalFibre, goal: 30, unit: 'g', color: 'bg-teal-400' },
              ].map((m) => (
                <div key={m.label}>
                  <div className="flex justify-between text-sm mb-1.5">
                    <span className="text-stone-600 font-medium">{m.label}</span>
                    <span className="text-stone-400">{Math.round(m.value)}{m.unit} <span className="text-stone-300">/ {m.goal}{m.unit}</span></span>
                  </div>
                  <MiniBar value={m.value} goal={m.goal} color={m.color} />
                </div>
              ))}
            </div>
          </div>

          {/* Weekly chart */}
          <div className="col-span-2 bg-white rounded-3xl p-5 shadow-sm border border-stone-100">
            <p className="text-xs text-stone-400 uppercase tracking-widest mb-4">This week</p>
            <div className="flex items-end gap-2 h-24">
              {weekCals.map((d, i) => {
                const isToday = d.date === TODAY
                const pct = d.total ? Math.max(6, (d.total / maxWeekCal) * 100) : 4
                return (
                  <div key={i} className="flex-1 flex flex-col items-center gap-1.5">
                    {d.total > 0 && (
                      <span className="text-xs text-stone-400" style={{ fontSize: 9 }}>{d.total.toLocaleString()}</span>
                    )}
                    <div className="w-full rounded-lg transition-all"
                      style={{ height: `${pct}%`, minHeight: 6, background: d.total === 0 ? '#f5f5f4' : isToday ? '#166534' : '#bbf7d0' }} />
                    <span className={`text-xs ${isToday ? 'font-bold text-green-800' : 'text-stone-400'}`}>{weekLabels[i]}</span>
                  </div>
                )
              })}
            </div>
            <div className="flex justify-between mt-3 text-xs text-stone-400">
              <span>Avg: {Math.round(avgWeekCal).toLocaleString()} cal</span>
              <span>Goal: {GOAL_CAL.toLocaleString()} cal</span>
            </div>
          </div>

          {/* Workouts */}
          <div className="col-span-2 bg-stone-900 text-white rounded-3xl p-5 shadow-sm">
            <div className="flex items-center justify-between mb-4">
              <p className="text-stone-400 text-xs uppercase tracking-widest">Today&apos;s workouts</p>
              <Link href="/workouts" className="text-xs text-green-400 hover:text-green-300 transition-colors">+ Add</Link>
            </div>
            {workouts.length === 0 ? (
              <div className="text-center py-4">
                <p className="text-stone-500 text-sm mb-3">No workouts logged yet</p>
                <Link href="/workouts" className="inline-block bg-green-700 hover:bg-green-600 text-white text-xs font-medium px-4 py-2 rounded-full transition-colors">
                  Log a workout
                </Link>
              </div>
            ) : (
              <div className="space-y-3">
                {workouts.map(w => (
                  <div key={w.id} className="flex items-center gap-3 bg-stone-800 rounded-2xl px-4 py-3">
                    <button
                      onClick={() => handleToggleWorkout(w.id, w.completed)}
                      className={`w-6 h-6 rounded-full border-2 flex items-center justify-center shrink-0 transition-colors ${w.completed ? 'bg-green-600 border-green-600' : 'border-stone-600'}`}
                    >
                      {w.completed && <span className="text-white text-xs">✓</span>}
                    </button>
                    <div className="flex-1 min-w-0">
                      <p className={`font-semibold text-sm ${w.completed ? 'line-through text-stone-500' : 'text-white'}`}>{w.name}</p>
                      <p className="text-stone-400 text-xs">{w.exercises.length} exercises · {w.duration_min} min</p>
                    </div>
                  </div>
                ))}
              </div>
            )}
          </div>

          {/* Quick links */}
          <Link href="/meal-log" className="bg-white rounded-3xl p-5 shadow-sm border border-stone-100 flex flex-col gap-2 hover:shadow-md transition-shadow">
            <span className="text-2xl">🥗</span>
            <p className="font-semibold text-stone-800 text-sm">Meal log</p>
            <p className="text-stone-400 text-xs">{logs.length} foods logged</p>
          </Link>

          <Link href="/scan" className="bg-white rounded-3xl p-5 shadow-sm border border-stone-100 flex flex-col gap-2 hover:shadow-md transition-shadow">
            <span className="text-2xl">📷</span>
            <p className="font-semibold text-stone-800 text-sm">Scan food</p>
            <p className="text-stone-400 text-xs">Add with barcode</p>
          </Link>

        </div>
      </div>
    </div>
  )
}
