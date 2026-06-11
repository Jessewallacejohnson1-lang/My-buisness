'use client'

import Link from 'next/link'
import { useState, useEffect, useCallback } from 'react'
import { getFoodLogs, addFoodLog, deleteFoodLog, type FoodLog } from '@/lib/db'
import { searchFood, type FoodResult } from '@/lib/food-search'

const MEALS = ['Breakfast', 'Lunch', 'Dinner', 'Snacks'] as const
type Meal = typeof MEALS[number]

const MEAL_ICONS: Record<Meal, string> = {
  Breakfast: '🌅', Lunch: '☀️', Dinner: '🌙', Snacks: '🍃',
}

const TODAY = new Date().toISOString().split('T')[0]

function scoreColor(score: number) {
  if (score >= 70) return { stroke: '#166534', text: 'text-green-800', bg: 'bg-green-50' }
  if (score >= 40) return { stroke: '#b45309', text: 'text-amber-700', bg: 'bg-amber-50' }
  return { stroke: '#b91c1c', text: 'text-red-700', bg: 'bg-red-50' }
}

function ScoreRing({ score, size = 48 }: { score: number; size?: number }) {
  const { stroke, text } = scoreColor(score)
  const r = 15.9
  const circ = 2 * Math.PI * r
  const dash = (score / 100) * circ
  return (
    <div className="relative shrink-0" style={{ width: size, height: size }}>
      <svg viewBox="0 0 36 36" width={size} height={size} className="-rotate-90">
        <circle cx="18" cy="18" r={r} fill="none" stroke="#e7e5e4" strokeWidth="3" />
        <circle cx="18" cy="18" r={r} fill="none" stroke={stroke} strokeWidth="3"
          strokeDasharray={`${dash} ${circ - dash}`} strokeLinecap="round" />
      </svg>
      <span className={`absolute inset-0 flex items-center justify-center text-xs font-bold ${text}`}>{score}</span>
    </div>
  )
}

function FoodCard({ food, onDelete }: { food: FoodLog; onDelete: () => void }) {
  const [open, setOpen] = useState(false)
  const { bg } = scoreColor(food.score)
  return (
    <div className="border border-stone-100 rounded-2xl overflow-hidden bg-white shadow-sm">
      <button onClick={() => setOpen(!open)} className="w-full text-left px-4 py-3.5 flex items-center gap-3">
        <ScoreRing score={food.score} />
        <div className="flex-1 min-w-0">
          <p className="font-semibold text-stone-900 text-sm truncate">{food.food_name}</p>
          {food.brand && <p className="text-stone-400 text-xs truncate">{food.brand}</p>}
          <div className="flex gap-3 mt-1 text-xs text-stone-500 flex-wrap">
            <span>{food.calories} cal</span>
            <span>{food.protein}g protein</span>
            <span>{food.carbs}g carbs</span>
            <span>{food.fat}g fat</span>
          </div>
        </div>
        <span className="text-stone-300 text-xs shrink-0">{open ? '▲' : '▼'}</span>
      </button>
      {open && (
        <div className={`px-4 pb-4 pt-1 border-t border-stone-100 ${bg}`}>
          {food.badges.length > 0 && (
            <div className="flex flex-wrap gap-2 mb-3">
              {food.badges.map((b) => (
                <span key={b.label} className={`inline-flex items-center gap-1 text-xs font-medium px-2.5 py-1 rounded-full ${b.color}`}>
                  {b.icon} {b.label}
                </span>
              ))}
            </div>
          )}
          {food.flags.map((f) => (
            <div key={f} className="flex items-start gap-2 text-xs text-red-700 bg-red-50 rounded-xl px-3 py-2 mb-1.5">
              <span className="shrink-0">⚠️</span><span>{f}</span>
            </div>
          ))}
          <button onClick={onDelete} className="mt-3 text-xs text-red-400 hover:text-red-600 transition-colors">
            Remove from log
          </button>
        </div>
      )}
    </div>
  )
}

