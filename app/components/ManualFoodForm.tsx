'use client'

import { useState } from 'react'
import { buildManualFood, type ManualKind } from '@/lib/manual-food'
import { unitOptions, gramsFor } from '@/lib/units'
import type { FoodResult } from '@/lib/food-search'
import { haptic } from '@/lib/haptics'
import { IconArrowLeft, IconLeaf } from './Icons'

const KINDS: { key: ManualKind; label: string; hint: string }[] = [
  { key: 'whole', label: 'Whole', hint: 'Single ingredient' },
  { key: 'home', label: 'Home-cooked', hint: 'Made from scratch' },
  { key: 'packaged', label: 'Packaged', hint: 'Pre-made / processed' },
]

const fieldCls =
  'w-full bg-paper-100 border border-black/[0.08] rounded-xl px-3.5 py-2.5 text-sm text-ink placeholder:text-ink-3 focus:border-moss-700/50 focus:outline-none transition-colors'
const numCls = `${fieldCls} font-mono tabular-nums`

// No food exists yet, so the unit list is the generic set: grams, oz, cup ≈, …
const SERVING_UNITS = unitOptions({ serving_grams: null, serving_size: null })

/** Parse a numeric input leniently: blank/garbage → 0, never NaN downstream. */
function num(v: string): number {
  const n = parseFloat(v)
  return isNaN(n) ? 0 : n
}

