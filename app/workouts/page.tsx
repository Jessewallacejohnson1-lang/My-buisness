'use client'

import Link from 'next/link'
import { useState, useEffect, useCallback } from 'react'
import { getWorkouts, addWorkout, deleteWorkout, toggleWorkoutComplete, type Workout } from '@/lib/db'

const TODAY = new Date().toISOString().split('T')[0]

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

  const load = useCallback(async () => {
    setLoading(true)
    try { setWorkouts(await getWorkouts(TODAY)) } finally { setLoading(false) }
  }, [])

  useEffect(() => { load() }, [load])

  const handleAddPreset = async (preset: typeof PRESET_WORKOUTS[0]) => {
    setAdding(true)
    try {
      await addWorkout({ ...preset, date: TODAY, completed: false })
      await load()
    } finally { setAdding(false) }
  }

  const handleAddCustom = async () => {
    if (!customName.trim()) return
    setAdding(true)
    try {
      await addWorkout({ name: customName.trim(), duration_min: parseInt(customDuration) || 30, exercises: [], date: TODAY, completed: false })
      setCustomName('')
      setCustomDuration('')
      setShowCustom(false)
      await load()
    } finally { setAdding(false) }
  }

  const dateLabel = new Date().toLocaleDateString('en-US', { weekday: 'long', month: 'short', day: 'numeric' })

  return (
    <div className="min-h-screen bg-stone-50" style={{ fontFamily: 'var(--font-nunito), sans-serif' }}>
      <nav className="flex items-center px-5 py-4 max-w-lg mx-auto">
        <Link href="/dashboard" className="text-stone-400 hover:text-stone-700 text-sm transition-colors">← Dashboard</Link>
        <span className="font-bold text-green-800 tracking-[0.2em] uppercase text-lg mx-auto pr-8">Grove</span>
      </nav>

      <div className="max-w-lg mx-auto px-5 pb-20">
        <p className="text-stone-400 text-sm mb-1">{dateLabel}</p>
        <h1 className="text-2xl text-stone-900 mb-6" style={{ fontFamily: 'var(--font-dm-serif), serif' }}>Workouts</h1>

        {/* Today's logged workouts */}
        {!loading && workouts.length > 0 && (
          <div className="mb-8">
            <p className="text-xs text-stone-400 uppercase tracking-widest mb-3">Logged today</p>
            <div className="space-y-2">
              {workouts.map(w => (
                <div key={w.id} className="bg-white rounded-2xl border border-stone-100 shadow-sm px-4 py-3 flex items-center gap-3">
                  <button
                    onClick={async () => { await toggleWorkoutComplete(w.id, !w.completed); await load() }}
                    className={`w-7 h-7 rounded-full border-2 flex items-center justify-center shrink-0 transition-colors ${w.completed ? 'bg-green-700 border-green-700' : 'border-stone-300 hover:border-green-500'}`}
                  >
                    {w.completed && <span className="text-white text-xs font-bold">✓</span>}
                  </button>
                  <div className="flex-1 min-w-0">
                    <p className={`font-semibold text-sm ${w.completed ? 'line-through text-stone-400' : 'text-stone-900'}`}>{w.name}</p>
                    <p className="text-stone-400 text-xs">{w.exercises.length > 0 ? `${w.exercises.length} exercises · ` : ''}{w.duration_min} min</p>
                  </div>
                  <button onClick={async () => { await deleteWorkout(w.id); await load() }} className="text-stone-300 hover:text-red-400 transition-colors text-lg leading-none">×</button>
                </div>
              ))}
            </div>
          </div>
        )}

        {/* Quick add presets */}
        <div className="mb-8">
          <p className="text-xs text-stone-400 uppercase tracking-widest mb-3">Quick add</p>
          <div className="space-y-2">
            {PRESET_WORKOUTS.map(p => (
              <button
                key={p.name}
                onClick={() => handleAddPreset(p)}
                disabled={adding || workouts.some(w => w.name === p.name)}
                className="w-full bg-white rounded-2xl border border-stone-100 shadow-sm px-4 py-3 flex items-center justify-between hover:border-green-600 transition-colors disabled:opacity-50 text-left"
              >
                <div>
                  <p className="font-semibold text-stone-900 text-sm">{p.name}</p>
                  <p className="text-stone-400 text-xs">{p.exercises.length} exercises · {p.duration_min} min</p>
                </div>
                <span className="text-green-700 text-lg shrink-0">
                  {workouts.some(w => w.name === p.name) ? '✓' : '+'}
                </span>
              </button>
            ))}
          </div>
        </div>

        {/* Custom workout */}
        <div>
          <p className="text-xs text-stone-400 uppercase tracking-widest mb-3">Custom</p>
          {!showCustom ? (
            <button
              onClick={() => setShowCustom(true)}
              className="w-full py-3 rounded-2xl border border-dashed border-stone-300 text-stone-400 text-sm hover:border-green-700 hover:text-green-700 transition-colors"
            >
              + Log a custom workout
            </button>
          ) : (
            <div className="bg-white rounded-2xl border border-stone-100 shadow-sm p-4 space-y-3">
              <input
                autoFocus
                value={customName}
                onChange={e => setCustomName(e.target.value)}
                placeholder="Workout name"
                className="w-full bg-stone-50 rounded-xl px-4 py-2.5 text-sm focus:outline-none focus:ring-2 focus:ring-green-700"
              />
              <input
                value={customDuration}
                onChange={e => setCustomDuration(e.target.value)}
                placeholder="Duration (minutes)"
                type="number"
                className="w-full bg-stone-50 rounded-xl px-4 py-2.5 text-sm focus:outline-none focus:ring-2 focus:ring-green-700"
              />
              <div className="flex gap-2">
                <button onClick={() => setShowCustom(false)} className="flex-1 py-2.5 rounded-xl border border-stone-200 text-stone-500 text-sm hover:bg-stone-50 transition-colors">Cancel</button>
                <button onClick={handleAddCustom} disabled={!customName.trim() || adding} className="flex-1 py-2.5 rounded-xl bg-green-800 text-white text-sm font-medium hover:bg-green-900 transition-colors disabled:opacity-50">
                  {adding ? 'Adding...' : 'Log workout'}
                </button>
              </div>
            </div>
          )}
        </div>
      </div>
    </div>
  )
}