function SearchModal({ meal, onClose, onAdd }: { meal: Meal; onClose: () => void; onAdd: (food: FoodResult) => Promise<void> }) {
  const [query, setQuery] = useState('')
  const [results, setResults] = useState<FoodResult[]>([])
  const [loading, setLoading] = useState(false)
  const [adding, setAdding] = useState<string | null>(null)

  const search = useCallback(async () => {
    if (!query.trim()) return
    setLoading(true)
    try {
      const res = await searchFood(query)
      setResults(res)
    } finally {
      setLoading(false)
    }
  }, [query])

  return (
    <div className="fixed inset-0 bg-black/40 z-50 flex items-end">
      <div className="bg-white w-full max-h-[90vh] rounded-t-3xl flex flex-col">
        <div className="px-5 pt-5 pb-3 border-b border-stone-100">
          <div className="flex items-center justify-between mb-3">
            <h2 className="font-semibold text-stone-900">Add to {meal}</h2>
            <button onClick={onClose} className="text-stone-400 hover:text-stone-700 text-xl leading-none">×</button>
          </div>
          <div className="flex gap-2">
            <input
              autoFocus
              value={query}
              onChange={e => setQuery(e.target.value)}
              onKeyDown={e => e.key === 'Enter' && search()}
              placeholder="Search foods..."
              className="flex-1 bg-stone-100 rounded-xl px-4 py-2.5 text-sm focus:outline-none focus:ring-2 focus:ring-green-700"
            />
            <button onClick={search} className="bg-green-800 text-white px-4 py-2.5 rounded-xl text-sm font-medium hover:bg-green-900 transition-colors">
              {loading ? '...' : 'Search'}
            </button>
          </div>
          <Link href="/scan" className="block text-center text-xs text-green-700 mt-2 hover:underline">
            📷 Scan a barcode instead
          </Link>
        </div>
        <div className="overflow-y-auto flex-1 px-5 py-3 space-y-2">
          {results.length === 0 && !loading && (
            <p className="text-center text-stone-400 text-sm py-8">Search for a food above</p>
          )}
          {results.map((r, i) => (
            <div key={i} className="flex items-center gap-3 bg-stone-50 rounded-2xl px-4 py-3">
              <ScoreRing score={r.score} size={40} />
              <div className="flex-1 min-w-0">
                <p className="font-semibold text-stone-900 text-sm truncate">{r.food_name}</p>
                {r.brand && <p className="text-stone-400 text-xs truncate">{r.brand}</p>}
                <p className="text-xs text-stone-500 mt-0.5">{r.calories} cal · {r.protein}g P · {r.carbs}g C · {r.fat}g F</p>
              </div>
              <button
                onClick={async () => {
                  setAdding(r.food_name)
                  await onAdd(r)
                  setAdding(null)
                  onClose()
                }}
                disabled={adding === r.food_name}
                className="shrink-0 bg-green-800 text-white text-xs px-3 py-1.5 rounded-full hover:bg-green-700 transition-colors disabled:opacity-50"
              >
                {adding === r.food_name ? '...' : 'Add'}
              </button>
            </div>
          ))}
        </div>
      </div>
    </div>
  )
}

