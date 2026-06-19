'use client'

import { useState, useEffect, useCallback } from 'react'
import {
  getWorkouts,
  addWorkout,
  deleteWorkout,
  toggleWorkoutComplete,
  updateWorkoutExercises,
  localDate,
  type Workout,
  type Exercise,
} from '@/lib/db'
import AppShell from '../components/AppShell'
import { IconAlert, IconCheck, IconChevronDown, IconPlus, IconX } from '../components/Icons'
import { haptic } from '@/lib/haptics'

const PRESET_WORKOUTS = [
  { name: 'Upper Body Strength', duration_min: 45, exercises: [{ name: 'Bench Press', sets: 4, reps: 8, weight: 0 }, { name: 'Shoulder Press', sets: 3, reps: 10, weight: 0 }, { name: 'Lat Pulldown', sets: 3, reps: 12, weight: 0 }, { name: 'Bicep Curls', sets: 3, reps: 12, weight: 0 }] },
  { name: 'Lower Body Strength', duration_min: 50, exercises: [{ name: 'Squats', sets: 4, reps: 10, weight: 0 }, { name: 'Romanian Deadlift', sets: 3, reps: 10, weight: 0 }, { name: 'Leg Press', sets: 3, reps: 12, weight: 0 }, { name: 'Calf Raises', sets: 4, reps: 15, weight: 0 }] },
  { name: 'Full Body HIIT', duration_min: 30, exercises: [{ name: 'Burpees', sets: 3, reps: 15, weight: 0 }, { name: 'Jump Squats', sets: 3, reps: 20, weight: 0 }, { name: 'Mountain Climbers', sets: 3, reps: 30, weight: 0 }, { name: 'Push-ups', sets: 3, reps: 15, weight: 0 }] },
  { name: 'Yoga & Stretch', duration_min: 40, exercises: [{ name: 'Sun Salutation', sets: 5, reps: 1, weight: 0 }, { name: 'Hip Flexor Stretch', sets: 2, reps: 1, weight: 0 }, { name: 'Pigeon Pose', sets: 2, reps: 1, weight: 0 }] },
  { name: 'Cardio Run', duration_min: 35, exercises: [{ name: 'Warm-up walk', sets: 1, reps: 1, weight: 0 }, { name: 'Steady run', sets: 1, reps: 1, weight: 0 }, { name: 'Cool-down walk', sets: 1, reps: 1, weight: 0 }] },
]

