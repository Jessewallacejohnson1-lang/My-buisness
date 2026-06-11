'use client'

import { useState, useEffect, useCallback } from 'react'
import {
  getWorkouts,
  addWorkout,
  deleteWorkout,
  toggleWorkoutComplete,
  localDate,
  type Workout,
} from '@/lib/db'
import AppShell from '../components/AppShell'
import { IconCheck, IconPlus, IconX } from '../components/Icons'

const PRESET_WORKOUTS = [
  { name: 'Upper Body Strength', duration_min: 45, exercises: [{ name: 'Bench Press', sets: 4, reps: 8, weight: 0 }, { name: 'Shoulder Press', sets: 3, reps: 10, weight: 0 }, { name: 'Lat Pulldown', sets: 3, reps: 12, weight: 0 }, { name: 'Bicep Curls', sets: 3, reps: 12, weight: 0 }] },
  { name: 'Lower Body Strength', duration_min: 50, exercises: [{ name: 'Squats', sets: 4, reps: 10, weight: 0 }, { name: 'Romanian Deadlift', sets: 3, reps: 10, weight: 0 }, { name: 'Leg Press', sets: 3, reps: 12, weight: 0 }, { name: 'Calf Raises', sets: 4, reps: 15, weight: 0 }] },
  { name: 'Full Body HIIT', duration_min: 30, exercises: [{ name: 'Burpees', sets: 3, reps: 15, weight: 0 }, { name: 'Jump Squats', sets: 3, reps: 20, weight: 0 }, { name: 'Mountain Climbers', sets: 3, reps: 30, weight: 0 }, { name: 'Push-ups', sets: 3, reps: 15, weight: 0 }] },
  { name: 'Yoga & Stretch', duration_min: 40, exercises: [{ name: 'Sun Salutation', sets: 5, reps: 1, weight: 0 }, { name: 'Hip Flexor Stretch', sets: 2, reps: 1, weight: 0 }, { name: 'Pigeon Pose', sets: 2, reps: 1, weight: 0 }] },
  { name: 'Cardio Run', duration_min: 35, exercises: [{ name: 'Warm-up walk', sets: 1, reps: 1, weight: 0 }, { name: 'Steady run', sets: 1, reps: 1, weight: 0 }, { name: 'Cool-down walk', sets: 1, reps: 1, weight: 0 }] },
]

