'use client'

import Link from 'next/link'
import { useState, useEffect, useCallback, useRef } from 'react'
import { getFoodLogs, addFoodLog, deleteFoodLog, getProfile, localDate, type FoodLog } from '@/lib/db'
import { searchFood, scaleFood, toLogEntry, type FoodResult } from '@/lib/food-search'
import { searchWholeFoods } from '@/lib/whole-foods'
import { unitOptions, gramsFor, roundCount } from '@/lib/units'
import { haptic } from '@/lib/haptics'
import AppShell from '../components/AppShell'
import ManualFoodForm from '../components/ManualFoodForm'
import ScoreWhy from '../components/ScoreWhy'
import ScoreRing, { scoreTone } from '../components/ScoreRing'
import {
  IconAlert,
  IconArrowLeft,
  IconBarcode,
  IconCheck,
  IconChevronDown,
  IconLeaf,
  IconMinus,
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
        onClick={() => { haptic('select'); setOpen(!open) }}
        aria-expanded={open}
        className="w-full text-left px-4 py-3.5 flex items-center gap-3.5 transition-colors hover:bg-paper-100/50"
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
            onClick={() => { haptic('warn'); onDelete() }}
            className="press mt-2 text-xs text-ink-3 hover:text-clay-700 transition-colors"
          >
            Remove from log
          </button>
        </div>
      )}
    </div>
  )
}