export default function MealLogPage() {
  const [logs, setLogs] = useState<FoodLog[]>([])
  const [loading, setLoading] = useState(true)
  const [modal, setModal] = useState<Meal | null>(null)

  const load = useCallback(async () => {
    setLoading(true)
    try { setLogs(await getFoodLogs(TODAY)) } finally { setLoading(false) }
  }, [])

  useEffect(() => { load() }, [load])

  const handleAdd = async (meal: Meal, food: FoodResult) => {
    await addFoodLog({ ...food, meal, date: TODAY })
    await load()
  }

  const handleDelete = async (id: string) => {
    await deleteFoodLog(id)
    await load()
  }

  const totalCal = logs.reduce((s, f) => s + f.calories, 0)
  const totalProtein = logs.reduce((s, f) => s + f.protein, 0)
  const totalCarbs = logs.reduce((s, f) => s + f.carbs, 0)
  const totalFat = logs.reduce((s, f) => s + f.fat, 0)
  const avgScore = logs.length ? Math.round(logs.reduce((s, f) => s + f.score, 0) / logs.length) : 0
  const goalCal = 2100
  const { stroke: avgStroke } = scoreColor(avgScore || 50)

  const dateLabel = new Date().toLocaleDateString('en-US', { weekday: 'long', month: 'short', day: 'numeric' })

  return (
    <div className="min-h-screen bg-stone-50" style={{ fontFamily: 'var(--font-nunito), sans-serif' }}>
      <nav className="flex items-center px-5 py-4 max-w-lg mx-auto">
        <Link href="/" className="text-stone-400 hover:text-stone-700 text-sm flex items-center gap-1.5 transition-colors">← Back</Link>
        <span className="font-bold text-green-800 tracking-[0.2em] uppercase text-lg mx-auto pr-8">Grove</span>
      </nav>

      <div className="max-w-lg mx-auto px-5 pb-20">
        <p className="text-stone-400 text-sm mb-4">{dateLabel}</p>

        {/* Summary card */}
        <div className="bg-white rounded-3xl border border-stone-100 shadow-sm p-5 mb-6">
          <div className="flex items-center justify-between mb-4">
            <div>
              <p className="text-xs text-stone-400 uppercase tracking-widest mb-0.5">Today&apos;s overview</p>
              <p className="text-2xl font-bold text-stone-900">{totalCal.toLocaleString()} <span className="text-base font-normal text-stone-400">/ {goalCal.toLocaleString()} cal</span></p>
            </div>
            {logs.length > 0 && (
              <div className="text-center">
                <div className="relative w-16 h-16">
                  <svg viewBox="0 0 36 36" className="w-16 h-16 -rotate-90">
                    <circle cx="18" cy="18" r="15.9" fill="none" stroke="#e7e5e4" strokeWidth="3" />
                    <circle cx="18" cy="18" r="15.9" fill="none" stroke={avgStroke} strokeWidth="3"
                      strokeDasharray={`${(avgScore / 100) * 100} ${100 - (avgScore / 100) * 100}`} strokeLinecap="round" />
                  </svg>
                  <span className="absolute inset-0 flex items-center justify-center text-sm font-bold text-stone-800">{avgScore}</span>
                </div>
                <p className="text-xs text-stone-400 mt-1">Clean score</p>
              </div>
            )}
          </div>
          <div className="h-2 bg-stone-100 rounded-full overflow-hidden mb-1">
            <div className="h-full bg-green-700 rounded-full transition-all" style={{ width: `${Math.min(100, (totalCal / goalCal) * 100)}%` }} />
          </div>
          <p className="text-xs text-stone-400 mb-4">{Math.max(0, goalCal - totalCal)} cal remaining</p>
          <div className="grid grid-cols-3 gap-3">
            {[
              { label: 'Protein', value: totalProtein, goal: 140, unit: 'g', color: 'bg-amber-400' },
              { label: 'Carbs', value: totalCarbs, goal: 210, unit: 'g', color: 'bg-orange-400' },
              { label: 'Fat', value: totalFat, goal: 70, unit: 'g', color: 'bg-green-500' },
            ].map((m) => (
              <div key={m.label} className="bg-stone-50 rounded-xl p-3">
                <p className="text-xs text-stone-400 mb-0.5">{m.label}</p>
                <p className="font-semibold text-sm text-stone-800">{Math.round(m.value)}{m.unit}</p>
                <div className="mt-1.5 h-1.5 bg-stone-200 rounded-full overflow-hidden">
                  <div className={`h-full rounded-full ${m.color}`} style={{ width: `${Math.min(100, (m.value / m.goal) * 100)}%` }} />
                </div>
              </div>
            ))}
          </div>
        </div>

        {/* Legend */}
        <div className="flex items-center gap-4 mb-6 px-1">
          <p className="text-xs text-stone-400 font-medium">Clean score:</p>
          <div className="flex gap-3">
            {[{ label: 'Clean', color: 'bg-green-700' }, { label: 'Moderate', color: 'bg-amber-500' }, { label: 'Avoid', color: 'bg-red-600' }].map(l => (
              <div key={l.label} className="flex items-center gap-1.5">
                <span className={`w-2 h-2 rounded-full ${l.color}`} />
                <span className="text-xs text-stone-500">{l.label}</span>
              </div>
            ))}
          </div>
        </div>

        {loading ? (
          <div className="text-center py-20 text-stone-400 text-sm">Loading...</div>
        ) : (
          MEALS.map((meal) => {
            const foods = logs.filter(f => f.meal === meal)
            return (
              <div key={meal} className="mb-7">
                <div className="flex items-center justify-between mb-3">
                  <div className="flex items-center gap-2">
                    <span>{MEAL_ICONS[meal]}</span>
                    <h2 className="font-semibold text-stone-800">{meal}</h2>
                  </div>
                  <span className="text-xs text-stone-400">{foods.reduce((s, f) => s + f.calories, 0)} cal</span>
                </div>
                <div className="space-y-2">
                  {foods.map(food => (
                    <FoodCard key={food.id} food={food} onDelete={() => handleDelete(food.id)} />
                  ))}
                </div>
                <button
                  onClick={() => setModal(meal)}
                  className="w-full mt-2 py-2.5 rounded-2xl border border-dashed border-stone-300 text-stone-400 text-sm hover:border-green-700 hover:text-green-700 transition-colors"
                >
                  + Add food
                </button>
              </div>
            )
          })
        )}

        <Link href="/scan" className="flex items-center justify-center gap-3 w-full bg-green-800 hover:bg-green-900 text-white py-4 rounded-2xl font-medium transition-colors">
          <span>📷</span> Scan a barcode to add food
        </Link>
      </div>

      {modal && (
        <SearchModal
          meal={modal}
          onClose={() => setModal(null)}
          onAdd={(food) => handleAdd(modal, food)}
        />
      )}
    </div>
  )
}