/** A logged session: completion toggle plus an expandable per-exercise weight/reps editor. */
function LoggedWorkout({
  workout,
  onToggle,
  onDelete,
  onSaveExercises,
}: {
  workout: Workout
  onToggle: (w: Workout) => void
  onDelete: (id: string) => void
  onSaveExercises: (id: string, exercises: Exercise[]) => void
}) {
  const [open, setOpen] = useState(false)
  const [draft, setDraft] = useState<Exercise[]>(workout.exercises)
  const hasExercises = workout.exercises.length > 0

  const update = (i: number, field: 'weight' | 'reps', value: string) => {
    const n = value === '' ? 0 : Math.max(0, parseFloat(value) || 0)
    setDraft((d) => d.map((ex, idx) => (idx === i ? { ...ex, [field]: n } : ex)))
  }

  const commit = () => {
    // Only persist if something actually changed.
    if (JSON.stringify(draft) !== JSON.stringify(workout.exercises)) {
      onSaveExercises(workout.id, draft)
    }
  }

  return (
    <div className="bg-paper-50 border border-black/[0.07] rounded-2xl overflow-hidden">
      <div className="px-4 py-3.5 flex items-center gap-3.5">
        <button
          onClick={() => onToggle(workout)}
          aria-label={workout.completed ? `Mark ${workout.name} incomplete` : `Mark ${workout.name} complete`}
          className={`press w-7 h-7 rounded-full border flex items-center justify-center shrink-0 transition-colors ${
            workout.completed
              ? 'bg-moss-700 border-moss-700 text-white'
              : 'border-paper-300 hover:border-moss-600'
          }`}
        >
          {workout.completed && <IconCheck className="pop w-4 h-4" strokeWidth={2.5} />}
        </button>
        <button
          onClick={() => { if (hasExercises) { haptic('select'); setOpen((o) => !o) } }}
          disabled={!hasExercises}
          aria-expanded={hasExercises ? open : undefined}
          className="flex-1 min-w-0 text-left"
        >
          <p className={`text-sm truncate ${workout.completed ? 'line-through text-ink-3' : 'text-ink'}`}>
            {workout.name}
          </p>
          <p className="font-mono text-[11px] text-ink-3 mt-0.5 tabular-nums">
            {hasExercises ? `${workout.exercises.length} exercises · ` : ''}
            {workout.duration_min} min
          </p>
        </button>
        {hasExercises && (
          <button
            onClick={() => { haptic('select'); setOpen((o) => !o) }}
            aria-label={open ? 'Hide exercises' : 'Edit exercises'}
            className="press text-ink-3 hover:text-ink transition-colors p-1"
          >
            <IconChevronDown className={`w-4 h-4 transition-transform ${open ? 'rotate-180' : ''}`} />
          </button>
        )}
        <button
          onClick={() => onDelete(workout.id)}
          aria-label={`Delete ${workout.name}`}
          className="press text-ink-3 hover:text-clay-700 transition-colors p-1 -m-1"
        >
          <IconX className="w-4 h-4" />
        </button>
      </div>
      {open && hasExercises && (
        <div className="px-4 pb-4 pt-1 border-t border-black/[0.07] space-y-2">
          <div className="grid grid-cols-[1fr_auto_auto] gap-x-3 items-center text-[10px] uppercase tracking-[0.14em] text-ink-3 pb-1">
            <span>Exercise</span>
            <span className="w-16 text-center">Weight kg</span>
            <span className="w-14 text-center">Reps</span>
          </div>
          {draft.map((ex, i) => (
            <div key={i} className="grid grid-cols-[1fr_auto_auto] gap-x-3 items-center">
              <span className="text-sm text-ink truncate">
                {ex.name}
                <span className="font-mono text-[11px] text-ink-3 ml-1.5">×{ex.sets}</span>
              </span>
              <input
                type="number"
                min="0"
                step="0.5"
                inputMode="decimal"
                value={ex.weight || ''}
                onChange={(e) => update(i, 'weight', e.target.value)}
                onBlur={commit}
                placeholder="—"
                className="w-16 bg-paper-100 border border-black/[0.08] rounded-lg px-2 py-1.5 text-sm text-ink text-center font-mono tabular-nums placeholder:text-ink-3 focus:border-moss-700/50 focus:outline-none transition-colors"
              />
              <input
                type="number"
                min="0"
                step="1"
                inputMode="numeric"
                value={ex.reps || ''}
                onChange={(e) => update(i, 'reps', e.target.value)}
                onBlur={commit}
                placeholder="—"
                className="w-14 bg-paper-100 border border-black/[0.08] rounded-lg px-2 py-1.5 text-sm text-ink text-center font-mono tabular-nums placeholder:text-ink-3 focus:border-moss-700/50 focus:outline-none transition-colors"
              />
            </div>
          ))}
          <p className="text-[11px] text-ink-3 pt-1 leading-relaxed">
            Log your working weight — your heaviest set shows up as a personal record on Progress.
          </p>
        </div>
      )}
    </div>
  )
}