/** Portion step: pick a unit (serving, grams, oz, cup…), with macros scaling live. */
function PortionView({
  food,
  meal,
  onBack,
  onConfirm,
}: {
  food: FoodResult
  meal: Meal
  onBack: () => void
  onConfirm: (scaled: FoodResult) => Promise<void>
}) {
  const opts = unitOptions(food)
  const [unitKey, setUnitKey] = useState(opts[0].key)
  const unit = opts.find((o) => o.key === unitKey) ?? opts[0]
  const [amount, setAmount] = useState(1)
  const [saving, setSaving] = useState(false)
  const [showWhy, setShowWhy] = useState(false)

  const step = unit.decimal ? 0.5 : 10
  const minAmt = unit.decimal ? 0.5 : 1
  const effectiveGrams = gramsFor(amount, unit)
  const scaled = scaleFood(food, effectiveGrams)

  const stepAmount = (delta: number) => {
    haptic('select')
    setAmount((a) => Math.max(minAmt, roundCount(a + delta)))
  }

  // Switching units resets to one of the new unit — predictable, no stale grams.
  const pickUnit = (key: string) => {
    if (key !== unitKey) { haptic('select'); setUnitKey(key); setAmount(1) }
  }

  const confirm = async () => {
    setSaving(true)
    haptic('tap')
    try {
      await onConfirm(scaled)
      haptic('success')
    } catch {
      haptic('error')
      setSaving(false)
    }
  }

  return (
    <>
      <div className="px-5 pt-5 pb-4 border-b border-black/[0.07]">
        <div className="flex items-center gap-3">
          <button
            onClick={onBack}
            aria-label="Back to search"
            className="press text-ink-2 hover:text-ink transition-colors p-1 -m-1"
          >
            <IconArrowLeft className="w-5 h-5" />
          </button>
          <h2 className="text-ink">
            Add to <span className="text-moss-700">{meal}</span>
          </h2>
        </div>
      </div>

      <div className="overflow-y-auto flex-1 px-5 py-5">
        {/* food + live total */}
        <div className="flex items-center gap-4 mb-6">
          <ScoreRing score={food.score} size={48} />
          <div className="min-w-0 flex-1">
            <p className="text-ink truncate">{food.food_name}</p>
            {food.whole ? (
              <p className="flex items-center gap-1 text-[11px] text-moss-700 mt-0.5">
                <IconLeaf className="w-3 h-3" /> Whole food
              </p>
            ) : food.manual ? (
              <p className="text-[11px] text-ink-3 mt-0.5">Your entry</p>
            ) : (
              food.brand && <p className="text-xs text-ink-3 truncate mt-0.5">{food.brand}</p>
            )}
          </div>
          <div className="text-right shrink-0">
            <p className="font-mono text-2xl text-ink tabular-nums leading-none">{scaled.calories}</p>
            <p className="text-[10px] uppercase tracking-[0.16em] text-ink-2 mt-1">kcal</p>
          </div>
        </div>

        {/* unit selector */}
        <div className="flex gap-1.5 overflow-x-auto pb-1 -mx-1 px-1 mb-4">
          {opts.map((o) => (
            <button
              key={o.key}
              onClick={() => pickUnit(o.key)}
              className={`press shrink-0 px-3.5 py-2 rounded-lg text-xs transition-colors border ${
                unitKey === o.key
                  ? 'bg-moss-700 border-moss-700 text-white font-semibold'
                  : 'bg-paper-50 border-black/[0.08] text-ink-2 hover:text-ink'
              }`}
            >
              {o.label}
            </button>
          ))}
        </div>

        {/* amount stepper */}
        <div className="flex items-center justify-center gap-5 py-2">
          <button
            onClick={() => stepAmount(-step)}
            aria-label="Less"
            disabled={amount <= minAmt}
            className="press w-11 h-11 rounded-full border border-black/[0.1] flex items-center justify-center text-ink hover:bg-paper-100 transition-colors disabled:opacity-40"
          >
            <IconMinus className="w-4 h-4" />
          </button>
          <input
            type="number"
            min={minAmt}
            step={step}
            inputMode="decimal"
            value={amount}
            onChange={(e) => { const v = parseFloat(e.target.value); if (!isNaN(v)) setAmount(v) }}
            onBlur={(e) => setAmount(Math.max(minAmt, roundCount(parseFloat(e.target.value) || minAmt)))}
            className="w-24 text-center font-mono text-3xl text-ink tabular-nums bg-transparent focus:outline-none"
          />
          <button
            onClick={() => stepAmount(step)}
            aria-label="More"
            className="press w-11 h-11 rounded-full border border-black/[0.1] flex items-center justify-center text-ink hover:bg-paper-100 transition-colors"
          >
            <IconPlus className="w-4 h-4" />
          </button>
        </div>
        <p className="text-center text-xs text-ink-3 mt-1">
          {unit.key === 'g' ? `${effectiveGrams}g total` : `${amount} ${unit.label.replace(' ≈', '')} = ${effectiveGrams}g`}
          {unit.approx && ' · volume is approximate'}
        </p>

        {/* scaled macros */}
        <div className="grid grid-cols-4 gap-2 mt-6 pt-5 border-t border-black/[0.07]">
          {[
            { label: 'Protein', value: scaled.protein, color: 'bg-moss-700' },
            { label: 'Carbs', value: scaled.carbs, color: 'bg-honey-600' },
            { label: 'Fat', value: scaled.fat, color: 'bg-clay-700' },
            { label: 'Fibre', value: scaled.fibre, color: 'bg-sky-500' },
          ].map((m) => (
            <div key={m.label} className="text-center">
              <p className="font-mono text-base text-ink tabular-nums">{m.value}g</p>
              <div className="flex items-center justify-center gap-1 mt-0.5">
                <span className={`w-1.5 h-1.5 rounded-full ${m.color}`} />
                <span className="text-[10px] text-ink-3">{m.label}</span>
              </div>
            </div>
          ))}
        </div>

        <ScoreWhy score={food.score} reasons={food.reasons} open={showWhy} onToggle={() => setShowWhy((v) => !v)} />
      </div>

      <div className="px-5 py-4 border-t border-black/[0.07]">
        <button
          onClick={confirm}
          disabled={saving}
          className="press w-full bg-moss-700 hover:bg-moss-800 text-white font-semibold py-3.5 rounded-xl text-sm transition-colors disabled:opacity-60 flex items-center justify-center gap-2"
        >
          {saving ? 'Adding…' : (
            <>
              <IconPlus className="w-4 h-4" strokeWidth={2.5} />
              Add {scaled.calories} kcal to {meal}
            </>
          )}
        </button>
      </div>
    </>
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
  const [searchError, setSearchError] = useState<string | null>(null)
  const [portioning, setPortioning] = useState<FoodResult | null>(null)
  const [manual, setManual] = useState(false)
  const [recentlyAdded, setRecentlyAdded] = useState<Set<string>>(new Set())
  const addedKey = (r: FoodResult) => `${r.food_name}|${r.brand ?? ''}`
  // Monotonic request id — guards against a slow earlier response overwriting
  // the results of a later, faster one as the user keeps typing.
  const reqId = useRef(0)

  const search = useCallback(async (q: string) => {
    const term = q.trim()
    if (term.length < 2) return
    const id = ++reqId.current
    setLoading(true)
    setSearchError(null)
    // Curated whole foods (eggs, banana, rice…) match instantly and sit on top,
    // since Open Food Facts is unreliable for unbranded basics.
    const whole = searchWholeFoods(term)
    if (whole.length) {
      setResults(whole)
      setSearched(true)
    }
    try {
      const found = await searchFood(term)
      if (id !== reqId.current) return // a newer search superseded this one
      setResults([...whole, ...found])
      setSearched(true)
    } catch (err) {
      if (id !== reqId.current) return
      // Whole-food matches already shown? Don't alarm the user about the network.
      if (whole.length === 0) {
        const isTimeout = err instanceof DOMException && err.name === 'AbortError'
        setSearchError(isTimeout
          ? 'Search timed out. Check your connection and try again.'
          : 'Search failed. Check your connection and try again.')
      }
      setSearched(true)
    } finally {
      if (id === reqId.current) setLoading(false)
    }
  }, [])

  // Live search — fire 450ms after the user stops typing. Both branches defer
  // their state writes to the timer/microtask so nothing runs synchronously in
  // the effect body (avoids cascading renders).
  useEffect(() => {
    const term = query.trim()
    if (term.length < 2) {
      reqId.current++ // cancel any in-flight result from a now-too-short query
      const t = setTimeout(() => {
        setResults([])
        setSearched(false)
        setLoading(false)
      }, 0)
      return () => clearTimeout(t)
    }
    const t = setTimeout(() => search(term), 450)
    return () => clearTimeout(t)
  }, [query, search])

  return (
    <div
      className="fixed inset-0 bg-black/60 z-50 flex items-end md:items-center md:justify-center fade-in"
      onClick={onClose}
      onKeyDown={(e) => e.key === 'Escape' && onClose()}
    >
      <div
        role="dialog"
        aria-modal="true"
        aria-label={`Add food to ${meal}`}
        onClick={(e) => e.stopPropagation()}
        className="sheet-up bg-paper-50 border-t md:border border-black/[0.09] w-full md:max-w-lg max-h-[88vh] md:max-h-[80vh] rounded-t-3xl md:rounded-3xl flex flex-col"
      >
        {manual ? (
          <ManualFoodForm
            initialName={query.trim()}
            onBack={() => setManual(false)}
            onSubmit={(food) => { setManual(false); setPortioning(food) }}
          />
        ) : portioning ? (
          <PortionView
            food={portioning}
            meal={meal}
            onBack={() => setPortioning(null)}
            onConfirm={async (scaled) => {
              await onAdd(scaled)
              const key = addedKey(scaled)
              setRecentlyAdded((s) => new Set(s).add(key))
              setTimeout(
                () => setRecentlyAdded((s) => { const n = new Set(s); n.delete(key); return n }),
                2400
              )
              setPortioning(null)
            }}
          />
        ) : (
          <>
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
          <div className="relative">
            <IconSearch className="w-4 h-4 text-ink-3 absolute left-3.5 top-1/2 -translate-y-1/2 pointer-events-none" />
            <input
              autoFocus
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              onKeyDown={(e) => e.key === 'Enter' && search(query)}
              placeholder="Search any food…"
              className="w-full bg-paper-100 border border-black/[0.08] rounded-xl pl-10 pr-10 py-3 text-sm text-ink placeholder:text-ink-3 focus:border-moss-700/50 focus:outline-none transition-colors"
            />
            <span className="absolute right-3.5 top-1/2 -translate-y-1/2 flex items-center">
              {loading ? (
                <span className="w-4 h-4 border-2 border-moss-700 border-t-transparent rounded-full animate-spin" />
              ) : query ? (
                <button
                  onClick={() => setQuery('')}
                  aria-label="Clear search"
                  className="press text-ink-3 hover:text-ink transition-colors"
                >
                  <IconX className="w-4 h-4" />
                </button>
              ) : null}
            </span>
          </div>
          <div className="flex items-center justify-center gap-5 mt-3">
            <Link
              href="/scan"
              className="flex items-center gap-2 text-xs text-ink-2 hover:text-moss-700 transition-colors"
            >
              <IconBarcode className="w-3.5 h-3.5" /> Scan a barcode
            </Link>
            <span className="text-ink-3 text-xs">·</span>
            <Link
              href="/scan"
              className="text-xs text-ink-2 hover:text-moss-700 transition-colors"
            >
              Photograph your plate
            </Link>
            <span className="text-ink-3 text-xs">·</span>
            <button
              onClick={() => { haptic('tap'); setManual(true) }}
              className="text-xs text-ink-2 hover:text-moss-700 transition-colors"
            >
              Enter manually
            </button>
          </div>
        </div>

        <div className="overflow-y-auto flex-1 px-5 py-4 space-y-2 min-h-[200px]">
          {!searched && !loading && (
            <p className="text-center text-ink-3 text-sm py-10">
              {query.trim().length === 1
                ? 'Keep typing…'
                : 'Search whole foods like eggs, rice, or chicken — plus 700,000+ packaged products. Each one scored as you go.'}
            </p>
          )}
          {searched && !loading && !searchError && results.length === 0 && (
            <div className="text-center py-10">
              <p className="text-ink-3 text-sm">
                Nothing found for &ldquo;{query}&rdquo;.
              </p>
              <button
                onClick={() => { haptic('tap'); setManual(true) }}
                className="press mt-3 inline-flex items-center gap-1.5 text-sm font-semibold text-moss-700 hover:text-moss-800 transition-colors"
              >
                <IconPlus className="w-4 h-4" strokeWidth={2.5} /> Enter it manually
              </button>
            </div>
          )}
          {searchError && (
            <div className="flex items-start gap-2.5 text-sm text-clay-700 bg-clay-700/10 border border-clay-700/20 rounded-2xl px-4 py-3.5 leading-relaxed mt-2">
              <IconAlert className="w-4 h-4 shrink-0 mt-0.5" />
              <span>{searchError}</span>
            </div>
          )}
          {results.map((r, i) => {
            const added = recentlyAdded.has(addedKey(r))
            return (
              <button
                key={`${r.food_name}-${r.brand ?? ''}-${i}`}
                onClick={() => { haptic('select'); setPortioning(r) }}
                className="press w-full text-left flex items-center gap-3.5 bg-paper-100 border border-black/[0.06] rounded-2xl px-4 py-3 hover:border-moss-700/30 transition-colors"
              >
                <ScoreRing score={r.score} size={40} />
                <div className="flex-1 min-w-0">
                  <p className="text-sm text-ink truncate">{r.food_name}</p>
                  {r.whole ? (
                    <p className="flex items-center gap-1 text-[11px] text-moss-700 mt-0.5">
                      <IconLeaf className="w-3 h-3" /> Whole food
                    </p>
                  ) : (
                    r.brand && <p className="text-xs text-ink-3 truncate mt-0.5">{r.brand}</p>
                  )}
                  <p className="font-mono text-[11px] text-ink-2 mt-1 tabular-nums">
                    {r.calories} kcal · {r.protein}P · {r.carbs}C · {r.fat}F
                    <span className="text-ink-3"> · per 100g</span>
                  </p>
                </div>
                {added ? (
                  <span className="pop shrink-0 flex items-center gap-1 text-xs font-semibold text-moss-700 bg-moss-700/15 border border-moss-700/30 px-2.5 py-1.5 rounded-lg">
                    <IconCheck className="w-3.5 h-3.5" strokeWidth={2.5} /> Added
                  </span>
                ) : (
                  <span className="shrink-0 flex items-center gap-1 text-xs text-moss-700">
                    <IconPlus className="w-3.5 h-3.5" strokeWidth={2.5} /> Add
                  </span>
                )}
              </button>
            )
          })}
        </div>
          </>
        )}
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
      // Profile is only used for the calorie goal here — a failure shouldn't
      // block the log, but log it so it's not silently invisible.
      const [foods, prof] = await Promise.all([
        getFoodLogs(localDate()),
        getProfile().catch((e) => {
          console.error('meal-log: profile load failed', e)
          return null
        }),
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
    const snapshot = logs
    setLogs((ls) => ls.filter((l) => l.id !== id))
    try {
      await deleteFoodLog(id)
      load()
    } catch {
      setLogs(snapshot)
    }
  }

  const totalCal = logs.reduce((s, f) => s + f.calories, 0)
  const totalProtein = logs.reduce((s, f) => s + f.protein, 0)
  const totalCarbs = logs.reduce((s, f) => s + f.carbs, 0)
  const totalFat = logs.reduce((s, f) => s + f.fat, 0)
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
            <p className="text-sm text-ink-2 mt-1.5">Everything you eat, scored 1–100.</p>
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
          {logs.length > 0 && (
            <div className="flex gap-3 mt-4 pt-3 border-t border-black/[0.06]">
              {[
                { label: 'Protein', value: Math.round(totalProtein), unit: 'g', color: 'bg-moss-700' },
                { label: 'Carbs', value: Math.round(totalCarbs), unit: 'g', color: 'bg-honey-600' },
                { label: 'Fat', value: Math.round(totalFat), unit: 'g', color: 'bg-clay-700' },
              ].map((m) => (
                <div key={m.label} className="flex-1 text-center">
                  <p className="font-mono text-sm text-ink tabular-nums">{m.value}{m.unit}</p>
                  <div className="flex items-center justify-center gap-1 mt-0.5">
                    <span className={`w-1.5 h-1.5 rounded-full ${m.color}`} />
                    <span className="text-[10px] text-ink-3">{m.label}</span>
                  </div>
                </div>
              ))}
            </div>
          )}
          {logs.length === 0 && (
            <div className="flex items-center gap-4 mt-4 pt-3 border-t border-black/[0.06]">
              <span className="text-[11px] text-ink-3">Score colors:</span>
              {[
                ['bg-moss-600', 'Clean 70+'],
                ['bg-honey-600', 'Moderate'],
                ['bg-clay-700', 'Avoid'],
              ].map(([dot, label]) => (
                <span key={label} className="flex items-center gap-1.5 text-[11px] text-ink-2">
                  <span className={`w-2 h-2 rounded-full ${dot}`} />
                  {label}
                </span>
              ))}
            </div>
          )}
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
                  onClick={() => { haptic('tap'); setSheet(meal) }}
                  className={`press w-full flex items-center justify-center gap-2 py-3 rounded-2xl border border-dashed border-paper-300 text-ink-2 text-sm hover:border-moss-700/50 hover:text-moss-700 transition-colors ${
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