export default function ManualFoodForm({
  initialName = '',
  onBack,
  onSubmit,
}: {
  initialName?: string
  onBack: () => void
  onSubmit: (food: FoodResult) => Promise<void> | void
}) {
  const [name, setName] = useState(initialName)
  const [brand, setBrand] = useState('')
  const [kind, setKind] = useState<ManualKind>('home')

  const [servingAmount, setServingAmount] = useState('1')
  const [unitKey, setUnitKey] = useState(SERVING_UNITS[0].key)

  const [calories, setCalories] = useState('')
  const [protein, setProtein] = useState('')
  const [carbs, setCarbs] = useState('')
  const [fat, setFat] = useState('')
  const [fibre, setFibre] = useState('')

  const [saving, setSaving] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const unit = SERVING_UNITS.find((u) => u.key === unitKey) ?? SERVING_UNITS[0]
  const servingGrams = gramsFor(num(servingAmount) || 1, unit)
  const servingLabel =
    unit.key === 'g'
      ? 'serving'
      : num(servingAmount) === 1
        ? unit.label.replace(' ≈', '')
        : `${servingAmount} ${unit.label.replace(' ≈', '')}`

  const canSave = name.trim().length > 0 && num(calories) > 0

  const submit = async () => {
    if (!canSave) {
      setError('Give it a name and at least the calories per serving.')
      return
    }
    setSaving(true)
    setError(null)
    haptic('tap')
    try {
      const food = buildManualFood({
        name,
        brand,
        servingGrams,
        servingLabel,
        kind,
        perServing: {
          calories: num(calories),
          protein: num(protein),
          carbs: num(carbs),
          fat: num(fat),
          fibre: num(fibre),
        },
      })
      await onSubmit(food)
    } catch {
      haptic('error')
      setError('Couldn’t add that. Check the numbers and try again.')
      setSaving(false)
    }
  }

  return (
    <>
      <div className="px-5 pt-5 pb-4 border-b border-black/[0.07]">
        <div className="flex items-center gap-3">
          <button
            onClick={onBack}
            aria-label="Back"
            className="press text-ink-2 hover:text-ink transition-colors p-1 -m-1"
          >
            <IconArrowLeft className="w-5 h-5" />
          </button>
          <h2 className="text-ink">Add it manually</h2>
        </div>
        <p className="text-xs text-ink-3 mt-2 leading-relaxed">
          For homemade meals, leftovers, or anything without a barcode. Enter what one serving contains.
        </p>
      </div>

      <div className="overflow-y-auto flex-1 px-5 py-5 space-y-5">
        <div className="space-y-3">
          <label className="block">
            <span className="block text-xs text-ink-2 mb-1.5">Name</span>
            <input
              autoFocus
              value={name}
              onChange={(e) => setName(e.target.value)}
              placeholder="e.g. Mom’s chicken curry"
              className={fieldCls}
            />
          </label>
          <label className="block">
            <span className="block text-xs text-ink-2 mb-1.5">Brand or source (optional)</span>
            <input
              value={brand}
              onChange={(e) => setBrand(e.target.value)}
              placeholder="e.g. leftovers, the deli"
              className={fieldCls}
            />
          </label>
        </div>

        {/* what kind — drives the score and explains it */}
        <div>
          <span className="block text-xs text-ink-2 mb-2">What kind of food is it?</span>
          <div className="grid grid-cols-3 gap-1.5">
            {KINDS.map((k) => (
              <button
                key={k.key}
                onClick={() => { haptic('select'); setKind(k.key) }}
                className={`press rounded-xl border px-2 py-2.5 text-left transition-colors ${
                  kind === k.key
                    ? 'border-moss-700 bg-moss-700/[0.06] shadow-[0_0_0_1px_var(--color-moss-700)]'
                    : 'border-black/[0.08] bg-paper-50 hover:border-black/[0.16]'
                }`}
              >
                <span className="flex items-center gap-1 text-xs text-ink">
                  {k.key === 'whole' && <IconLeaf className="w-3 h-3 text-moss-700" />}
                  {k.label}
                </span>
                <span className="block text-[10px] text-ink-3 mt-0.5 leading-tight">{k.hint}</span>
              </button>
            ))}
          </div>
        </div>

        {/* one serving = amount + unit */}
        <div>
          <span className="block text-xs text-ink-2 mb-1.5">One serving is</span>
          <div className="flex gap-2">
            <input
              type="number"
              min="0"
              step="any"
              inputMode="decimal"
              value={servingAmount}
              onChange={(e) => setServingAmount(e.target.value)}
              className={`${numCls} w-24 text-center`}
            />
            <select
              value={unitKey}
              onChange={(e) => { haptic('select'); setUnitKey(e.target.value) }}
              className={`${fieldCls} flex-1`}
            >
              {SERVING_UNITS.map((u) => (
                <option key={u.key} value={u.key}>{u.label}</option>
              ))}
            </select>
          </div>
          <p className="text-[11px] text-ink-3 mt-1.5">
            ≈ {servingGrams}g per serving{unit.approx ? ' (volume is approximate)' : ''}
          </p>
        </div>

        {/* macros per serving */}
        <div>
          <span className="block text-xs text-ink-2 mb-1.5">Per serving</span>
          <div className="space-y-2">
            <label className="flex items-center gap-3">
              <span className="text-sm text-ink w-20">Calories</span>
              <input type="number" min="0" inputMode="numeric" value={calories} onChange={(e) => setCalories(e.target.value)} placeholder="kcal" className={`${numCls} flex-1`} />
            </label>
            <div className="grid grid-cols-2 gap-2">
              {[
                { label: 'Protein', v: protein, set: setProtein },
                { label: 'Carbs', v: carbs, set: setCarbs },
                { label: 'Fat', v: fat, set: setFat },
                { label: 'Fibre', v: fibre, set: setFibre },
              ].map((m) => (
                <label key={m.label} className="flex items-center gap-2">
                  <span className="text-xs text-ink-2 w-14">{m.label}</span>
                  <input type="number" min="0" step="any" inputMode="decimal" value={m.v} onChange={(e) => m.set(e.target.value)} placeholder="g" className={`${numCls} flex-1`} />
                </label>
              ))}
            </div>
          </div>
        </div>

        {error && (
          <p className="text-clay-700 text-xs leading-relaxed" role="alert">{error}</p>
        )}
      </div>

      <div className="px-5 py-4 border-t border-black/[0.07]">
        <button
          onClick={submit}
          disabled={saving || !canSave}
          className="press w-full bg-moss-700 hover:bg-moss-800 text-white font-semibold py-3.5 rounded-xl text-sm transition-colors disabled:opacity-50"
        >
          {saving ? 'Adding…' : 'Continue'}
        </button>
      </div>
    </>
  )
}