export default function WorkoutsPage() {
  const [workouts, setWorkouts] = useState<Workout[]>([])
  const [loading, setLoading] = useState(true)
  const [showCustom, setShowCustom] = useState(false)
  const [customName, setCustomName] = useState('')
  const [customDuration, setCustomDuration] = useState('')
  const [adding, setAdding] = useState(false)
  const [actionError, setActionError] = useState<string | null>(null)

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
    haptic('tap')
    try {
      await addWorkout({ ...preset, date: today, completed: false })
      await load()
    } catch {
      haptic('error')
    } finally {
      setAdding(false)
    }
  }

  const handleAddCustom = async () => {
    if (!customName.trim()) return
    setAdding(true)
    haptic('tap')
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
    const snapshot = workouts
    const next = workouts.map((x) => (x.id === w.id ? { ...x, completed: !w.completed } : x))
    setActionError(null)
    setWorkouts(next)
    // Strong, celebratory buzz when this tap finishes the whole session.
    const justFinishedSession = !w.completed && next.every((x) => x.completed)
    haptic(justFinishedSession ? 'success' : !w.completed ? 'select' : 'tap')
    try {
      await toggleWorkoutComplete(w.id, !w.completed)
      load()
    } catch {
      setWorkouts(snapshot)
      setActionError("Couldn't update the workout. Check your connection.")
      haptic('error')
    }
  }

  const handleSaveExercises = async (id: string, exercises: Exercise[]) => {
    const snapshot = workouts
    setActionError(null)
    setWorkouts((ws) => ws.map((w) => (w.id === id ? { ...w, exercises } : w)))
    haptic('tap')
    try {
      await updateWorkoutExercises(id, exercises)
    } catch {
      setWorkouts(snapshot)
      setActionError("Couldn't save your exercise weights. Check your connection.")
      haptic('error')
    }
  }

  const handleDelete = async (id: string) => {
    const snapshot = workouts
    setActionError(null)
    setWorkouts((ws) => ws.filter((x) => x.id !== id))
    try {
      await deleteWorkout(id)
      load()
    } catch {
      setWorkouts(snapshot)
      setActionError("Couldn't remove the workout. Check your connection.")
    }
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

        {actionError && (
          <div className="rise flex items-start gap-2.5 text-sm text-clay-700 bg-clay-700/10 border border-clay-700/20 rounded-2xl px-4 py-3.5 mb-5 leading-relaxed">
            <IconAlert className="w-4 h-4 shrink-0 mt-0.5" />
            <span>{actionError}</span>
          </div>
        )}

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
                {done === workouts.length && workouts.length > 0 && (
                  <div className="bounce-in flex items-center gap-3 bg-moss-700/10 border border-moss-700/20 rounded-2xl px-4 py-3.5 mb-4">
                    <span className="w-7 h-7 rounded-full bg-moss-700 text-white flex items-center justify-center shrink-0">
                      <IconCheck className="w-4 h-4" strokeWidth={2.5} />
                    </span>
                    <div>
                      <p className="text-sm text-ink font-semibold">Session complete</p>
                      <p className="text-xs text-ink-2 mt-0.5">All {workouts.length} {workouts.length === 1 ? 'workout' : 'workouts'} done — great work today.</p>
                    </div>
                  </div>
                )}
                <h2 className="text-[11px] uppercase tracking-[0.18em] text-ink-2 mb-3 px-0.5">
                  Logged today
                </h2>
                <div className="space-y-2">
                  {workouts.map((w) => (
                    <LoggedWorkout
                      key={w.id}
                      workout={w}
                      onToggle={handleToggle}
                      onDelete={handleDelete}
                      onSaveExercises={handleSaveExercises}
                    />
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
                      className="press w-full bg-paper-50 border border-black/[0.07] rounded-2xl px-4 py-3.5 flex items-center justify-between gap-3 text-left hover:border-moss-700/30 transition-colors disabled:opacity-40 disabled:hover:border-black/[0.07]"
                    >
                      <div className="min-w-0">
                        <p className="text-sm text-ink truncate">{p.name}</p>
                        <p className="font-mono text-[11px] text-ink-3 mt-0.5 tabular-nums">
                          {p.exercises.length} exercises · {p.duration_min} min
                        </p>
                      </div>
                      {logged ? (
                        <IconCheck className="pop w-4 h-4 text-moss-700 shrink-0" />
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
                  onClick={() => { haptic('tap'); setShowCustom(true) }}
                  className="press w-full flex items-center justify-center gap-2 py-3.5 rounded-2xl border border-dashed border-paper-300 text-ink-2 text-sm hover:border-moss-700/50 hover:text-moss-700 transition-colors"
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
                      className="press flex-1 py-3 rounded-xl border border-black/[0.08] text-ink-2 text-sm hover:text-ink hover:bg-paper-100 transition-colors"
                    >
                      Cancel
                    </button>
                    <button
                      onClick={handleAddCustom}
                      disabled={!customName.trim() || adding}
                      className="press flex-1 py-3 rounded-xl bg-moss-700 hover:bg-moss-800 text-white text-sm font-semibold transition-colors disabled:opacity-50"
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
