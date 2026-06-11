'use client'

import Link from 'next/link'
import { useState, useEffect, useCallback } from 'react'
import { getFoodLogs, addFoodLog, deleteFoodLog, getProfile, localDate, type FoodLog } from '@/lib/db'
import { searchFood, toLogEntry, type FoodResult } from '@/lib/food-search'
import AppShell from '../components/AppShell'
import ScoreRing, { scoreTone } from '../components/ScoreRing'
import {
  IconAlert,
  IconBarcode,
  IconChevronDown,
  IconLeaf,
  IconPlus,
  IconSearch,
  IconX,
} from '../components/Icons'

const MEALS = ['Breakfast', 'Lunch', 'Dinner', 'Snacks'] as const
type Meal = (typeof MEALS)[number]

function FoodCard({ food, onDelete }: { food: FoodLog; onDelete: () => void }) {
  const [open, setOpen] = useState(false)
  return (
    <div className="bg-paper-50 border border-black/[0.07] rounded-2xl overflow-hidden">
      <button
        onClick={() => setOpen(!open)}
        aria-expanded={open}
        className="w-full text-left px-4 py-3.5 flex items-center gap-3.5"
      >
        <ScoreRing score={food.score} />
        <div className="flex-1 min-w-0">
          <p className="text-sm text-ink truncate">{food.food_name}</p>
          {food.brand && <p className="text-xs text-ink-3 truncate mt-0.5">{food.brand}</p>}
          <p className="font-mono text-[11px] text-ink-2 mt-1 tabular-nums">
            {food.calories} kcal · {food.protein}P · {food.carbs}C · {food.fat}F
          </p>
        </div>
        <IconChevronDown
          className={`w-4 h-4 text-ink-3 shrink-0 transition-transform ${open ? 'rotate-180' : ''}`}
        />
      </button>
      {open && (
        <div className="px-4 pb-4 pt-3 border-t border-black/[0.07]">
          {food.badges.length > 0 && (
            <div className="flex flex-wrap gap-1.5 mb-3">
              {food.badges.map((b) => (
                <span
                  key={b.label}
                  className="inline-flex items-center gap-1.5 text-[11px] text-moss-700 bg-moss-700/10 border border-moss-700/20 px-2.5 py-1 rounded-full"
                >
                  <IconLeaf className="w-3 h-3" />
                  {b.label}
                </span>
              ))}
            </div>
          )}
          {food.flags.map((f) => (
            <div
              key={f}
              className="flex items-start gap-2.5 text-xs text-clay-700 bg-clay-700/10 border border-clay-700/20 rounded-xl px-3 py-2.5 mb-1.5 leading-relaxed"
            >
              <IconAlert className="w-3.5 h-3.5 shrink-0 mt-px" />
              <span>{f}</span>
            </div>
          ))}
          <button
            onClick={onDelete}
            className="mt-2 text-xs text-ink-3 hover:text-clay-700 transition-colors"
          >
            Remove from log
          </button>
        </div>
      )}
    </div>
  )
}