export default function WorkoutsPage() {
  const [workouts, setWorkouts] = useState<Workout[]>([])
  const [loading, setLoading] = useState(true)
  const [showCustom, setShowCustom] = useState(false)
  const [customName, setCustomName] = useState('')
  const [customDuration, setCustomDuration] = useState('')
  const [adding, setAdding] = useState(false)

  const today = localDate()

  const load = useCallback(async () => {
    try {
      setWorkouts(await getWorkouts(localDate()))
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => {
    load()
  }, [load])

  const handleAddPreset = async (preset: (typeof PRESET_WORKOUTS)[0]) => {
    setAdding(true)
    try {
      await addWorkout({ ...preset, date: today, completed: false })
      await load()
    } finally {
      setAdding(false)
    }
  }

  const handleAddCustom = async () => {
    if (!customName.trim()) return
    setAdding(true)
    try {
      await addWorkout({
        name: customName.trim(),
        duration_min: parseInt(customDuration) || 30,
        exercises: [],
        date: today,
        completed: false,
      })
      setCustomName('')
      setCustomDuration('')
      setShowCustom(false)
      await load()
    } finally {
      setAdding(false)
    }
  }

  const handleToggle = async (w: Workout) => {
    setWorkouts((ws) => ws.map((x) => (x.id === w.id ? { ...x, completed: !w.completed } : x)))
    await toggleWorkoutComplete(w.id, !w.completed)
    load()
  }

  const handleDelete = async (id: string) => {
    setWorkouts((ws) => ws.filter((x) => x.id !== id))
    await deleteWorkout(id)
    load()
  }

  const done = workouts.filter((w) => w.completed).length

  return (
    <AppShell>
      <div className="max-w-lg md:max-w-2xl mx-auto px-5 md:px-8 pt-6 md:pt-10">
        <header className="rise mb-8 flex items-end justify-between">
          <div>
            <h1 className="font-display text-3xl text-ink">Train</h1>
            <p className="text-sm text-ink-2 mt-1.5">Tap a session to add it, tap the circle when done.</p>
            <p className="font-mono text-[11px] uppercase tracking-wider text-ink-2 mt-2">
              {new Date().toLocaleDateString('en-US', {
                weekday: 'long',
                month: 'long',
                day: 'numeric',
              })}
            </p>
          </div>
          {workouts.length > 0 && (
            <p className="font-mono text-sm text-ink-2 tabular-nums">
              <span className="text-ink">{done}</span>/{workouts.length} done
            </p>
          )}
        </header>

        {loading ? (
          <div className="space-y-3">
            {[0, 1, 2].map((i) => (
              <div
                key={i}
                className="h-16 bg-paper-50 border border-black/[0.07] rounded-2xl animate-pulse"
              />
            ))}
          </div>
        ) : (
          <>
            {workouts.length > 0 && (
              <section className="rise mb-9" style={{ animationDelay: '60ms' }}>
                <h2 className="text-[11px] uppercase tracking-[0.18em] text-ink-2 mb-3 px-0.5">
                  Logged today
                </h2>
                <div className="space-y-2">
                  {workouts.map((w) => (
                    <div
                      key={w.id}
                      className="bg-paper-50 border border-black/[0.07] rounded-2xl px-4 py-3.5 flex items-center gap-3.5"
                    >
                      <button
                        onClick={() => handleToggle(w)}
                        aria-label={w.completed ? `Mark ${w.name} incomplete` : `Mark ${w.name} complete`}
                        className={`w-7 h-7 rounded-full border flex items-center justify-center shrink-0 transition-colors ${
                          w.completed
                            ? 'bg-moss-700 border-moss-700 text-white'
                            : 'border-paper-300 hover:border-moss-600'
                        }`}
                      >
                        {w.completed && <IconCheck className="w-4 h-4" strokeWidth={2.5} />}
                      </button>
                      <div className="flex-1 min-w-0">
                        <p
                          className={`text-sm truncate ${
                            w.completed ? 'line-through text-ink-3' : 'text-ink'
                          }`}
                        >
                          {w.name}
                        </p>
                        <p className="font-mono text-[11px] text-ink-3 mt-0.5 tabular-nums">
                          {w.exercises.length > 0 ? `${w.exercises.length} exercises · ` : ''}
                          {w.duration_min} min
                        </p>
                      </div>
                      <button
                        onClick={() => handleDelete(w.id)}
                        aria-label={`Delete ${w.name}`}
                        className="text-ink-3 hover:text-clay-700 transition-colors p-1 -m-1"
                      >
                        <IconX className="w-4 h-4" />
                      </button>
                    </div>
                  ))}
                </div>
              </section>
            )}

            <section className="rise mb-9" style={{ animationDelay: '120ms' }}>
              <h2 className="text-[11px] uppercase tracking-[0.18em] text-ink-2 mb-3 px-0.5">
                Quick start
              </h2>
              <div className="space-y-2">
                {PRESET_WORKOUTS.map((p) => {
                  const logged = workouts.some((w) => w.name === p.name)
                  return (
                    <button
                      key={p.name}
                      onClick={() => handleAddPreset(p)}
                      disabled={adding || logged}
                      className="w-full bg-paper-50 border border-black/[0.07] rounded-2xl px-4 py-3.5 flex items-center justify-between gap-3 text-left hover:border-moss-700/30 transition-colors disabled:opacity-40 disabled:hover:border-black/[0.07]"
                    >
                      <div className="min-w-0">
                        <p className="text-sm text-ink truncate">{p.name}</p>
                        <p className="font-mono text-[11px] text-ink-3 mt-0.5 tabular-nums">
                          {p.exercises.length} exercises · {p.duration_min} min
                        </p>
                      </div>
                      {logged ? (
                        <IconCheck className="w-4 h-4 text-moss-700 shrink-0" />
                      ) : (
                        <IconPlus className="w-4 h-4 text-moss-700 shrink-0" />
                      )}
                    </button>
                  )
                })}
              </div>
            </section>

            <section className="rise pb-4" style={{ animationDelay: '180ms' }}>
              <h2 className="text-[11px] uppercase tracking-[0.18em] text-ink-2 mb-3 px-0.5">
                Custom
              </h2>
              {!showCustom ? (
                <button
                  onClick={() => setShowCustom(true)}
                  className="w-full flex items-center justify-center gap-2 py-3.5 rounded-2xl border border-dashed border-paper-300 text-ink-2 text-sm hover:border-moss-700/50 hover:text-moss-700 transition-colors"
                >
                  <IconPlus className="w-4 h-4" /> Log a custom session
                </button>
              ) : (
                <div className="bg-paper-50 border border-black/[0.07] rounded-2xl p-4 space-y-3">
                  <input
                    autoFocus
                    value={customName}
                    onChange={(e) => setCustomName(e.target.value)}
                    placeholder="Session name"
                    className="w-full bg-paper-100 border border-black/[0.08] rounded-xl px-4 py-3 text-sm text-ink placeholder:text-ink-3 focus:border-moss-700/50 focus:outline-none transition-colors"
                  />
                  <input
                    value={customDuration}
                    onChange={(e) => setCustomDuration(e.target.value)}
                    placeholder="Duration (minutes)"
                    type="number"
                    min={1}
                    className="w-full bg-paper-100 border border-black/[0.08] rounded-xl px-4 py-3 text-sm text-ink placeholder:text-ink-3 focus:border-moss-700/50 focus:outline-none transition-colors"
                  />
                  <div className="flex gap-2">
                    <button
                      onClick={() => setShowCustom(false)}
                      className="flex-1 py-3 rounded-xl border border-black/[0.08] text-ink-2 text-sm hover:text-ink hover:bg-paper-100 transition-colors"
                    >
                      Cancel
                    </button>
                    <button
                      onClick={handleAddCustom}
                      disabled={!customName.trim() || adding}
                      className="flex-1 py-3 rounded-xl bg-moss-700 hover:bg-moss-800 text-white text-sm font-semibold transition-colors disabled:opacity-50"
                    >
                      {adding ? 'Logging…' : 'Log session'}
                    </button>
                  </div>
                </div>
              )}
            </section>
          </>
        )}
      </div>
    </AppShell>
  )
}