function SearchSheet({
  meal,
  onClose,
  onAdd,
}: {
  meal: Meal
  onClose: () => void
  onAdd: (food: FoodResult) => Promise<void>
}) {
  const [query, setQuery] = useState('')
  const [results, setResults] = useState<FoodResult[]>([])
  const [loading, setLoading] = useState(false)
  const [searched, setSearched] = useState(false)
  const [adding, setAdding] = useState<string | null>(null)

  const search = useCallback(async () => {
    if (!query.trim()) return
    setLoading(true)
    try {
      setResults(await searchFood(query))
      setSearched(true)
    } finally {
      setLoading(false)
    }
  }, [query])

  return (
    <div
      className="fixed inset-0 bg-black/60 z-50 flex items-end md:items-center md:justify-center fade-in"
      onClick={onClose}
    >
      <div
        role="dialog"
        aria-label={`Add food to ${meal}`}
        onClick={(e) => e.stopPropagation()}
        className="sheet-up bg-paper-50 border-t md:border border-black/[0.09] w-full md:max-w-lg max-h-[88vh] md:max-h-[80vh] rounded-t-3xl md:rounded-3xl flex flex-col"
      >
        <div className="px-5 pt-5 pb-4 border-b border-black/[0.07]">
          <div className="flex items-center justify-between mb-4">
            <h2 className="text-ink">
              Add to <span className="text-moss-700">{meal}</span>
            </h2>
            <button
              onClick={onClose}
              aria-label="Close"
              className="text-ink-2 hover:text-ink transition-colors p-1 -m-1"
            >
              <IconX className="w-5 h-5" />
            </button>
          </div>
          <div className="flex gap-2">
            <div className="flex-1 relative">
              <IconSearch className="w-4 h-4 text-ink-3 absolute left-3.5 top-1/2 -translate-y-1/2 pointer-events-none" />
              <input
                autoFocus
                value={query}
                onChange={(e) => setQuery(e.target.value)}
                onKeyDown={(e) => e.key === 'Enter' && search()}
                placeholder="Search any food…"
                className="w-full bg-paper-100 border border-black/[0.08] rounded-xl pl-10 pr-4 py-3 text-sm text-ink placeholder:text-ink-3 focus:border-moss-700/50 focus:outline-none transition-colors"
              />
            </div>
            <button
              onClick={search}
              disabled={loading}
              className="bg-moss-700 hover:bg-moss-800 text-white font-semibold px-4 rounded-xl text-sm transition-colors disabled:opacity-60"
            >
              {loading ? '…' : 'Search'}
            </button>
          </div>
          <Link
            href="/scan"
            className="flex items-center justify-center gap-2 text-xs text-ink-2 hover:text-moss-700 mt-3 transition-colors"
          >
            <IconBarcode className="w-3.5 h-3.5" /> Scan a barcode instead
          </Link>
        </div>

        <div className="overflow-y-auto flex-1 px-5 py-4 space-y-2 min-h-[200px]">
          {!searched && !loading && (
            <p className="text-center text-ink-3 text-sm py-10">
              Search the Open Food Facts database — 700,000+ foods, each one scored.
            </p>
          )}
          {searched && !loading && results.length === 0 && (
            <p className="text-center text-ink-3 text-sm py-10">
              Nothing found for “{query}”. Try a simpler name or scan the barcode.
            </p>
          )}
          {results.map((r, i) => (
            <div
              key={i}
              className="flex items-center gap-3.5 bg-paper-100 border border-black/[0.06] rounded-2xl px-4 py-3"
            >
              <ScoreRing score={r.score} size={40} />
              <div className="flex-1 min-w-0">
                <p className="text-sm text-ink truncate">{r.food_name}</p>
                {r.brand && <p className="text-xs text-ink-3 truncate mt-0.5">{r.brand}</p>}
                <p className="font-mono text-[11px] text-ink-2 mt-1 tabular-nums">
                  {r.calories} kcal · {r.protein}P · {r.carbs}C · {r.fat}F
                </p>
              </div>
              <button
                onClick={async () => {
                  setAdding(r.food_name)
                  try {
                    await onAdd(r)
                    onClose()
                  } finally {
                    setAdding(null)
                  }
                }}
                disabled={adding !== null}
                className="shrink-0 flex items-center gap-1 bg-moss-700 hover:bg-moss-800 text-white font-semibold text-xs px-3 py-2 rounded-lg transition-colors disabled:opacity-60"
              >
                {adding === r.food_name ? '…' : (
                  <>
                    <IconPlus className="w-3.5 h-3.5" strokeWidth={2.5} /> Add
                  </>
                )}
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
  const [goalCalState, setGoalCalState] = useState(2100)
  const [loading, setLoading] = useState(true)
  const [sheet, setSheet] = useState<Meal | null>(null)

  const today = localDate()

  const load = useCallback(async () => {
    try {
      const [foods, prof] = await Promise.all([
        getFoodLogs(localDate()),
        getProfile().catch(() => null),
      ])
      setLogs(foods)
      if (prof) setGoalCalState(prof.goal_calories)
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => {
    load()
  }, [load])

  const handleAdd = async (meal: Meal, food: FoodResult) => {
    await addFoodLog(toLogEntry(food, meal, today))
    await load()
  }

  const handleDelete = async (id: string) => {
    setLogs((ls) => ls.filter((l) => l.id !== id))
    await deleteFoodLog(id)
    load()
  }

  const totalCal = logs.reduce((s, f) => s + f.calories, 0)
  const avgScore = logs.length
    ? Math.round(logs.reduce((s, f) => s + f.score, 0) / logs.length)
    : 0
  const goalCal = goalCalState
  const tone = scoreTone(avgScore || 100)

  return (
    <AppShell>
      <div className="max-w-lg md:max-w-2xl mx-auto px-5 md:px-8 pt-6 md:pt-10">
        <header className="rise mb-6 flex items-end justify-between">
          <div>
            <h1 className="font-display text-3xl text-ink">Meals</h1>
            <p className="font-mono text-[11px] uppercase tracking-wider text-ink-2 mt-2">
              {new Date().toLocaleDateString('en-US', {
                weekday: 'long',
                month: 'long',
                day: 'numeric',
              })}
            </p>
          </div>
          {logs.length > 0 && (
            <div className="text-right">
              <p className="font-mono text-2xl text-ink tabular-nums">{avgScore}</p>
              <p className={`text-[11px] uppercase tracking-[0.18em] ${tone.text}`}>
                {tone.word} day
              </p>
            </div>
          )}
        </header>

        {/* day summary */}
        <div
          className="rise bg-paper-50 border border-black/[0.07] rounded-2xl p-5 mb-8"
          style={{ animationDelay: '60ms' }}
        >
          <div className="flex justify-between items-baseline mb-2">
            <span className="text-[11px] uppercase tracking-[0.18em] text-ink-2">Energy</span>
            <span className="font-mono text-sm text-ink tabular-nums">
              {totalCal.toLocaleString()}{' '}
              <span className="text-ink-3">/ {goalCal.toLocaleString()} kcal</span>
            </span>
          </div>
          <div className="h-1.5 bg-paper-200 rounded-full overflow-hidden">
            <div
              className="h-full bg-honey-600 rounded-full transition-all duration-700"
              style={{ width: `${Math.min(100, (totalCal / goalCal) * 100)}%` }}
            />
          </div>
        </div>

        {loading ? (
          <div className="space-y-3">
            {[0, 1, 2].map((i) => (
              <div
                key={i}
                className="h-20 bg-paper-50 border border-black/[0.07] rounded-2xl animate-pulse"
              />
            ))}
          </div>
        ) : (
          MEALS.map((meal, mi) => {
            const foods = logs.filter((f) => f.meal === meal)
            const mealCal = foods.reduce((s, f) => s + f.calories, 0)
            return (
              <section
                key={meal}
                className="rise mb-8"
                style={{ animationDelay: `${120 + mi * 60}ms` }}
              >
                <div className="flex items-baseline justify-between mb-3 px-0.5">
                  <h2 className="text-[11px] uppercase tracking-[0.18em] text-ink-2">{meal}</h2>
                  <span className="font-mono text-[11px] text-ink-3 tabular-nums">
                    {mealCal > 0 ? `${mealCal.toLocaleString()} kcal` : '—'}
                  </span>
                </div>
                <div className="space-y-2">
                  {foods.map((food) => (
                    <FoodCard key={food.id} food={food} onDelete={() => handleDelete(food.id)} />
                  ))}
                </div>
                <button
                  onClick={() => setSheet(meal)}
                  className={`w-full flex items-center justify-center gap-2 py-3 rounded-2xl border border-dashed border-paper-300 text-ink-2 text-sm hover:border-moss-700/50 hover:text-moss-700 transition-colors ${
                    foods.length > 0 ? 'mt-2' : ''
                  }`}
                >
                  <IconPlus className="w-4 h-4" /> Add food
                </button>
              </section>
            )
          })
        )}
      </div>

      {sheet && (
        <SearchSheet
          meal={sheet}
          onClose={() => setSheet(null)}
          onAdd={(food) => handleAdd(sheet, food)}
        />
      )}
    </AppShell>
  )
}
